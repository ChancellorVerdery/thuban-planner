import Foundation

// The Schedule tab's pure core: given the sections of every course planned for a term, the user's blocked times,
// filters and exclusions, list every weekly timetable that takes exactly one section (or one linked set) of each
// course with no time conflict. Deterministic, capped, and it explains an empty answer.

/// A weekly recurring time the user keeps free ("Work", "Gym"): a weekday and [start, end) in minutes.
public struct TimetableBlock: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var day: BannerWeekday
    public var start: Int
    public var end: Int
    public var label: String

    public init(id: String = UUID().uuidString, day: BannerWeekday, start: Int, end: Int, label: String = "") {
        self.id = id
        self.day = day
        self.start = min(start, end)
        self.end = max(start, end)
        self.label = label
    }

    /// A timed meeting on this weekday whose time overlaps the block.
    public func overlaps(_ meeting: BannerMeeting) -> Bool {
        guard meeting.isTimed, let begin = meeting.begin, let end = meeting.end, meeting.days.contains(day) else { return false }
        return begin < self.end && start < end
    }

    public func overlaps(_ section: BannerSection) -> Bool { section.timedMeetings.contains(where: overlaps) }

    /// "Mon 12:00–1:00 PM".
    public var summary: String { "\(day.shortLabel) \(BannerClock.range(start, end))" }
}

/// Section filters (per term).
public struct TimetableFilters: Codable, Hashable, Sendable {
    /// Only sections with seatsAvailable > 0.
    public var openSeatsOnly: Bool
    /// Hide sections that are full or already have a wait list.
    public var hideFullOrWaitlisted: Bool
    /// Allow online / no-set-time sections.
    public var allowOnline: Bool
    /// Allowed campus descriptions; empty = any campus.
    public var campuses: [String]

    public init(openSeatsOnly: Bool = false, hideFullOrWaitlisted: Bool = false, allowOnline: Bool = true, campuses: [String] = []) {
        self.openSeatsOnly = openSeatsOnly
        self.hideFullOrWaitlisted = hideFullOrWaitlisted
        self.allowOnline = allowOnline
        self.campuses = campuses
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openSeatsOnly = (try? c.decodeIfPresent(Bool.self, forKey: .openSeatsOnly)) ?? false
        hideFullOrWaitlisted = (try? c.decodeIfPresent(Bool.self, forKey: .hideFullOrWaitlisted)) ?? false
        allowOnline = (try? c.decodeIfPresent(Bool.self, forKey: .allowOnline)) ?? true
        campuses = (try? c.decodeIfPresent([String].self, forKey: .campuses)) ?? []
    }

    enum CodingKeys: String, CodingKey { case openSeatsOnly, hideFullOrWaitlisted, allowOnline, campuses }
}

/// How the list of timetables is ordered.
public enum TimetableSort: String, Codable, CaseIterable, Sendable, Identifiable {
    case fewestDays, fewestSessions, latestStart, earliestFinish, leastGaps, mostSeats

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fewestDays: return "Fewest class days"
        case .fewestSessions: return "Fewest class sessions"
        case .latestStart: return "Latest start"
        case .earliestFinish: return "Earliest finish"
        case .leastGaps: return "Least time between classes"
        case .mostSeats: return "Most open seats"
        }
    }
}

/// One way to take a course: a single section, or a set of linked sections taken together.
public struct TimetableChoice: Hashable, Sendable, Identifiable {
    public var sections: [BannerSection]
    /// CRNs joined with "+" in order.
    public var id: String { sections.map(\.crn).joined(separator: "+") }

    public init(sections: [BannerSection]) { self.sections = sections }

    public var crns: [String] { sections.map(\.crn) }

