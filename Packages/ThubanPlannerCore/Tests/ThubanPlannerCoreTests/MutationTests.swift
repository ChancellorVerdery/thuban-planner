import XCTest
@testable import ThubanPlannerCore

/// Atlas `course.js` CRUD rules.
final class MutationTests: XCTestCase {
    var counter = 0
    func nextId() -> String { counter += 1; return "c-\(counter)" }

    func testAddTerm() {
        var d = PlannerData()
        XCTAssertEqual(d.addTerm(season: .fall, year: 2025)?.key, "fall-2025")
        d.addTerm(season: .spring, year: 2025, current: true)
        XCTAssertEqual(d.terms.map(\.key), ["spring-2025", "fall-2025"], "kept sorted by rank")
        // A new current term clears the others.
        d.addTerm(season: .spring, year: 2026, current: true)
        XCTAssertEqual(d.terms.filter(\.current).map(\.key), ["spring-2026"])
        // An existing key is returned unchanged — its current flag is NOT updated.
        let existing = d.addTerm(season: .fall, year: 2025, current: true)
        XCTAssertEqual(existing?.current, false)
        XCTAssertEqual(d.terms.filter(\.current).map(\.key), ["spring-2026"])
        XCTAssertEqual(d.terms.count, 3)
        XCTAssertNil(d.addTerm(season: .fall, year: .infinity))
    }

    func testSetCurrentAndRemoveTerm() {
        var d = PlannerData()
        d.addTerm(season: .fall, year: 2025)
        d.addTerm(season: .spring, year: 2026, current: true)
        d.addCourse(code: "A", term: "fall-2025", makeId: nextId)
        d.addCourse(code: "B", term: "spring-2026", makeId: nextId)
        d.setCurrentTerm("fall-2025")
        XCTAssertEqual(d.currentTerm?.key, "fall-2025")
        d.setCurrentTerm("nope")
        XCTAssertNil(d.currentTerm, "an unknown key clears every flag (Atlas)")
        d.removeTerm("fall-2025")
        XCTAssertEqual(d.terms.map(\.key), ["spring-2026"])
        XCTAssertNil(d.courses[0].term, "its classes fall back to 'to take'")
        XCTAssertEqual(d.courses[1].term, "spring-2026")
    }

    func testAddCourse() {
        var d = PlannerData()
        let c = d.addCourse(code: "  MEGR 2144 ", title: " Solid Mechanics ", credits: 3, prereqs: [" MEGR 2141 ", ""], coreqs: ["", " X"],
                            summerOk: true, term: "", makeId: nextId)
        XCTAssertEqual(c, Course(id: "c-1", code: "MEGR 2144", title: "Solid Mechanics", credits: 3, prereqs: ["MEGR 2141"], coreqs: ["X"],
                                 summerOk: true, term: nil))
        XCTAssertNil(d.addCourse(code: " ", title: "", makeId: nextId), "code or title required")
        XCTAssertEqual(d.addCourse(title: "New class", credits: -1, makeId: nextId)?.credits, 3)
        XCTAssertEqual(d.addCourse(title: "NaN", credits: .nan, makeId: nextId)?.credits, 3)
        XCTAssertEqual(d.courses.count, 3)
    }

    func testUpdateCourse() {
        var d = PlannerData()
        d.addCourse(code: "A", credits: 4, makeId: nextId)
        d.addCourse(code: "B", makeId: nextId)
        XCTAssertNil(d.updateCourse("missing", CoursePatch(code: "X")))
        d.updateCourse("c-1", CoursePatch(code: " A1 ", title: "Alpha", credits: -5, prereqs: ["B", " "], summerOk: true, term: .some("fall-2025")))
        XCTAssertEqual(d.courses[0], Course(id: "c-1", code: "A1", title: "Alpha", credits: 4, prereqs: ["B"], summerOk: true, term: "fall-2025"))
        d.updateCourse("c-1", CoursePatch(credits: 0, term: .some(nil)))
        XCTAssertEqual(d.courses[0].credits, 0)
        XCTAssertNil(d.courses[0].term, "term .some(nil) = back to 'to take'")
        d.updateCourse("c-1", CoursePatch(term: .some("")))
        XCTAssertNil(d.courses[0].term)
        XCTAssertEqual(CoursePatch.refs(fromText: " MATH 1241, ,PHYS 2101 ,"), ["MATH 1241", "PHYS 2101"])
    }

    func testRemoveCourseRemovesEveryCopy() {
        var d = PlannerData(courses: [Course(id: "x", code: "A"), Course(id: "y", code: "B"), Course(id: "x", code: "C")])
        d.removeCourse("x")
        XCTAssertEqual(d.courses.map(\.id), ["y"])
    }

    func testSettings() {
        var d = PlannerData()
        d.setSetting(.maxCredits(18))
        d.setSetting(.summerMax(-4))
        d.setSetting(.strategy(.even))
        XCTAssertEqual(d.settings, PlannerSettings(maxCredits: 18, summerMax: 0, strategy: .even))
        d.setSetting(.maxCredits(.nan))
        XCTAssertEqual(d.settings.maxCredits, 0)
        d.normalize()
        XCTAssertEqual(d.settings.maxCredits, 15, "a 0 cap is reset on the next load, like Atlas")
        XCTAssertEqual(d.settings.summerMax, 0)
    }

    func testToggleDisabledTerm() {
        var d = PlannerData(disabledTerms: ["summer-2026", "fall-2026", "summer-2026"])
        d.toggleDisabledTerm("summer-2026")
        XCTAssertEqual(d.disabledTerms, ["fall-2026"], "removes every copy")
        d.toggleDisabledTerm("summer-2027")
        XCTAssertEqual(d.disabledTerms, ["fall-2026", "summer-2027"])
        XCTAssertTrue(d.isDisabled("summer-2027"))
    }

    func testReMintDuplicateIds() {
        var d = PlannerData(courses: [Course(id: "x", code: "A"), Course(id: "x", code: "B"), Course(id: "c-1", code: "C"), Course(id: "x", code: "D")])
        XCTAssertEqual(d.reMintDuplicateIds(makeId: nextId), 2)
        XCTAssertEqual(d.courses.map(\.id), ["x", "c-2", "c-1", "c-3"], "a fresh id never collides with an existing one")
    }

    func testLookups() {
        let d = PlannerData(courses: [Course(id: "a", code: "MATH 1241"), Course(id: "b", code: "math 1241", prereqs: ["NOPE", "MATH 1241"]),
                                      Course(id: "c", code: "", title: "Elective", term: "fall-2025")],
                            terms: [Term(season: .fall, year: 2025, current: true)])
        XCTAssertEqual(d.course(forRef: " Math 1241 ")?.id, "b", "the last course with the code wins")
        XCTAssertNil(d.course(forRef: ""))
        XCTAssertEqual(d.unknownRefs, ["NOPE"])
        XCTAssertEqual(d.toTake.map(\.id), ["a", "b"])
        XCTAssertEqual(d.taken.map(\.id), ["c"])
        XCTAssertEqual(d.courses(inTerm: "fall-2025").map(\.id), ["c"])
        XCTAssertEqual(d.courses[2].displayName, "Elective")
        XCTAssertEqual(d.courses[2].displayCode, "—")
    }

    func testPlannerIdShape() {
        let id = PlannerID.make("c", now: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertTrue(id.hasPrefix("c-" + String(Int64(1_790_000_000_000), radix: 36)))
        XCTAssertEqual(id.count, 2 + String(Int64(1_790_000_000_000), radix: 36).count + 5)
    }
}
