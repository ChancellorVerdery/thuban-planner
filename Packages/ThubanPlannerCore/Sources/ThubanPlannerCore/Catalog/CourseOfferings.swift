import Foundation

/// Which courses UNC Charlotte actually scheduled, per Banner term and subject, from the PUBLIC class search (one
/// search per subject per term). "Offered" = at least one section in any of the last six Banner terms (two years,
/// summers included, the calendar term counting as the newest) or in any upcoming term Banner lists.
/// Stored as `offerings-cache.json` next to planner.json (safe to delete); a snapshot ships in the core's resources so
/// the panel works before the first fetch and in the offline smoke run.
public struct CourseOfferings: Codable, Hashable, Sendable {
    public struct SubjectEntry: Codable, Hashable, Sendable {
        public var fetchedAt: Date
        /// Course number ("3225", "2101L") → number of sections.
        public var sections: [String: Int]

        public init(fetchedAt: Date, sections: [String: Int]) {
            self.fetchedAt = fetchedAt
            self.sections = sections
        }
    }

    public struct TermEntry: Codable, Hashable, Sendable {
        public var code: String
        public var description: String
        public var subjects: [String: SubjectEntry]

        public init(code: String, description: String, subjects: [String: SubjectEntry] = [:]) {
            self.code = code
            self.description = description
            self.subjects = subjects
        }
    }

    public var version: Int = 1
    /// Banner's term list (newest first) when it was last read.
    public var terms: [BannerTerm] = []
    public var termsFetchedAt: Date?
    /// Banner term code → what was found.
    public var byTerm: [String: TermEntry] = [:]
    /// Free text: where the data came from ("Banner public class search, 2026-10-05").
    public var source: String?

    public init(terms: [BannerTerm] = [], termsFetchedAt: Date? = nil, byTerm: [String: TermEntry] = [:], source: String? = nil) {
        self.terms = terms
        self.termsFetchedAt = termsFetchedAt
        self.byTerm = byTerm
        self.source = source
    }

    public static let empty = CourseOfferings()

