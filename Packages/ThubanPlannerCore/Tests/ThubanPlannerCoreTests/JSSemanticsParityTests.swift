import XCTest
import JavaScriptCore
@testable import ThubanPlannerCore

/// The JavaScript primitives the port reimplements (`JS`), checked exhaustively or on large seeded samples against
/// a real engine (JavaScriptCore, in-process). Each of these was a source of real mismatches found by
/// `DifferentialParityTests` and fixed in the Swift.
final class JSSemanticsParityTests: XCTestCase {
    private var context: JSContext!

    override func setUpWithError() throws {
        context = try XCTUnwrap(JSContext())
    }

    /// Calls `fn` (a JS function source taking one array) on `input` and returns the array it produces.
    private func jsMap(_ fn: String, _ input: [Any]) throws -> [Any] {
        let f = try XCTUnwrap(context.evaluateScript("(\(fn))"))
        let out = try XCTUnwrap(f.call(withArguments: [input]).toArray())
        XCTAssertNil(context.exception, context.exception?.toString() ?? "")
        return out
    }

    // MARK: Number → string

    func testNumberStringMatchesJavaScript() throws {
        var r = SeededRandom(seed: 42)
        var values: [Double] = [0, -0.0, 1, -1, 0.1, 0.2, 0.30000000000000004, 1e21, 1e-7, 1e-6, 0.000001234, 123456789012345683968,
                                1e300, 5e-324, 1.7976931348623157e308, 2.5, 1e15, 1e16, 123456789.125, 99999999999999999999.0,
                                1e20, 1.5e-10, 4.35, 100, 2025.5, -2.5e-8, 1234567.125]
        for _ in 0 ..< 20_000 {
            let bits = r.next()
            let d = Double(bitPattern: bits)
            if d.isFinite { values.append(d) }
            values.append(Double(r.int(-1_000_000, 1_000_000)) / Double([1, 10, 100, 1000, 3, 7][r.int(0, 5)]))
            values.append(pow(10, Double(r.int(-25, 25))) * r.unit())
        }
        let js = try jsMap("a => a.map(String)", values)
        for (value, text) in zip(values, js) {
            XCTAssertEqual(JS.numberString(value), text as? String, "\(value)")
        }
    }

    // MARK: String → number

    func testNumberFromStringMatchesJavaScript() throws {
        var inputs = ["", " ", "3", " 4 ", "abc", "0x10", "0X1f", "0b101", "0o17", "-0x5", "1e1", "1e400", "-1e400", "Infinity",
                      "-Infinity", "+Infinity", "infinity", "NaN", ".5", "5.", "+3", "-2", "1_0", "00012", "0.1e1", "1.5e+1",
                      "1e", "e1", ".", "+", "-", "0x", "\u{00A0}7\u{00A0}", "\u{0085}5", "\u{200B}5", "\u{3000}6", "\u{FEFF}2",
                      "\u{2028}8", "\u{180E}4", "\t9\n", "1 2", "١٢", "１２", "0.0000001", "123456789012345678901234567890"]
        var r = SeededRandom(seed: 7)
        let alphabet = Array("0123456789.eE+-x ")
        for _ in 0 ..< 3000 { inputs.append(String((0 ..< r.int(1, 6)).map { _ in r.pick(alphabet) })) }
        let js = try jsMap("a => a.map(x => { const n = Number(x); return Number.isNaN(n) ? 'NaN' : n })", inputs)
        for (input, value) in zip(inputs, js) {
            let swift = JS.number(fromString: input)
            if let text = value as? String { XCTAssertTrue(swift.isNaN, "Number(\(input.debugDescription)) = NaN, swift \(swift)") }
            else { XCTAssertEqual(swift, (value as? NSNumber)?.doubleValue, "Number(\(input.debugDescription))") }
        }
    }

    // MARK: trim / toLowerCase (every BMP code point)

    func testTrimMatchesJavaScriptForEveryBMPCodePoint() throws {
        let scalars = (0 ... 0xFFFF).compactMap(Unicode.Scalar.init).filter { $0.value != 0 }
        let inputs = scalars.map { "\($0)x\($0)" }
        let js = try jsMap("a => a.map(s => s.trim())", inputs)
        for (input, text) in zip(inputs, js) {
            XCTAssertEqual(JS.trim(input), text as? String, "U+\(String(input.unicodeScalars.first!.value, radix: 16))")
        }
    }

