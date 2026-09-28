import XCTest
@testable import ThubanPlannerCore

/// Scheduler rules beyond Atlas's own tests: strategies, coreq groups, caps, disabled terms, cycles, unknown refs,
/// the empty plan, the 60-term guard, duplicates, board shape and the UI helpers.
final class SchedulerTests: XCTestCase {
    func C(_ code: String, _ credits: Double, pre: [String] = [], co: [String] = [], summer: Bool = false, term: String? = nil) -> Course {
        Course(id: "id-\(code)", code: code, title: "Title \(code)", credits: credits, prereqs: pre, coreqs: co, summerOk: summer, term: term)
    }

    func plan(_ courses: [Course], max: Double = 15, summer: Double = 9, strategy: Strategy = .soonestSummer,
              terms: [Term] = [Term(season: .fall, year: 2025, current: true)], disabled: [String] = []) -> PlannerData {
        PlannerData(courses: courses, terms: terms, disabledTerms: disabled,
                    settings: PlannerSettings(maxCredits: max, summerMax: summer, strategy: strategy))
    }

    func run(_ s: PlannerData, _ day: String = "2025-10-01") -> Schedule {
        Scheduler.scheduleDegree(s, now: TestSupport.date(day), calendar: TestSupport.utc)
    }

    func term(_ p: Schedule, _ code: String) -> String? { p.boardTerm(of: "id-\(code)")?.key }

    // MARK: Empty and trivial plans

    func testEmptyPlanWithNoTerms() {
        let p = run(PlannerData())
        XCTAssertEqual(p, Schedule(board: [], edges: [], unplaceable: [], warnings: [], termsToFinish: 0, gradTerm: nil))
        XCTAssertEqual(Scheduler.planStatus(PlannerData(), p), "0 classes · nothing left to schedule")
    }

    func testRecordedTermsAppearEvenWhenEmpty() {
        let terms = [Term(season: .spring, year: 2025), Term(season: .fall, year: 2025, current: true)]
        let p = run(plan([C("A", 3, term: "spring-2025")], terms: terms))
        XCTAssertEqual(p.board.map(\.key), ["spring-2025", "fall-2025"])
        XCTAssertEqual(p.board.map(\.kind), [.past, .current])
        XCTAssertEqual(p.board[1].courseIds, [])
        XCTAssertEqual(p.columns.map(\.key), ["spring-2025"], "the map draws only columns with classes")
        XCTAssertEqual(p.termsToFinish, 0)
        XCTAssertEqual(p.gradTerm, "fall-2025", "grad term is the last column, even an empty current one")
    }

    func testNoRecordedTermsStartsAfterTheCalendarTerm() {
        // 2025-10-01 is in fall 2025 → the route starts with the term AFTER the one before it = fall 2025 itself.
        let p = run(plan([C("A", 3)], terms: []), "2025-10-01")
        XCTAssertEqual(term(p, "A"), "fall-2025")
        let june = run(plan([C("A", 3, summer: true)], terms: []), "2026-06-15")
        XCTAssertEqual(term(june, "A"), "summer-2026")
        let january = run(plan([C("A", 3)], terms: []), "2027-01-10")
        XCTAssertEqual(term(january, "A"), "spring-2027")
    }

    // MARK: Ordering

    func testCriticalPathFirstThenCreditsThenCode() {
        // Chain A → B → C gates the most work; D/E are free. Cap 6 → the chain head goes first.
        let s = plan([C("E", 3), C("D", 3), C("C", 3, pre: ["B"]), C("B", 3, pre: ["A"]), C("A", 3)], max: 6)
        let p = run(s)
        XCTAssertEqual(p.plannedTerms.first?.courseIds.first, "id-A")
        XCTAssertEqual(p.plannedTerms.map(\.key), ["spring-2026", "fall-2026", "spring-2027"], "no summer-offered class → no summer column")
        // Equal depth + credits → code order (localeCompare): D before E.
        XCTAssertEqual(p.plannedTerms[0].courseIds, ["id-A", "id-D"])
    }

    func testCodeTieBreakUsesLocaleCompare() {
        // "cs 10a" < "cs_101" < "cs-101" < "cs101" in ICU order (byte order would put "cs-101" first).
        let courses = ["CS101", "cs-101", "CS_101", "CS 10a"].enumerated().map { i, code in
            Course(id: "c\(i)", code: code, title: "", credits: 1)
        }
        let p = run(plan(courses, max: 1))
        XCTAssertEqual(p.plannedTerms.map { $0.courseIds[0] }, ["c3", "c2", "c1", "c0"])
    }

    // MARK: Coreq groups

    func testCoreqChainIsPulledInAsOneGroup() {
        // A needs B same-or-earlier, B needs C → all three share a term.
        let p = run(plan([C("A", 3, co: ["B"]), C("B", 3, co: ["C"]), C("C", 3)]))
        XCTAssertEqual(Set([term(p, "A"), term(p, "B"), term(p, "C")]).count, 1)
    }

