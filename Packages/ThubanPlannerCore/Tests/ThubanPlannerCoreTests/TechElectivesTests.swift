import Foundation
import XCTest
@testable import ThubanPlannerCore

final class CatalogDatasetTests: XCTestCase {
    func testBundledDatasetMatchesCatalogAndDegreeWorks() throws {
        let d = try XCTUnwrap(CatalogDataset.bsme2025)
        XCTAssertEqual(d.program.catalogYear, "2025-2026")
        XCTAssertEqual(d.program.techElectives.count, 4)
        XCTAssertEqual(d.program.techElectives.minimumMEGR, 3)
        XCTAssertEqual(d.program.techElectives.credits, 12)
        XCTAssertEqual(d.electives.count, 76)
        XCTAssertEqual(d.electives.filter(\.inCatalog).count, 68)
        XCTAssertEqual(d.electives.filter(\.inDegreeWorks).count, 75)
        XCTAssertEqual(d.electives.filter { $0.inCatalog && !$0.inDegreeWorks }.map(\.code), ["MEGR 3221"])
        XCTAssertEqual(Set(d.electives.filter { !$0.inCatalog }.map(\.code)),
                       ["MEGR 3222", "MEGR 3243", "MEGR 3280", "MEGR 4212", "MEGR 4213", "MEGR 4281", "MEGR 4282", "MEGR 4313"])
        XCTAssertNotNil(d.electives.first { $0.code == "MEGR 3221" }?.condition)
        // Codes DegreeWorks lists that only the 2026-27 catalog has; two are in neither.
        XCTAssertEqual(d.course("MEGR 4313")?.catalogYear, "2026-2027")
        XCTAssertNil(d.course("MEGR 3222"))
        XCTAssertNil(d.course("MEGR 3243"))
        XCTAssertEqual(d.electiveSubjects, ["MEGR", "PHYS", "BIOL", "MATH"])
        XCTAssertEqual(d.course("phys4242")?.title, "Quantum Mechanics II")
    }

    /// The Swift parser and tools/catalog/reqparse.py must agree on every requirement line in the dataset.
    func testSwiftParserAgreesWithDatasetGroups() throws {
        let d = try XCTUnwrap(CatalogDataset.bsme2025)
        var checked = 0
        for course in d.courses.values {
            XCTAssertEqual(CatalogRequirementParser.parse(course.prereqText).groups, course.prereqGroups, "\(course.code) prereq: \(course.prereqText ?? "")")
            XCTAssertEqual(CatalogRequirementParser.parse(course.coreqText).groups, course.coreqGroups, "\(course.code) coreq")
            XCTAssertEqual(CatalogRequirementParser.parse(course.preOrCoreqText).groups, course.preOrCoreqGroups, "\(course.code) pre/co")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 140)
    }

    func testRequirementParser() {
        func p(_ s: String) -> [[String]] { CatalogRequirementParser.parse(s).groups }
        XCTAssertEqual(p("MATH 2171, MEGR 2144, and either MEGR 2240 or MEGR 2242 with grades of C or above"),
                       [["MATH 2171"], ["MEGR 2144"], ["MEGR 2240", "MEGR 2242"]])
        XCTAssertEqual(p("PHYS 3220 or MATH 2241; PHYS 3121 or MEGR 2144; PHYS 3141; and MATH 2171 or PHYS 3101; all with grades of C or above."),
                       [["PHYS 3220", "MATH 2241"], ["PHYS 3121", "MEGR 2144"], ["PHYS 3141"], ["MATH 2171", "PHYS 3101"]])
        XCTAssertEqual(p("MEGR 2144 and (MEGR 3171L or MEGR 3174)"), [["MEGR 2144"], ["MEGR 3171L", "MEGR 3174"]])
        XCTAssertEqual(p("MEGR 3112, 3114, and 3116"), [["MEGR 3112"], ["MEGR 3114"], ["MEGR 3116"]])
        XCTAssertEqual(p("(MEGR 1000 and MEGR 1001) or MEGR 2000"), [["MEGR 1000", "MEGR 2000"], ["MEGR 1001", "MEGR 2000"]])
        XCTAssertEqual(p("MEGR 2141, MEGR 2144, or MEGR 2160"), [["MEGR 2141", "MEGR 2144", "MEGR 2160"]])
        let waiver = CatalogRequirementParser.parse("BIOL 1110  or BIOL 2120 with grade of C or above, or permission of department.")
        XCTAssertEqual(waiver.groups, [["BIOL 1110", "BIOL 2120"]])
        XCTAssertEqual(waiver.notes, ["with grade of C or above", "or permission of department"])
        let aside = CatalogRequirementParser.parse("MEGR 3121 (Optional for PHYS/MEGR dual majors in place of PHYS 3101 prerequisite)")
        XCTAssertEqual(aside.groups, [["MEGR 3121"]])
        XCTAssertEqual(aside.notes.count, 1)
        XCTAssertEqual(p("Junior standing"), [])
        XCTAssertEqual(p(""), [])
    }

