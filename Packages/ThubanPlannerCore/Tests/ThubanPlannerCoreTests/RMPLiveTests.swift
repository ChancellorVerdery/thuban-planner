import Foundation
import XCTest
@testable import ThubanPlannerCore

/// LIVE check against www.ratemyprofessors.com — runs ONLY with `THUBAN_PLANNER_LIVE_RMP=1` (see scripts/test.sh).
/// Read-only GraphQL teacher searches scoped to the two UNC Charlotte pages, for three instructors taken from the
/// captured Banner PHYS sections (one expected on RMP, one hyphenated, one not on RMP). About 8 requests, paced.
final class RMPLiveTests: XCTestCase {
    func testLookUpBannerInstructors() async throws {
        guard ProcessInfo.processInfo.environment["THUBAN_PLANNER_LIVE_RMP"] == "1" else {
            throw XCTSkip("Live Rate My Professors check is off (set THUBAN_PLANNER_LIVE_RMP=1).")
        }
        let sections = try BannerSearchPage.decode(TestSupport.fixture("banner/searchResults-PHYS-202680.json")).sections
        let names = Set(sections.flatMap(\.instructors))
        let client = RMPClient()
        var found = 0
        for raw in ["Ritchie Dudley", "Farida Mohiuddin-Jacobs", "Yuri Nesmelov"] {
            XCTAssertTrue(names.contains(raw), "\(raw) teaches PHYS in the Banner capture")
            let name = try XCTUnwrap(RMPPersonName.parse(raw))
            let candidates = try await client.candidates(for: name)
            let match = RMPMatcher.match(name: name, candidates: candidates, subject: "PHYS")
            switch match {
            case .found(let r):
                found += 1
                let pages = r.profiles.map { "\($0.schoolLegacyId)/\($0.legacyId) \($0.avgRating) × \($0.numRatings)" }.joined(separator: ", ")
                print("live: \(raw) → \(r.avgRating.map { String(format: "%.2f", $0) } ?? "–") / 5, \(r.numRatings) ratings, difficulty "
                      + "\(r.avgDifficulty.map { String(format: "%.2f", $0) } ?? "–"), would take again "
                      + "\(r.wouldTakeAgainPercent.map { String(format: "%.0f%%", $0) } ?? "–") [\(pages)]")
            case .ambiguous(let list):
                print("live: \(raw) → ambiguous: \(list.map(\.displayName).joined(separator: ", "))")
            case .notFound:
                print("live: \(raw) → not on Rate My Professors at UNC Charlotte")
            }
        }
        let requests = await client.requestCount
        print("live: \(requests) requests")
        XCTAssertGreaterThanOrEqual(found, 1)
    }
}
