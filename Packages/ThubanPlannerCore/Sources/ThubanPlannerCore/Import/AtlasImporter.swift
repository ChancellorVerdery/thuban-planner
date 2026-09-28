import Foundation

/// What an import would bring in — shown BEFORE anything is replaced (Settings → Import).
public struct ImportSummary: Hashable, Sendable {
    public var email: String?
    /// Every class, and how they split.
    public var courses: Int
    public var taken: Int
    public var toTake: Int
    public var creditsTaken: Double
    public var creditsToTake: Double
    /// Recorded semesters ("Fall 2024" …) in order, and the current one.
    public var terms: Int
    public var termLabels: [String]
    public var currentTerm: String?
    public var disabledTerms: [String]
    public var settings: PlannerSettings
    /// Requirement refs that match no class code (they are ignored by the scheduler, as in Atlas).
    public var unknownRefs: [String]
    /// Where the imported plan says you finish ("Spring 2028"), and in how many more terms.
    public var gradTerm: String?
    public var termsToFinish: Int
    /// Rows that were dropped or repaired, in plain words ("1 class had no id and was skipped").
    public var warnings: [String]

    public var isEmpty: Bool { courses == 0 && terms == 0 }
}

/// A decoded, converted import that has not been applied yet.
public struct AtlasImport: Sendable {
    public var data: PlannerData
    public var summary: ImportSummary
}

/// One-time (re-runnable) import of the Atlas Course Planner plugin. READ-ONLY by construction: the SQL is a single
/// SELECT inside a `BEGIN TRANSACTION READ ONLY … ROLLBACK`, sent on stdin over
/// `ssh -o BatchMode=yes <host> docker exec -i stack-postgres-1 psql -U atlas_user -d atlas -At`. The account's
/// `course.*` rows come back as ONE JSON document (`AtlasDocument`). The same document can be imported from a file.
/// Nothing here writes local data — see `AppModel.applyImport` — and nothing can write to Atlas.
public struct AtlasImporter: Sendable {
    public static let sshPath = "/usr/bin/ssh"
    public static let container = "stack-postgres-1"
    public static let databaseUser = "atlas_user"
    public static let database = "atlas"
    public static let defaultTimeout: TimeInterval = 60

    public var host: String
    public var email: String
    public var runner: CommandRunner
    public var timeout: TimeInterval

