import Foundation

/// How summer terms are switched on and off (Thuban-only, 2026-10-05; stored in `preferences.json`, never in
/// planner.json, so Atlas documents and every parity test are unaffected).
public enum SummerMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Summers follow Banner: on when a class still to take ran in that summer's schedule (or, until that schedule is
    /// released, in the most recent released summer).
    case automatic
    /// The per-summer toggles (`PlannerData.disabledTerms`) and each class's "Offered in summer" box, as entered.
    case manual

    public var id: String { rawValue }
    public var label: String { self == .automatic ? "Automatic" : "Manual" }
}

/// The automatic summer rule. Pure: it reads the plan and `CourseOfferings` (Banner's public class search, one
/// search per subject per term) and returns decisions plus an EFFECTIVE copy of the plan for the scheduler. The
/// stored plan is never changed, so switching back to Manual restores every toggle and checkbox exactly.
///
/// - Reference schedule of a summer: that summer itself when Banner lists it AND it is released (at least one
///   section in a subject fetched for it); otherwise the most recent EARLIER summer
///   that has sections. No such summer → no data (the stored manual values apply).
/// - A class is offered in a reference when that term has ≥ 1 section of its code or an equivalent
///   (`CourseCode.equivalentCodes`). Known = the reference has data for one of those codes' subjects.
/// - A summer is ON iff at least one class still to take is summer-eligible there: offered by the data, or — when
///   its subject has no data — its stored "Offered in summer" box is ticked.
/// - Effective plan: `disabledTerms` follows the decisions for the summers in the horizon (others keep their stored
///   state), and each to-take class with data gets `summerOk` = offered in the reference of the earliest summer in
///   the horizon (in practice every summer shares one reference: the latest released summer). Classes without data
///   keep their stored box. The scheduler (`Scheduler.scheduleDegree`) runs unchanged on that copy; summer caps,
///   minimums and transfer credit still apply.
public enum SummerAutomation {
    public struct Reference: Hashable, Sendable {
        /// The summer whose schedule is used ("summer-2026").
        public var termKey: String
        public var code: String
        /// True when this is the summer's own schedule; false = a fallback because it isn't released yet.
        public var isOwnSchedule: Bool
    }

    public struct Decision: Hashable, Sendable, Identifiable {
        public var summerKey: String
        /// Nil when Banner has nothing usable (the stored value is used).
        public var reference: Reference?
        public var enabled: Bool
        /// To-take classes Banner shows in the reference schedule (display codes, plan order).
        public var offered: [String]
        /// To-take classes with no data whose stored "Offered in summer" box is ticked.
        public var byYourSetting: [String]
        public var id: String { summerKey }

        /// "On — MEGR 3116, ENGR 3295 offered in Summer 2026 (Summer 2027 schedule not released)".
        public var reason: String {
            let summer = TermKey.label(summerKey)
            guard let reference else {
                return "\(enabled ? "On" : "Off") — no Banner schedule to check yet, so your setting is used"
            }
            let refLabel = TermKey.label(reference.termKey)
            let note = reference.isOwnSchedule ? "" : " (\(summer) schedule not released)"
            if !offered.isEmpty {
                let list = offered.count > 3 ? offered.prefix(3).joined(separator: ", ") + " + \(offered.count - 3) more" : offered.joined(separator: ", ")
                return "On — \(list) offered in \(refLabel)\(note)"
            }
            if !byYourSetting.isEmpty {
                return "On — \(byYourSetting.prefix(3).joined(separator: ", ")) marked “Offered in summer” (no Banner data)\(note)"
            }
            return reference.isOwnSchedule
                ? "Off — none of your remaining classes are offered in \(refLabel)"
                : "Off — none of your remaining classes ran in \(refLabel)\(note)"
        }
    }