    /// The choices for a course: every unlinked section on its own; a linked section once per set it links to
    /// (`linkedSets[crn]`, from `fetchLinkedSections`), or on its own when no sets are known. Duplicate sets (seen
    /// from both sides) are merged. Ordered by section number then CRN.
    public static func build(sections: [BannerSection], linkedSets: [String: [[BannerSection]]] = [:]) -> [TimetableChoice] {
        var out: [TimetableChoice] = []
        var seen = Set<[String]>()
        func add(_ group: [BannerSection]) {
            var unique: [BannerSection] = []
            for s in group where !unique.contains(where: { $0.crn == s.crn }) { unique.append(s) }
            let key = unique.map(\.crn).sorted()
            guard !unique.isEmpty, seen.insert(key).inserted else { return }
            out.append(TimetableChoice(sections: unique))
        }
        for section in sections.sorted(by: sectionOrder) {
            if section.isLinked, let sets = linkedSets[section.crn], !sets.isEmpty {
                for set in sets { add([section] + set.sorted(by: sectionOrder)) }
            } else {
                add([section])
            }
        }
        return out
    }

    static func sectionOrder(_ a: BannerSection, _ b: BannerSection) -> Bool {
        if a.sequenceNumber != b.sequenceNumber { return a.sequenceNumber < b.sequenceNumber }
        return a.crn < b.crn
    }

    public func conflicts(with other: TimetableChoice) -> Bool {
        for a in sections { for b in other.sections where a.conflicts(with: b) { return true } }
        return false
    }

    /// Two sections of the choice itself conflict (a broken linked set).
    public var conflictsInternally: Bool {
        for i in sections.indices { for j in sections.indices where j > i && sections[i].conflicts(with: sections[j]) { return true } }
        return false
    }
}

/// A course as the generator sees it.
public struct TimetableCourse: Hashable, Sendable {
    /// "MEGR 2144" — the identity used in results and problems.
    public var code: String
    public var title: String
    public var choices: [TimetableChoice]
    /// Sections the user excluded.
    public var excludedCRNs: Set<String>
    /// The user's (or the Banner plan's) pinned section: only choices containing it are used.
    public var pinnedCRN: String?

    public init(code: String, title: String = "", choices: [TimetableChoice], excludedCRNs: Set<String> = [], pinnedCRN: String? = nil) {
        self.code = code
        self.title = title
        self.choices = choices
        self.excludedCRNs = excludedCRNs
        self.pinnedCRN = pinnedCRN
    }
}

/// Why a choice was left out, in the order they are checked.
public enum TimetableRejection: String, Codable, Hashable, CaseIterable, Sendable {
    case notPinned, excluded, noOpenSeat, fullOrWaitlisted, online, campus, blocked, selfConflict

    /// "excluded by you", used in "3 excluded by you, 2 full".
    public var phrase: String {
        switch self {
        case .notPinned: return "not the pinned section"
        case .excluded: return "excluded by you"
        case .noOpenSeat: return "no open seat"
        case .fullOrWaitlisted: return "full or wait-listed"
        case .online: return "online"
        case .campus: return "another campus"
        case .blocked: return "in a blocked time"
        case .selfConflict: return "linked sections that overlap"
        }
    }
}

/// Per-course accounting of the generator's filtering.
public struct TimetableCourseReport: Hashable, Sendable {
    public var code: String
    public var totalChoices: Int
    public var eligibleChoices: Int
    public var rejections: [TimetableRejection: Int]

    /// "8 sections: 3 excluded by you, 5 in a blocked time".
    public var rejectionSummary: String {
        let parts = TimetableRejection.allCases.compactMap { r -> String? in
            guard let n = rejections[r], n > 0 else { return nil }
            return "\(n) \(r.phrase)"
        }
        return parts.joined(separator: ", ")
    }
}

/// Why there are no timetables.
public enum TimetableProblem: Hashable, Sendable {
    /// Banner lists no sections for the course this term.
    case noSections(course: String)
    /// Every section was filtered out.
    case noEligibleSections(course: String, report: TimetableCourseReport)
    /// Every remaining section of one course overlaps every remaining section of the other.
    case alwaysConflict(first: String, second: String)
    /// Every course has sections and no pair always clashes, but no full combination fits.
    case noCombination

