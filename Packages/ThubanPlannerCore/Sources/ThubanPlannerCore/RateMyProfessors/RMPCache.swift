import Foundation

/// `rmp-cache.json`: what Rate My Professors said per instructor name (normalized key) — the UNC Charlotte profiles
/// that could be that person (`RMPMatcher.isCandidate`), matched against the course when shown. Safe to delete.
/// An entry with candidates is fresh for 7 days; an empty ("not on RMP") one for 2 days.
public struct RMPCache: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public var fetchedAt: Date
        public var candidates: [RMPTeacher]

        public init(fetchedAt: Date, candidates: [RMPTeacher]) {
            self.fetchedAt = fetchedAt
            self.candidates = candidates
        }
    }

    public static let foundMaxAge: TimeInterval = 7 * 24 * 3600
    public static let notFoundMaxAge: TimeInterval = 2 * 24 * 3600
    /// Entries older than this are dropped on save.
    public static let pruneAge: TimeInterval = 60 * 24 * 3600

    public var version: Int = 1
    public var entries: [String: Entry] = [:]

    public init() {}

    public static func isFresh(_ entry: Entry, now: Date) -> Bool {
        now.timeIntervalSince(entry.fetchedAt) < (entry.candidates.isEmpty ? notFoundMaxAge : foundMaxAge)
    }

    public func entry(for name: RMPPersonName) -> Entry? { entries[name.key] }

    public func freshEntry(for name: RMPPersonName, now: Date) -> Entry? {
        entry(for: name).flatMap { Self.isFresh($0, now: now) ? $0 : nil }
    }

    public mutating func store(_ candidates: [RMPTeacher], for name: RMPPersonName, at date: Date) {
        entries[name.key] = Entry(fetchedAt: date, candidates: candidates)
    }

    public mutating func prune(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.fetchedAt) < Self.pruneAge }
    }

    enum CodingKeys: String, CodingKey { case version, entries }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        entries = (try? c.decodeIfPresent([String: Entry].self, forKey: .entries)) ?? [:]
    }
}

/// Reads and writes `rmp-cache.json` next to planner.json (THUBAN_PLANNER_HOME honoured), atomically, 0600.
public final class RMPCacheStore: @unchecked Sendable {
    public let directory: URL
    public var url: URL { directory.appendingPathComponent("rmp-cache.json") }

    public init(directory: URL = AppPaths.home) { self.directory = directory }

    /// A missing or unreadable cache is simply empty.
    public func load() -> RMPCache { (try? JSONFile.read(RMPCache.self, from: url)) ?? RMPCache() }

    public func save(_ cache: RMPCache, now: Date = Date()) throws {
        var pruned = cache
        pruned.prune(now: now)
        try JSONFile.write(pruned, to: url, permissions: 0o600)
    }

    public func delete() throws { try JSONFile.remove(url) }
}
