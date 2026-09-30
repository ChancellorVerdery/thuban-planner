import XCTest
@testable import ThubanPlannerCore

/// DIFFERENTIAL PARITY: the Swift port against Atlas's own JavaScript (`AtlasJS`, run in-process under
/// JavaScriptCore) on thousands of seeded pseudo-random inputs.
///
/// Every case is a raw JSON document plus a fixed "now". Atlas's side: backend `decompose` → Postgres → `recompose`
/// → UI `loadCourse()` → `scheduleDegree(s, new Date(now))` → `upcomingSummers` / `planStatus`. Swift's side:
/// `PlannerData(json:)` → `Scheduler.scheduleDegree(now:calendar:)` → `upcomingSummers` / `planStatus`. The
/// normalized document, the whole schedule (board, edges, unplaceable, warnings, termsToFinish, gradTerm), the summer
/// toggles and the status line are compared field by field.
///
/// "now" is the same instant on both sides and both read it in the process's local time zone (JS `Date#getMonth`,
/// Swift `Calendar.current` — the app's calendar); the fixed instants include month edges so a time-zone slip shows.
///
/// Two generators:
/// - `planCase`: realistic plans — 0–60 classes (plus some 61–90 for TimSort's merge paths), DAG and cyclic
///   requirements, lecture↔lab coreq loops, unknown refs, duplicate codes and ids, case / white-space variants of
///   refs, zero-credit, fractional and heavy classes, summer mixes, no / past / current / several-current terms,
///   disabled terms (including garbage keys), all three strategies, caps as numbers, numeric strings, tiny values
///   and invalid values, many "now"s across seasons.
/// - `messyCase`: hostile documents — every field of every kind (null, booleans, numbers printed in exponent form,
///   numeric strings with JS-only syntax, Unicode white space, arrays, objects), id-less / numeric ids, retired
///   `preOrCo`, bad seasons and years, non-array collections, invalid settings and non-object roots.
///
/// On acyclic plans the comparator call order cannot matter, so each case also runs under JavaScriptCore's NATIVE
/// sort and must agree with the V8-order run — an independent check on the V8 TimSort port (`V8Sort`).
final class DifferentialParityTests: XCTestCase {
    static let planCaseCount = 2400
    static let messyCaseCount = 800

    struct ParityCase {
        var name: String
        var raw: JSONValue
        var now: Date
    }

    struct Outcome {
        var cases = 0
        var mismatches: [String] = []
        var byArea: [String: Int] = [:]
        var jsErrors = 0
        var acyclic = 0
        var nativeSortDisagreements: [String] = []
        var cyclicWhereSortOrderMattered = 0
        var unplaceableCases = 0
        var strategies: [String: Int] = [:]
    }

    func testSwiftMatchesAtlasOnGeneratedPlans() throws {
        var rng = SeededRandom(seed: 0x7_4b1d_2026)
        let cases = (0 ..< Self.planCaseCount).map { Self.planCase($0, &rng) }
        let outcome = try Self.compare(cases)
        Self.report("plans", outcome)
        XCTAssertEqual(outcome.cases, Self.planCaseCount)
        XCTAssertEqual(outcome.jsErrors, 0, "Atlas threw on a generated plan")
        XCTAssertEqual(outcome.mismatches.count, 0, "\(outcome.mismatches.count) of \(outcome.cases) plans differ from Atlas:\n"
            + outcome.mismatches.prefix(8).joined(separator: "\n\n"))
        XCTAssertEqual(outcome.nativeSortDisagreements.count, 0, "acyclic plan depends on sort order:\n"
            + outcome.nativeSortDisagreements.prefix(3).joined(separator: "\n"))
        // The generator really reaches the hard paths.
        XCTAssertGreaterThan(outcome.acyclic, 500)
        XCTAssertGreaterThan(Self.planCaseCount - outcome.acyclic, 500, "cyclic plans")
        XCTAssertGreaterThan(outcome.unplaceableCases, 200)
        for strategy in Strategy.allCases { XCTAssertGreaterThan(outcome.strategies[strategy.rawValue] ?? 0, 500, strategy.rawValue) }
    }

