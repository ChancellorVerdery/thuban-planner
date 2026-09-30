import Foundation

/// The whole local document (`planner.json`): the same model as Atlas's `atlas.course.v1` blob plus import
/// provenance. A value type; every rule over it is a pure function (Scheduler, mutations) and is unit-tested.
///
/// Decoding is TOLERANT and reproduces Atlas's `loadCourse()` normalization exactly (via the backend's
/// `decompose`, which also folds the retired `preOrCo` bucket into `coreqs`): missing keys take defaults,
/// id-less courses are dropped (duplicate ids are kept), fields are coerced with JavaScript's `Number` / `String` /
/// truthiness rules, terms are validated, re-keyed, de-duplicated (first wins), sorted by rank and left with at most
/// one current term (the latest), non-string disabled-term keys are dropped, and invalid settings fall back
/// (max 15, summer min(9, max), strategy soonest-summer). See `normalize()` for the typed half of the same rules.
public struct PlannerData: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int = PlannerData.currentVersion
    public var courses: [Course] = []
    /// Past and current terms, sorted by rank.
    public var terms: [Term] = []
    /// Term keys the scheduler must skip (typically summers). May name terms with no `Term` row. Order kept.
    public var disabledTerms: [String] = []
    public var settings: PlannerSettings = .default
    /// When the document came from an Atlas import (whole seconds), and from where ("atlas:beelink", "file:x.json").
    public var importedAt: Date?
    public var importSource: String?

    public init(courses: [Course] = [], terms: [Term] = [], disabledTerms: [String] = [], settings: PlannerSettings = .default,
                importedAt: Date? = nil, importSource: String? = nil) {
        self.courses = courses
        self.terms = terms
        self.disabledTerms = disabledTerms
        self.settings = settings
        self.importedAt = importedAt
        self.importSource = importSource
    }

    public static let empty = PlannerData()

    public var isEmpty: Bool { courses.isEmpty && terms.isEmpty }

    // MARK: Lookups

    /// The first course with `id` (Atlas `find`).
    public func course(_ id: String) -> Course? { courses.first { $0.id == id } }

    public func term(_ key: String) -> Term? { terms.first { $0.key == key } }

    public var currentTerm: Term? { terms.first(where: \.current) }

    /// Classes still to take (no term), in document order.
    public var toTake: [Course] { courses.filter { $0.term == nil } }

    /// Classes taken or in progress, in document order.
    public var taken: [Course] { courses.filter { $0.term != nil } }

    /// Classes recorded in `termKey`, in document order.
    public func courses(inTerm termKey: String) -> [Course] { courses.filter { $0.term == termKey } }

    /// The course a requirement ref names, matching codes case- and space-insensitively; the LAST course with that
    /// code wins (the scheduler's rule). nil for an unknown ref. Matching is JavaScript string equality (`JSKey`),
    /// like the scheduler's `byCode` map.
    public func course(forRef ref: String) -> Course? {
        let key = JSKey(Course.normalizeRef(ref))
        guard !key.text.isEmpty else { return nil }
        return courses.last { !$0.code.isEmpty && JSKey(Course.normalizeRef($0.code)) == key }
    }

    /// Requirement refs (prereqs + coreqs) across the plan that match no course code, de-duplicated, first-seen order.
    public var unknownRefs: [String] {
        var seen = Set<JSKey>()
        var out: [String] = []
        for item in courses {
            for ref in item.prereqs + item.coreqs where course(forRef: ref) == nil {
                if seen.insert(JSKey(Course.normalizeRef(ref))).inserted { out.append(ref) }
            }
        }
        return out
    }

    public func isDisabled(_ termKey: String) -> Bool { disabledTerms.contains(termKey) }

    // MARK: Normalization (loadCourse, typed half)

    /// Re-applies `loadCourse()`'s rules to a typed value: term keys recomputed from season + year, invalid years
    /// dropped, duplicate keys dropped (first wins), terms stably sorted by rank, one current (the latest), settings
    /// defaults (max ≤ 0 or not finite → 15; summer < 0 or not finite → min(9, max)), course text trimmed, refs
    /// cleaned, negative / non-finite credits → 3, empty term key → nil. Idempotent. `AppModel` runs it after every
    /// mutation — Atlas re-loads (and so re-normalizes) after every write, and the scheduler always sees this shape.
    public mutating func normalize() {
        courses = courses.map { c in
            var c = c
            c.code = JS.trim(c.code)
            c.title = JS.trim(c.title)
            if !c.credits.isFinite || c.credits < 0 { c.credits = 3 }
            c.prereqs = PlannerData.cleanRefs(c.prereqs)
            c.coreqs = PlannerData.cleanRefs(c.coreqs)
            if c.term?.isEmpty == true { c.term = nil }
            return c
        }
        var seen = Set<String>()
        let valid = terms.filter { $0.year.isFinite }.map { Term(season: $0.season, year: $0.year, current: $0.current) }
            .filter { seen.insert($0.key).inserted }
        terms = PlannerData.stableSortedByRank(valid)
        PlannerData.demoteExtraCurrents(&terms)
        if !settings.maxCredits.isFinite || settings.maxCredits <= 0 { settings.maxCredits = PlannerSettings.defaultMaxCredits }
        if !settings.summerMax.isFinite || settings.summerMax < 0 { settings.summerMax = Swift.min(9, settings.maxCredits) }
        if !settings.minCredits.isFinite || settings.minCredits < 0 { settings.minCredits = 0 }
        if !settings.summerMin.isFinite || settings.summerMin < 0 { settings.summerMin = 0 }
    }

    public func normalized() -> PlannerData {
        var copy = self
        copy.normalize()
        return copy
    }

    /// `cleanRefs` for typed refs: trimmed, empties dropped (order and duplicates kept).
    public static func cleanRefs(_ refs: [String]) -> [String] {
        refs.map(JS.trim).filter { !$0.isEmpty }
    }

    /// Terms sorted by rank, ties keeping their order (JavaScript's sort is stable).
    static func stableSortedByRank(_ terms: [Term]) -> [Term] {
        terms.enumerated().sorted { a, b in
            let ra = a.element.rank, rb = b.element.rank
            if ra != rb { return ra < rb }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// At most one current term: when several are flagged, all but the LAST (by rank) are demoted.
    static func demoteExtraCurrents(_ terms: inout [Term]) {
        let currents = terms.indices.filter { terms[$0].current }
        guard currents.count > 1 else { return }
        for index in currents.dropLast() { terms[index].current = false }
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey { case version, courses, terms, disabledTerms, settings, importedAt, importSource }

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        self = PlannerData(json: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(courses, forKey: .courses)
        try c.encode(terms, forKey: .terms)
        try c.encode(disabledTerms, forKey: .disabledTerms)
        try c.encode(settings, forKey: .settings)
        try c.encodeIfPresent(importedAt, forKey: .importedAt)
        try c.encodeIfPresent(importSource, forKey: .importSource)
    }

    /// Builds a normalized document from any JSON (a `planner.json`, an Atlas `atlas.course.v1` blob, or the
    /// importer's recomposed rows) with `loadCourse()` + `decompose()`'s rules. Never fails: garbage → empty plan.
    public init(json raw: JSONValue) {
        let s: [String: JSONValue]
        if case .object(let o) = raw { s = o } else { s = [:] }

        // Courses: drop non-objects and id-less rows; coerce every field.
        var courses: [Course] = []
        for entry in s["courses"]?.arrayValue ?? [] {
            guard case .object(let c) = entry, JS.truthy(c["id"]) else { continue }
            let credits = JS.number(c["credits"])
            let termValue = c["term"]?.stringValue
            courses.append(Course(
                id: JS.string(c["id"]),
                code: JS.trim(JS.truthy(c["code"]) ? JS.string(c["code"]) : ""),
                title: JS.trim(JS.truthy(c["title"]) ? JS.string(c["title"]) : ""),
                credits: credits.isFinite && credits >= 0 ? credits : 3,
                prereqs: PlannerData.cleanRefs(json: c["prereqs"]),
                // decompose(): fold the retired preOrCo bucket into coreqs, de-duplicated (exact text), order kept.
                coreqs: PlannerData.uniq(PlannerData.cleanRefs(json: c["coreqs"]) + PlannerData.cleanRefs(json: c["preOrCo"])),
                summerOk: JS.truthy(c["summerOk"]),
                term: (termValue?.isEmpty == false) ? termValue : nil))
        }

        // Terms: valid season + finite year, key recomputed, first key wins, sorted by rank, one current.
        var seen = Set<String>()
        var terms: [Term] = []
        for entry in s["terms"]?.arrayValue ?? [] {
            guard case .object(let t) = entry, let seasonText = t["season"]?.stringValue, let season = Season(rawValue: seasonText) else { continue }
            let year = JS.number(t["year"])
            guard year.isFinite else { continue }
            let term = Term(season: season, year: year, current: JS.truthy(t["current"]))
            if seen.insert(term.key).inserted { terms.append(term) }
        }
        terms = PlannerData.stableSortedByRank(terms)
        PlannerData.demoteExtraCurrents(&terms)

        let disabled = (s["disabledTerms"]?.arrayValue ?? []).compactMap(\.stringValue)

        // Settings: `!Number.isFinite(Number(x)) || x <= 0` (the comparison coerces the same way).
        var settings = PlannerSettings.default
        let g = s["settings"].flatMap { $0.isObject ? $0 : nil }
        let maxCredits = JS.number(g?["maxCredits"])
        settings.maxCredits = (!maxCredits.isFinite || maxCredits <= 0) ? PlannerSettings.defaultMaxCredits : maxCredits
        let summerMax = JS.number(g?["summerMax"])
        settings.summerMax = (!summerMax.isFinite || summerMax < 0) ? Swift.min(9, settings.maxCredits) : summerMax
        settings.strategy = g?["strategy"]?.stringValue.flatMap(Strategy.init(rawValue:)) ?? .soonestSummer
        // Thuban-only minimums (absent from Atlas data → 0, off).
        let minCredits = JS.number(g?["minCredits"])
        settings.minCredits = (!minCredits.isFinite || minCredits < 0) ? 0 : minCredits
        let summerMin = JS.number(g?["summerMin"])
        settings.summerMin = (!summerMin.isFinite || summerMin < 0) ? 0 : summerMin

        self.init(courses: courses, terms: terms, disabledTerms: disabled, settings: settings)
        if case .number(let v)? = s["version"] { version = Int(v) }
        if let text = s["importedAt"]?.stringValue { importedAt = ISO8601DateFormatter().date(from: text) }
        importSource = s["importSource"]?.stringValue
    }

    /// Atlas `cleanRefs`: an array's elements as `String(x).trim()`, empties dropped; anything else → [].
    static func cleanRefs(json value: JSONValue?) -> [String] {
        guard let items = value?.arrayValue else { return [] }
        return items.map { JS.trim(JS.string($0)) }.filter { !$0.isEmpty }
    }

    /// De-duplicates exact strings (JS `Set` semantics: code units, not canonical equivalence), first occurrence
    /// wins (decompose's `uniq`).
    static func uniq(_ items: [String]) -> [String] {
        var seen = Set<JSKey>()
        return items.filter { seen.insert(JSKey($0)).inserted }
    }
}