    func testCoreqGroupMustFitTheCapTogether() {
        // Lecture 4 + lab 1 with cap 4: the group never fits → both unplaceable.
        let p = run(plan([C("LEC", 4, co: ["LAB"]), C("LAB", 1, co: ["LEC"])], max: 4))
        XCTAssertEqual(Set(p.unplaceable), ["id-LEC", "id-LAB"])
        XCTAssertEqual(p.warnings, ["Couldn't place: LEC, LAB — check for missing prerequisites or a prerequisite cycle."])
    }

    func testMutualCoreqsSchedulTogether() {
        let p = run(plan([C("LEC", 3, co: ["LAB"]), C("LAB", 1, co: ["LEC"])]))
        XCTAssertEqual(term(p, "LEC"), "spring-2026")
        XCTAssertEqual(term(p, "LAB"), "spring-2026")
        XCTAssertEqual(p.edges.filter { $0.kind == .coreq }.count, 2)
    }

    func testCoreqAlreadyDoneIsSatisfied() {
        let p = run(plan([C("A", 3, term: "fall-2025"), C("B", 3, co: ["A"])]))
        XCTAssertEqual(term(p, "B"), "spring-2026")
        XCTAssertEqual(p.edges, [RouteEdge(from: "id-A", to: "id-B", kind: .coreq)])
    }

    // MARK: Summer

    func testSummerCapAndOfferingInTheSameGroup() {
        // A summer-ok class whose coreq is NOT summer-ok cannot go to summer.
        let s = plan([C("A", 3, co: ["B"], summer: true), C("B", 3), C("S", 3, summer: true)], max: 3, summer: 3,
                     terms: [Term(season: .spring, year: 2026, current: true)])
        let p = run(s, "2026-03-01")
        XCTAssertEqual(term(p, "S"), "summer-2026")
        XCTAssertNotEqual(term(p, "A"), "summer-2026")
    }

    func testSummerMaxZeroMeansNoSummerClasses() {
        let p = run(plan([C("S", 3, summer: true)], summer: 0, terms: [Term(season: .spring, year: 2026, current: true)]), "2026-03-01")
        XCTAssertEqual(term(p, "S"), "fall-2026")
    }

    func testOptionalSummerOnlyWhenItFinishesStrictlyEarlier() {
        let spring = [Term(season: .spring, year: 2026, current: true)]
        // One summer class: with summers finishes summer-2026 < fall-2026 → use it.
        let useIt = run(plan([C("S", 3, summer: true)], strategy: .soonestOptionalSummer, terms: spring), "2026-03-01")
        XCTAssertEqual(term(useIt, "S"), "summer-2026")
        // S summer-ok + F fall-only, both fit in fall: fall-2026 either way → skip the summer.
        let skip = run(plan([C("S", 3, summer: true), C("F", 3)], max: 12, strategy: .soonestOptionalSummer, terms: spring), "2026-03-01")
        // …while S + a 12-credit F only finish in fall-2026 WITH the summer (else spring-2027) → use it.
        let save = run(plan([C("S", 3, summer: true), C("F", 12)], max: 12, strategy: .soonestOptionalSummer, terms: spring), "2026-03-01")
        XCTAssertEqual(term(save, "S"), "summer-2026")
        XCTAssertEqual(save.gradTerm, "fall-2026")
        XCTAssertEqual(term(skip, "S"), "fall-2026", "summers only if they save a term")
        XCTAssertFalse(skip.board.contains { $0.key == "summer-2026" })
    }

    // MARK: Disabled terms

    func testDisabledFallIsSkippedToo() {
        let p = run(plan([C("A", 3)], disabled: ["spring-2026", "summer-2026"]))
        XCTAssertEqual(term(p, "A"), "fall-2026")
    }

    // MARK: Even load

    func testEvenLoadUsesSummersWhenItCannotFinishWithout() {
        let spring = [Term(season: .spring, year: 2026, current: true)]
        // Fall / spring caps round to 0, so the no-summer run cannot finish → the even strategy uses summers.
        let p = run(plan([C("S", 3, summer: true)], max: 0.0001, summer: 3, strategy: .even, terms: spring), "2026-03-01")
        XCTAssertEqual(term(p, "S"), "summer-2026")
    }

    func testEvenLoadLightCapIsCeilOfAverage() {
        // 5 × 3 cr, cap 12 → soonest needs 2 terms → target ceil(15/2) = 8 → scale 8/12 → cap round(8) = 8: 2 classes a term.
        let cs = ["A", "B", "C", "D", "E"].map { C($0, 3) }
        let p = run(plan(cs, max: 12, strategy: .even))
        XCTAssertEqual(p.plannedTerms.map(\.credits), [6, 6, 3])
    }

    // MARK: Cycles, unknown refs, guards

    func testUnknownRefsAreIgnored() {
        let p = run(plan([C("A", 3, pre: ["NOPE 999"], co: ["ALSO NOT"])]))
        XCTAssertEqual(term(p, "A"), "spring-2026")
        XCTAssertTrue(p.edges.isEmpty)
    }

