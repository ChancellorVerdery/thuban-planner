import XCTest
@testable import ThubanPlannerCore

final class SummerAutomationTests: XCTestCase {
    let now = TestSupport.date("2026-10-05")   // fall 2026

    func term(_ code: String) -> BannerTerm {
        BannerTerm(code: code, description: TermKey.label(BannerTermCode.termKey(code)!))
    }

    /// Banner lists up to Spring 2027 (Summer 2027 not released); Summer 2026 ran MEGR 3116 and MATH 2164.
    func offerings(summer2027: [String: [String: Int]]? = nil) -> CourseOfferings {
        var o = CourseOfferings(terms: ["202710", "202680", "202660", "202610", "202580", "202560"].map(term), termsFetchedAt: now)
        func put(_ code: String, _ subjects: [String: [String: Int]]) {
            var entry = CourseOfferings.TermEntry(code: code, description: TermKey.label(BannerTermCode.termKey(code)!))
            for (s, sections) in subjects { entry.subjects[s] = .init(fetchedAt: now, sections: sections) }
            o.byTerm[code] = entry
        }
        put("202560", ["MEGR": ["3116": 1, "3114": 2], "MATH": ["2164": 1]])
        put("202660", ["MEGR": ["3116": 2], "MATH": ["2164": 1, "1241": 3]])
        if let summer2027 {
            o.terms.insert(term("202760"), at: 0)
            put("202760", summer2027)
        }
        return o
    }

    /// Recorded through Fall 2026 (current); to take: MEGR 3116 (summer box off), MEGR 3114 (box on), MATH 2164,
    /// PHIL 3527 (no data for PHIL; box on). Summer 2027 switched off by hand.
    func plan(philSummer: Bool = true) -> PlannerData {
        PlannerData(courses: [
            Course(id: "done", code: "MATH 1241", term: "fall-2026"),
            Course(id: "heat", code: "MEGR 3116", summerOk: false),
            Course(id: "fluids", code: "MEGR 3114", summerOk: true),
            Course(id: "linalg", code: "MATH 2164", summerOk: false),
            Course(id: "ethics", code: "PHIL 3527", summerOk: philSummer),
        ], terms: [Term(season: .fall, year: 2026, current: true)], disabledTerms: ["summer-2027"],
           settings: PlannerSettings(maxCredits: 6, summerMax: 6))
    }

    // MARK: Reference

    func testReferenceFallsBackToLatestReleasedSummer() {
        let o = offerings()
        let ref = SummerAutomation.reference(for: "summer-2027", offerings: o)
        XCTAssertEqual(ref, .init(termKey: "summer-2026", code: "202660", isOwnSchedule: false))
        XCTAssertEqual(SummerAutomation.reference(for: "summer-2028", offerings: o)?.termKey, "summer-2026")
        XCTAssertNil(SummerAutomation.reference(for: "fall-2027", offerings: o))
        XCTAssertNil(SummerAutomation.reference(for: "summer-2027", offerings: .empty))
    }

    func testReleasedSummerIsItsOwnReference() {
        let o = offerings(summer2027: ["MEGR": ["3114": 1]])
        XCTAssertEqual(SummerAutomation.reference(for: "summer-2027", offerings: o), .init(termKey: "summer-2027", code: "202760", isOwnSchedule: true))
        XCTAssertEqual(SummerAutomation.reference(for: "summer-2028", offerings: o)?.termKey, "summer-2027")
        // Listed but no sections yet (schedule not built) → still the fallback.
        let empty = offerings(summer2027: ["MEGR": [:]])
        XCTAssertEqual(SummerAutomation.reference(for: "summer-2027", offerings: empty)?.termKey, "summer-2026")
    }

    func testOfferedUsesEquivalentsAndKnowsWhenThereIsNoData() {
        var o = offerings()
        o.byTerm["202660"]?.subjects["PHYS"] = .init(fetchedAt: now, sections: ["1101L": 2])
        let ref = SummerAutomation.reference(for: "summer-2027", offerings: o)!
        XCTAssertEqual(SummerAutomation.offered("MEGR 3116", in: ref, offerings: o), true)
        XCTAssertEqual(SummerAutomation.offered("MEGR 3114", in: ref, offerings: o), false)
        XCTAssertEqual(SummerAutomation.offered("PHYS 2101L", in: ref, offerings: o), true, "PHYS 1101L is equivalent")
        XCTAssertNil(SummerAutomation.offered("PHIL 3527", in: ref, offerings: o))
    }

    // MARK: Decisions + effective plan

    func testEnablesSummerWhenARemainingClassRanThere() throws {
        let data = plan()
        let r = SummerAutomation.evaluate(data, offerings: offerings(), now: now, calendar: TestSupport.utc)
        let s27 = try XCTUnwrap(r.decision("summer-2027"))
        XCTAssertTrue(s27.enabled)
        XCTAssertEqual(s27.offered, ["MEGR 3116", "MATH 2164"])
        XCTAssertEqual(s27.byYourSetting, ["PHIL 3527"])
        XCTAssertEqual(s27.reason, "On — MEGR 3116, MATH 2164 offered in Summer 2026 (Summer 2027 schedule not released)")
        // Effective: the manual "off" is overridden, class availability follows the data, PHIL keeps its box.
        XCTAssertFalse(r.effective.disabledTerms.contains("summer-2027"))
        XCTAssertEqual(r.effective.course("heat")?.summerOk, true)
        XCTAssertEqual(r.effective.course("fluids")?.summerOk, false)
        XCTAssertEqual(r.effective.course("ethics")?.summerOk, true)
        XCTAssertEqual(r.summerOverrides, ["heat": true, "fluids": false, "linalg": true])
        // Stored plan untouched.
        XCTAssertEqual(data, plan())
        XCTAssertEqual(r.effective.courses.map(\.id), data.courses.map(\.id))
        XCTAssertEqual(r.effective.terms, data.terms)
        XCTAssertEqual(r.effective.settings, data.settings)
    }