    func testCourseCodesAndEquivalents() {
        XCTAssertEqual(CourseCode.normalize("megr3090"), "MEGR 3090")
        XCTAssertEqual(CourseCode.normalize(" PHYS  2101l "), "PHYS 2101L")
        XCTAssertEqual(CourseCode.equivalentCodes("phys 2101L"), ["PHYS 2101L", "PHYS 1101L"])
        XCTAssertEqual(CourseCode.equivalentCodes("PHYS 1101L"), ["PHYS 1101L", "PHYS 2101L"])
        XCTAssertEqual(CourseCode.equivalentCodes("MEGR 3122"), ["MEGR 3122", "MEGR 3123"])
        let index = PlanCourseIndex(BSMESampleData.make())
        XCTAssertEqual(index.find("PHYS 2101L")?.code, "PHYS 1101L")
        XCTAssertEqual(index.find("math2241")?.code, "MATH 2241")
    }
}

final class TechElectivesTests: XCTestCase {
    var dataset: CatalogDataset { CatalogDataset.bsme2025! }
    let now = TestSupport.date("2026-10-05")

    /// The user's example: Quantum II ← Quantum I ← Modern Physics ← Physics II. With MATH 2241, MEGR 2144, MATH 2171,
    /// PHYS 2102 and MATH 1241 / 1242 in the plan, exactly PHYS 3141 and PHYS 4241 are missing.
    func testPhysicsQuantumChain() throws {
        let data = BSMESampleData.make()
        let plan = RequirementChainResolver(dataset: dataset, data: data).resolve(["PHYS 4242"])
        XCTAssertEqual(plan.additions.map(\.code), ["PHYS 3141", "PHYS 4241", "PHYS 4242"])
        XCTAssertEqual(plan.prerequisiteAdditions.count, 2)
        XCTAssertEqual(plan.credits, 9)
        XCTAssertTrue(plan.warnings.isEmpty, "\(plan.warnings)")
        let root = try XCTUnwrap(plan.roots.first)
        XCTAssertEqual(root.state, .add)
        let q1 = try XCTUnwrap(root.children.first)
        XCTAssertEqual(q1.code, "PHYS 4241")
        XCTAssertEqual(q1.children.map(\.code), ["MATH 2241", "MEGR 2144", "PHYS 3141", "MATH 2171"])
        XCTAssertEqual(q1.children[0].alternatives, ["PHYS 3220", "MATH 2241"])
        XCTAssertEqual(q1.children[0].state, .inPlan(code: "MATH 2241", term: "fall-2026"))
        XCTAssertEqual(q1.children[1].state, .inPlan(code: "MEGR 2144", term: nil))
        let modern = q1.children[2]
        XCTAssertEqual(modern.state, .add)
        XCTAssertEqual(modern.children.map(\.code), ["PHYS 2102", "MATH 1241", "MATH 1242"])
        XCTAssertEqual(modern.children.last?.kind, .coreq)
        // Requirements are concrete plan codes, so the scheduler orders them.
        let q1Addition = try XCTUnwrap(plan.additions.first { $0.code == "PHYS 4241" })
        XCTAssertEqual(q1Addition.prereqs, ["MATH 2241", "MEGR 2144", "PHYS 3141", "MATH 2171"])
        XCTAssertEqual(plan.additions.first { $0.code == "PHYS 3141" }?.coreqs, ["MATH 1242"])
        XCTAssertEqual(plan.additions.last?.prereqs, ["PHYS 4241"])
        // Nothing to choose: every OR-group already has an option in the plan.
        XCTAssertTrue(plan.choices.isEmpty)
    }

