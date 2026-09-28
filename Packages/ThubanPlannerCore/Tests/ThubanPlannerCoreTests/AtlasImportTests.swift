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
        XCTAssertEqual(s.warnings, ["1 class shared an id with another and got a new one",
                                    // Atlas treats the two to-take rows sharing c-mf1k2a20 as one class; here both are planned.
                                    "Because of the shared ids, this route places some classes differently than Atlas's; both finish Spring 2028 in 3 more terms"])
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
            "Because of the shared ids, this route places some classes differently than Atlas's; both finish Spring 2027 in 2 more terms",
            "1 class is marked taken in a semester that isn't in your list (it still counts as done)",
        ])
    }

    func testJSONEncodedJSONBIsUnwrapped() throws {
        let json = #"{"user_found":true,"settings":{"max_credits":"\"12\"","summer_max":"3","strategy":"even","disabled_terms":[]},"terms":[],"courses":[]}"#
        let d = try AtlasImporter.convert(try AtlasDocument.decode(Data(json.utf8)), source: "x", now: now).data
        XCTAssertEqual(d.settings, PlannerSettings(maxCredits: 12, summerMax: 3, strategy: .even))
    }
    // MARK: Postgres text forms (a file saved from plain psql output)

    func testPostgresArrayLiterals() {
        XCTAssertEqual(AtlasDocument.postgresArray(.string("{}")), .array([]))
        XCTAssertEqual(AtlasDocument.postgresArray(.string("{A,B}")), .array([.string("A"), .string("B")]))
        XCTAssertEqual(AtlasDocument.postgresArray(.string(#"{"MATH 1241",NULL,"say \"hi\"","a\\b",""}"#)),
                       .array([.string("MATH 1241"), .null, .string(#"say "hi""#), .string(#"a\b"#), .string("")]))
        XCTAssertEqual(AtlasDocument.postgresArray(.string(#"{"NULL",null}"#)), .array([.string("NULL"), .null]),
                       "a quoted NULL is text; an unquoted one (any case) is SQL NULL")
        XCTAssertEqual(AtlasDocument.postgresArray(.string("{{a,b},{c}}")), .array([.array([.string("a"), .string("b")]), .array([.string("c")])]))
        XCTAssertEqual(AtlasDocument.postgresArray(.string(" { x , y } ")), .array([.string("x"), .string("y")]))
        // Not literals: unchanged.
        for text in ["MATH 1241", "{a,b", #"{"a}"#, "{a}b}", "[\"a\"]"] {
            XCTAssertEqual(AtlasDocument.postgresArray(.string(text)), .string(text), text)
        }
        XCTAssertEqual(AtlasDocument.postgresArray(.array([.string("a")])), .array([.string("a")]))
        XCTAssertEqual(AtlasDocument.postgresArray(.null), .null)
    }

    func testPostgresBooleans() {
        XCTAssertEqual(AtlasDocument.postgresBool(.string("t")), .bool(true))
        XCTAssertEqual(AtlasDocument.postgresBool(.string("f")), .bool(false))
        XCTAssertEqual(AtlasDocument.postgresBool(.string("false")), .bool(false))
        XCTAssertEqual(AtlasDocument.postgresBool(.string("yes")), .string("yes"))
        XCTAssertEqual(AtlasDocument.postgresBool(.bool(true)), .bool(true))
        XCTAssertEqual(AtlasDocument.postgresBool(.number(0)), .number(0))
    }

    func testPostgresTextFormsImportCorrectly() throws {
        let json = #"""
        {"user_found":true,
         "settings":{"max_credits":15,"summer_max":9,"strategy":"soonest-summer","disabled_terms":"{summer-2027,summer-2028}"},
         "terms":[{"key":"spring-2026","season":"spring","year":2026,"current":"f"},{"key":"fall-2026","season":"fall","year":2026,"current":"t"}],
         "courses":[
           {"id":"a","code":"B","title":"B","credits":3,"prereqs":"{}","coreqs":"{}","summer_ok":"t","term_key":"fall-2026"},
           {"id":"b","code":"C","title":"C","credits":3,"prereqs":"{}","coreqs":"{}","summer_ok":"t","term_key":null},
           {"id":"c","code":"D","title":"D","credits":3,"prereqs":"{B,\"C\"}","coreqs":"{}","summer_ok":"f","term_key":null},
           {"id":"d","code":"E","title":"E","credits":3,"prereqs":"B, C","coreqs":null,"summer_ok":"f","term_key":null}]}
        """#
        let result = try AtlasImporter.convert(try AtlasDocument.decode(Data(json.utf8)), source: "file", now: now, calendar: TestSupport.utc)
        let d = result.data
        XCTAssertEqual(d.disabledTerms, ["summer-2027", "summer-2028"])
        XCTAssertEqual(d.courses.map(\.prereqs), [[], [], ["B", "C"], []])
        XCTAssertEqual(d.courses.map(\.summerOk), [true, true, false, false])
        XCTAssertEqual(d.terms.map(\.current), [false, true])
        XCTAssertEqual(result.summary.warnings, ["1 class had requirements that could not be read (they were skipped)"],
                       "only the plain string is unreadable; no bogus 'marked current' warning")
    }

    func testUnreadableDisabledTermsAreReported() throws {
        let json = #"{"user_found":true,"settings":{"max_credits":15,"summer_max":9,"strategy":"even","disabled_terms":"summer-2027"},"terms":[],"courses":[]}"#
        let result = try AtlasImporter.convert(try AtlasDocument.decode(Data(json.utf8)), source: "x", now: now)
        XCTAssertEqual(result.data.disabledTerms, [])
        XCTAssertEqual(result.summary.warnings, ["The switched-off terms could not be read and were skipped"])
    }

    // MARK: Duplicate ids and the route

    func testReMintingThatChangesTheRouteIsReported() throws {
        // Atlas: MATH 2 shares id x with the (taken) MATH 1, so Atlas counts it done and PHYS 1 fits in one term.
        let json = #"""
        {"user_found":true,"settings":{"max_credits":15,"summer_max":9,"strategy":"soonest-summer","disabled_terms":[]},
         "terms":[{"key":"fall-2025","season":"fall","year":2025,"current":true}],
         "courses":[
           {"id":"x","code":"MATH 1","title":"M1","credits":3,"prereqs":[],"coreqs":[],"summer_ok":true,"term_key":"fall-2025"},
           {"id":"x","code":"MATH 2","title":"M2","credits":3,"prereqs":[],"coreqs":[],"summer_ok":true,"term_key":null},
           {"id":"y","code":"PHYS 1","title":"P1","credits":3,"prereqs":["MATH 2"],"coreqs":[],"summer_ok":true,"term_key":null}]}
        """#
        let document = try AtlasDocument.decode(Data(json.utf8))
        let atlas = Scheduler.scheduleDegree(PlannerData(json: document.recomposed), now: now, calendar: TestSupport.utc)
        XCTAssertEqual(atlas.termsToFinish, 1)
        let result = try AtlasImporter.convert(document, source: "x", now: now, calendar: TestSupport.utc, makeId: nextId)
        XCTAssertEqual(result.summary.termsToFinish, 2)
        XCTAssertEqual(result.summary.warnings, [
            "1 class shared an id with another and got a new one",
            "Because of the shared ids, this route differs from Atlas's: it finishes Summer 2026 in 2 more terms instead of Spring 2026 in 1 more term",
        ])
    }

    func testReMintingThatKeepsTheRouteSaysNothingMore() throws {
        let json = #"""
        {"user_found":true,"settings":{"max_credits":15,"summer_max":9,"strategy":"soonest-summer","disabled_terms":[]},
         "terms":[{"key":"fall-2025","season":"fall","year":2025,"current":true}],
         "courses":[
           {"id":"x","code":"MATH 1","title":"M1","credits":3,"prereqs":[],"coreqs":[],"summer_ok":true,"term_key":"fall-2025"},
           {"id":"x","code":"MATH 1L","title":"M1 lab","credits":1,"prereqs":[],"coreqs":[],"summer_ok":true,"term_key":"fall-2025"},
           {"id":"y","code":"PHYS 1","title":"P1","credits":3,"prereqs":["MATH 1"],"coreqs":[],"summer_ok":true,"term_key":null}]}
        """#
        let result = try AtlasImporter.convert(try AtlasDocument.decode(Data(json.utf8)), source: "x", now: now, calendar: TestSupport.utc, makeId: nextId)
        XCTAssertEqual(result.summary.warnings, ["1 class shared an id with another and got a new one"])
    }

    func testRouteDifferenceComparesClassForClass() {
        func board(_ ids: [String]) -> Schedule {
            Schedule(board: [BoardTerm(key: "spring-2026", season: .spring, year: 2026, current: false, kind: .future, courseIds: ids, credits: 6)],
                     termsToFinish: 1, gradTerm: "spring-2026")
        }
        XCTAssertNil(AtlasImporter.routeDifference(atlas: board(["x", "y"]), imported: board(["c-new-1", "y"]), originalId: ["c-new-1": "x"]))
        XCTAssertEqual(AtlasImporter.routeDifference(atlas: board(["x", "y"]), imported: board(["y", "c-new-1"]), originalId: ["c-new-1": "x"]),
                       "Because of the shared ids, this route places some classes differently than Atlas's; both finish Spring 2026 in 1 more term")
    }
}