    func testRefsMatchCaseAndSpaceInsensitively() {
        let p = run(plan([C("MATH 1241", 3), C("MATH 1242", 3, pre: ["  math 1241 "])], max: 6))
        XCTAssertEqual(term(p, "MATH 1241"), "spring-2026")
        XCTAssertEqual(term(p, "MATH 1242"), "fall-2026", "not summer-offered, so after the summer")
        XCTAssertEqual(p.edges.first, RouteEdge(from: "id-MATH 1241", to: "id-MATH 1242", kind: .prereq))
    }

    func testDownstreamOfACycleIsUnplaceableButOthersPlace() {
        let p = run(plan([C("P", 3, pre: ["Q"]), C("Q", 3, pre: ["P"]), C("R", 3, pre: ["P"]), C("FREE", 3)]))
        XCTAssertEqual(Set(p.unplaceable), ["id-P", "id-Q", "id-R"])
        XCTAssertEqual(term(p, "FREE"), "spring-2026")
        XCTAssertEqual(p.termsToFinish, 1)
        XCTAssertTrue(p.warnings[0].hasPrefix("Couldn't place: "))
    }

    func testSixtyTermGuard() {
        // A class bigger than every cap never places; the run stops after 60 generated terms.
        let p = run(plan([C("HUGE", 40)]))
        XCTAssertEqual(p.unplaceable, ["id-HUGE"])
        XCTAssertEqual(p.termsToFinish, 0)
        XCTAssertEqual(p.warnings, ["Couldn't place: HUGE — check for missing prerequisites or a prerequisite cycle."])
        // A long chain of 61 one-per-term classes: only 60 terms are walked (summers included).
        let chain = (0 ..< 61).map { i in C("K\(i)", 15, pre: i == 0 ? [] : ["K\(i - 1)"], summer: true) }
        let long = run(plan(chain, summer: 15))
        XCTAssertEqual(long.termsToFinish, 60)
        XCTAssertEqual(long.unplaceable, ["id-K60"])
    }

    func testWarningNamesFallBackToTitleThenId() {
        let courses = [Course(id: "x1", code: "", title: "Mystery", credits: 99), Course(id: "x2", code: "", title: "", credits: 99)]
        let p = run(plan(courses))
        XCTAssertEqual(p.warnings, ["Couldn't place: Mystery, x2 — check for missing prerequisites or a prerequisite cycle."])
    }

    func testDuplicateIdsBehaveLikeAtlas() {
        // Two rows share an id: Atlas places the id once (the LAST row stands for it) and reports nothing twice.
        let courses = [Course(id: "dup", code: "A", title: "", credits: 3), Course(id: "dup", code: "B", title: "", credits: 4)]
        let p = run(plan(courses))
        XCTAssertEqual(p.plannedTerms.map(\.courseIds), [["dup"]])
        XCTAssertEqual(p.plannedTerms.first?.credits, 4)
        XCTAssertEqual(p.unplaceable, [])
    }

    // MARK: Board

    func testBoardCreditsAndKinds() {
        let s = plan([C("A", 3, term: "fall-2025"), C("B", 4.5, pre: ["A"]), C("C", 1.5, pre: ["A"])])
        let p = run(s)
        XCTAssertEqual(p.board.map(\.kind), [.current, .future])
        XCTAssertEqual(p.board.map(\.credits), [3, 6])
        XCTAssertEqual(p.status(of: "id-A"), .inProgress("fall-2025"))
        XCTAssertEqual(p.status(of: "id-B"), .planned("spring-2026"))
        XCTAssertEqual(Scheduler.planStatus(s, p), "2 to take · 6 credits · 1 more term · finishes Spring 2026")
    }

    func testClassInAnUnrecordedTermCountsAsDone() {
        let p = run(plan([C("OLD", 3, term: "fall-2010"), C("NEW", 3, pre: ["OLD"])]))
        XCTAssertEqual(term(p, "NEW"), "spring-2026")
        XCTAssertEqual(p.status(of: "id-OLD"), .unscheduled)
        XCTAssertTrue(p.edges.isEmpty, "no ribbon from a class that is not on the board")
    }

    // MARK: Helpers

    func testUpcomingSummers() {
        let s = plan([], disabled: ["summer-2031", "fall-2027", "summer-2027"])
        XCTAssertEqual(Scheduler.upcomingSummers(s, now: TestSupport.date("2025-10-01"), calendar: TestSupport.utc),
                       ["summer-2026", "summer-2027", "summer-2028", "summer-2029", "summer-2030"])
        let noTerms = PlannerData()
        XCTAssertEqual(Scheduler.upcomingSummers(noTerms, now: TestSupport.date("2026-06-15"), calendar: TestSupport.utc).first, "summer-2027")
    }

    func testPlanStatusPluralAndNoGrad() {
        let s = plan([C("HUGE", 40)])
        XCTAssertEqual(Scheduler.planStatus(s, run(s)), "1 to take · 40 credits · 0 more terms")
    }
}
