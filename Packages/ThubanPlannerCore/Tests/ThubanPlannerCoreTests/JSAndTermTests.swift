import XCTest
@testable import ThubanPlannerCore

final class JSAndTermTests: XCTestCase {
    // MARK: Term keys

    func testTermKeyHelpers() {
        XCTAssertEqual(TermKey.make(.fall, 2025), "fall-2025")
        XCTAssertEqual(TermKey.make(.spring, 2025.5), "spring-2025.5")
        XCTAssertEqual(TermKey.label("fall-2025"), "Fall 2025")
        XCTAssertEqual(TermKey.label("winter-2025"), "winter 2025")
        XCTAssertEqual(TermKey.rank("fall-2025"), 2025 * 3 + 2)
        XCTAssertEqual(TermKey.rank("spring-2026"), 2026 * 3)
        XCTAssertTrue(TermKey.rank("bogus").isNaN)
        XCTAssertEqual(TermKey.next("spring-2026"), "summer-2026")
        XCTAssertEqual(TermKey.next("summer-2026"), "fall-2026")
        XCTAssertEqual(TermKey.next("fall-2026"), "spring-2027")
        XCTAssertEqual(TermKey.previous("spring-2026"), "fall-2025")
        XCTAssertEqual(TermKey.previous("fall-2026"), "summer-2026")
        XCTAssertEqual(TermKey.previous("summer-2026"), "spring-2026")
        XCTAssertEqual(TermKey.season("summer-2026"), .summer)
    }

    func testCurrentTermKeyBoundaries() {
        let cal = TestSupport.utc
        XCTAssertEqual(TermKey.current(now: TestSupport.date("2026-01-01"), calendar: cal), "spring-2026")
        XCTAssertEqual(TermKey.current(now: TestSupport.date("2026-05-31"), calendar: cal), "spring-2026")
        XCTAssertEqual(TermKey.current(now: TestSupport.date("2026-06-01"), calendar: cal), "summer-2026")
        XCTAssertEqual(TermKey.current(now: TestSupport.date("2026-08-31"), calendar: cal), "summer-2026")
        XCTAssertEqual(TermKey.current(now: TestSupport.date("2026-09-01"), calendar: cal), "fall-2026")
        XCTAssertEqual(TermKey.current(now: TestSupport.date("2026-12-31"), calendar: cal), "fall-2026")
        // Atlas uses local time: UTC midnight Oct 1 is still Sep 30 in New York → fall either way; Sep 1 is not.
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(TermKey.current(now: TestSupport.date("2026-09-01"), calendar: ny), "summer-2026")
    }

    // MARK: JS semantics

    func testNumberCoercion() {
        XCTAssertTrue(JS.number(nil).isNaN)
        XCTAssertEqual(JS.number(.null), 0)
        XCTAssertEqual(JS.number(.bool(true)), 1)
        XCTAssertEqual(JS.number(.string("  12.5 ")), 12.5)
        XCTAssertEqual(JS.number(.string("")), 0)
        XCTAssertEqual(JS.number(.string("0x1F")), 31)
        XCTAssertEqual(JS.number(.string("0b101")), 5)
        XCTAssertEqual(JS.number(.string(".5")), 0.5)
        XCTAssertEqual(JS.number(.string("5.")), 5)
        XCTAssertEqual(JS.number(.string("-Infinity")), -.infinity)
        for bad in ["inf", "nan", "1_000", "12abc", "0x", "+0x10", "--1", "1e", "Infinityx"] {
            XCTAssertTrue(JS.number(.string(bad)).isNaN, bad)
        }
        XCTAssertEqual(JS.number(.array([])), 0)
        XCTAssertEqual(JS.number(.array([.number(7)])), 7)
        XCTAssertTrue(JS.number(.array([.number(1), .number(2)])).isNaN)
        XCTAssertTrue(JS.number(.object([:])).isNaN)
    }

    func testStringAndTruthiness() {
        XCTAssertEqual(JS.string(.number(3)), "3")
        XCTAssertEqual(JS.string(.number(1.5)), "1.5")
        XCTAssertEqual(JS.string(.array([.string("a"), .null, .number(2)])), "a,,2")
        XCTAssertEqual(JS.string(.object([:])), "[object Object]")
        XCTAssertEqual(JS.string(nil), "undefined")
        XCTAssertFalse(JS.truthy(.number(.nan)))
        XCTAssertFalse(JS.truthy(.string("")))
        XCTAssertTrue(JS.truthy(.string("false")))
        XCTAssertTrue(JS.truthy(.array([])))
        XCTAssertFalse(JS.truthy(nil))
    }

