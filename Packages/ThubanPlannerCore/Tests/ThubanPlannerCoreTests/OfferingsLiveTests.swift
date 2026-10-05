import Foundation
import XCTest
@testable import ThubanPlannerCore

/// LIVE: brings a course-offerings snapshot up to date from UNC Charlotte's PUBLIC class search — runs ONLY with
/// `THUBAN_PLANNER_LIVE_OFFERINGS=<output json>` (scripts/test.sh). One `getTerms`, then ONE subject search per
/// subject per term in the window (the bundled dataset's elective subjects), paced; GET search only (plus the
/// read-only term/search and resetDataForm POSTs), through BannerRequestGuard. Never signs in. Starts from the
/// existing file, so a rerun only fetches what is missing or stale.
final class OfferingsLiveTests: XCTestCase {
    func testSnapshotOfferings() async throws {
        guard let out = ProcessInfo.processInfo.environment["THUBAN_PLANNER_LIVE_OFFERINGS"], !out.isEmpty else {
            throw XCTSkip("Live offerings snapshot is off (set THUBAN_PLANNER_LIVE_OFFERINGS=<output json>).")
        }
        let dataset = try XCTUnwrap(CatalogDataset.bsme2025)
        let url = URL(fileURLWithPath: out)
        let start = ((try? JSONFile.read(CourseOfferings.self, from: url)) ?? nil) ?? .empty
        let fetcher = OfferingsFetcher(client: BannerClient(), pause: 0.6)
        let subjects = dataset.electiveSubjects
        let result = try await fetcher.refresh(start, subjects: subjects, progress: { done, total in
            print("live: \(done) / \(total)")
        }, save: { snapshot in try? JSONFile.write(snapshot, to: url) })
        try JSONFile.write(result, to: url)
        let window = result.window(now: Date())
        print("live: window past \(window.past.map(\.description)) upcoming \(window.upcoming.map(\.description))")
        for elective in dataset.electives {
            let s = result.summary(for: elective.code, window: window)
            print("live: \(elective.code) offered=\(s.isOffered) past=\(s.past) upcoming=\(s.upcoming)")
        }
        XCTAssertFalse(window.past.isEmpty)
    }
}