    func testDisablesSummerWhenNothingRan() throws {
        var data = plan(philSummer: false)
        data.courses.removeAll { ["heat", "linalg"].contains($0.id) }
        data.disabledTerms = []
        let r = SummerAutomation.evaluate(data, offerings: offerings(), now: now, calendar: TestSupport.utc)
        let s27 = try XCTUnwrap(r.decision("summer-2027"))
        XCTAssertFalse(s27.enabled)
        XCTAssertEqual(s27.reason, "Off — none of your remaining classes ran in Summer 2026 (Summer 2027 schedule not released)")
        XCTAssertTrue(r.effective.disabledTerms.contains("summer-2027"))
        XCTAssertTrue(r.decisions.allSatisfy { !$0.enabled })
        // The route then has no summers.
        let s = Scheduler.scheduleDegree(r.effective, now: now, calendar: TestSupport.utc)
        XCTAssertFalse(s.plannedTerms.contains { $0.season == .summer })
    }

    func testRouteUsesTheSummerOnlyForOfferedClasses() {
        let data = plan()
        let r = SummerAutomation.evaluate(data, offerings: offerings(), now: now, calendar: TestSupport.utc)
        let s = Scheduler.scheduleDegree(r.effective, now: now, calendar: TestSupport.utc)
        let summer = s.board.first { $0.key == "summer-2027" }
        XCTAssertNotNil(summer)
        XCTAssertTrue(summer!.courseIds.allSatisfy { ["heat", "linalg", "ethics"].contains($0) }, "\(summer!.courseIds)")
        XCTAssertLessThanOrEqual(summer!.credits, 6, "the summer cap still applies")
        // Manual: the stored plan keeps Summer 2027 off.
        let manual = Scheduler.scheduleDegree(data, now: now, calendar: TestSupport.utc)
        XCTAssertNil(manual.board.first { $0.key == "summer-2027" })
    }

    func testNoOfferingsFallsBackToStoredValues() {
        let data = plan()
        let r = SummerAutomation.evaluate(data, offerings: .empty, now: now, calendar: TestSupport.utc)
        XCTAssertFalse(r.hasData)
        XCTAssertEqual(r.effective, data)
        XCTAssertEqual(r.decision("summer-2027")?.enabled, false)
        XCTAssertEqual(r.decision("summer-2028")?.enabled, true)
        XCTAssertEqual(r.decision("summer-2027")?.reason, "Off — no Banner schedule to check yet, so your setting is used")
        XCTAssertEqual(Scheduler.scheduleDegree(r.effective, now: now, calendar: TestSupport.utc),
                       Scheduler.scheduleDegree(data, now: now, calendar: TestSupport.utc))
    }

    /// Atlas documents never carry the mode (it lives in preferences.json), and with no offerings the effective plan
    /// is the document itself — so the scheduler input for Atlas data is unchanged.
    func testAtlasParityUnaffected() throws {
        let legacy = try AtlasImporter.document(fromFile: TestSupport.fixtureURL("atlas-legacy.json"))
        let data = try AtlasImporter.convert(legacy, source: "file:x", now: now, calendar: TestSupport.utc).data
        XCTAssertEqual(SummerAutomation.evaluate(data, offerings: .empty, now: now, calendar: TestSupport.utc).effective, data)
        let encoded = String(decoding: try JSONEncoder().encode(data), as: UTF8.self)
        XCTAssertFalse(encoded.contains("summerMode"))
    }

    func testPreferencesDefaultToAutomatic() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"textSize":"large"}"#.utf8))
        XCTAssertEqual(old.summerMode, .automatic)
        var p = Preferences()
        p.summerMode = .manual
        let back = try JSONDecoder().decode(Preferences.self, from: try JSONEncoder().encode(p))
        XCTAssertEqual(back.summerMode, .manual)
    }

    // MARK: Fetching

    func testFetchesHorizonSummersAndTheLatestPastSummerForRemainingSubjects() {
        let data = plan()
        XCTAssertEqual(SummerAutomation.subjects(data), ["MATH", "MEGR", "PHIL"])
        let summers = SummerAutomation.horizon(data, now: now, calendar: TestSupport.utc)
        XCTAssertEqual(summers.first, "summer-2027")
        // Not released: only Summer 2026 (finished, MATH / MEGR cached → only PHIL is missing).
        let pending = OfferingsFetcher.pendingSummers(offerings(), summers: summers, subjects: SummerAutomation.subjects(data),
                                                      now: now, calendar: TestSupport.utc)
        XCTAssertEqual(pending.map { "\($0.0.code) \($0.1)" }, ["202660 PHIL"])
        // Released: Summer 2027 too (newest first).
        let released = offerings(summer2027: [:])
        let terms = SummerAutomation.termsToFetch(released, summers: summers, now: now, calendar: TestSupport.utc)
        XCTAssertEqual(terms.map(\.code), ["202760", "202660"])
    }
}
