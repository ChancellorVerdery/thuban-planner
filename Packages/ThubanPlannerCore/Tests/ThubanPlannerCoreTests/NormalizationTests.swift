import XCTest
@testable import ThubanPlannerCore

/// `PlannerData(json:)` = Atlas `loadCourse()` + the backend mapper's `decompose()`. Ports
/// atlas-backend/test/course.test.mjs (every case, expressed on the typed result) and the preOrCo self-checks of
/// atlas-ui/tools/migrate-course-prereqs.mjs.
final class NormalizationTests: XCTestCase {
    func decode(_ json: String) throws -> PlannerData {
        try JSONFile.decoder.decode(PlannerData.self, from: Data(json.utf8))
    }

    // 1. Exactly what loadCourse() produces from empty localStorage.
    func testDefaultState() throws {
        let d = try decode(#"{"courses":[],"terms":[],"disabledTerms":[],"settings":{"maxCredits":15,"summerMax":9,"strategy":"soonest-summer"}}"#)
        XCTAssertEqual(d, PlannerData())
        XCTAssertEqual(d.settings, PlannerSettings(maxCredits: 15, summerMax: 9, strategy: .soonestSummer))
    }

    // 2. Rich edge-case state: empty strings, null term, unicode, fractional credits / year, numeric-string settings,
    //    orphan disabled keys (incl. "").
    func testRichEdgeCaseState() throws {
        let d = try decode(#"""
        {"courses":[
          {"id":"c-abc123","code":"","title":"数学 · Análisis 𝕀 — \"quotes\" & <tags>","credits":0,"prereqs":[],"coreqs":[],"summerOk":false,"term":null},
          {"id":"c-def456","code":"MATH 201","title":"","credits":1.5,"prereqs":["MATH 101","φυσική-100"],"coreqs":["MATH 201L","STAT 200"],"summerOk":true,"term":"fall-2025"}],
         "terms":[{"key":"spring-2025.5","season":"spring","year":2025.5,"current":true},{"key":"fall-2025","season":"fall","year":2025,"current":false}],
         "disabledTerms":["summer-2026","summer-2028",""],
         "settings":{"maxCredits":"18","summerMax":"6","strategy":"even"}}
        """#)
        XCTAssertEqual(d.courses, [
            Course(id: "c-abc123", code: "", title: "数学 · Análisis 𝕀 — \"quotes\" & <tags>", credits: 0),
            Course(id: "c-def456", code: "MATH 201", title: "", credits: 1.5, prereqs: ["MATH 101", "φυσική-100"],
                   coreqs: ["MATH 201L", "STAT 200"], summerOk: true, term: "fall-2025"),
        ])
        // spring-2025.5 ranks 6076.5 < fall-2025 = 6077.
        XCTAssertEqual(d.terms.map(\.key), ["spring-2025.5", "fall-2025"])
        XCTAssertEqual(d.terms.map(\.current), [true, false])
        XCTAssertEqual(d.terms[0].label, "Spring 2025.5")
        XCTAssertEqual(d.disabledTerms, ["summer-2026", "summer-2028", ""])
        // Numeric strings are kept as their numbers (Atlas keeps the string; every use coerces it).
        XCTAssertEqual(d.settings, PlannerSettings(maxCredits: 18, summerMax: 6, strategy: .even))
    }

    // 3. Realistic state survives unchanged, and re-encodes to the same value.
    func testRealisticStateRoundTrips() throws {
        let json = #"""
        {"courses":[
          {"id":"c-m1a2b3c4d","code":"CS 101","title":"Intro to Programming","credits":3,"prereqs":[],"coreqs":[],"summerOk":true,"term":"fall-2024"},
          {"id":"c-m1a2b3c4e","code":"CS 201","title":"Data Structures","credits":4,"prereqs":["CS 101"],"coreqs":[],"summerOk":false,"term":"spring-2025"},
          {"id":"c-m1a2b3c4f","code":"CS 301","title":"Algorithms","credits":3,"prereqs":["CS 201"],"coreqs":[],"summerOk":false,"term":null},
          {"id":"c-m1a2b3c4g","code":"CS 301L","title":"Algorithms Lab","credits":1,"prereqs":[],"coreqs":["CS 301"],"summerOk":false,"term":null},
          {"id":"c-m1a2b3c4h","code":"PHYS 150","title":"Mechanics","credits":4,"prereqs":[],"coreqs":["MATH 140"],"summerOk":true,"term":null},
          {"id":"c-m1a2b3c4i","code":"MATH 140","title":"Calculus I","credits":4,"prereqs":[],"coreqs":[],"summerOk":true,"term":"fall-2024"}],
         "terms":[{"key":"fall-2024","season":"fall","year":2024,"current":false},{"key":"spring-2025","season":"spring","year":2025,"current":false},
                  {"key":"fall-2025","season":"fall","year":2025,"current":true}],
         "disabledTerms":["summer-2026"],
         "settings":{"maxCredits":16,"summerMax":7,"strategy":"soonest-optional-summer"}}
        """#
        let d = try decode(json)
        XCTAssertEqual(d.courses.count, 6)
        XCTAssertEqual(d.courses[3].coreqs, ["CS 301"])
        XCTAssertEqual(d.currentTerm?.key, "fall-2025")
        XCTAssertEqual(d.settings.strategy, .soonestOptionalSummer)
        let again = try JSONFile.decoder.decode(PlannerData.self, from: try JSONFile.encoder.encode(d))
        XCTAssertEqual(again, d)
        XCTAssertEqual(d.normalized(), d, "normalize() is a no-op on a loaded document")
    }

    // 4. Renderer-seed blob: courses only, missing fields, id-less row, duplicate ids, coercions.
    func testRendererSeedBlob() throws {
        let d = try decode(#"""
        {"courses":[{"id":"c-x","code":"CS 101"},{"code":"NO-ID","title":"dropped by loader"},{"id":"c-x","code":"CS 101"},
          {"id":"c-y","code":" MATH 2 ","title":42,"credits":"4","prereqs":["CS 101","",3],"summerOk":1,"term":""}]}
        """#)
        XCTAssertEqual(d.courses, [
            Course(id: "c-x", code: "CS 101", title: "", credits: 3),
            Course(id: "c-x", code: "CS 101", title: "", credits: 3),
            Course(id: "c-y", code: "MATH 2", title: "42", credits: 4, prereqs: ["CS 101", "3"], summerOk: true, term: nil),
        ])
        XCTAssertEqual(d.terms, [])
        XCTAssertEqual(d.disabledTerms, [])
        XCTAssertEqual(d.settings, .default)
    }

    // 5. Totally empty blob → defaults; so do garbage documents.
    func testEmptyBlob() throws {
        XCTAssertEqual(try decode("{}"), PlannerData())
        XCTAssertEqual(try decode("[]"), PlannerData())
        XCTAssertEqual(try decode(#"{"courses":"nope","terms":7,"settings":[1]}"#), PlannerData())
    }

    // 6. Legacy terms: duplicate keys, several currents, invalid entries, stale keys, non-string disabled terms.
    func testLegacyTermsDedupeAndSingleCurrent() throws {
        let d = try decode(#"""
        {"courses":[],"terms":[
          {"season":"fall","year":2025,"current":true},
          {"season":"fall","year":"2025","current":true},
          {"key":"stale-key","season":"spring","year":2026,"current":true},
          {"season":"winter","year":2026},
          {"season":"summer","year":"soon"},
          "garbage"],
         "disabledTerms":["summer-2026",42,null],
         "settings":{"maxCredits":16,"summerMax":6,"strategy":"even"}}
        """#)
        XCTAssertEqual(d.terms, [Term(season: .fall, year: 2025, current: false), Term(season: .spring, year: 2026, current: true)])
        XCTAssertEqual(d.disabledTerms, ["summer-2026"])
    }

    // 7. Unsorted loader-valid terms come back in rank order.
    func testTermsSortedByRank() throws {
        let d = try decode(#"{"terms":[{"key":"fall-2025","season":"fall","year":2025,"current":true},{"key":"spring-2024","season":"spring","year":2024,"current":false}]}"#)
        XCTAssertEqual(d.terms.map(\.key), ["spring-2024", "fall-2025"])
    }

    // MARK: Settings coercion (loadCourse lines 65-69)

    func testSettingsDefaults() throws {
        func settings(_ json: String) throws -> PlannerSettings { try decode(#"{"settings":\#(json)}"#).settings }
        XCTAssertEqual(try settings(#"{"maxCredits":0}"#).maxCredits, 15)
        XCTAssertEqual(try settings(#"{"maxCredits":-3}"#).maxCredits, 15)
        XCTAssertEqual(try settings(#"{"maxCredits":"abc"}"#).maxCredits, 15)
        XCTAssertEqual(try settings(#"{"maxCredits":null}"#).maxCredits, 15)
        XCTAssertEqual(try settings(#"{"maxCredits":""}"#).maxCredits, 15)
        XCTAssertEqual(try settings(#"{"maxCredits":true}"#).maxCredits, 1, "Number(true) = 1 and true <= 0 is false")
        XCTAssertEqual(try settings(#"{"maxCredits":6}"#).summerMax, 6, "summer default = min(9, max)")
        XCTAssertEqual(try settings(#"{"maxCredits":"12"}"#).summerMax, 9)
        XCTAssertEqual(try settings(#"{"summerMax":0}"#).summerMax, 0, "0 is a valid summer cap")
        XCTAssertEqual(try settings(#"{"summerMax":-1}"#).summerMax, 9)
        XCTAssertEqual(try settings(#"{"summerMax":" 4 "}"#).summerMax, 4)
        XCTAssertEqual(try settings(#"{"strategy":"fastest"}"#).strategy, .soonestSummer)
        XCTAssertEqual(try settings(#""not an object""#), .default)
    }

    // MARK: Course coercion

    func testCourseFieldCoercion() throws {
        let d = try decode(#"""
        {"courses":[
          {"id":7,"code":0,"title":false,"credits":null,"prereqs":[null,true,{"a":1},["x","y"]],"summerOk":"0","term":5},
          {"id":"a","credits":"0x10","summerOk":[]},
          {"id":"b","credits":-1,"summerOk":0},
          {"id":"c","credits":"1e1"},
          {"id":"d","credits":"12 credits"},
          {"id":0,"code":"dropped: falsy id"},
          {"id":"","code":"dropped: empty id"},
          null, 3]}
        """#)
        XCTAssertEqual(d.courses.map(\.id), ["7", "a", "b", "c", "d"])
        let c = d.courses[0]
        XCTAssertEqual(c.code, "", "a falsy code becomes ''")
        XCTAssertEqual(c.title, "")
        XCTAssertEqual(c.credits, 0, "Number(null) = 0 is a valid credit count")
        XCTAssertEqual(c.prereqs, ["null", "true", "[object Object]", "x,y"], "String(x) of each element")
        XCTAssertTrue(c.summerOk, "'0' is a non-empty string → truthy")
        XCTAssertNil(c.term, "a non-string term is 'to take'")
        XCTAssertEqual(d.courses[1].credits, 16)
        XCTAssertTrue(d.courses[1].summerOk, "[] is truthy")
        XCTAssertEqual(d.courses[2].credits, 3, "negative credits → 3")
        XCTAssertFalse(d.courses[2].summerOk)
        XCTAssertEqual(d.courses[3].credits, 10)
        XCTAssertEqual(d.courses[4].credits, 3, "'12 credits' is NaN → 3")
    }

    func testTermIsNotTrimmedAndEmptyTermIsToTake() throws {
        let d = try decode(#"{"courses":[{"id":"a","term":" fall-2025"},{"id":"b","term":""}]}"#)
        XCTAssertEqual(d.courses[0].term, " fall-2025")
        XCTAssertNil(d.courses[1].term)
    }

    // MARK: preOrCo → coreqs (decompose + migrate-course-prereqs self-check)

    func testPreOrCoOnlyBecomesCoreqs() throws {
        let d = try decode(#"{"courses":[{"id":"c1","code":"MATH2","preOrCo":["MATH1"]}]}"#)
        XCTAssertEqual(d.courses[0].coreqs, ["MATH1"])
    }

    func testPreOrCoFoldsAfterCoreqsDeduplicatedExactly() throws {
        let d = try decode(#"{"courses":[{"id":"c2","coreqs":["CS101","CS102","CS101"],"preOrCo":["cs102","CS103","CS102"]}]}"#)
        // decompose's uniq is exact-text (the migrate tool's is case-insensitive; the DB holds decompose's result).
        // Both spellings resolve to the same class, so the route is the same either way.
        XCTAssertEqual(d.courses[0].coreqs, ["CS101", "CS102", "cs102", "CS103"])
    }

    func testEmptyPreOrCoLeavesCoreqs() throws {
        let d = try decode(#"{"courses":[{"id":"c4","coreqs":["A"],"preOrCo":[]}]}"#)
        XCTAssertEqual(d.courses[0].coreqs, ["A"])
    }

    func testUnrelatedFieldsSurviveTheFold() throws {
        let d = try decode(#"{"courses":[{"id":"c5","code":"ENGR301","title":"Statics","credits":3,"prereqs":["PHYS250"],"coreqs":["MATH241"],"preOrCo":["MATH241","MATH242"],"summerOk":true,"term":null}]}"#)
        XCTAssertEqual(d.courses[0], Course(id: "c5", code: "ENGR301", title: "Statics", credits: 3, prereqs: ["PHYS250"],
                                            coreqs: ["MATH241", "MATH242"], summerOk: true, term: nil))
    }

    // MARK: Typed normalize()

    func testNormalizeMatchesTheLoaderOnTypedValues() {
        var d = PlannerData(
            courses: [Course(id: "a", code: "  X ", title: " t ", credits: -2, prereqs: [" A ", ""], coreqs: ["", "B "], term: "")],
            terms: [Term(season: .fall, year: 2025, current: true), Term(season: .spring, year: 2025, current: true),
                    Term(season: .fall, year: 2025), Term(season: .summer, year: .nan)],
            settings: PlannerSettings(maxCredits: 0, summerMax: -1, strategy: .even))
        d.normalize()
        XCTAssertEqual(d.courses[0], Course(id: "a", code: "X", title: "t", credits: 3, prereqs: ["A"], coreqs: ["B"], term: nil))
        XCTAssertEqual(d.terms, [Term(season: .spring, year: 2025, current: false), Term(season: .fall, year: 2025, current: true)])
        XCTAssertEqual(d.settings, PlannerSettings(maxCredits: 15, summerMax: 9, strategy: .even))
    }

    func testProvenanceRoundTrips() throws {
        var d = PlannerData(courses: [Course(id: "a", code: "A")])
        d.importedAt = Date(timeIntervalSince1970: 1_790_000_000)
        d.importSource = "atlas:beelink"
        let back = try JSONFile.decoder.decode(PlannerData.self, from: try JSONFile.encoder.encode(d))
        XCTAssertEqual(back, d)
    }
}
