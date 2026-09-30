import Foundation
import XCTest
@testable import ThubanPlannerCore

/// LIVE check against selfservice.uncc.edu — runs ONLY with `THUBAN_PLANNER_LIVE_BANNER=1` (see scripts/test.sh).
/// Public, read-only calls only: the term list, then one class search for MEGR 2144 (term selection page, one
/// `term/search` POST, `resetDataForm`, `searchResults`). Never signs in. Keep runs rare.
final class BannerLiveTests: XCTestCase {
    func testPublicTermsAndOneSectionSearch() async throws {
        guard ProcessInfo.processInfo.environment["THUBAN_PLANNER_LIVE_BANNER"] == "1" else {
            throw XCTSkip("Live Banner check is off (set THUBAN_PLANNER_LIVE_BANNER=1).")
        }
        let client = BannerClient()
        let terms = try await client.terms()
        XCTAssertFalse(terms.isEmpty)
        XCTAssertFalse(terms.contains { $0.description.localizedCaseInsensitiveContains("view only") })
        print("live: \(terms.count) terms, newest \(terms[0].code) \(terms[0].description)")
        // The newest spring or fall term with a Thuban key.
        let term = try XCTUnwrap(terms.first { $0.termKey.map { TermKey.season($0) != .summer } ?? false })
        let sections = try await client.sections(subject: "MEGR", courseNumber: "2144", term: term.code)
        print("live: MEGR 2144 in \(term.description): \(sections.count) sections — " +
              sections.map { "\($0.sequenceNumber) \($0.crn) \($0.timeSummary) seats \($0.seatsAvailable)" }.joined(separator: "; "))
        XCTAssertFalse(sections.isEmpty, "MEGR 2144 is offered every spring and fall")
        XCTAssertTrue(sections.allSatisfy { $0.courseCode == "MEGR 2144" && $0.term == term.code })
        let result = TimetableGenerator.generate(courses: [TimetableCourse(code: "MEGR 2144", choices: TimetableChoice.build(sections: sections))])
        XCTAssertEqual(result.options.count, TimetableChoice.build(sections: sections).filter { !$0.conflictsInternally }.count)
    }
}