    func testToLowerCaseMatchesJavaScript() throws {
        var inputs = (0 ... 0xFFFF).compactMap(Unicode.Scalar.init).filter { $0.value != 0 }.map { String($0) }
        inputs += ["ΦΥΣ 101", "ΣΑ", "Α.Σ", "ΑΣ'Β", "ΑΣ\u{301}", "ΑΣ\u{301}Β", "Σ", " Σ ", "ΑΣΣ", "ΑΣ-Β", "İST 1", "ΑΣ1"]
        let js = try jsMap("a => a.map(s => s.toLowerCase())", inputs)
        var failures = 0
        for (input, text) in zip(inputs, js) where JS.toLowerCase(input) != text as? String {
            failures += 1
            if failures < 10 { XCTFail("toLowerCase(\(input.debugDescription)): swift \(JS.toLowerCase(input).debugDescription) js \(String(describing: text))") }
        }
        XCTAssertEqual(failures, 0)
    }

    // MARK: localeCompare

    func testLocaleCompareMatchesJavaScript() throws {
        XCTAssertNotNil(ICUCollator.root, "libicucore collator")
        var r = SeededRandom(seed: 99)
        let ascii = (0x20 ... 0x7E).map { Character(Unicode.Scalar($0)!) } + ["\t", "\u{7}"]
        let wide: [Character] = ["é", "e\u{301}", "É", "ß", "ﬁ", "φ", "ς", "σ", "Σ", "ω", "日", "𝐌", "İ", "ı", "\u{00A0}", "ø", "Å", "ñ"]
        var pairs: [[String]] = []
        for c1 in ascii { for c2 in ascii { pairs.append([String(c1), String(c2)]) } }
        for _ in 0 ..< 8000 {
            let pool = r.chance(0.7) ? ascii : ascii + wide
            let a = String((0 ..< r.int(0, 6)).map { _ in r.pick(pool) })
            var b = String((0 ..< r.int(0, 6)).map { _ in r.pick(pool) })
            if r.chance(0.3) { b = a.lowercased() }
            if r.chance(0.2) { b = a + String(r.pick(pool)) }
            pairs.append([a, b])
        }
        let js = try jsMap("a => a.map(([x, y]) => x.localeCompare(y))", pairs)
        var failures = 0
        for (pair, value) in zip(pairs, js) {
            let expected = (value as? NSNumber)?.intValue ?? 99
            if JS.localeCompare(pair[0], pair[1]) != expected.signum() {
                failures += 1
                if failures < 10 { XCTFail("\(pair[0].debugDescription).localeCompare(\(pair[1].debugDescription)) = \(expected), swift \(JS.localeCompare(pair[0], pair[1]))") }
            }
        }
        XCTAssertEqual(failures, 0)
    }

    // MARK: Dates

    /// `currentTermKey(now)` reads `getMonth()` / `getFullYear()`: Gregorian, in local time, whatever the user's
    /// calendar system.
    func testCurrentTermIsGregorianWhateverTheUsersCalendar() throws {
        let now = TestSupport.date("2026-09-28")
        for id in [Calendar.Identifier.buddhist, .japanese, .hebrew, .islamicUmmAlQura, .gregorian] {
            var calendar = Calendar(identifier: id)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            XCTAssertEqual(TermKey.current(now: now, calendar: calendar), "fall-2026", "\(id)")
        }
        let js = try XCTUnwrap(context.evaluateScript("(() => { const d = new Date(\(now.timeIntervalSince1970 * 1000)); return [d.getUTCMonth(), d.getUTCFullYear()] })()").toArray())
        XCTAssertEqual(js.compactMap { ($0 as? NSNumber)?.intValue }, [8, 2026])
    }

    // MARK: JS string identity

    func testJSKeyUsesCodeUnitsNotCanonicalEquivalence() {
        XCTAssertEqual("é", "e\u{301}") // Swift: canonically equivalent …
        XCTAssertNotEqual(JSKey("é"), JSKey("e\u{301}")) // … JavaScript: different strings.
        XCTAssertEqual(Set([JSKey("é"), JSKey("e\u{301}"), JSKey("é")]).count, 2)
        XCTAssertEqual(PlannerData.uniq(["É", "E\u{301}", "É"]), ["É", "E\u{301}"])
    }
}