    /// Without the math and mechanics classes, the OR-groups become choices with the cheapest option picked and the
    /// alternatives exposed; switching an option changes what is added.
    func testChoicesPickShortestChainAndCanBeSwitched() throws {
        var data = BSMESampleData.make()
        data.courses.removeAll { ["MATH 2241", "MEGR 2144", "MATH 2171", "MEGR 2141"].contains($0.code) }
        let resolver = RequirementChainResolver(dataset: dataset, data: data)
        let plan = resolver.resolve(["PHYS 4242"])
        let group = try XCTUnwrap(plan.choices.first { $0.key == "PHYS 4241#p0" })
        XCTAssertEqual(group.options, ["PHYS 3220", "MATH 2241"])
        XCTAssertEqual(group.chosen, "MATH 2241", "MATH 2241 needs only itself; PHYS 3220 needs PHYS 3101 and MATH 2241")
        XCTAssertTrue(plan.additions.contains { $0.code == "MATH 2241" })
        let switched = resolver.resolve(["PHYS 4242"], choices: ["PHYS 4241#p0": "PHYS 3220"])
        XCTAssertTrue(switched.additions.contains { $0.code == "PHYS 3220" })
        XCTAssertTrue(switched.additions.contains { $0.code == "PHYS 3101" })
        // Prerequisites always precede the classes that need them.
        for (i, a) in switched.additions.enumerated() {
            for ref in a.prereqs + a.coreqs {
                if let j = switched.additions.firstIndex(where: { $0.code == ref }) { XCTAssertLessThan(j, i, "\(ref) before \(a.code)") }
            }
        }
        // An unknown choice falls back to the default.
        XCTAssertEqual(resolver.resolve(["PHYS 4242"], choices: ["PHYS 4241#p0": "ART 1000"]).additions, plan.additions)
    }

    func testDedupeCyclesUnknownAndCoreqLoops() throws {
        func c(_ code: String, pre: [[String]] = [], co: [[String]] = []) -> CatalogDataset.Course {
            CatalogDataset.Course(code: code, title: code, credits: 3, prereqGroups: pre, coreqGroups: co)
        }
        let rule = CatalogDataset.TechElectiveRule(label: "TE", count: 2, credits: 6, minimumMEGR: 1, rule: "", degreeWorks: nil)
        let program = CatalogDataset.Program(id: "t", name: "Test", catalogTitle: nil, school: "UNCC", catalogYear: "2025-2026",
                                             catalogURL: "", techElectives: rule, core: [])
        let courses = [c("AAAA 4000", pre: [["AAAA 3000"]]), c("BBBB 4000", pre: [["AAAA 3000"], ["ZZZZ 9999"]]),
                       c("AAAA 3000"), c("CYCL 1000", pre: [["CYCL 2000"]]), c("CYCL 2000", pre: [["CYCL 1000"]]),
                       c("LECT 3000", co: [["LECT 3000L"]]), c("LECT 3000L", co: [["LECT 3000"]])]
        let dataset = CatalogDataset(program: program, electives: [], courses: Dictionary(uniqueKeysWithValues: courses.map { ($0.code, $0) }))
        let resolver = RequirementChainResolver(dataset: dataset, data: PlannerData())
        let both = resolver.resolve(["AAAA 4000", "BBBB 4000"])
        XCTAssertEqual(both.additions.map(\.code), ["AAAA 3000", "AAAA 4000", "ZZZZ 9999", "BBBB 4000"])
        XCTAssertEqual(both.additions[0].requiredFor, ["AAAA 4000", "BBBB 4000"])
        XCTAssertFalse(both.additions[2].inCatalog)
        XCTAssertTrue(both.warnings.contains { $0.contains("ZZZZ 9999") })
        XCTAssertEqual(both.roots[1].children[0].state, .addedAbove)
        let cycle = resolver.resolve(["CYCL 1000"])
        XCTAssertTrue(cycle.warnings.contains { $0.hasPrefix("Requirement cycle") }, "\(cycle.warnings)")
        XCTAssertEqual(Set(cycle.additions.map(\.code)), ["CYCL 1000", "CYCL 2000"])
        let lab = resolver.resolve(["LECT 3000"])
        XCTAssertTrue(lab.warnings.isEmpty)
        XCTAssertEqual(Set(lab.additions.map(\.code)), ["LECT 3000", "LECT 3000L"])
        XCTAssertEqual(lab.additions.first { $0.code == "LECT 3000" }?.coreqs, ["LECT 3000L"])
    }

