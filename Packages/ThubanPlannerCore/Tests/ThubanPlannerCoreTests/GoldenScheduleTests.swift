import XCTest
@testable import ThubanPlannerCore

/// Parity with Atlas: Fixtures/golden-schedule.json holds 400 seeded random plans run through ATLAS'S OWN
/// `scheduleDegree` (tools/golden, JavaScriptCore + V8 sort order; regenerate with scripts/golden.sh). Every case —
/// requirement cycles, lecture↔lab coreq loops, duplicate codes / ids, unknown refs, 0-credit and 15-credit classes,
/// summer caps of 0, disabled terms, no recorded terms, > 64 classes (TimSort merges), all three strategies — must
/// produce the identical board, edges, unplaceable list, warnings, terms-to-finish, graduation term, upcoming
/// summers and status line.
final class GoldenScheduleTests: XCTestCase {
    struct Golden: Decodable {
        struct Case: Decodable {
            var name: String
            var now: Double
            var input: Input
            var expected: Expected
        }
        struct Input: Decodable {
            struct RawTerm: Decodable { var key: String; var season: Season; var year: Double; var current: Bool }
            struct RawSettings: Decodable { var maxCredits: Double; var summerMax: Double; var strategy: Strategy }
            var courses: [Course]
            var terms: [RawTerm]
            var disabledTerms: [String]
            var settings: RawSettings
        }
        struct Expected: Decodable {
            var schedule: Schedule
            var summers: [String]
            var status: String
        }
        var cases: [Case]
    }

    static func goldenCases() throws -> [Golden.Case] {
        let data = try Data(contentsOf: TestSupport.fixtureURL("golden-schedule.json"))
        return try JSONDecoder().decode(Golden.self, from: data).cases
    }

    static func plan(_ input: Golden.Input) -> PlannerData {
        // Used exactly as Atlas received it (no normalization), like scheduleDegree(s).
        let terms = input.terms.map { raw -> Term in
            var t = Term(season: raw.season, year: raw.year, current: raw.current)
            t.key = raw.key
            return t
        }
        return PlannerData(courses: input.courses, terms: terms, disabledTerms: input.disabledTerms,
                           settings: PlannerSettings(maxCredits: input.settings.maxCredits, summerMax: input.settings.summerMax,
                                                     strategy: input.settings.strategy))
    }

    func testEveryGoldenCaseMatchesAtlas() throws {
        let cases = try Self.goldenCases()
        XCTAssertEqual(cases.count, 400)
        var failures = 0
        for c in cases {
            let data = Self.plan(c.input)
            let now = Date(timeIntervalSince1970: c.now / 1000)
            let schedule = Scheduler.scheduleDegree(data, now: now, calendar: TestSupport.utc)
            if schedule != c.expected.schedule {
                failures += 1
                if failures <= 3 { XCTFail("\(c.name): schedule differs\n swift: \(schedule)\n atlas: \(c.expected.schedule)") }
            }
            XCTAssertEqual(Scheduler.upcomingSummers(data, now: now, calendar: TestSupport.utc), c.expected.summers, c.name)
            XCTAssertEqual(Scheduler.planStatus(data, schedule), c.expected.status, c.name)
        }
        XCTAssertEqual(failures, 0, "\(failures) of \(cases.count) golden cases differ")
    }

    func testGoldenSetCoversTheHardCases() throws {
        let cases = try Self.goldenCases()
        XCTAssertGreaterThan(cases.filter { $0.input.courses.count >= 64 }.count, 5, "TimSort merge paths")
        XCTAssertGreaterThan(cases.filter { !$0.expected.schedule.unplaceable.isEmpty }.count, 20, "unplaceable / cycles")
        XCTAssertGreaterThan(cases.filter { $0.expected.schedule.unplaceable.isEmpty && $0.expected.schedule.termsToFinish > 2 }.count, 20)
        XCTAssertGreaterThan(cases.filter { $0.input.terms.isEmpty }.count, 10, "no recorded terms → starts from now")
        for strategy in Strategy.allCases {
            XCTAssertGreaterThan(cases.filter { $0.input.settings.strategy == strategy }.count, 50, strategy.rawValue)
        }
        XCTAssertTrue(cases.contains { $0.expected.schedule.edges.contains { $0.kind == RequirementKind.coreq } })
    }
}
