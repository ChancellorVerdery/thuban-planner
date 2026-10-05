import Foundation

/// Brings `CourseOfferings` up to date from Banner's PUBLIC class search with as few requests as possible: the term
/// list (once a day), then ONE subject search per subject per term in the window that is missing or stale
/// (`CourseOfferings.needsFetch`) — finished terms are never refetched. Sequential, paced. Every request goes through
/// `BannerClient` and so through `BannerRequestGuard` (GET search, POST only to term/search and resetDataForm).
public struct OfferingsFetcher: Sendable {
    public var client: BannerClient
    /// Pause between subject searches.
    public var pause: TimeInterval

    public init(client: BannerClient, pause: TimeInterval = 0.45) {
        self.client = client
        self.pause = pause
    }

    /// The (term, subject) pairs `offerings` still needs for `subjects`, newest term first.
    public static func pending(_ offerings: CourseOfferings, subjects: [String], now: Date, calendar: Calendar = .current) -> [(BannerTerm, String)] {
        let window = offerings.window(now: now, calendar: calendar)
        var out: [(BannerTerm, String)] = []
        for term in window.upcoming + window.past {
            for subject in subjects where offerings.needsFetch(term: term, subject: subject, now: now, calendar: calendar) {
                out.append((term, subject.uppercased()))
            }
        }
        return out
    }

    /// Updates and returns the offerings. `progress(done, total)` after each search; `save` after each search too,
    /// so an interrupted run keeps what it got.
    public func refresh(_ start: CourseOfferings, subjects: [String], now: Date = Date(), calendar: Calendar = .current,
                        progress: @Sendable (Int, Int) async -> Void = { _, _ in },
                        save: @Sendable (CourseOfferings) async -> Void = { _ in }) async throws -> CourseOfferings {
        var offerings = start
        if offerings.termsAreStale(now: now) {
            offerings.terms = try await client.terms(max: 30)
            offerings.termsFetchedAt = now
        }
        let work = Self.pending(offerings, subjects: subjects, now: now, calendar: calendar)
        await progress(0, work.count)
        for (index, (term, subject)) in work.enumerated() {
            try Task.checkCancellation()
            if index > 0, pause > 0 { try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000)) }
            let sections = try await client.subjectSections(subject: subject, term: term.code)
            offerings.store(term: term, subject: subject, sections: sections, now: now)
            offerings.source = "UNC Charlotte Banner public class search"
            await save(offerings)
            await progress(index + 1, work.count)
        }
        return offerings
    }
}

extension CatalogDataset {
    /// Subjects whose offerings matter: the electives' subjects, most electives first ("MEGR", "PHYS", "MATH", "BIOL").
    public var electiveSubjects: [String] {
        var counts: [String: Int] = [:]
        for elective in electives { counts[CourseCode.subject(elective.code), default: 0] += 1 }
        return counts.keys.filter { !$0.isEmpty }.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }
}