    public var message: String {
        switch self {
        case .noSections(let course):
            return "\(course) has no sections this term."
        case .noEligibleSections(let course, let report):
            let why = report.rejectionSummary
            return "\(course): none of its \(report.totalChoices) section\(report.totalChoices == 1 ? "" : "s") can be used\(why.isEmpty ? "" : " — \(why)")."
        case .alwaysConflict(let a, let b):
            return "\(a) and \(b) always overlap — every remaining section of one clashes with every remaining section of the other."
        case .noCombination:
            return "Each class fits on its own, but no combination of sections fits together."
        }
    }
}

/// Numbers a timetable is sorted by.
public struct TimetableMetrics: Hashable, Sendable {
    /// Distinct weekdays with a timed meeting.
    public var classDays: Int
    /// The earliest begin of any timed meeting (nil when nothing is timed).
    public var earliestStart: Int?
    /// The latest end of any timed meeting.
    public var latestEnd: Int?
    /// Sum over class days of the day's first begin (for tie-breaks).
    public var sumOfDayStarts: Int
    /// Sum over class days of the day's last end.
    public var sumOfDayEnds: Int
    /// Idle minutes between classes on the same day, summed over the week.
    public var gapMinutes: Int
    /// Open seats summed over the timetable's sections (negative seats count as 0).
    public var openSeats: Int
    /// Timed class meetings in a week: one per meeting per weekday it meets (MWF = 3, TR = 2; online / TBA = 0).
    public var classSessions: Int = 0

    public static func of(_ sections: [BannerSection]) -> TimetableMetrics {
        var byDay: [BannerWeekday: [(Int, Int)]] = [:]
        var sessions = 0
        for section in sections {
            for meeting in section.timedMeetings {
                guard let b = meeting.begin, let e = meeting.end else { continue }
                sessions += meeting.days.count
                for day in meeting.days { byDay[day, default: []].append((b, e)) }
            }
        }
        var gaps = 0, sumStarts = 0, sumEnds = 0
        var earliest: Int?, latest: Int?
        for (_, intervals) in byDay {
            let sorted = intervals.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            var runEnd = sorted[0].1
            for interval in sorted.dropFirst() {
                if interval.0 > runEnd { gaps += interval.0 - runEnd }
                runEnd = max(runEnd, interval.1)
            }
            let dayStart = sorted[0].0
            let dayEnd = sorted.map(\.1).max() ?? runEnd
            sumStarts += dayStart
            sumEnds += dayEnd
            earliest = min(earliest ?? dayStart, dayStart)
            latest = max(latest ?? dayEnd, dayEnd)
        }
        return TimetableMetrics(classDays: byDay.count, earliestStart: earliest, latestEnd: latest, sumOfDayStarts: sumStarts,
                                sumOfDayEnds: sumEnds, gapMinutes: gaps,
                                openSeats: sections.reduce(0) { $0 + max(0, $1.seatsAvailable) }, classSessions: sessions)
    }
}

/// One conflict-free timetable: one choice per course, in the courses' order.
public struct TimetableOption: Hashable, Sendable, Identifiable {
    public struct Pick: Hashable, Sendable {
        public var course: String
        public var choice: TimetableChoice
    }

    public var picks: [Pick]
    public var metrics: TimetableMetrics

    /// "MEGR 2144:20263|PHYS 2101:10001" — stable identity, also the final tie-break.
    public var id: String { picks.map { "\($0.course):\($0.choice.id)" }.joined(separator: "|") }

    public var sections: [BannerSection] { picks.flatMap(\.choice.sections) }
    public var crns: [String] { sections.map(\.crn) }
}

/// What `TimetableGenerator.generate` returns.
public struct TimetableResult: Hashable, Sendable {
    public var options: [TimetableOption]
    /// True when the search stopped at `limit` (there may be more).
    public var capped: Bool
    public var limit: Int
    public var reports: [TimetableCourseReport]
    /// Empty when `options` is non-empty.
    public var problems: [TimetableProblem]

    public static let empty = TimetableResult(options: [], capped: false, limit: TimetableGenerator.defaultLimit, reports: [], problems: [])
}

public enum TimetableGenerator {
    public static let defaultLimit = 10_000