    public struct Result: Hashable, Sendable {
        public var decisions: [Decision]
        /// The plan the scheduler should use.
        public var effective: PlannerData
        /// To-take class id → the summer availability the data gave it (only classes with data).
        public var summerOverrides: [String: Bool]
        /// The reference used for per-class availability (nil = no data).
        public var classReference: Reference?
        /// True when at least one summer could be decided from Banner data.
        public var hasData: Bool { decisions.contains { $0.reference != nil } }

        public func decision(_ summerKey: String) -> Decision? { decisions.first { $0.summerKey == summerKey } }
    }

    // MARK: Reference

    /// True when the term has at least one section in any subject fetched for it.
    static func hasSections(_ offerings: CourseOfferings, code: String) -> Bool {
        offerings.byTerm[code]?.subjects.values.contains { $0.sections.values.contains { $0 > 0 } } ?? false
    }

    /// The schedule that decides `summerKey` (see the type's rules).
    public static func reference(for summerKey: String, offerings: CourseOfferings) -> Reference? {
        guard TermKey.season(summerKey) == .summer, let ownCode = BannerTermCode.code(forTermKey: summerKey) else { return nil }
        let listed = offerings.terms.contains { $0.code == ownCode }
        let fetched = offerings.byTerm[ownCode].map { !$0.subjects.isEmpty } ?? false
        if listed && fetched && hasSections(offerings, code: ownCode) {
            return Reference(termKey: summerKey, code: ownCode, isOwnSchedule: true)
        }
        let rank = TermKey.rank(summerKey)
        let earlier = offerings.byTerm.keys.compactMap { code -> (String, String)? in
            guard let key = BannerTermCode.termKey(code), TermKey.season(key) == .summer, TermKey.rank(key) < rank,
                  hasSections(offerings, code: code) else { return nil }
            return (key, code)
        }.max { TermKey.rank($0.0) < TermKey.rank($1.0) }
        return earlier.map { Reference(termKey: $0.0, code: $0.1, isOwnSchedule: false) }
    }

    /// Whether `course` ran in the reference term: nil = no data for its subject there.
    public static func offered(_ courseCode: String, in reference: Reference, offerings: CourseOfferings) -> Bool? {
        guard let term = offerings.byTerm[reference.code] else { return nil }
        var known = false
        for candidate in CourseCode.equivalentCodes(courseCode) {
            guard let split = BannerText.splitCourseCode(candidate), let subject = term.subjects[split.subject] else { continue }
            known = true
            if (subject.sections[split.number] ?? 0) > 0 { return true }
        }
        return known ? false : nil
    }

    // MARK: Decisions

    /// The summers the rule decides: Atlas's `upcomingSummers` horizon for the stored plan.
    public static func horizon(_ data: PlannerData, now: Date, calendar: Calendar = .current) -> [String] {
        Scheduler.upcomingSummers(data, now: now, calendar: calendar)
    }

    public static func evaluate(_ data: PlannerData, offerings: CourseOfferings, now: Date, calendar: Calendar = .current) -> Result {
        let summers = horizon(data, now: now, calendar: calendar)
        let toTake = data.toTake
        var decisions: [Decision] = []
        for key in summers {
            guard let reference = reference(for: key, offerings: offerings) else {
                decisions.append(Decision(summerKey: key, reference: nil, enabled: !data.isDisabled(key), offered: [], byYourSetting: []))
                continue
            }
            var offered: [String] = []
            var bySetting: [String] = []
            for course in toTake where !course.code.isEmpty {
                switch Self.offered(course.code, in: reference, offerings: offerings) {
                case true?: offered.append(course.code)
                case nil: if course.summerOk { bySetting.append(course.code) }
                case false?: break
                }
            }
            decisions.append(Decision(summerKey: key, reference: reference, enabled: !offered.isEmpty || !bySetting.isEmpty,
                                      offered: offered, byYourSetting: bySetting))
        }

        var effective = data
        for d in decisions where d.reference != nil {
            effective.disabledTerms.removeAll { $0 == d.summerKey }
            if !d.enabled { effective.disabledTerms.append(d.summerKey) }
        }
        let classReference = decisions.lazy.compactMap(\.reference).first
        var overrides: [String: Bool] = [:]
        if let classReference {
            for i in effective.courses.indices where effective.courses[i].term == nil && !effective.courses[i].code.isEmpty {
                guard let value = offered(effective.courses[i].code, in: classReference, offerings: offerings) else { continue }
                overrides[effective.courses[i].id] = value
                effective.courses[i].summerOk = value
            }
        }
        return Result(decisions: decisions, effective: effective, summerOverrides: overrides, classReference: classReference)
    }

