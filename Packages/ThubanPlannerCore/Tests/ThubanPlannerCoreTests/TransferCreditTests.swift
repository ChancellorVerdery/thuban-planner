import XCTest
@testable import ThubanPlannerCore

final class TransferCreditTests: XCTestCase {
    let now = TestSupport.date("2026-10-01")

    /// Fall 2025 (current), one transfer class, two to take that need it.
    func plan() -> PlannerData {
        PlannerData(courses: [
            Course(id: "past", code: "MATH 1241", credits: 3, term: "fall-2025"),
            Course(id: "ap", code: "CHEM 1251", title: "AP Chemistry", credits: 4, term: TermKey.transfer),
            Course(id: "ap-lab", code: "CHEM 1251L", credits: 1, coreqs: ["CHEM 1251"], term: TermKey.transfer),
            Course(id: "cc", code: "ENGL 1101", credits: 3, prereqs: ["MATH 1241"], term: TermKey.transfer),
            Course(id: "a", code: "MEGR 3161", credits: 3, prereqs: ["chem 1251", "MATH 1241"]),
            Course(id: "b", code: "ENGL 2116", credits: 3, coreqs: ["ENGL 1101"]),
            Course(id: "c", code: "MEGR 3152", credits: 3, prereqs: ["MEGR 3161", "STAT 9999"]),
        ], terms: [Term(season: .fall, year: 2025, current: true)])
    }

    // MARK: Model