    func testSwiftNormalizesMessyDocumentsLikeAtlas() throws {
        var rng = SeededRandom(seed: 0xbad_d0c5)
        let cases = (0 ..< Self.messyCaseCount).map { Self.messyCase($0, &rng) }
        let outcome = try Self.compare(cases)
        Self.report("messy", outcome)
        XCTAssertEqual(outcome.cases, Self.messyCaseCount)
        XCTAssertEqual(outcome.mismatches.count, 0, "\(outcome.mismatches.count) of \(outcome.cases) messy documents differ from Atlas:\n"
            + outcome.mismatches.prefix(8).joined(separator: "\n\n"))
        XCTAssertEqual(outcome.nativeSortDisagreements.count, 0, outcome.nativeSortDisagreements.prefix(3).joined(separator: "\n"))
    }

    /// The harness itself: the fixtures load, Atlas's normalization runs, and a known answer comes back.
    func testHarnessRunsAtlas() throws {
        let js = try AtlasJS()
        let raw = #"{"courses":[{"id":"a","code":"MATH 1","credits":"4"},{"id":"b","code":"MATH 2","prereqs":[" math 1 "]}],"settings":{"maxCredits":"4"}}"#
        let now = TestSupport.date("2025-10-01").timeIntervalSince1970 * 1000
        let out = try JSONValue.parse(Data(js.run(raw: raw, nowMs: now, v8Sort: true).utf8))
        XCTAssertNil(out["error"], JSONDiff.short(out))
        XCTAssertEqual(out["schedule"]?["termsToFinish"], .number(2))
        XCTAssertEqual(out["normalized"]?["settings"]?["maxCredits"], .number(4))
        XCTAssertEqual(out["schedule"]?["edges"]?.arrayValue?.count, 1)
    }

    // MARK: Comparison

    static func compare(_ cases: [ParityCase]) throws -> Outcome {
        let js = try AtlasJS()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var outcome = Outcome()
        for c in cases {
            outcome.cases += 1
            let rawText = String(decoding: try encoder.encode(c.raw), as: UTF8.self)
            let nowMs = c.now.timeIntervalSince1970 * 1000
            let atlasText = js.run(raw: rawText, nowMs: nowMs, v8Sort: true)
            let atlas = try JSONValue.parse(Data(atlasText.utf8))
            if let error = atlas["error"] {
                outcome.jsErrors += 1
                outcome.mismatches.append("\(c.name): Atlas threw \(JSONDiff.short(error))\n raw: \(rawText.prefix(600))")
                continue
            }

            // Swift, from the very same bytes.
            let data = PlannerData(json: try JSONValue.parse(Data(rawText.utf8)))
            let schedule = Scheduler.scheduleDegree(data, now: c.now, calendar: .current)
            let swift: JSONValue = .object([
                "normalized": .object([
                    "courses": try reencode(data.courses),
                    "terms": try reencode(data.terms),
                    "disabledTerms": try reencode(data.disabledTerms),
                    "settings": try atlasSettings(data.settings),
                ]),
                "schedule": try reencode(schedule),
                "summers": try reencode(Scheduler.upcomingSummers(data, now: c.now, calendar: .current)),
                "status": .string(Scheduler.planStatus(data, schedule)),
            ])

            outcome.strategies[data.settings.strategy.rawValue, default: 0] += 1
            if !schedule.unplaceable.isEmpty { outcome.unplaceableCases += 1 }

            var lines: [String] = []
            for area in ["normalized", "schedule", "summers", "status"] {
                let d = JSONDiff.diff(swift[area], atlas[area], path: area)
                if !d.isEmpty { outcome.byArea[area, default: 0] += 1; lines += d }
            }
            if !lines.isEmpty {
                outcome.mismatches.append("\(c.name) (now \(c.now)): swift ≠ atlas\n  " + lines.joined(separator: "\n  ")
                                          + "\n  raw: \(rawText.prefix(1500))")
            }

            // Independent check of the sort-order machinery: without a requirement cycle (lazily memoized depths)
            // and without a term key whose rank is NaN (an inconsistent comparator), the order of comparator calls
            // cannot change anything, so JavaScriptCore's own merge sort must give the same answer.
            if isAcyclic(data) && !hasUnrankableKeys(data) {
                outcome.acyclic += 1
                let native = js.run(raw: rawText, nowMs: nowMs, v8Sort: false)
                if native != atlasText {
                    let d = JSONDiff.diff((try? JSONValue.parse(Data(native.utf8))) ?? .null, atlas, path: "native")
                    outcome.nativeSortDisagreements.append("\(c.name): native sort ≠ V8 sort\n  " + d.joined(separator: "\n  ")
                                                           + "\n  raw: \(rawText.prefix(1500))")
                }
            } else if js.run(raw: rawText, nowMs: nowMs, v8Sort: false) != atlasText {
                outcome.cyclicWhereSortOrderMattered += 1
            }
        }
        return outcome
    }