    func testApplyTagsNeverTouchesExistingAndIsIdempotent() throws {
        var data = BSMESampleData.make()
        let before = data.courses
        let plan = RequirementChainResolver(dataset: dataset, data: data).resolve(["PHYS 4242"])
        var n = 0
        let ids = TechElectives.apply(plan, to: &data) { n += 1; return "c-new-\(n)" }
        XCTAssertEqual(ids, ["c-new-1", "c-new-2", "c-new-3"])
        XCTAssertEqual(Array(data.courses.prefix(before.count)), before)
        let added = Array(data.courses.dropFirst(before.count))
        XCTAssertEqual(added.map(\.code), ["PHYS 3141", "PHYS 4241", "PHYS 4242"])
        XCTAssertTrue(added.allSatisfy { $0.term == nil })
        XCTAssertEqual(added[2].tags, ["tech-elective"])
        XCTAssertEqual(added[0].tags, ["prereq:PHYS 4242"])
        // Scheduler: the chain lands in order, later than its prerequisites.
        let schedule = Scheduler.scheduleDegree(data, now: now, calendar: TestSupport.utc)
        XCTAssertTrue(schedule.unplaceable.isEmpty)
        func rank(_ id: String) -> Double { TermKey.rank(schedule.board.first { $0.courseIds.contains(id) }!.key) }
        XCTAssertLessThan(rank("c-new-1"), rank("c-new-2"))
        XCTAssertLessThan(rank("c-new-2"), rank("c-new-3"))
        // Again: nothing more to add.
        let again = RequirementChainResolver(dataset: dataset, data: data).resolve(["PHYS 4242"])
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(TechElectives.apply(again, to: &data), [])
        // Removal offers the two prerequisites added only for it.
        let removal = TechElectives.removal(of: "PHYS 4242", data: data)
        XCTAssertEqual(removal.elective?.id, "c-new-3")
        XCTAssertEqual(Set(removal.prerequisites.map(\.code)), ["PHYS 3141", "PHYS 4241"])
    }

    func testRemovalKeepsSharedPrerequisites() throws {
        var data = BSMESampleData.make()
        let resolver = { RequirementChainResolver(dataset: self.dataset, data: data) }
        TechElectives.apply(resolver().resolve(["PHYS 4242"]), to: &data)
        // PHYS 4110 also needs PHYS 3141 (already added for PHYS 4242) — it stays when PHYS 4242 goes.
        TechElectives.apply(resolver().resolve(["PHYS 4110"]), to: &data)
        let removal = TechElectives.removal(of: "PHYS 4242", data: data)
        XCTAssertEqual(removal.prerequisites.map(\.code), ["PHYS 4241"])
        // A taken elective is never offered for removal.
        XCTAssertNil(TechElectives.removal(of: "MATH 2241", data: data).elective)
    }

    func testTagsAreOptionalAndInvisibleToAtlasData() throws {
        let plain = Course(id: "c-1", code: "MEGR 2144")
        let encoded = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(encoded.contains("tags"))
        let json = #"{"courses":[{"id":"a","code":"X 1","tags":["tech-elective"," ","tech-elective"]},{"id":"b","code":"X 2","tags":"oops"},{"id":"c","code":"X 3","tags":[]}]}"#
        let data = try JSONDecoder().decode(PlannerData.self, from: Data(json.utf8))
        XCTAssertEqual(data.courses.map(\.tags), [["tech-elective"], nil, nil])
        var tagged = data
        tagged.courses[2].tags = []
        tagged.normalize()
        XCTAssertNil(tagged.courses[2].tags)
        // Round trip.
        let back = try JSONDecoder().decode(PlannerData.self, from: try JSONEncoder().encode(data))
        XCTAssertEqual(back.courses.map(\.tags), [["tech-elective"], nil, nil])
    }

