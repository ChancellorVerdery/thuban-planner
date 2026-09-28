import Foundation

/// A partial course edit (Atlas `updateCourse(s, id, patch)`): nil = leave that field alone. `term` is a double
/// optional: `.some(nil)` moves the class back to "to take".
public struct CoursePatch: Hashable, Sendable {
    public var code: String?
    public var title: String?
    public var credits: Double?
    public var prereqs: [String]?
    public var coreqs: [String]?
    public var summerOk: Bool?
    public var term: String??

    public init(code: String? = nil, title: String? = nil, credits: Double? = nil, prereqs: [String]? = nil, coreqs: [String]? = nil,
                summerOk: Bool? = nil, term: String?? = nil) {
        self.code = code
        self.title = title
        self.credits = credits
        self.prereqs = prereqs
        self.coreqs = coreqs
        self.summerOk = summerOk
        self.term = term
    }

    /// Splits a comma-separated requirement field ("MATH 1241, PHYS 2101") the way Atlas's inputs do.
    public static func refs(fromText text: String) -> [String] {
        text.split(separator: ",", omittingEmptySubsequences: false).map { JS.trim(String($0)) }.filter { !$0.isEmpty }
    }
}

/// Every write to the plan — Atlas `course.js` CRUD, same rules, pure and deterministic (ids come from `makeId`).
/// They do not re-normalize; `AppModel.mutate` calls `normalize()` afterwards, like Atlas's reload after each save.
extension PlannerData {
    // MARK: Terms

    /// Atlas `addTerm`. nil when the year is not finite. An existing key is returned unchanged (its `current` flag
    /// is NOT updated). A new current term clears every other current flag. Terms stay sorted by rank.
    @discardableResult
    public mutating func addTerm(season: Season, year: Double, current: Bool = false) -> Term? {
        guard year.isFinite else { return nil }
        let key = TermKey.make(season, year)
        if let existing = terms.first(where: { $0.key == key }) { return existing }
        if current { for i in terms.indices { terms[i].current = false } }
        let term = Term(season: season, year: year, current: current)
        terms.append(term)
        terms = PlannerData.stableSortedByRank(terms)
        return term
    }

    @discardableResult
    public mutating func addTerm(season: Season, year: Int, current: Bool = false) -> Term? {
        addTerm(season: season, year: Double(year), current: current)
    }

    /// Atlas `setCurrentTerm`: exactly `key` becomes current (an unknown key clears every flag).
    public mutating func setCurrentTerm(_ key: String) {
        for i in terms.indices { terms[i].current = terms[i].key == key }
    }

    /// Atlas `removeTerm`: drops the term; its classes fall back to "to take".
    public mutating func removeTerm(_ key: String) {
        terms.removeAll { $0.key == key }
        for i in courses.indices where courses[i].term == key { courses[i].term = nil }
    }

    // MARK: Courses

    /// Atlas `addCourse`. Text is trimmed, refs cleaned, credits default to 3 when not finite / negative, an empty
    /// term is nil. Returns nil (and adds nothing) when both code and title are empty.
    @discardableResult
    public mutating func addCourse(code: String = "", title: String = "", credits: Double = 3, prereqs: [String] = [], coreqs: [String] = [],
                                   summerOk: Bool = false, term: String? = nil,
                                   makeId: () -> String = { PlannerID.make("c") }) -> Course? {
        let code = JS.trim(code), title = JS.trim(title)
        guard !code.isEmpty || !title.isEmpty else { return nil }
        let course = Course(id: makeId(), code: code, title: title,
                            credits: credits.isFinite && credits >= 0 ? credits : 3,
                            prereqs: PlannerData.cleanRefs(prereqs), coreqs: PlannerData.cleanRefs(coreqs),
                            summerOk: summerOk, term: (term?.isEmpty ?? true) ? nil : term)
        courses.append(course)
        return course
    }

    /// Atlas `updateCourse`: patches the FIRST course with `id`. Credits that are not finite / negative keep the old
    /// value. Returns the updated course, nil for an unknown id.
    @discardableResult
    public mutating func updateCourse(_ id: String, _ patch: CoursePatch) -> Course? {
        guard let i = courses.firstIndex(where: { $0.id == id }) else { return nil }
        if let code = patch.code { courses[i].code = JS.trim(code) }
        if let title = patch.title { courses[i].title = JS.trim(title) }
        if let credits = patch.credits, credits.isFinite, credits >= 0 { courses[i].credits = credits }
        if let prereqs = patch.prereqs { courses[i].prereqs = PlannerData.cleanRefs(prereqs) }
        if let coreqs = patch.coreqs { courses[i].coreqs = PlannerData.cleanRefs(coreqs) }
        if let summerOk = patch.summerOk { courses[i].summerOk = summerOk }
        if let term = patch.term { courses[i].term = (term?.isEmpty ?? true) ? nil : term }
        return courses[i]
    }

    /// Atlas `removeCourse`: removes every course with `id`.
    public mutating func removeCourse(_ id: String) {
        courses.removeAll { $0.id == id }
    }

    // MARK: Settings

    /// Atlas `setSetting`: credit caps become `max(0, value)` (NaN → 0 — the next normalization then restores the
    /// default, as Atlas's next load does); the strategy is set as given.
    public mutating func setSetting(_ setting: PlannerSetting) {
        switch setting {
        case .maxCredits(let value): settings.maxCredits = Swift.max(0, value.isNaN ? 0 : value)
        case .summerMax(let value): settings.summerMax = Swift.max(0, value.isNaN ? 0 : value)
        case .strategy(let strategy): settings.strategy = strategy
        }
    }

    /// Atlas `toggleDisabledTerm`: removes every copy of `key`, or appends it.
    public mutating func toggleDisabledTerm(_ key: String) {
        if disabledTerms.contains(key) {
            disabledTerms.removeAll { $0 == key }
        } else {
            disabledTerms.append(key)
        }
    }

    // MARK: Repair

    /// Gives every course whose id repeats an earlier one a fresh id (Atlas keeps duplicate ids; this app keys
    /// rows by id). Returns how many were re-minted. Used by the importer, never on load.
    @discardableResult
    public mutating func reMintDuplicateIds(makeId: () -> String = { PlannerID.make("c") }) -> Int {
        var taken = Set(courses.map(\.id))
        var seen = Set<String>()
        var count = 0
        for i in courses.indices where !seen.insert(courses[i].id).inserted {
            var fresh = makeId()
            while taken.contains(fresh) { fresh = makeId() }
            courses[i].id = fresh
            taken.insert(fresh)
            seen.insert(fresh)
            count += 1
        }
        return count
    }
}