    func testTransferTermSurvivesDecodingNormalizationAndMutations() throws {
        var data = plan()
        data.normalize()
        XCTAssertEqual(data.transferCourses.map(\.id), ["ap", "ap-lab", "cc"])
        XCTAssertTrue(data.course("ap")!.isTaken)
        let json = try JSONEncoder().encode(data)
        let back = try JSONDecoder().decode(PlannerData.self, from: json)
        XCTAssertEqual(back, data)
        XCTAssertEqual(back.course("ap")?.term, "transfer")
        // Unrelated writes never touch it.
        data.removeTerm("fall-2025")
        data.addTerm(season: .spring, year: 2026)
        data.updateCourse("ap", CoursePatch(title: "AP Chem"))
        XCTAssertEqual(data.transferCourses.count, 3)
        data.moveToTransfer(["a"])
        XCTAssertTrue(data.course("a")!.isTransfer)
        data.clearTransferCredit()
        XCTAssertTrue(data.transferCourses.isEmpty)
        XCTAssertNil(data.course("ap")?.term)
    }

    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("transfer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlannerStore(directory: dir)
        let data = SampleData.makeWithTransferCredit(now: now, calendar: TestSupport.utc)
        try store.save(data)
        XCTAssertEqual(try store.load(), data)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"term\":\"transfer\"") || text.contains("\"term\" : \"transfer\""))
    }

    func testLabels() {
        XCTAssertEqual(TermKey.displayLabel("transfer"), "Transfer credit")
        XCTAssertEqual(TermKey.displayLabel("fall-2025"), "Fall 2025")
        XCTAssertEqual(TermKey.label("transfer"), "transfer NaN", "Atlas's termLabel is untouched")
    }

    // MARK: Atlas's scheduler

    func testAtlasSchedulerCountsTransferAsTakenAndDrawsItNowhere() {
        let s = Scheduler.scheduleDegree(plan(), now: now, calendar: TestSupport.utc)
        XCTAssertNil(s.transferColumn)
        XCTAssertEqual(s.status(of: "ap"), .unscheduled)
        // Prereqs on transfer classes are met: MEGR 3161 goes in the first planned term.
        XCTAssertEqual(s.status(of: "a"), .planned("spring-2026"))
        XCTAssertEqual(s.status(of: "b"), .planned("spring-2026"))
        XCTAssertFalse(s.edges.contains { $0.from == "ap" })
    }

    // MARK: Post-step

    func testColumnIsFirstWithCreditsEdgesAndAtlasOutputUnchanged() throws {
        let data = plan()
        let atlas = Scheduler.scheduleDegree(data, now: now, calendar: TestSupport.utc)
        let s = Scheduler.withTransferColumn(atlas, data)
        let column = try XCTUnwrap(s.board.first)
        XCTAssertEqual(column.kind, .transfer)
        XCTAssertEqual(column.key, "transfer")
        XCTAssertEqual(column.label, "Transfer credit")
        XCTAssertEqual(column.courseIds, ["ap", "ap-lab", "cc"])
        XCTAssertEqual(column.credits, 8)
        XCTAssertEqual(s.columns.first?.kind, .transfer)
        XCTAssertEqual(s.transferColumn, column)
        // Atlas's part is untouched.
        XCTAssertEqual(Array(s.board.dropFirst()), atlas.board)
        XCTAssertEqual(Array(s.edges.prefix(atlas.edges.count)), atlas.edges)
        XCTAssertEqual(s.unplaceable, atlas.unplaceable)
        XCTAssertEqual(s.warnings, atlas.warnings)
        XCTAssertEqual(s.termsToFinish, atlas.termsToFinish)
        XCTAssertEqual(s.gradTerm, atlas.gradTerm)
        XCTAssertEqual(Scheduler.planStatus(data, s), Scheduler.planStatus(data, atlas))
        // New ribbons: from transfer classes only (ref matching is case-insensitive); the backwards one
        // (MATH 1241 → ENGL 1101) is not drawn.
        let added = Array(s.edges.dropFirst(atlas.edges.count))
        XCTAssertEqual(added, [
            RouteEdge(from: "ap", to: "ap-lab", kind: .coreq),
            RouteEdge(from: "ap", to: "a", kind: .prereq),
            RouteEdge(from: "cc", to: "b", kind: .coreq),
        ])
        // Statuses.
        XCTAssertEqual(s.status(of: "ap"), .transfer)
        XCTAssertEqual(CourseStatus.transfer.termKey, "transfer")
        XCTAssertEqual(s.status(of: "a"), atlas.status(of: "a"))
        XCTAssertEqual(s.plannedTerms, atlas.plannedTerms)
    }

    func testNoTransferCreditMeansNoColumn() {
        var data = plan()
        data.clearTransferCredit()
        let atlas = Scheduler.scheduleDegree(data, now: now, calendar: TestSupport.utc)
        XCTAssertEqual(Scheduler.withTransferColumn(atlas, data), atlas)
        XCTAssertEqual(Scheduler.withTransferColumn(.empty, .empty), .empty)
    }

    /// Atlas documents (the legacy fixture, the psql capture, the sample degree) never produce the column, and the
    /// post-step returns Atlas's schedule exactly.
    func testAtlasDocumentsNeverProduceTheColumn() throws {
        let legacy = try AtlasImporter.document(fromFile: TestSupport.fixtureURL("atlas-legacy.json"))
        let converted = try AtlasImporter.convert(legacy, source: "file:atlas-legacy.json", now: now, calendar: TestSupport.utc)
        for data in [converted.data, SampleData.make(now: now, calendar: TestSupport.utc)] {
            XCTAssertTrue(data.transferCourses.isEmpty)
            let atlas = Scheduler.scheduleDegree(data, now: now, calendar: TestSupport.utc)
            XCTAssertEqual(Scheduler.withTransferColumn(atlas, data), atlas)
        }
    }

    func testSampleWithTransferCredit() {
        let data = SampleData.makeWithTransferCredit(now: now, calendar: TestSupport.utc)
        let s = Scheduler.withTransferColumn(Scheduler.scheduleDegree(data, now: now, calendar: TestSupport.utc), data)
        XCTAssertEqual(s.board.first?.courseIds, ["c-sample-42", "c-sample-t1", "c-sample-t2", "c-sample-t3"])
        XCTAssertEqual(s.board.first?.credits, 12)
        XCTAssertTrue(s.edges.contains(RouteEdge(from: "c-sample-t1", to: "c-sample-41", kind: .prereq)))
        XCTAssertTrue(s.unplaceable.isEmpty)
    }

    // MARK: Electives / degree import

    func testTransferClassesCountAsTakenForElectivesAndImport() throws {
        let dataset = try XCTUnwrap(CatalogDataset.bsme2025)
        var data = BSMESampleData.make()
        let id = try XCTUnwrap(data.courses.first { $0.code == "MATH 2241" }?.id)
        data.moveToTransfer([id])
        // The chain resolver sees it in the plan (with its transfer term) and never re-adds it.
        let chain = RequirementChainResolver(dataset: dataset, data: data).resolve(["PHYS 4242"])
        XCTAssertFalse(chain.additions.contains { $0.code == "MATH 2241" })
        XCTAssertEqual(chain.roots.first?.children.first?.children.first?.state, .inPlan(code: "MATH 2241", term: "transfer"))
        // A degree import never adds it again.
        let doc = DegreeDocumentParser.parse("MATH 2241 - Calculus III (3)\nMEGR 9999 - Imaginary (3)")
        let plan = DegreeImportMerge.plan(doc, documentName: "x.txt", data: data)
        XCTAssertFalse(plan.toAdd.contains { $0.code == "MATH 2241" })
    }
}