    public init(host: String = Preferences.defaultAtlasHost, email: String = Preferences.defaultAtlasEmail,
                runner: CommandRunner = DefaultCommandRunner.make(), timeout: TimeInterval = AtlasImporter.defaultTimeout) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runner = runner
        self.timeout = timeout
    }

    // MARK: Command

    /// `ssh` arguments (the executable is `sshPath`). The remote command is fixed; only the host varies.
    public func sshArguments() throws -> [String] {
        try AtlasImporter.validateHost(host)
        return ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host,
                "docker", "exec", "-i", AtlasImporter.container,
                "psql", "-U", AtlasImporter.databaseUser, "-d", AtlasImporter.database, "-At"]
    }

    /// Human-readable command for the Settings pane ("ssh beelink docker exec …").
    public var commandDescription: String {
        "ssh \(host.isEmpty ? "<host>" : host) docker exec -i \(AtlasImporter.container) psql -U \(AtlasImporter.databaseUser) -d \(AtlasImporter.database) -At"
    }

    public static func validateHost(_ host: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_@:[]"))
        guard !host.isEmpty, !host.hasPrefix("-"), host.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ThubanError.invalid("“\(host)” is not a valid ssh host.")
        }
    }

    public static func validateEmail(_ email: String) throws {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        let forbidden = CharacterSet(charactersIn: "'\"\\;`$").union(.whitespacesAndNewlines).union(.controlCharacters)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              email.unicodeScalars.allSatisfy({ !forbidden.contains($0) }) else {
            throw ThubanError.invalid("“\(email)” is not a valid email address.")
        }
    }

    /// The psql script: quiet, stop on error, one read-only transaction, one SELECT returning one JSON line.
    /// Tables and columns are Atlas's `course` schema (atlas-backend/services/plugins/course.js).
    public static func sql(email: String) throws -> String {
        try validateEmail(email)
        let literal = "'" + email.replacingOccurrences(of: "'", with: "''") + "'"
        func rows(_ table: String, _ columns: [String]) -> String {
            let fields = columns.map { "'\($0)', t.\($0)" }.joined(separator: ", ")
            return "COALESCE((SELECT json_agg(json_build_object(\(fields)) ORDER BY t.ord) FROM course.\(table) t WHERE t.user_id = (SELECT id FROM u)), '[]'::json)"
        }
        return """
        \\set QUIET on
        \\set ON_ERROR_STOP on
        BEGIN TRANSACTION READ ONLY;
        WITH u AS (SELECT id FROM auth.users WHERE lower(email) = lower(\(literal)) ORDER BY created_at LIMIT 1)
        SELECT json_build_object(
          'format', '\(AtlasDocument.format)',
          'email', \(literal),
          'user_found', EXISTS (SELECT 1 FROM u),
          'exported_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'settings', (SELECT json_build_object('max_credits', t.max_credits, 'summer_max', t.summer_max, 'strategy', t.strategy, 'disabled_terms', t.disabled_terms) FROM course.settings t WHERE t.user_id = (SELECT id FROM u) ORDER BY t.ord LIMIT 1),
          'terms', \(rows("terms", ["key", "season", "year", "current"])),
          'courses', \(rows("courses", ["id", "code", "title", "credits", "prereqs", "coreqs", "summer_ok", "term_key"]))
        )::text;
        ROLLBACK;

        """
    }

    // MARK: Fetch

    /// Runs the SQL over ssh and decodes the document. Throws `ThubanError.importFailed` for ssh / docker / psql
    /// failures (with their stderr) and `ThubanError.decoding` for unreadable output.
    public func fetch() async throws -> AtlasDocument {
        let arguments = try sshArguments()
        let script = try AtlasImporter.sql(email: email)
        let result = try await runner.run(executable: AtlasImporter.sshPath, arguments: arguments, stdin: Data(script.utf8), timeout: timeout)
        guard result.status == 0 else {
            let detail = result.stderrText.isEmpty ? "exit status \(result.status)" : result.stderrText
            throw ThubanError.importFailed("Atlas could not be read (\(detail)).")
        }
        let document = try AtlasDocument.decode(result.stdout)
        guard document.userFound else { throw ThubanError.importFailed("Atlas has no account with the email \(email).") }
        return document
    }

    /// Reads a saved document (the same JSON the SQL returns).
    public static func document(fromFile url: URL) throws -> AtlasDocument {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ThubanError.importFailed("\(url.lastPathComponent) could not be opened: \(error.localizedDescription)") }
        let document = try AtlasDocument.decode(data)
        guard document.userFound else { throw ThubanError.importFailed("That file has no Atlas account in it.") }
        return document
    }

    /// fetch + convert: the dry run. Nothing is written anywhere.
    public func dryRun(now: Date = Date()) async throws -> AtlasImport {
        try AtlasImporter.convert(try await fetch(), source: "atlas:\(host)", now: now)
    }

    // MARK: Convert

    /// Builds a fresh `PlannerData` from the document: the rows are recomposed into Atlas's blob and normalized
    /// exactly like `loadCourse()` / the backend's `decompose()` (see `PlannerData(json:)`). Then one repair Atlas does
    /// not need: courses sharing an id get fresh ids (this app keys rows by id). Atlas's scheduler identifies classes by
    /// id, so rows sharing an id share "done" state there; re-minting can therefore change the route. The route is
    /// computed both ways and, when it differs, a warning says how (`routeDifference`). Everything dropped or repaired
    /// is reported in `summary.warnings`. `makeId` mints the repair ids (injectable for tests).
    public static func convert(_ document: AtlasDocument, source: String, now: Date = Date(), calendar: Calendar = .current,
                               makeId: () -> String = { PlannerID.make("c") }) throws -> AtlasImport {
        var warnings: [String] = []
        func warn(_ count: Int, _ one: String, _ many: String) { if count > 0 { warnings.append("\(count) \(count == 1 ? one : many)") } }

        var data = PlannerData(json: document.recomposed)
        // The route exactly as Atlas computes it for these rows (duplicate ids and all), to compare after re-minting.
        let atlasSchedule = Scheduler.scheduleDegree(data, now: now, calendar: calendar)

        // What normalization dropped.
        warn(document.courses.count - data.courses.count, "class had no id and was skipped", "classes had no id and were skipped")
        let validTermRows = document.terms.filter { row in
            guard case .object(let t) = row, let season = t["season"]?.stringValue, Season(rawValue: season) != nil else { return false }
            return JS.number(t["year"]).isFinite
        }
        warn(document.terms.count - validTermRows.count, "semester row was unreadable and was skipped", "semester rows were unreadable and were skipped")
        warn(validTermRows.count - data.terms.count, "duplicate semester was merged", "duplicate semesters were merged")
        var firstRowPerKey: [String: Bool] = [:] // key → current flag of the row that survives de-duplication
        for row in validTermRows {
            let key = TermKey.make(Season(rawValue: row["season"]?.stringValue ?? "") ?? .spring, JS.number(row["year"]))
            if firstRowPerKey[key] == nil { firstRowPerKey[key] = JS.truthy(row["current"].map(AtlasDocument.postgresBool)) }
        }
        let flaggedCurrent = firstRowPerKey.values.filter { $0 }.count
        if flaggedCurrent > 1 && data.terms.filter(\.current).count == 1 {
            warnings.append("\(flaggedCurrent) semesters were marked current; the latest one is kept")
        }
        let recomposed = document.recomposed
        if let rawDisabled = recomposed["disabledTerms"] {
            if let raw = rawDisabled.arrayValue {
                warn(raw.count - data.disabledTerms.count, "switched-off term was not text and was skipped", "switched-off terms were not text and were skipped")
            } else if rawDisabled != .null {
                warnings.append("The switched-off terms could not be read and were skipped")
            }
        }
        // Requirement lists that are neither arrays nor null (after Postgres text forms are converted) are dropped by
        // loadCourse(); say so.
        if case .array(let rows)? = recomposed["courses"] {
            let unreadable = rows.filter { row in
                ["prereqs", "coreqs", "preOrCo"].contains { key in
                    guard let v = row[key] else { return false }
                    return v != .null && v.arrayValue == nil
                }
            }.count
            warn(unreadable, "class had requirements that could not be read (they were skipped)",
                 "classes had requirements that could not be read (they were skipped)")
        }
        if document.settings == nil { warnings.append("No planner settings in Atlas; the defaults are used (15 credits, summer 9, soonest)") }

        let idsBefore = data.courses.map(\.id)
        let reMinted = data.reMintDuplicateIds(makeId: makeId)
        warn(reMinted, "class shared an id with another and got a new one", "classes shared an id with another and got new ones")
        let schedule = Scheduler.scheduleDegree(data, now: now, calendar: calendar)
        if reMinted > 0, let difference = AtlasImporter.routeDifference(
            atlas: atlasSchedule, imported: schedule,
            originalId: Dictionary(zip(data.courses.map(\.id), idsBefore), uniquingKeysWith: { first, _ in first })) {
            warnings.append(difference)
        }
        let termKeys = Set(data.terms.map(\.key))
        let orphans = data.courses.filter { $0.term.map { !termKeys.contains($0) } ?? false }.count
        warn(orphans, "class is marked taken in a semester that isn't in your list (it still counts as done)",
             "classes are marked taken in semesters that aren't in your list (they still count as done)")

        data.importedAt = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)) // whole seconds: ISO 8601
        data.importSource = source

        let summary = ImportSummary(
            email: document.email,
            courses: data.courses.count,
            taken: data.taken.count,
            toTake: data.toTake.count,
            creditsTaken: data.taken.reduce(0) { $0 + $1.credits },
            creditsToTake: data.toTake.reduce(0) { $0 + $1.credits },
            terms: data.terms.count,
            termLabels: data.terms.map(\.label),
            currentTerm: data.currentTerm?.label,
            disabledTerms: data.disabledTerms,
            settings: data.settings,
            unknownRefs: data.unknownRefs,
            gradTerm: schedule.gradTermLabel,
            termsToFinish: schedule.termsToFinish,
            warnings: warnings)
        return AtlasImport(data: data, summary: summary)
    }

    /// Plain-words difference between Atlas's route for the imported rows and the route after duplicate ids were
    /// re-minted, or nil when they are the same. `originalId` maps each re-minted id back to the id it replaced, so
    /// the boards are compared class for class.
    static func routeDifference(atlas: Schedule, imported: Schedule, originalId: [String: String]) -> String? {
        func back(_ id: String) -> String { originalId[id] ?? id }
        let finishSame = atlas.termsToFinish == imported.termsToFinish && atlas.gradTerm == imported.gradTerm
        let boardSame = atlas.board.map { [$0.key] + $0.courseIds } == imported.board.map { [$0.key] + $0.courseIds.map(back) }
            && atlas.unplaceable == imported.unplaceable.map(back)
        if finishSame && boardSame { return nil }
        func finish(_ s: Schedule) -> String {
            guard let grad = s.gradTerm, s.termsToFinish > 0 else { return "nothing left to schedule" }
            return "\(TermKey.label(grad)) in \(s.termsToFinish) more term\(s.termsToFinish == 1 ? "" : "s")"
        }
        if !finishSame {
            return "Because of the shared ids, this route differs from Atlas's: it finishes \(finish(imported)) instead of \(finish(atlas))"
        }
        return "Because of the shared ids, this route places some classes differently than Atlas's; both finish \(finish(atlas))"
    }
}