    enum CodingKeys: String, CodingKey { case version, terms, termsFetchedAt, byTerm, source }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        terms = ((try? c.decodeIfPresent([BannerTerm].self, forKey: .terms)) ?? nil) ?? []
        termsFetchedAt = (try? c.decodeIfPresent(Date.self, forKey: .termsFetchedAt)) ?? nil
        byTerm = ((try? c.decodeIfPresent([String: TermEntry].self, forKey: .byTerm)) ?? nil) ?? [:]
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil
    }

    // MARK: Window

    /// The terms that decide "offered": `past` = the newest six terms up to and including the calendar term (two years
    /// with summers), newest first; `upcoming` = every listed term after it, soonest first. Only Banner's own terms
    /// with a readable code count.
    public struct Window: Hashable, Sendable {
        public var past: [BannerTerm]
        public var upcoming: [BannerTerm]
        public var all: [BannerTerm] { upcoming + past }
    }

    public static let pastTermCount = 6

    public static func window(terms: [BannerTerm], now: Date, calendar: Calendar = .current) -> Window {
        let current = TermKey.rank(TermKey.current(now: now, calendar: calendar))
        var seen = Set<String>()
        let readable = terms.filter { $0.termKey != nil && seen.insert($0.code).inserted }
            .sorted { TermKey.rank($0.termKey!) > TermKey.rank($1.termKey!) }
        let past = Array(readable.filter { TermKey.rank($0.termKey!) <= current }.prefix(pastTermCount))
        let upcoming = readable.filter { TermKey.rank($0.termKey!) > current }.reversed()
        return Window(past: past, upcoming: Array(upcoming))
    }

    public func window(now: Date, calendar: Calendar = .current) -> Window {
        Self.window(terms: terms, now: now, calendar: calendar)
    }

    // MARK: Freshness

    /// A finished term's sections never change: fetched once, kept. The calendar term and upcoming terms are
    /// refetched after a week.
    public static let refreshInterval: TimeInterval = 7 * 24 * 3600

    /// Whether `subject` in `term` needs a (re)fetch.
    public func needsFetch(term: BannerTerm, subject: String, now: Date, calendar: Calendar = .current) -> Bool {
        guard let entry = byTerm[term.code]?.subjects[subject.uppercased()] else { return true }
        guard let key = term.termKey else { return false }
        let finished = TermKey.rank(key) < TermKey.rank(TermKey.current(now: now, calendar: calendar))
        if finished { return false }
        return now.timeIntervalSince(entry.fetchedAt) > Self.refreshInterval
    }

    /// Banner's term list is re-read after a day.
    public func termsAreStale(now: Date) -> Bool {
        guard let at = termsFetchedAt, !terms.isEmpty else { return true }
        return now.timeIntervalSince(at) > 24 * 3600
    }

    public mutating func store(term: BannerTerm, subject: String, sections: [BannerSection], now: Date) {
        var counts: [String: Int] = [:]
        for section in sections where section.subject.uppercased() == subject.uppercased() {
            counts[section.courseNumber.uppercased(), default: 0] += 1
        }
        var entry = byTerm[term.code] ?? TermEntry(code: term.code, description: term.description)
        entry.description = term.description
        entry.subjects[subject.uppercased()] = SubjectEntry(fetchedAt: now, sections: counts)
        byTerm[term.code] = entry
    }

    // MARK: Queries

    /// What is known about one course across a window.
    public struct Summary: Hashable, Sendable {
        /// Term keys with at least one section, newest first.
        public var past: [String]
        /// Upcoming term keys with at least one section, soonest first.
        public var upcoming: [String]
        /// False when no term in the window has data for the course's subject (nothing fetched yet).
        public var known: Bool
        /// Offered in a summer term of the window.
        public var summer: Bool

        public var isOffered: Bool { !past.isEmpty || !upcoming.isEmpty }
        /// The newest term it ran in, e.g. "spring-2026".
        public var mostRecent: String? { past.first }
    }

    public func summary(for code: String, window: Window) -> Summary {
        guard let split = BannerText.splitCourseCode(code) else { return Summary(past: [], upcoming: [], known: false, summer: false) }
        var known = false
        func offered(_ term: BannerTerm) -> Bool {
            guard let subject = byTerm[term.code]?.subjects[split.subject] else { return false }
            known = true
            return (subject.sections[split.number] ?? 0) > 0
        }
        let past = window.past.filter(offered).compactMap(\.termKey)
        let upcoming = window.upcoming.filter(offered).compactMap(\.termKey)
        let summer = (past + upcoming).contains { TermKey.season($0) == .summer }
        return Summary(past: past, upcoming: upcoming, known: known, summer: summer)
    }

    /// The newest moment any subject in the window was fetched.
    public func lastFetched(window: Window) -> Date? {
        window.all.compactMap { byTerm[$0.code]?.subjects.values.map(\.fetchedAt).max() }.max()
    }

    // MARK: Bundled snapshot

    /// The offerings captured when the dataset was built (core resources), used until the app has fetched its own.
    public static let bundledSnapshot: CourseOfferings? = {
        guard let url = Bundle.module.url(forResource: "uncc-offerings-snapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONFile.decoder.decode(CourseOfferings.self, from: data)
    }()
}

/// Reads and writes `offerings-cache.json` next to planner.json (THUBAN_PLANNER_HOME honoured), atomically, 0600.
public final class OfferingsStore: @unchecked Sendable {
    public let directory: URL
    public var url: URL { directory.appendingPathComponent("offerings-cache.json") }

    public init(directory: URL = AppPaths.home) { self.directory = directory }

    /// A missing or unreadable cache is empty.
    public func load() -> CourseOfferings {
        (try? JSONFile.read(CourseOfferings.self, from: url)) ?? .empty
    }

    public func save(_ offerings: CourseOfferings) throws {
        try JSONFile.write(offerings, to: url, permissions: 0o600)
    }
}