    /// Swift value → JSON the way `JSON.stringify` would write it (NaN / ±Infinity become null).
    /// Settings as Atlas knows them: the Thuban-only minimums must come out of any Atlas document as 0 (off), which
    /// is also what keeps the schedule identical; they are then dropped from the comparison.
    static func atlasSettings(_ settings: PlannerSettings) throws -> JSONValue {
        guard settings.minCredits == 0, settings.summerMin == 0 else {
            return .string("Thuban minimums not off: \(settings.minCredits) / \(settings.summerMin)")
        }
        guard case .object(var o) = try reencode(settings) else { return try reencode(settings) }
        o["minCredits"] = nil
        o["summerMin"] = nil
        return .object(o)
    }

    static func reencode<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: nonFinite, negativeInfinity: nonFinite, nan: nonFinite)
        return nullifyNonFinite(try JSONValue.parse(encoder.encode(value)))
    }

    private static let nonFinite = "\u{1}non-finite\u{1}"

    private static func nullifyNonFinite(_ v: JSONValue) -> JSONValue {
        switch v {
        case .string(nonFinite): return .null
        case .array(let a): return .array(a.map(nullifyNonFinite))
        case .object(let o): return .object(o.mapValues(nullifyNonFinite))
        default: return v
        }
    }

    /// No cycle in the scheduler's requirement graph (refs resolved like `scheduleDegree`: the last course with a
    /// code wins, ids stand for the last course carrying them).
    static func isAcyclic(_ data: PlannerData) -> Bool {
        var byCode: [String: String] = [:]
        for c in data.courses where !c.code.isEmpty { byCode[Scheduler.norm(c.code)] = c.id }
        var dependents: [String: [String]] = [:]
        for c in data.courses {
            for ref in c.prereqs + c.coreqs {
                if let r = byCode[Scheduler.norm(ref)] { dependents[r, default: []].append(c.id) }
            }
        }
        var state: [String: Int] = [:] // 1 = on stack, 2 = done
        func visit(_ id: String) -> Bool {
            if state[id] == 2 { return true }
            if state[id] == 1 { return false }
            state[id] = 1
            for next in dependents[id] ?? [] where !visit(next) { return false }
            state[id] = 2
            return true
        }
        return data.courses.allSatisfy { visit($0.id) }
    }

    /// A term or disabled-term key whose `termRank` is NaN ("summer", "fall-1e-7"): sorting by rank then uses an
    /// inconsistent comparator and the result is engine-specific (Atlas = V8).
    static func hasUnrankableKeys(_ data: PlannerData) -> Bool {
        (data.terms.map(\.key) + data.disabledTerms).contains { TermKey.rank($0).isNaN }
    }

    static func report(_ label: String, _ o: Outcome) {
        print("""
        [parity:\(label)] cases=\(o.cases) mismatches=\(o.mismatches.count) byArea=\(o.byArea) jsErrors=\(o.jsErrors) \
        orderIndependent=\(o.acyclic) nativeSortDisagreements=\(o.nativeSortDisagreements.count) \
        cyclicSortOrderMattered=\(o.cyclicWhereSortOrderMattered) unplaceable=\(o.unplaceableCases) strategies=\(o.strategies)
        """)
    }

    // MARK: Fixed "now"s (local time, like the app)

    static func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0) -> Date {
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (y, m, d, h, min, s)
        return Calendar.current.date(from: parts)!
    }

    static let fixedNows: [Date] = [
        local(2025, 10, 1), local(2026, 1, 1, 0, 0, 1), local(2026, 3, 15), local(2026, 5, 31, 23, 59, 59),
        local(2026, 6, 1, 0, 0, 0), local(2026, 7, 4), local(2026, 8, 31, 23, 59, 59), local(2026, 9, 1, 0, 0, 1),
        local(2026, 9, 28), local(2026, 12, 31, 23, 59, 59), local(2027, 1, 1, 0, 0, 0), local(2027, 6, 15),
        local(2024, 2, 29), local(2023, 11, 11), local(2028, 5, 1), local(2022, 8, 20),
    ]

    // MARK: Plan generator

    static let depts = ["MATH", "PHYS", "CS", "MEGR", "ENGR", "CHEM", "ECON", "STAT", "ENGL", "BIOL"]

    static func makeCode(_ r: inout SeededRandom) -> String {
        let x = r.unit()
        let n = r.int(100, 4999)
        let d = r.pick(depts)
        if x < 0.04 { return "" }
        if x < 0.10 { return "\(d)-\(n)" }
        if x < 0.14 { return "\(d.lowercased()) \(n)" }
        if x < 0.17 { return "\(d)_\(n)" }
        if x < 0.20 { return "\(d)\(n)" }
        if x < 0.23 { return "\(d) \(n)L" }
        if x < 0.25 { return "\(d).\(n)" }
        if x < 0.26 { return "\(d) \(n / 100)" } // short numbers: "MATH 10" vs "MATH 2" ordering
        return "\(d) \(n)"
    }

    static let planCredits: [JSONValue] = [
        .number(0), .number(0.5), .number(1), .number(1), .number(1.5), .number(2), .number(3), .number(3), .number(3),
        .number(3), .number(3), .number(4), .number(4), .number(4), .number(5), .number(6), .number(12), .number(15),
        .number(20), .number(0.1), .number(0.2), .number(2.25), .number(3.3),
    ]

    static func planCase(_ k: Int, _ r: inout SeededRandom) -> ParityCase {
        let size: Int
        if k % 23 == 0 { size = 0 }
        else if k % 50 == 1 { size = r.int(61, 90) }
        else if k % 9 == 0 { size = r.int(1, 4) }
        else if k % 13 == 0 { size = r.int(50, 60) }
        else { size = r.int(3, 45) }

        var codes: [String] = []
        var courses: [[String: JSONValue]] = []
        for i in 0 ..< size {
            var code = makeCode(&r)
            if i > 0 && r.chance(0.05) { code = codes[r.int(0, i - 1)] }                   // duplicate code
            if i > 0 && r.chance(0.04) { code = codes[r.int(0, i - 1)].lowercased() }      // case variant
            if i > 0 && r.chance(0.02) { code = codes[r.int(0, i - 1)].uppercased() }
            codes.append(code)
            var rawCode = code
            if r.chance(0.03) { rawCode = "  \(code)\t" }                                  // stored with padding
            let id: JSONValue
            if i > 0 && r.chance(0.02) { id = courses[r.int(0, i - 1)]["id"]! }            // duplicate id
            else if r.chance(0.02) { id = .number(Double(90_000 + i)) }                     // numeric id
            else { id = .string("c-\(k)-\(i)") }
            var credits = r.pick(planCredits)
            if r.chance(0.04), case .number(let n) = credits { credits = .string(r.chance(0.5) ? JS.numberString(n) : " \(JS.numberString(n)) ") }
            let title: JSONValue = !code.isEmpty ? .string("Title \(i)") : (r.chance(0.5) ? .string("Untitled \(i)") : .string(""))
            courses.append([
                "id": id, "code": .string(rawCode), "title": title, "credits": credits,
                "prereqs": .array([]), "coreqs": .array([]), "summerOk": .bool(r.chance(0.4)), "term": .null,
            ])
        }

        func refOf(_ j: Int, _ r: inout SeededRandom) -> String {
            let c = codes[j]
            let x = r.unit()
            if x < 0.70 { return c }
            if x < 0.80 { return "  \(c.lowercased()) " }
            if x < 0.85 { return c.uppercased() }
            if x < 0.90 { return "\t\(c)" }
            if x < 0.95 { return "\u{00A0}\(c)\u{00A0}" }
            return c.replacingOccurrences(of: " ", with: "  ")                           // inner space → unknown ref
        }
        func append(_ i: Int, _ key: String, _ ref: String) {
            guard case .array(var list)? = courses[i][key] else { return }
            list.append(.string(ref))
            courses[i][key] = .array(list)
        }

        let acyclic = r.chance(0.5)
        let prereqRate = r.pick([0.2, 0.45, 0.7])
        for i in 0 ..< size {
            let np = r.chance(prereqRate) ? r.int(1, 3) : 0
            for _ in 0 ..< np where size > 1 {
                let j = acyclic ? (i > 0 ? r.int(0, i - 1) : -1) : r.int(0, size - 1)
                if j >= 0 && j != i && !codes[j].isEmpty { append(i, "prereqs", refOf(j, &r)) }
            }
            if r.chance(0.06) { append(i, "prereqs", "XYZ \(r.int(100, 999))") }        // unknown ref
            if r.chance(0.2) && size > 1 {
                let j = acyclic ? (i > 0 ? r.int(0, i - 1) : -1) : r.int(0, size - 1)
                if j >= 0 && j != i && !codes[j].isEmpty {
                    append(i, "coreqs", refOf(j, &r))
                    if !acyclic && r.chance(0.5) { append(j, "coreqs", codes[i].isEmpty ? "none" : codes[i]) } // lecture ↔ lab
                }
            }
            if r.chance(0.02) { append(i, "coreqs", "") }                                 // empty ref, dropped
        }

        // Recorded terms.
        let nTerms = k % 11 == 0 ? 0 : r.int(0, 6)
        var key = TermKey.make(r.pick(Season.allCases), r.int(2021, 2027))
        var terms: [[String: JSONValue]] = []
        for _ in 0 ..< nTerms {
            let p = TermKey.parse(key)
            if !(p.season == .summer && r.chance(0.6)) {
                let year: JSONValue = r.chance(0.05) ? .string(JS.numberString(p.year)) : .number(p.year)
                terms.append(["key": .string(key), "season": .string(p.seasonText), "year": year, "current": .bool(false)])
            }
            key = TermKey.next(key)
        }
        if !terms.isEmpty {
            let x = r.unit()
            if x < 0.75 { terms[terms.count - 1]["current"] = .bool(true) }
            else if x < 0.82 { terms[r.int(0, terms.count - 1)]["current"] = .bool(true) }
            else if x < 0.88 { for i in terms.indices where r.chance(0.6) { terms[i]["current"] = .bool(true) } } // several
        }
        if terms.count > 2 && r.chance(0.1) { terms.shuffle(using: &r) }                    // stored out of order
        if !terms.isEmpty && r.chance(0.05) { terms.append(terms[r.int(0, terms.count - 1)]) } // duplicate row
        let termKeys = terms.compactMap { $0["key"]?.stringValue }
        for i in courses.indices {
            if !termKeys.isEmpty && r.chance(0.3) { courses[i]["term"] = .string(r.pick(termKeys)) }
            else if r.chance(0.02) { courses[i]["term"] = .string("fall-2010") }             // unrecorded term
            else if r.chance(0.01) { courses[i]["term"] = .string("") }
        }

        // Disabled terms around the planning horizon.
        let now = r.chance(0.75) ? r.pick(fixedNows) : local(r.int(2021, 2029), r.int(1, 12), r.int(1, 28), r.int(0, 23), r.int(0, 59))
        var disabled: [JSONValue] = []
        var cursor = termKeys.last.map { key -> String in
            // the normalized last term (keys are recomputed), close enough for choosing what to disable
            key
        } ?? TermKey.current(now: now)
        for _ in 0 ..< 10 {
            cursor = TermKey.next(cursor)
            if r.chance(TermKey.season(cursor) == .summer ? 0.4 : 0.07) { disabled.append(.string(cursor)) }
        }
        if r.chance(0.05) { disabled.append(.string("winter-2027")) }
        if r.chance(0.03), let past = termKeys.first { disabled.append(.string(past)) }
        if r.chance(0.03) { disabled.append(.number(2027)) }
        if disabled.count > 1 && r.chance(0.05) { disabled.append(disabled[0]) }

        let maxPool: [JSONValue] = [.number(15), .number(15), .number(15), .number(12), .number(18), .number(16), .number(9),
                                    .number(6), .number(3), .number(1), .number(0.5), .number(2), .number(21), .number(30),
                                    .string("18"), .string(" 12 "), .string("15.0"), .string("0x10"), .string("1e1"),
                                    .number(0), .number(-3), .string("abc"), .null, .string(""), .number(4.5)]
        let summerPool: [JSONValue] = [.number(9), .number(9), .number(6), .number(0), .number(3), .number(12), .number(1),
                                       .string("6"), .string("0"), .number(-1), .null, .string("x"), .number(20), .number(0.5),
                                       .number(4.5), .string("")]
        var settings: [String: JSONValue] = ["maxCredits": r.pick(maxPool)]
        if !r.chance(0.12) { settings["summerMax"] = r.pick(summerPool) }
        let x = r.unit()
        settings["strategy"] = x < 0.02 ? .string("fastest") : (x < 0.03 ? .null : .string(Strategy.allCases[k % 3].rawValue))

        let raw: JSONValue = .object([
            "courses": .array(courses.map { .object($0) }),
            "terms": .array(terms.map { .object($0) }),
            "disabledTerms": .array(disabled),
            "settings": .object(settings),
        ])
        return ParityCase(name: "plan-\(k)", raw: raw, now: now)
    }

    // MARK: Messy-document generator

    static let scalarPool: [JSONValue] = [
        .null, .bool(true), .bool(false), .number(0), .number(-0.0), .number(1), .number(-1), .number(3), .number(2.5),
        .number(1e21), .number(1e-7), .number(0.000001), .number(123456789012345683968), .number(0.1), .number(1e300),
        .number(4.35), .number(100), .number(1234567.125), .number(5e-324), .number(0.00001234),
        .string(""), .string(" "), .string("3"), .string(" 4 "), .string("abc"), .string("0x10"), .string("0X1f"),
        .string("1e1"), .string("Infinity"), .string("-Infinity"), .string("+Infinity"), .string(".5"), .string("5."),
        .string("+3"), .string("-2"), .string("1_0"), .string("\u{00A0}7\u{00A0}"), .string("\u{0085}5"),
        .string("\u{200B}5"), .string("\u{3000}6\u{3000}"), .string("\u{FEFF}2"), .string("\u{2028}8"), .string("0b101"),
        .string("0o17"), .string("-0x5"), .string("1e400"), .string("NaN"), .string("infinity"), .string("0.1e1"),
        .string("00012"), .string("1.5e+1"), .string("\t9\n"), .string("\u{000B}3\u{000C}"), .string("\u{180E}4"),
        .array([]), .array([.number(4)]), .array([.number(1), .number(2)]), .array([.null]), .array([.string(" 6 ")]),
        .array([.array([.number(7)])]), .object([:]), .object(["a": .number(1)]),
    ]

    static let codePool: [String] = [
        "MATH 1241", "math 1241", " MATH 1241 ", "MATH  1241", "PHYS 2101", "PHYS 2101L", "CS-1", "cs-1", "ENGR_1201",
        "MEGR 2144", "MATH 10", "MATH 2", "MATH-10", "Math 1241", "ÉCON 201", "E\u{301}CON 201", "écon 201",
        "ΦΥΣ 101", "φυσ 101", "φυς 101", "ﬁn 100", "FIN 100", "STRASSE 1", "STRAßE 1", "İST 1", "ist 1",
        "\u{00A0}CHEM 1251\u{00A0}", "CHEM\u{00A0}1251", "chem 1251", "a", "A", "b", "_", "-", "1", "10", "2",
        "MATH\u{0007}1", "Ω 1", "ω 1", "日本 101", "𝐌𝐀𝐓𝐇 1", "C#", "C++", "c++", "x\u{0085}", "\u{0085}y",
    ]

    static func messyString(_ r: inout SeededRandom) -> JSONValue {
        r.chance(0.7) ? .string(r.pick(codePool)) : r.pick(scalarPool)
    }

    static func messyRefs(_ r: inout SeededRandom) -> JSONValue? {
        let x = r.unit()
        if x < 0.15 { return nil }
        if x < 0.25 { return r.pick(scalarPool) }
        var list: [JSONValue] = []
        for _ in 0 ..< r.int(0, 4) {
            let y = r.unit()
            if y < 0.6 { list.append(.string(r.pick(codePool))) }
            else if y < 0.7 { list.append(.array([.string(r.pick(codePool)), .number(1)])) }
            else { list.append(r.pick(scalarPool)) }
        }
        return .array(list)
    }

    static func messyCase(_ k: Int, _ r: inout SeededRandom) -> ParityCase {
        let now = r.pick(fixedNows)
        if k % 40 == 0 {
            let roots: [JSONValue] = [.null, .array([]), .number(0), .string("x"), .bool(true), .object([:]), .number(5), .bool(false),
                                      .array([.object(["id": .string("a")])]), .string("")]
            return ParityCase(name: "messy-\(k)-root", raw: roots[(k / 40) % roots.count], now: now)
        }
        var doc: [String: JSONValue] = [:]

        // Courses.
        let idPool: [JSONValue] = [.string("c-1"), .string("c-2"), .string("c-3"), .number(7), .number(8), .string(""), .number(0),
                                   .null, .bool(true), .bool(false), .string(" c-4 "), .string("c-é"), .string("c-e\u{301}"),
                                   .number(1.5), .string("7")]
        var courses: [JSONValue] = []
        for i in 0 ..< r.int(0, 18) {
            if r.chance(0.05) { courses.append(r.pick(scalarPool)); continue }
            var c: [String: JSONValue] = [:]
            if !r.chance(0.05) { c["id"] = r.chance(0.6) ? .string("m-\(k)-\(i)") : r.pick(idPool) }
            if !r.chance(0.08) { c["code"] = messyString(&r) }
            if !r.chance(0.2) { c["title"] = r.chance(0.5) ? .string("  Some title \(i) ") : messyString(&r) }
            if !r.chance(0.1) { c["credits"] = r.chance(0.4) ? r.pick(planCredits) : r.pick(scalarPool) }
            if let refs = messyRefs(&r) { c["prereqs"] = refs }
            if let refs = messyRefs(&r) { c["coreqs"] = refs }
            if r.chance(0.2), let refs = messyRefs(&r) { c["preOrCo"] = refs }
            if !r.chance(0.2) { c["summerOk"] = r.chance(0.5) ? .bool(r.chance(0.5)) : r.pick(scalarPool) }
            let termPool: [JSONValue] = [.string("fall-2025"), .string("spring-2026"), .string("summer-2025"), .string(""),
                                         .null, .number(2025), .string("Fall 2025"), .bool(true), .string("fall-2025 ")]
            if r.chance(0.5) { c["term"] = r.chance(0.8) ? r.pick(termPool) : r.pick(scalarPool) }
            if r.chance(0.1) { c["extra"] = .string("kept by Atlas, ignored") }
            courses.append(.object(c))
        }
        if !r.chance(0.08) { doc["courses"] = r.chance(0.93) ? .array(courses) : r.pick(scalarPool) }

        // Terms.
        let seasonPool: [JSONValue] = [.string("spring"), .string("summer"), .string("fall"), .string("fall"), .string("spring"),
                                       .string("Fall"), .string("winter"), .null, .number(1), .string(" fall")]
        let yearPool: [JSONValue] = [.number(2024), .number(2025), .number(2025), .number(2026), .string("2025"), .string(" 2026 "),
                                     .number(2025.5), .number(-1), .number(0), .number(1e21), .number(1e-7), .string(""), .null,
                                     .bool(true), .array([.number(2027)]), .string("0x7e9"), .string("2025abc"), .string("1e3"),
                                     .number(275_760), .number(-50), .number(99_999), .number(2025.0)]
        var terms: [JSONValue] = []
        for _ in 0 ..< r.int(0, 7) {
            if r.chance(0.07) { terms.append(r.pick(scalarPool)); continue }
            var t: [String: JSONValue] = [:]
            if !r.chance(0.05) { t["season"] = r.pick(seasonPool) }
            if !r.chance(0.05) { t["year"] = r.pick(yearPool) }
            if r.chance(0.6) { t["current"] = r.chance(0.6) ? .bool(r.chance(0.4)) : r.pick(scalarPool) }
            if r.chance(0.3) { t["key"] = .string("bogus-key") }
            terms.append(.object(t))
        }
        if !r.chance(0.08) { doc["terms"] = r.chance(0.93) ? .array(terms) : r.pick(scalarPool) }

        // Disabled terms.
        let disabledPool: [JSONValue] = [.string("summer-2026"), .string("summer-2027"), .string("fall-2026"), .string("summer-1e+21"),
                                         .string("summer"), .string("summer-"), .string(""), .string("winter-2026"),
                                         .string("summer-2026.5"), .string("summer-0x7ea")]
        var disabled: [JSONValue] = []
        for _ in 0 ..< r.int(0, 5) { disabled.append(r.chance(0.75) ? r.pick(disabledPool) : r.pick(scalarPool)) }
        if !r.chance(0.08) { doc["disabledTerms"] = r.chance(0.93) ? .array(disabled) : r.pick(scalarPool) }

        // Settings.
        if !r.chance(0.08) {
            if r.chance(0.08) { doc["settings"] = r.pick(scalarPool) }
            else {
                var g: [String: JSONValue] = [:]
                if !r.chance(0.15) { g["maxCredits"] = r.chance(0.5) ? r.pick([.number(15), .number(12), .number(6), .number(3)]) : r.pick(scalarPool) }
                if !r.chance(0.15) { g["summerMax"] = r.chance(0.5) ? r.pick([.number(9), .number(6), .number(0)]) : r.pick(scalarPool) }
                let strategies: [JSONValue] = [.string("soonest-summer"), .string("soonest-optional-summer"), .string("even"),
                                               .string("Even"), .null, .number(1), .string(" even")]
                if !r.chance(0.1) { g["strategy"] = r.pick(strategies) }
                doc["settings"] = .object(g)
            }
        }
        if r.chance(0.1) { doc["version"] = .number(1) }
        if r.chance(0.05) { doc["preOrCo"] = .array([]) }
        return ParityCase(name: "messy-\(k)", raw: .object(doc), now: now)
    }
}

/// splitmix64 — small, fast and fully deterministic across runs and platforms.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(next() % UInt64(hi - lo + 1)) }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0, items.count - 1)] }
}