    // MARK: Fetching

    /// The summer terms worth fetching for the rule: every summer in the horizon that Banner lists, plus the most
    /// recent listed summer up to the calendar term (the fallback reference). Newest first.
    public static func termsToFetch(_ offerings: CourseOfferings, summers: [String], now: Date, calendar: Calendar = .current) -> [BannerTerm] {
        let wanted = Set(summers.compactMap { BannerTermCode.code(forTermKey: $0) })
        let current = TermKey.rank(TermKey.current(now: now, calendar: calendar))
        var out = offerings.terms.filter { wanted.contains($0.code) }
        let pastSummer = offerings.terms.filter { term in
            guard let key = term.termKey else { return false }
            return TermKey.season(key) == .summer && TermKey.rank(key) <= current
        }.max { TermKey.rank($0.termKey!) < TermKey.rank($1.termKey!) }
        if let pastSummer, !out.contains(where: { $0.code == pastSummer.code }) { out.append(pastSummer) }
        var seen = Set<String>()
        return out.filter { seen.insert($0.code).inserted }.sorted { TermKey.rank($0.termKey ?? "") > TermKey.rank($1.termKey ?? "") }
    }

    /// Subjects of the classes still to take (and their equivalents), sorted.
    public static func subjects(_ data: PlannerData) -> [String] {
        var out = Set<String>()
        for course in data.toTake {
            for code in CourseCode.equivalentCodes(course.code) {
                if let split = BannerText.splitCourseCode(code) { out.insert(split.subject) }
            }
        }
        return out.sorted()
    }
}

extension OfferingsFetcher {
    /// The (term, subject) pairs the summer rule still needs.
    public static func pendingSummers(_ offerings: CourseOfferings, summers: [String], subjects: [String], now: Date,
                                      calendar: Calendar = .current) -> [(BannerTerm, String)] {
        var out: [(BannerTerm, String)] = []
        for term in SummerAutomation.termsToFetch(offerings, summers: summers, now: now, calendar: calendar) {
            for subject in subjects where offerings.needsFetch(term: term, subject: subject, now: now, calendar: calendar) {
                out.append((term, subject.uppercased()))
            }
        }
        return out
    }

    /// Brings the summer terms the rule needs up to date (term list once a day; finished summers fetched once,
    /// upcoming ones weekly), one paced subject search at a time through `BannerClient` / `BannerRequestGuard`.
    public func refreshSummers(_ start: CourseOfferings, summers: [String], subjects: [String], now: Date = Date(),
                               calendar: Calendar = .current,
                               save: @Sendable (CourseOfferings) async -> Void = { _ in }) async throws -> CourseOfferings {
        var offerings = start
        if offerings.termsAreStale(now: now) {
            offerings.terms = try await client.terms(max: 30)
            offerings.termsFetchedAt = now
            await save(offerings)
        }
        let work = Self.pendingSummers(offerings, summers: summers, subjects: subjects, now: now, calendar: calendar)
        for (index, (term, subject)) in work.enumerated() {
            try Task.checkCancellation()
            if index > 0, pause > 0 { try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000)) }
            let sections = try await client.subjectSections(subject: subject, term: term.code)
            offerings.store(term: term, subject: subject, sections: sections, now: now)
            offerings.source = "UNC Charlotte Banner public class search"
            await save(offerings)
        }
        return offerings
    }
}
