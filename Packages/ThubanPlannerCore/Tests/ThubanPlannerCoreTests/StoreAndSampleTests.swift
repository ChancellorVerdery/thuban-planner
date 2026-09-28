import XCTest
@testable import ThubanPlannerCore

final class StoreAndSampleTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("planner-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Store

    func testLoadMissingIsEmptyAndSaveRoundTrips() throws {
        let store = PlannerStore(directory: directory)
        XCTAssertFalse(store.exists)
        XCTAssertEqual(try store.load(), .empty)
        let sample = SampleData.make(now: TestSupport.date("2026-09-28"), calendar: TestSupport.utc)
        try store.save(sample)
        XCTAssertTrue(store.exists)
        XCTAssertEqual(try store.load(), sample)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testUnreadableFileThrowsInsteadOfBeingOverwritten() throws {
        let store = PlannerStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            guard case ThubanError.store = error else { return XCTFail("\(error)") }
        }
    }

    func testDailyBackupOncePerDayAndSnapshots() throws {
        let store = PlannerStore(directory: directory)
        var data = PlannerData()
        data.addCourse(code: "A", makeId: { "c-1" })
        try store.save(data, now: TestSupport.date("2026-09-27"))
        XCTAssertEqual(store.backups().count, 0, "nothing to back up before the first file exists")
        data.addCourse(code: "B", makeId: { "c-2" })
        try store.save(data, now: TestSupport.date("2026-09-28"))
        try store.save(data, now: TestSupport.date("2026-09-28"))
        XCTAssertEqual(store.backups().filter { $0.label == "daily" }.count, 1)
        let snapshot = try XCTUnwrap(try store.snapshot(label: "before import"))
        XCTAssertTrue(snapshot.lastPathComponent.hasPrefix("planner-before-import-"))
        XCTAssertEqual(store.backups().first { $0.url.lastPathComponent == snapshot.lastPathComponent }?.label, "before-import")
        XCTAssertEqual(try store.read(backup: snapshot).courses.map(\.code), ["A", "B"])
    }

    func testDailyBackupsArePruned() throws {
        let store = PlannerStore(directory: directory)
        try store.save(PlannerData())
        let calendar = TestSupport.utc
        for day in 0 ..< 20 {
            let date = calendar.date(byAdding: .day, value: day, to: TestSupport.date("2026-01-01"))!
            try store.save(PlannerData(), now: date)
        }
        XCTAssertEqual(store.backups().filter { $0.label == "daily" }.count, PlannerStore.dailyBackupsKept)
    }

    func testPreferencesTolerantDecoding() throws {
        let prefs = try JSONFile.decoder.decode(Preferences.self, from: Data(#"{"atlasHost":"nas","textSize":"huge","importOffered":true}"#.utf8))
        XCTAssertEqual(prefs.atlasHost, "nas")
        XCTAssertEqual(prefs.textSize, .regular)
        XCTAssertEqual(prefs.atlasEmail, Preferences.defaultAtlasEmail)
        XCTAssertTrue(prefs.importOffered)
    }

    // MARK: Sample

    func testSampleIsARealisticDegree() {
        let now = TestSupport.date("2026-09-28")
        let sample = SampleData.make(now: now, calendar: TestSupport.utc)
        XCTAssertEqual(sample.courses.count, 43)
        XCTAssertEqual(sample.taken.count, 29)
        XCTAssertEqual(sample.toTake.count, 14)
        XCTAssertEqual(sample.terms.map(\.key), ["fall-2024", "spring-2025", "fall-2025", "spring-2026", "fall-2026"])
        XCTAssertEqual(sample.currentTerm?.key, "fall-2026")
        XCTAssertEqual(sample.disabledTerms, ["summer-2027"])
        XCTAssertEqual(Set(sample.courses.map(\.id)).count, 43, "unique ids")
        XCTAssertEqual(sample.unknownRefs, ["STAT 3128"])
        XCTAssertEqual(sample.normalized(), sample, "already normalized")

        let schedule = Scheduler.scheduleDegree(sample, now: now, calendar: TestSupport.utc)
        XCTAssertEqual(schedule.unplaceable, [])
        XCTAssertTrue(schedule.warnings.isEmpty)
        XCTAssertFalse(schedule.board.contains { $0.key == "summer-2027" }, "the internship summer stays empty")
        XCTAssertGreaterThanOrEqual(schedule.termsToFinish, 3)
        XCTAssertTrue(schedule.edges.contains { $0.kind == .coreq })
        XCTAssertEqual(schedule.board.filter { $0.kind != .future }.count, 5)
        for column in schedule.plannedTerms {
            XCTAssertLessThanOrEqual(column.credits, column.season == .summer ? 7 : 16)
        }
        // The Senior Design chain is last.
        XCTAssertEqual(schedule.status(of: "c-sample-38").termKey, schedule.gradTerm)
    }

    func testSampleFollowsTheCalendar() {
        let spring = SampleData.make(now: TestSupport.date("2027-02-10"), calendar: TestSupport.utc)
        XCTAssertEqual(spring.terms.map(\.key), ["spring-2025", "fall-2025", "spring-2026", "fall-2026", "spring-2027"])
        XCTAssertEqual(spring.disabledTerms, ["summer-2027"])
        let summer = SampleData.make(now: TestSupport.date("2026-07-01"), calendar: TestSupport.utc)
        XCTAssertEqual(summer.currentTerm?.key, "summer-2026")
        XCTAssertEqual(summer.disabledTerms, ["summer-2027"])
    }
}
