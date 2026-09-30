import Foundation

/// Everything the user chose for one term in the Schedule tab.
public struct TimetableTermState: Codable, Hashable, Sendable {
    /// Courses added by code ("MEGR 2144"), canonical form.
    public var addedCourses: [String]
    /// Courses removed from this term's builder (canonical codes).
    public var removedCourses: [String]
    /// Sections the user excluded.
    public var excludedCRNs: [String]
    /// The user's own pins: course code → CRN.
    public var pins: [String: String]
    public var blocks: [TimetableBlock]
    public var filters: TimetableFilters
    /// Sort criteria in priority order (never empty; no duplicates).
    public var sorts: [TimetableSort] {
        didSet { let n = TimetableSort.normalizedList(sorts); if n != sorts { sorts = n } }
    }
    /// The first criterion; setting it replaces the whole list with just that one.
    public var sort: TimetableSort {
        get { sorts.first ?? .fewestDays }
        set { sorts = [newValue] }
    }
    /// The timetable last shown (0-based).
    public var selectedIndex: Int

    public init(addedCourses: [String] = [], removedCourses: [String] = [],
                excludedCRNs: [String] = [], pins: [String: String] = [:], blocks: [TimetableBlock] = [],
                filters: TimetableFilters = TimetableFilters(), sort: TimetableSort = .fewestDays, sorts: [TimetableSort]? = nil,
                selectedIndex: Int = 0) {
        self.addedCourses = addedCourses
        self.removedCourses = removedCourses
        self.excludedCRNs = excludedCRNs
        self.pins = pins
        self.blocks = blocks
        self.filters = filters
        self.sorts = TimetableSort.normalizedList(sorts ?? [sort])
        self.selectedIndex = selectedIndex
    }

    enum CodingKeys: String, CodingKey {
        case addedCourses, removedCourses, excludedCRNs, pins, blocks, filters, sort, sorts, selectedIndex
    }

    /// Writes `sorts` and, for older builds, `sort` (the first criterion).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(addedCourses, forKey: .addedCourses)
        try c.encode(removedCourses, forKey: .removedCourses)
        try c.encode(excludedCRNs, forKey: .excludedCRNs)
        try c.encode(pins, forKey: .pins)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(filters, forKey: .filters)
        try c.encode(sort, forKey: .sort)
        try c.encode(sorts, forKey: .sorts)
        try c.encode(selectedIndex, forKey: .selectedIndex)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addedCourses = (try? c.decodeIfPresent([String].self, forKey: .addedCourses)) ?? []
        removedCourses = (try? c.decodeIfPresent([String].self, forKey: .removedCourses)) ?? []
        excludedCRNs = (try? c.decodeIfPresent([String].self, forKey: .excludedCRNs)) ?? []
        pins = (try? c.decodeIfPresent([String: String].self, forKey: .pins)) ?? [:]
        blocks = (try? c.decodeIfPresent([TimetableBlock].self, forKey: .blocks)) ?? []
        filters = (try? c.decodeIfPresent(TimetableFilters.self, forKey: .filters)) ?? TimetableFilters()
        // `sorts` (a list; unknown entries skipped), else an older file's single `sort`, else the default.
        let list = ((try? c.decodeIfPresent([JSONValue].self, forKey: .sorts)) ?? nil)?
            .compactMap { $0.stringValue.flatMap(TimetableSort.init(rawValue:)) } ?? []
        let single = (try? c.decodeIfPresent(TimetableSort.self, forKey: .sort)) ?? nil
        sorts = TimetableSort.normalizedList(list.isEmpty ? single.map { [$0] } ?? [] : list)
        selectedIndex = max(0, (try? c.decodeIfPresent(Int.self, forKey: .selectedIndex)) ?? 0)
    }
}

/// `schedule.json`: the Schedule tab's choices, per Banner term code.
public struct TimetableDocument: Codable, Hashable, Sendable {
    public var version: Int
    public var lastTermCode: String?
    public var terms: [String: TimetableTermState]

    public init(version: Int = 1, lastTermCode: String? = nil, terms: [String: TimetableTermState] = [:]) {
        self.version = version
        self.lastTermCode = lastTermCode
        self.terms = terms
    }

    public static let empty = TimetableDocument()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        lastTermCode = try? c.decodeIfPresent(String.self, forKey: .lastTermCode)
        terms = (try? c.decodeIfPresent([String: TimetableTermState].self, forKey: .terms)) ?? [:]
    }

    enum CodingKeys: String, CodingKey { case version, lastTermCode, terms }

    public func state(_ termCode: String) -> TimetableTermState { terms[termCode] ?? TimetableTermState() }
}

/// `schedule-cache.json`: what Banner last said (terms, sections per term + course). Safe to
/// delete; everything in it is fetched again.
public struct BannerCache: Codable, Hashable, Sendable {
    public struct SectionEntry: Codable, Hashable, Sendable {
        public var fetchedAt: Date
        public var sections: [BannerSection]
        /// CRN → linked sets (only for linked sections).
        public var linkedSets: [String: [[BannerSection]]]

        public init(fetchedAt: Date, sections: [BannerSection], linkedSets: [String: [[BannerSection]]] = [:]) {
            self.fetchedAt = fetchedAt
            self.sections = sections
            self.linkedSets = linkedSets
        }
    }

    public var version: Int = 1
    public var terms: [BannerTerm] = []
    public var termsFetchedAt: Date?
    public var sections: [String: SectionEntry] = [:]

    public init() {}

    public static func key(term: String, course: String) -> String {
        "\(term)|\(BannerText.canonicalCourseCode(course) ?? course.uppercased())"
    }

    public func sections(term: String, course: String) -> SectionEntry? { sections[Self.key(term: term, course: course)] }

    public mutating func store(_ entry: SectionEntry, term: String, course: String) { sections[Self.key(term: term, course: course)] = entry }

    enum CodingKeys: String, CodingKey { case version, terms, termsFetchedAt, sections }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        terms = (try? c.decodeIfPresent([BannerTerm].self, forKey: .terms)) ?? []
        termsFetchedAt = try? c.decodeIfPresent(Date.self, forKey: .termsFetchedAt)
        sections = (try? c.decodeIfPresent([String: SectionEntry].self, forKey: .sections)) ?? [:]
    }
}

/// Reads and writes `schedule.json` and `schedule-cache.json` next to planner.json (THUBAN_PLANNER_HOME honoured),
/// atomically, mode 0600.
public final class TimetableStore: @unchecked Sendable {
    public let directory: URL
    public var documentURL: URL { directory.appendingPathComponent("schedule.json") }
    public var cacheURL: URL { directory.appendingPathComponent("schedule-cache.json") }

    public init(directory: URL = AppPaths.home) { self.directory = directory }

    /// Throws when schedule.json exists but cannot be read (the caller then keeps it and does not overwrite).
    public func loadDocument() throws -> TimetableDocument {
        try JSONFile.read(TimetableDocument.self, from: documentURL) ?? .empty
    }

    public func saveDocument(_ document: TimetableDocument) throws {
        try JSONFile.write(document, to: documentURL, permissions: 0o600)
    }

    /// A missing or unreadable cache is simply empty.
    public func loadCache() -> BannerCache {
        (try? JSONFile.read(BannerCache.self, from: cacheURL)) ?? BannerCache()
    }

    public func saveCache(_ cache: BannerCache) throws {
        try JSONFile.write(cache, to: cacheURL, permissions: 0o600)
    }

    public func deleteCache() throws { try JSONFile.remove(cacheURL) }
}