    func testStatusesProgressAndOfferings() throws {
        let offerings = try XCTUnwrap(CourseOfferings.bundledSnapshot)
        let window = offerings.window(now: now, calendar: TestSupport.utc)
        XCTAssertEqual(window.past.compactMap(\.termKey), ["fall-2026", "summer-2026", "spring-2026", "fall-2025", "summer-2025", "spring-2025"])
        XCTAssertEqual(window.upcoming.compactMap(\.termKey), ["spring-2027"])
        var data = BSMESampleData.make()
        let statuses = TechElectives.statuses(dataset: dataset, data: data, offerings: offerings, window: window)
        XCTAssertEqual(statuses.count, 76)
        let q2 = try XCTUnwrap(statuses.first { $0.code == "PHYS 4242" })
        XCTAssertTrue(q2.isOffered)
        XCTAssertEqual(q2.offering.past, ["spring-2026", "spring-2025"])
        XCTAssertEqual(q2.offering.upcoming, ["spring-2027"])
        XCTAssertEqual(q2.readiness, .needs(count: 2, chain: ["PHYS 4241", "PHYS 3141"]))
        XCTAssertEqual(q2.missing, ["PHYS 3141", "PHYS 4241"])
        XCTAssertFalse(try XCTUnwrap(statuses.first { $0.code == "MEGR 3162" }).isOffered)
        XCTAssertEqual(try XCTUnwrap(statuses.first { $0.code == "MEGR 3225" }).readiness, .ready)
        // MEGR 3237 names only the old MEGR 3122; the plan's MEGR 3123 satisfies it (catalog-documented pair).
        XCTAssertEqual(try XCTUnwrap(statuses.first { $0.code == "MEGR 3237" }).readiness, .ready)
        // MEGR 3221 is the design elective here, so it does not count as a technical elective (MEGR 3216 isn't planned).
        let design = try XCTUnwrap(statuses.first { $0.code == "MEGR 3221" })
        XCTAssertEqual(design.planState, .planned)
        XCTAssertFalse(design.counts)
        XCTAssertEqual(TechElectives.progress(dataset: dataset, data: data).text, "0 of 4 chosen · 0 of 3 MEGR")
        let resolver = { RequirementChainResolver(dataset: self.dataset, data: data) }
        TechElectives.apply(resolver().resolve(["PHYS 4242"]), to: &data)
        TechElectives.apply(resolver().resolve(["MEGR 3225"]), to: &data)
        var progress = TechElectives.progress(dataset: dataset, data: data)
        XCTAssertEqual(progress.text, "2 of 4 chosen · 1 of 3 MEGR")
        XCTAssertFalse(progress.isComplete)
        TechElectives.apply(resolver().resolve(["MEGR 4242", "MEGR 3282"]), to: &data)
        progress = TechElectives.progress(dataset: dataset, data: data)
        XCTAssertEqual(progress.chosen.count, 4)
        XCTAssertEqual(progress.megr, 3)
        XCTAssertTrue(progress.isComplete)
        data.courses.append(Course(id: "c-3216", code: "MEGR 3216", title: "Thermal/Fluid Design"))
        XCTAssertEqual(TechElectives.progress(dataset: dataset, data: data).chosen.count, 5, "MEGR 3221 counts once MEGR 3216 is the design elective")
    }

