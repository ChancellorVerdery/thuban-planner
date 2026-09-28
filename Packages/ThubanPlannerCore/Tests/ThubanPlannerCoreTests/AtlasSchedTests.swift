import XCTest
@testable import ThubanPlannerCore

/// Atlas's own scheduler unit tests (atlas-ui/tmp-e2e/course-sched.mjs), case for case.
final class AtlasSchedTests: XCTestCase {
    /// `C(code, credits, opts)`: id "id-<code>", title = code.
    func C(_ code: String, _ credits: Double, prereqs: [String] = [], coreqs: [String] = [], summerOk: Bool = false, term: String? = nil) -> Course {
        Course(id: "id-\(code)", code: code, title: code, credits: credits, prereqs: prereqs, coreqs: coreqs, summerOk: summerOk, term: term)
    }

    func base(_ courses: [Course], maxCredits: Double = 15, summerMax: Double = 9, strategy: Strategy = .soonestSummer,
              terms: [Term] = [], disabled: [String] = []) -> PlannerData {
        PlannerData(courses: courses, terms: terms, disabledTerms: disabled,
                    settings: PlannerSettings(maxCredits: maxCredits, summerMax: summerMax, strategy: strategy))
    }

    func termOf(_ plan: Schedule, _ code: String) -> String? {
        plan.board.first { $0.courseIds.contains("id-\(code)") }?.key
    }

    func rank(_ key: String?) -> Double { TermKey.rank(key ?? "") }

    let fall25 = Term(season: .fall, year: 2025, current: true)
    let spring26 = Term(season: .spring, year: 2026, current: true)
    func sched(_ s: PlannerData, _ day: String) -> Schedule { Scheduler.scheduleDegree(s, now: TestSupport.date(day), calendar: TestSupport.utc) }

    // 1) prereq ordering + credit cap
    func testPrereqOrderingAndCreditCap() {
        let p = sched(base([C("A", 15), C("B", 3, prereqs: ["A"])], maxCredits: 15, terms: [fall25]), "2025-10-01")
        XCTAssertGreaterThan(rank(termOf(p, "B")), rank(termOf(p, "A")), "B (needs A) lands later than A")
        XCTAssertEqual(termOf(p, "A"), "spring-2026", "A goes to the first future term")
    }

    // 2) small classes share a term; a cap-filling class stands alone
    func testSmallClassesShareACapFillingClassStandsAlone() {
        let p = sched(base([C("X", 3), C("Y", 3), C("Z", 15)], maxCredits: 15, terms: [fall25]), "2025-10-01")
        XCTAssertNotNil(termOf(p, "X"))
        XCTAssertEqual(termOf(p, "X"), termOf(p, "Y"), "two small classes share a term")
        XCTAssertNotEqual(termOf(p, "Z"), termOf(p, "X"), "the 15-credit class is alone")
    }

    // 3) coreq same-or-earlier: the coreq shares the term (pulled in as a group)
    func testCoreqSharesTheTerm() {
        let p = sched(base([C("A", 4), C("B", 4, coreqs: ["A"])], terms: [fall25]), "2025-10-01")
        XCTAssertEqual(termOf(p, "A"), termOf(p, "B"), "coreq A shares B’s term")
    }

    // 4) a prereq completed in a past term is satisfied
    func testPrereqDoneInAPastTerm() {
        let p = sched(base([C("CALC1", 4, term: "fall-2025"), C("CALC2", 4, prereqs: ["CALC1"])], terms: [fall25]), "2025-10-01")
        XCTAssertEqual(termOf(p, "CALC2"), "spring-2026", "CALC2 schedules right after its already-done prereq")
    }

    // 5) summer availability
    func testSummerAvailability() {
        let p = sched(base([C("S1", 6, summerOk: true), C("S2", 6)], maxCredits: 6, summerMax: 6, terms: [spring26]), "2026-03-01")
        XCTAssertEqual(termOf(p, "S1"), "summer-2026", "a summer-offered class fills the summer")
        XCTAssertEqual(termOf(p, "S2"), "fall-2026", "a class not offered in summer skips to fall")
    }

    // 6) disabled summer skipped
    func testDisabledSummerSkipped() {
        let p = sched(base([C("S1", 6, summerOk: true), C("S2", 6, summerOk: true)], maxCredits: 6, summerMax: 6, terms: [spring26],
                           disabled: ["summer-2026"]), "2026-03-01")
        XCTAssertNotEqual(termOf(p, "S1"), "summer-2026")
        XCTAssertNotEqual(termOf(p, "S2"), "summer-2026", "nothing lands in the disabled summer")
    }

    // 7) strategy: even load caps each term below the hard max
    func testEvenLoadSpreads() {
        let cs = [C("A", 3), C("B", 3), C("C", 3), C("D", 3)] // 12 cr, no deps
        let soonest = sched(base(cs, maxCredits: 12, strategy: .soonestSummer, terms: [fall25]), "2025-10-01")
        let even = sched(base(cs, maxCredits: 12, strategy: .even, terms: [fall25]), "2025-10-01")
        let soonestTerms = Set(cs.map { termOf(soonest, $0.code) }).count
        let evenTerms = Set(cs.map { termOf(even, $0.code) }).count
        XCTAssertEqual(soonestTerms, 1, "soonest packs all 4 into one 12-credit term")
        XCTAssertGreaterThanOrEqual(evenTerms, soonestTerms, "even load spreads across more terms (lighter each)")
    }

    // 7b) even load never fails where soonest succeeds: a 15cr class survives the lighter cap
    func testEvenLoadFallsBackToFullCaps() {
        let p = sched(base([C("BIG", 15), C("S1", 3), C("S2", 3)], maxCredits: 15, strategy: .even, terms: [fall25]), "2025-10-01")
        XCTAssertEqual(p.unplaceable, [])
        XCTAssertNotNil(termOf(p, "BIG"), "even load falls back to full caps instead of dropping a big class")
    }

    // 8) prereq cycle reported, not dropped
    func testPrereqCycleReported() {
        let p = sched(base([C("P", 3, prereqs: ["Q"]), C("Q", 3, prereqs: ["P"])], terms: [fall25]), "2025-10-01")
        XCTAssertEqual(p.unplaceable.count, 2)
        XCTAssertGreaterThanOrEqual(p.warnings.count, 1, "a prereq cycle is flagged unplaceable")
    }

    // 9) edges connect placed courses
    func testEdgesConnectPlacedCourses() {
        let p = sched(base([C("A", 3), C("B", 3, prereqs: ["A"])], terms: [fall25]), "2025-10-01")
        XCTAssertTrue(p.edges.contains(RouteEdge(from: "id-A", to: "id-B", kind: .prereq)), "a prereq edge A→B exists")
    }
}
