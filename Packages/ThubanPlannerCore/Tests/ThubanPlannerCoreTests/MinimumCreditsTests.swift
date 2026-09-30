import XCTest
@testable import ThubanPlannerCore

/// Thuban-only minimum credits per regular term and per summer (settings `minCredits` / `summerMin`).
final class MinimumCreditsTests: XCTestCase {
    func C(_ code: String, _ credits: Double = 3, pre: [String] = [], co: [String] = [], summer: Bool = false) -> Course {
        Course(id: "id-\(code)", code: code, title: "Title \(code)", credits: credits, prereqs: pre, coreqs: co, summerOk: summer)
    }

    func plan(_ courses: [Course], max: Double = 15, summerMax: Double = 9, min: Double = 0, summerMin: Double = 0,
              strategy: Strategy = .soonestSummer) -> PlannerData {
        PlannerData(courses: courses, terms: [Term(season: .fall, year: 2025, current: true)], disabledTerms: [],
                    settings: PlannerSettings(maxCredits: max, summerMax: summerMax, strategy: strategy,
                                              minCredits: min, summerMin: summerMin))
    }

    func run(_ s: PlannerData) -> Schedule {
        Scheduler.scheduleDegree(s, now: TestSupport.date("2025-10-01"), calendar: TestSupport.utc)
    }

    func credits(_ p: Schedule) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: p.plannedTerms.map { ($0.key, $0.credits) })
    }

    // MARK: Settings

    func testMinimumsDefaultToOffAndSurviveARoundTrip() throws {
        let atlas = PlannerData(json: .object(["settings": .object(["maxCredits": .number(14)])]))
        XCTAssertEqual(atlas.settings.minCredits, 0)
        XCTAssertEqual(atlas.settings.summerMin, 0)
        let bad = PlannerData(json: .object(["settings": .object(["minCredits": .number(-3), "summerMin": .string("x")])]))
        XCTAssertEqual(bad.settings.minCredits, 0)
        XCTAssertEqual(bad.settings.summerMin, 0)

        var s = plan([])
        s.setSetting(.minCredits(12))
        s.setSetting(.summerMin(6))
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PlannerData.self, from: data)
        XCTAssertEqual(back.settings.minCredits, 12)
        XCTAssertEqual(back.settings.summerMin, 6)
    }

    func testEffectiveMinimumNeverExceedsTheCap() {
        let g = PlannerSettings(maxCredits: 12, summerMax: 6, minCredits: 15, summerMin: 9)
        XCTAssertEqual(g.effectiveMin(summer: false), 12)
        XCTAssertEqual(g.effectiveMin(summer: true), 6)
    }

    func testZeroMinimumsLeaveTheAtlasScheduleUntouched() {
        let courses = (1 ... 8).map { C("A\($0)") } + [C("S", summer: true)]
        XCTAssertEqual(run(plan(courses)), run(plan(courses, min: 0, summerMin: 0)))
    }

    // MARK: Summer minimum

    func testSummerUnderTheMinimumIsSkipped() {
        let courses = [C("P"), C("S", pre: ["P"], summer: true)]
        XCTAssertEqual(run(plan(courses)).boardTerm(of: "id-S")?.key, "summer-2026")
        let p = run(plan(courses, summerMin: 6))
        XCTAssertEqual(p.boardTerm(of: "id-S")?.key, "fall-2026", "a 3-credit summer is below 6 → the class waits for fall")
        XCTAssertFalse(p.plannedTerms.contains { $0.season == .summer })
        XCTAssertTrue(p.warnings.isEmpty)
    }

    func testSummerAtTheMinimumIsKept() {
        let courses = [C("P"), C("S1", pre: ["P"], summer: true), C("S2", pre: ["P"], summer: true)]
        let p = run(plan(courses, summerMin: 6))
        XCTAssertEqual(credits(p)["summer-2026"], 6)
    }

    // MARK: Regular minimum

    func testLightLastTermTakesClassesFromEarlierTerm() {
        let courses = (1 ... 8).map { C("A\($0)") } // 24 credits, cap 15 → 15 + 9 without a minimum
        XCTAssertEqual(credits(run(plan(courses))), ["spring-2026": 15, "fall-2026": 9])
        let p = run(plan(courses, min: 12))
        XCTAssertEqual(credits(p), ["spring-2026": 12, "fall-2026": 12])
        XCTAssertEqual(p.termsToFinish, 2)
        XCTAssertEqual(p.gradTerm, "fall-2026", "balancing never moves the finish term")
        XCTAssertTrue(p.warnings.isEmpty)
    }

    func testBalancingKeepsPrerequisitesEarlier() {
        // A gates F, so A must stay in spring; one of the free classes moves instead.
        let courses = [C("A"), C("B"), C("C"), C("D"), C("E"), C("F", pre: ["A"])]
        let p = run(plan(courses, min: 6))
        XCTAssertEqual(p.boardTerm(of: "id-A")?.key, "spring-2026")
        XCTAssertEqual(p.boardTerm(of: "id-F")?.key, "fall-2026")
        XCTAssertEqual(credits(p)["fall-2026"], 6)
        for edge in p.edges where edge.kind == .prereq {
            let from = p.board.firstIndex { $0.courseIds.contains(edge.from) }!
            let to = p.board.firstIndex { $0.courseIds.contains(edge.to) }!
            XCTAssertLessThan(from, to)
        }
    }

    func testBalancingKeepsCorequisiteUsersAtOrAfter() {
        // L is a coreq of M (M needs L same term or earlier) and both sit in spring: L can't move later than M.
        let courses = [C("L"), C("M", co: ["L"]), C("X", pre: ["M"]), C("B"), C("D")]
        let p = run(plan(courses, max: 12, min: 6))
        let order = p.board.map(\.key)
        let lTerm = order.firstIndex(of: p.boardTerm(of: "id-L")!.key)!
        let mTerm = order.firstIndex(of: p.boardTerm(of: "id-M")!.key)!
        XCTAssertLessThanOrEqual(lTerm, mTerm)
    }

    func testUnreachableMinimumWarns() {
        let courses = (1 ... 6).map { C("A\($0)") } // 18 credits: 15 + 3; spring can only give 3 and stay ≥ 12
        let p = run(plan(courses, min: 12))
        XCTAssertEqual(credits(p), ["spring-2026": 12, "fall-2026": 6])
        XCTAssertEqual(p.warnings, ["Fall 2026 has 6 credits — under your 12-credit minimum. Add an elective or lower the minimum."])
    }

    func testEvenLoadCapNeverDropsBelowTheMinimum() {
        let courses = (1 ... 6).map { C("A\($0)") } // even target 9 per term, minimum 12 lifts the light cap
        let p = run(plan(courses, min: 12, strategy: .even))
        XCTAssertGreaterThanOrEqual(p.plannedTerms.first?.credits ?? 0, 12)
    }
}