    func testOfferingsWindowAndFreshness() {
        let terms = ["202710", "202680", "202660", "202610", "202580", "202560", "202510", "202480"].map {
            BannerTerm(code: $0, description: TermKey.label(BannerTermCode.termKey($0)!))
        }
        let w = CourseOfferings.window(terms: terms, now: now, calendar: TestSupport.utc)
        XCTAssertEqual(w.past.map(\.code), ["202680", "202660", "202610", "202580", "202560", "202510"])
        XCTAssertEqual(w.upcoming.map(\.code), ["202710"])
        var o = CourseOfferings(terms: terms, termsFetchedAt: now)
        XCTAssertTrue(o.needsFetch(term: terms[3], subject: "MEGR", now: now, calendar: TestSupport.utc))
        let section = BannerSection(crn: "1", term: "202610", subject: "MEGR", courseNumber: "3225", sequenceNumber: "001", title: "FEA", meetings: [])
        o.store(term: terms[3], subject: "MEGR", sections: [section, section], now: now)
        XCTAssertEqual(o.byTerm["202610"]?.subjects["MEGR"]?.sections["3225"], 2)
        // A finished term is never refetched; the current / upcoming ones after a week.
        XCTAssertFalse(o.needsFetch(term: terms[3], subject: "MEGR", now: now.addingTimeInterval(400 * 86400), calendar: TestSupport.utc))
        o.store(term: terms[1], subject: "MEGR", sections: [], now: now)
        XCTAssertFalse(o.needsFetch(term: terms[1], subject: "MEGR", now: now.addingTimeInterval(6 * 86400), calendar: TestSupport.utc))
        XCTAssertTrue(o.needsFetch(term: terms[1], subject: "MEGR", now: now.addingTimeInterval(8 * 86400), calendar: TestSupport.utc))
        let s = o.summary(for: "MEGR 3225", window: w)
        XCTAssertEqual(s.past, ["spring-2026"])
        XCTAssertTrue(s.known)
        XCTAssertFalse(o.summary(for: "PHYS 4242", window: w).known)
    }

    /// One subject search per subject per term; a second run the same day sends no searches; every request is a
    /// guarded read.
    func testFetcherMakesOneSearchPerSubjectPerTerm() async throws {
        let transport = FakeBannerTransport { request in
            let path = request.url!.path
            if path.hasSuffix("term/termSelection") {
                return (Data(#"<html><head><meta name="synchronizerToken" content="tok"/></head></html>"#.utf8), 200, nil)
            }
            if path.hasSuffix("term/search") { return (Data(#"{"fwdURL":"/x"}"#.utf8), 200, nil) }
            if path.hasSuffix("resetDataForm") { return (Data("true".utf8), 200, nil) }
            if path.hasSuffix("getTerms") { return ((try? TestSupport.fixture("banner/getTerms.json")) ?? Data(), 200, nil) }
            if path.hasSuffix("searchResults/searchResults") {
                let megr = request.url!.query?.contains("txt_subject=MEGR") == true
                return ((try? TestSupport.fixture(megr ? "banner/searchResults-MEGR2144.json" : "banner/searchResults-PHYS-202680.json")) ?? Data(), 200, nil)
            }
            return (Data(), 404, nil)
        }
        let fetcher = OfferingsFetcher(client: BannerClient(transport: transport, uniqueSessionId: "t"), pause: 0)
        let first = try await fetcher.refresh(.empty, subjects: ["PHYS", "MEGR"], now: now, calendar: TestSupport.utc)
        let window = first.window(now: now, calendar: TestSupport.utc)
        let searches = transport.requests.filter { $0.url!.path.hasSuffix("searchResults/searchResults") }
        XCTAssertEqual(searches.count, window.all.count * 2)
        XCTAssertTrue(searches.allSatisfy { req in
            let q = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!.queryItems!
            return q.first { $0.name == "pageMaxSize" }?.value == "500" && q.first { $0.name == "txt_courseNumber" } == nil
        })
        for request in transport.requests {
            XCTAssertTrue(BannerRequestGuard.check(method: request.httpMethod!, url: request.url!).isAllowed)
            if request.httpMethod == "POST" {
                XCTAssertTrue(request.url!.path.hasSuffix("term/search") || request.url!.path.hasSuffix("resetDataForm"))
            }
        }
        XCTAssertTrue(first.summary(for: "PHYS 2101", window: window).known)
        transport.requests.removeAll()
        _ = try await fetcher.refresh(first, subjects: ["PHYS", "MEGR"], now: now.addingTimeInterval(3600), calendar: TestSupport.utc)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(OfferingsFetcher.pending(first, subjects: ["PHYS", "MEGR", "BIOL"], now: now, calendar: TestSupport.utc).allSatisfy { $0.1 == "BIOL" })
    }
}