    /// Every conflict-free timetable (up to `limit`), sorted by `sort` with the option id as the final tie-break.
    /// Courses with the same code are merged (their choices unioned). No courses → no options and no problems.
    public static func generate(courses rawCourses: [TimetableCourse], blocks: [TimetableBlock] = [],
                                filters: TimetableFilters = TimetableFilters(), sort: TimetableSort = .fewestDays,
                                limit: Int = defaultLimit) -> TimetableResult {
        let courses = merge(rawCourses)
        guard !courses.isEmpty else { return TimetableResult(options: [], capped: false, limit: limit, reports: [], problems: []) }

        // 1. Filter each course's choices, counting why the others were dropped.
        var reports: [TimetableCourseReport] = []
        var eligible: [[TimetableChoice]] = []
        var problems: [TimetableProblem] = []
        for course in courses {
            var kept: [TimetableChoice] = []
            var rejections: [TimetableRejection: Int] = [:]
            let pinValid = course.pinnedCRN.map { pin in course.choices.contains { $0.crns.contains(pin) } } ?? false
            for choice in course.choices {
                if let reason = rejection(of: choice, course: course, pinValid: pinValid, blocks: blocks, filters: filters) {
                    rejections[reason, default: 0] += 1
                } else {
                    kept.append(choice)
                }
            }
            let report = TimetableCourseReport(code: course.code, totalChoices: course.choices.count, eligibleChoices: kept.count, rejections: rejections)
            reports.append(report)
            eligible.append(kept)
            if course.choices.isEmpty {
                problems.append(.noSections(course: course.code))
            } else if kept.isEmpty {
                problems.append(.noEligibleSections(course: course.code, report: report))
            }
        }
        guard problems.isEmpty else { return TimetableResult(options: [], capped: false, limit: limit, reports: reports, problems: problems) }

        // 2. Flatten the choices and precompute conflicts between choices of different courses.
        var flat: [TimetableChoice] = []
        var owner: [Int] = []
        var domains: [[Int]] = []
        for (c, choices) in eligible.enumerated() {
            var domain: [Int] = []
            for choice in choices { domain.append(flat.count); flat.append(choice); owner.append(c) }
            domains.append(domain)
        }
        let n = flat.count
        var conflict = [Bool](repeating: false, count: n * n)
        for i in 0..<n {
            for j in (i + 1)..<max(i + 1, n) where owner[i] != owner[j] {
                if flat[i].conflicts(with: flat[j]) { conflict[i * n + j] = true; conflict[j * n + i] = true }
            }
        }

        // 3. A pair of courses whose choices all clash can never work.
        for a in 0..<courses.count {
            for b in (a + 1)..<max(a + 1, courses.count) {
                let always = domains[a].allSatisfy { i in domains[b].allSatisfy { j in conflict[i * n + j] } }
                if always { problems.append(.alwaysConflict(first: courses[a].code, second: courses[b].code)) }
            }
        }
        guard problems.isEmpty else { return TimetableResult(options: [], capped: false, limit: limit, reports: reports, problems: problems) }

        // 4. Backtracking with forward checking; the course with the fewest remaining choices goes next.
        var found: [[Int]] = []
        var assignment = [Int](repeating: -1, count: courses.count)
        var capped = false
        func search(_ domains: [[Int]], _ assigned: Int) {
            if capped { return }
            if assigned == courses.count {
                if found.count >= limit { capped = true; return }
                found.append(assignment)
                return
            }
            var next = -1
            for c in 0..<courses.count where assignment[c] < 0 {
                if next < 0 || domains[c].count < domains[next].count { next = c }
            }
            for i in domains[next] {
                assignment[next] = i
                var narrowed = domains
                narrowed[next] = [i]
                var dead = false
                for c in 0..<courses.count where assignment[c] < 0 {
                    narrowed[c] = narrowed[c].filter { !conflict[i * n + $0] }
                    if narrowed[c].isEmpty { dead = true; break }
                }
                if !dead { search(narrowed, assigned + 1) }
                assignment[next] = -1
                if capped { return }
            }
        }
        search(domains, 0)
        if found.isEmpty {
            return TimetableResult(options: [], capped: false, limit: limit, reports: reports, problems: [.noCombination])
        }

        // 5. Build, measure, sort.
        var options = found.map { vector -> TimetableOption in
            let picks = vector.enumerated().map { c, i in TimetableOption.Pick(course: courses[c].code, choice: flat[i]) }
            return TimetableOption(picks: picks, metrics: TimetableMetrics.of(picks.flatMap(\.choice.sections)))
        }
        options = sorted(options, by: sort)
        return TimetableResult(options: options, capped: capped, limit: limit, reports: reports, problems: [])
    }