    func testNumberString() {
        XCTAssertEqual(JS.numberString(15), "15")
        XCTAssertEqual(JS.numberString(-0.0), "0")
        XCTAssertEqual(JS.numberString(4.5), "4.5")
        XCTAssertEqual(JS.numberString(0.1 + 0.2), "0.30000000000000004")
        XCTAssertEqual(JS.numberString(1e21), "1e+21")
        XCTAssertEqual(JS.numberString(1e-7), "1e-7")
        XCTAssertEqual(JS.numberString(.nan), "NaN")
        XCTAssertEqual(JS.numberString(-.infinity), "-Infinity")
    }

    func testMathRound() {
        XCTAssertEqual(JS.round(2.5), 3)
        XCTAssertEqual(JS.round(-2.5), -2)
        XCTAssertEqual(JS.round(0.49999999999999994), 0)
        XCTAssertEqual(JS.round(10.000000000000002), 10)
        XCTAssertTrue(JS.max(0, .nan).isNaN)
        XCTAssertEqual(JS.or(0, 5), 5)
        XCTAssertEqual(JS.or(.nan, -1), -1)
        XCTAssertEqual(JS.or(-2, 5), -2)
    }

    func testJSONValueKeepsBooleansAndNumbersApart() throws {
        let v = try JSONValue.parse(Data(#"[true, 1, 0, false, "1", null, 1.5]"#.utf8))
        XCTAssertEqual(v, .array([.bool(true), .number(1), .number(0), .bool(false), .string("1"), .null, .number(1.5)]))
    }

    // MARK: localeCompare

    func testLocaleCompareMatchesJavaScriptCoreOrderForASCII() {
        // Output of JavaScriptCore: [...printable ASCII].sort((a, b) => a.localeCompare(b)).join('')
        let expected = Array(" _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ")
        let chars = (32 ..< 127).map { Character(UnicodeScalar(UInt8($0))) }
        let sorted = V8Sort.sorted(chars) { Double(JS.localeCompare(String($0), String($1))) }
        XCTAssertEqual(String(sorted), String(expected))
    }

    func testLocaleCompareOnCodes() {
        let codes = ["cs 101", "cs-101", "cs101", "cs_101", "cs.101", "cs1010", "cs 10a", "math2", "math10"]
        let sorted = V8Sort.sorted(codes) { Double(JS.localeCompare($0, $1)) }
        // Same list JavaScriptCore produced.
        XCTAssertEqual(sorted, ["cs 101", "cs 10a", "cs_101", "cs-101", "cs.101", "cs101", "cs1010", "math10", "math2"])
        XCTAssertEqual(JS.localeCompare("abc", "ABC"), -1, "lowercase first on the tertiary level")
        XCTAssertEqual(JS.localeCompare("abc", "abc"), 0)
        XCTAssertEqual(JS.localeCompare("ab", "abc"), -1)
        XCTAssertEqual(JS.localeCompare("é", "f"), -1, "non-ASCII falls back to ICU via Foundation")
    }

    // MARK: V8 sort

    func testV8SortIsASortedStableSort() {
        var generator = SystemRandomNumberGenerator()
        for trial in 0 ..< 300 {
            let n = trial < 150 ? Int.random(in: 0 ..< 80, using: &generator) : Int.random(in: 0 ..< 1500, using: &generator)
            let keys = Swift.max(1, n / Int.random(in: 1 ... 8, using: &generator))
            var items = (0 ..< n).map { (key: Int.random(in: 0 ..< keys, using: &generator), position: $0) }
            if trial % 3 == 0 { items.sort { $0.key < $1.key }; items = items.enumerated().map { (key: $1.key, position: $0) } }
            if trial % 5 == 0 { items.reverse(); items = items.enumerated().map { (key: $1.key, position: $0) } }
            let sorted = V8Sort.sorted(items) { Double($0.key - $1.key) }
            XCTAssertEqual(sorted.count, n)
            for i in sorted.indices.dropFirst() {
                let a = sorted[i - 1], b = sorted[i]
                XCTAssertTrue(a.key < b.key || (a.key == b.key && a.position < b.position), "trial \(trial)")
                if !(a.key < b.key || (a.key == b.key && a.position < b.position)) { return }
            }
        }
    }

    func testV8SortComparatorCallOrderForShortArrays() {
        // n < 64: CountAndMakeRun then binary insertion — the first call compares element 1 with element 0.
        var calls: [String] = []
        _ = V8Sort.sorted(["b", "a", "c", "d"]) { x, y in calls.append("\(x)\(y)"); return x < y ? -1 : (x > y ? 1 : 0) }
        XCTAssertEqual(calls.first, "ab")
        XCTAssertEqual(calls, ["ab", "ca", "cb", "db", "dc"])
    }
}
