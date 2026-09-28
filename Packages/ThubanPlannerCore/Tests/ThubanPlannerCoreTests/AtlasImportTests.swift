import XCTest
@testable import ThubanPlannerCore

final class AtlasImportTests: XCTestCase {
    var counter = 0
    func nextId() -> String { counter += 1; return "c-new-\(counter)" }
    let now = TestSupport.date("2026-09-28")

    // MARK: SQL

    func testSQLIsReadOnly() throws {
        let sql = try AtlasImporter.sql(email: "student@example.com")
        XCTAssertTrue(sql.contains("BEGIN TRANSACTION READ ONLY;"))
        XCTAssertTrue(sql.contains("ROLLBACK;"))
        XCTAssertTrue(sql.contains("\\set QUIET on"))
        XCTAssertTrue(sql.contains("\\set ON_ERROR_STOP on"))
        let upper = sql.uppercased()
        for verb in ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "TRUNCATE", "CREATE", "GRANT", "COPY", "COMMIT", "MERGE", "UPSERT"] {
            XCTAssertNil(upper.range(of: "\\b\(verb)\\b", options: .regularExpression), "SQL must not contain \(verb)")
        }
        XCTAssertEqual(upper.components(separatedBy: "::TEXT;").count - 1, 1, "one statement between BEGIN and ROLLBACK")
        for table in ["settings", "terms", "courses"] { XCTAssertTrue(sql.contains("course.\(table) t"), table) }
        for column in ["max_credits", "summer_max", "strategy", "disabled_terms", "summer_ok", "term_key", "prereqs", "coreqs"] {
            XCTAssertTrue(sql.contains("t.\(column)"), column)
        }
        XCTAssertTrue(sql.contains("ORDER BY t.ord"))
        XCTAssertTrue(sql.contains("lower('student@example.com')"))
    }

    func testRejectsUnsafeInput() {
        XCTAssertThrowsError(try AtlasImporter.sql(email: "x'); DROP TABLE course.courses; --@a.b"))
        XCTAssertThrowsError(try AtlasImporter.sql(email: "not-an-email"))
        XCTAssertThrowsError(try AtlasImporter(host: "-oProxyCommand=evil").sshArguments())
        XCTAssertThrowsError(try AtlasImporter(host: "bee link").sshArguments())
        XCTAssertThrowsError(try AtlasImporter(host: "").sshArguments())
        XCTAssertNoThrow(try AtlasImporter(host: "me@beelink.local").sshArguments())
    }

    func testCommandDescription() {
        XCTAssertEqual(AtlasImporter(host: "beelink").commandDescription,
                       "ssh beelink docker exec -i stack-postgres-1 psql -U atlas_user -d atlas -At")
    }

    // MARK: Fetch through a fixture runner (never ssh)

    func testFetchRunsSSHWithBatchModeAndConverts() async throws {
        let runner = FixtureRunner(result: CommandResult(status: 0, stdout: try TestSupport.fixture("atlas-psql-output.txt"), stderr: Data()))
        let importer = AtlasImporter(host: "beelink", email: "alex.morgan@example.com", runner: runner)
        let document = try await importer.fetch()
        XCTAssertEqual(runner.executable, "/usr/bin/ssh")
        XCTAssertEqual(Array(runner.arguments.prefix(5)), ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "beelink"])
        XCTAssertEqual(Array(runner.arguments.dropFirst(5)),
                       ["docker", "exec", "-i", "stack-postgres-1", "psql", "-U", "atlas_user", "-d", "atlas", "-At"])
        let stdin = String(decoding: runner.stdin, as: UTF8.self)
        XCTAssertTrue(stdin.contains("READ ONLY"))
        XCTAssertTrue(stdin.contains("lower('alex.morgan@example.com')"))
        XCTAssertEqual(runner.runs, 1)

        let result = try AtlasImporter.convert(document, source: "atlas:beelink", now: now, calendar: TestSupport.utc, makeId: nextId)
        let s = result.summary
        XCTAssertEqual(s.email, "alex.morgan@example.com")
        XCTAssertEqual(s.courses, 22)
        XCTAssertEqual(s.taken, 13)
        XCTAssertEqual(s.toTake, 9)
        XCTAssertEqual(s.terms, 5)
        XCTAssertEqual(s.termLabels.first, "Fall 2024")
        XCTAssertEqual(s.currentTerm, "Fall 2026")
        XCTAssertEqual(s.disabledTerms, ["summer-2027"])
        XCTAssertEqual(s.settings, PlannerSettings(maxCredits: 18, summerMax: 6, strategy: .soonestOptionalSummer), "jsonb '18' → 18")
        XCTAssertEqual(s.unknownRefs, ["megr 3152", "STAT 3128"])
        XCTAssertEqual(s.warnings, ["1 class shared an id with another and got a new one"])
        XCTAssertNotNil(s.gradTerm)
        XCTAssertGreaterThan(s.termsToFinish, 0)

        let data = result.data
        XCTAssertEqual(data.importSource, "atlas:beelink")
        XCTAssertEqual(data.importedAt, now)
        XCTAssertEqual(data.courses[20].id, "c-new-1", "the duplicate id was re-minted")
        XCTAssertEqual(data.courses[20].code, "MATH 2164")
        XCTAssertEqual(data.courses[21].credits, 3, "numeric string credits")
        XCTAssertNil(data.courses[21].term, "empty term_key → to take")
        XCTAssertEqual(data.courses[17].prereqs, ["MEGR 3114", "megr 3152"], "refs trimmed")
        XCTAssertEqual(data.normalized(), data)
    }

    func testDryRunCombinesFetchAndConvert() async throws {
        let runner = FixtureRunner(result: CommandResult(status: 0, stdout: try TestSupport.fixture("atlas-psql-output.txt"), stderr: Data()))
        let result = try await AtlasImporter(host: "beelink", runner: runner).dryRun(now: now)
        XCTAssertEqual(result.summary.courses, 22)
        XCTAssertEqual(result.data.importSource, "atlas:beelink")
    }

    func testPsqlNoiseAroundTheDocumentIsIgnored() throws {
        let line = String(decoding: try TestSupport.fixture("atlas-psql-output.txt"), as: UTF8.self)
        let noisy = "WARNING:  there is no transaction in progress\n" + line + "\n"
        let document = try AtlasDocument.decode(Data(noisy.utf8))
        XCTAssertEqual(document.courses.count, 22)
    }

    func testFetchFailureCarriesStderr() async {
        let runner = FixtureRunner(result: CommandResult(status: 255, stdout: Data(), stderr: Data("ssh: Could not resolve hostname beelink".utf8)))
        do {
            _ = try await AtlasImporter(runner: runner).fetch()
            XCTFail("expected an error")
        } catch let error as ThubanError {
            guard case .importFailed(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("Could not resolve hostname"))
        } catch { XCTFail("\(error)") }
    }

    func testUnknownAccount() async {
        let json = #"{"format":"thuban.atlas-course.v1","email":"nobody@example.com","user_found":false,"settings":null,"terms":[],"courses":[]}"#
        let runner = FixtureRunner(result: CommandResult(status: 0, stdout: Data((json + "\n").utf8), stderr: Data()))
        do {
            _ = try await AtlasImporter(email: "nobody@example.com", runner: runner).fetch()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no account"))
        }
    }

    func testGarbageOutput() {
        XCTAssertThrowsError(try AtlasDocument.decode(Data())) { XCTAssertEqual($0.localizedDescription, "Atlas returned nothing.") }
        XCTAssertThrowsError(try AtlasDocument.decode(Data("psql: error: connection refused".utf8)))
    }

    func testAccountWithNoPlannerData() throws {
        let json = #"{"format":"thuban.atlas-course.v1","email":"a@b.co","user_found":true,"settings":null,"terms":[],"courses":[]}"#
        let result = try AtlasImporter.convert(try AtlasDocument.decode(Data(json.utf8)), source: "atlas:beelink", now: now)
        XCTAssertTrue(result.summary.isEmpty)
        XCTAssertEqual(result.data.settings, .default)
        XCTAssertEqual(result.summary.warnings, ["No planner settings in Atlas; the defaults are used (15 credits, summer 9, soonest)"])
    }

    // MARK: Legacy / tolerant rows (the backend mapper's edge cases, arriving as rows)

    func testLegacyRowsNormalizeLikeLoadCourse() throws {
        let document = try AtlasImporter.document(fromFile: TestSupport.fixtureURL("atlas-legacy.json"))
        let result = try AtlasImporter.convert(document, source: "file:atlas-legacy.json", now: now, calendar: TestSupport.utc, makeId: nextId)
        let d = result.data
        XCTAssertEqual(d.courses.map(\.id), ["c-x", "c-new-1", "c-y", "c-z"])
        XCTAssertEqual(d.courses[2], Course(id: "c-y", code: "MATH 2", title: "42", credits: 4, prereqs: ["CS 101", "3"], summerOk: true))
        XCTAssertEqual(d.courses[3].credits, 0, "credits null → Number(null) = 0")
        XCTAssertEqual(d.courses[3].coreqs, ["CS 101", "MATH 2"], "pre_or_co folded, exact duplicates dropped")
        XCTAssertEqual(d.terms, [Term(season: .fall, year: 2025, current: false), Term(season: .spring, year: 2026, current: true)])
        XCTAssertEqual(d.disabledTerms, ["summer-2026"])
        XCTAssertEqual(d.settings, PlannerSettings(maxCredits: 16, summerMax: 9, strategy: .soonestSummer))
        XCTAssertEqual(result.summary.warnings, [
            "1 class had no id and was skipped",
            "3 semester rows were unreadable and were skipped",
            "1 duplicate semester was merged",
            "2 semesters were marked current; the latest one is kept",
            "2 switched-off terms were not text and were skipped",
            "1 class shared an id with another and got a new one",
            "1 class is marked taken in a semester that isn't in your list (it still counts as done)",
        ])
    }

    func testJSONEncodedJSONBIsUnwrapped() throws {
        let json = #"{"user_found":true,"settings":{"max_credits":"\"12\"","summer_max":"3","strategy":"even","disabled_terms":[]},"terms":[],"courses":[]}"#
        let d = try AtlasImporter.convert(try AtlasDocument.decode(Data(json.utf8)), source: "x", now: now).data
        XCTAssertEqual(d.settings, PlannerSettings(maxCredits: 12, summerMax: 3, strategy: .even))
    }
}