    /// Sorts timetables; ties fall back to the option id, so the order never depends on search order.
    public static func sorted(_ options: [TimetableOption], by sort: TimetableSort) -> [TimetableOption] {
        let keyed = options.map { (option: $0, id: $0.id, key: sortKey($0.metrics, sort)) }
        return keyed.sorted { a, b in
            if a.key != b.key { return a.key.lexicographicallyPrecedes(b.key) }
            return a.id < b.id
        }.map(\.option)
    }

    /// Smaller is better, compared lexicographically.
    static func sortKey(_ m: TimetableMetrics, _ sort: TimetableSort) -> [Int] {
        let start = m.earliestStart ?? 24 * 60      // nothing timed = the latest possible start
        let end = m.latestEnd ?? 0                  // … and the earliest possible finish
        let avgStart = m.classDays > 0 ? m.sumOfDayStarts / m.classDays : 24 * 60
        let avgEnd = m.classDays > 0 ? m.sumOfDayEnds / m.classDays : 0
        switch sort {
        case .fewestDays: return [m.classDays, m.gapMinutes, -start, end]
        case .fewestSessions: return [m.classSessions, m.classDays, m.gapMinutes, -start, end]
        case .latestStart: return [-start, -avgStart, m.classDays, m.gapMinutes]
        case .earliestFinish: return [end, avgEnd, m.classDays, m.gapMinutes]
        case .leastGaps: return [m.gapMinutes, m.classDays, -start, end]
        case .mostSeats: return [-m.openSeats, m.classDays, m.gapMinutes]
        }
    }

    static func rejection(of choice: TimetableChoice, course: TimetableCourse, pinValid: Bool, blocks: [TimetableBlock],
                          filters: TimetableFilters) -> TimetableRejection? {
        if pinValid, let pin = course.pinnedCRN, !choice.crns.contains(pin) { return .notPinned }
        if choice.sections.contains(where: { course.excludedCRNs.contains($0.crn) }) { return .excluded }
        if filters.openSeatsOnly, choice.sections.contains(where: { !$0.hasOpenSeat }) { return .noOpenSeat }
        if filters.hideFullOrWaitlisted, choice.sections.contains(where: \.isFullOrWaitlisted) { return .fullOrWaitlisted }
        if !filters.allowOnline, choice.sections.contains(where: \.isOnline) { return .online }
        if !filters.campuses.isEmpty, choice.sections.contains(where: { !filters.campuses.contains($0.campus) }) { return .campus }
        if choice.sections.contains(where: { s in blocks.contains { $0.overlaps(s) } }) { return .blocked }
        if choice.conflictsInternally { return .selfConflict }
        return nil
    }

    /// Courses with the same code (case / space-insensitive) are merged into the first one.
    static func merge(_ courses: [TimetableCourse]) -> [TimetableCourse] {
        var out: [TimetableCourse] = []
        var index: [String: Int] = [:]
        for course in courses {
            let key = course.code.uppercased().filter { !$0.isWhitespace }
            if let i = index[key] {
                for choice in course.choices where !out[i].choices.contains(where: { $0.id == choice.id }) { out[i].choices.append(choice) }
                out[i].excludedCRNs.formUnion(course.excludedCRNs)
                if out[i].pinnedCRN == nil { out[i].pinnedCRN = course.pinnedCRN }
            } else {
                index[key] = out.count
                out.append(course)
            }
        }
        return out
    }
}
