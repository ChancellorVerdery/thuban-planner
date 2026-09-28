import Foundation

/// The handful of JavaScript semantics Atlas's course planner relies on, reproduced exactly so the Swift port gives
/// the same answers: truthiness, `Number(x)`, `String(x)`, number-to-text, `Math.round/max/min`, and
/// `String.prototype.localeCompare` for course codes. A missing value (JS `undefined`) is `nil`.
public enum JS {
    // MARK: Truthiness

    /// `!!x`.
    public static func truthy(_ value: JSONValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    // MARK: Number(x)

    /// `Number(x)`: undefined → NaN, null → 0, booleans → 0/1, strings by the StringToNumber grammar, arrays through
    /// their string form, objects → NaN.
    public static func number(_ value: JSONValue?) -> Double {
        guard let value else { return .nan }
        switch value {
        case .null: return 0
        case .bool(let b): return b ? 1 : 0
        case .number(let n): return n
        case .string(let s): return number(fromString: s)
        case .array: return number(fromString: string(value))
        case .object: return .nan
        }
    }

    /// JS StringToNumber: surrounding white space ignored, "" → 0, decimal literals (with exponent), ±Infinity, and
    /// unsigned 0x / 0o / 0b integers. Anything else → NaN (so "12abc", "inf", "nan", "1_000" are NaN).
    public static func number(fromString raw: String) -> Double {
        let s = raw.trimmingCharacters(in: jsWhitespace)
        if s.isEmpty { return 0 }
        switch s {
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }
        let lower = s.lowercased()
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where lower.hasPrefix(prefix) {
            let digits = s.dropFirst(2)
            guard !digits.isEmpty else { return .nan }
            var total = 0.0
            for ch in digits {
                guard let d = ch.hexDigitValue, d < radix else { return .nan }
                total = total * Double(radix) + Double(d)
            }
            return total
        }
        guard s.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil else { return .nan }
        return Double(s) ?? .nan
    }

    // MARK: String(x)

    /// `String(x)`: numbers as JS prints them, arrays joined with "," (null / undefined elements empty), objects
    /// "[object Object]". Undefined → "undefined".
    public static func string(_ value: JSONValue?) -> String {
        guard let value else { return "undefined" }
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return numberString(n)
        case .string(let s): return s
        case .array(let a):
            return a.map { element -> String in
                if case .null = element { return "" }
                return string(element)
            }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    /// Number → text the way JavaScript prints it: integers without ".0", "NaN", "Infinity", otherwise the shortest
    /// round-trip form (Swift's `description`, which matches JS for everything a planner holds; exponent forms are
    /// rewritten to JS's "1e-7" / "1e+21").
    public static func numberString(_ n: Double) -> String {
        if n.isNaN { return "NaN" }
        if n.isInfinite { return n > 0 ? "Infinity" : "-Infinity" }
        if n == 0 { return "0" }
        if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
        var text = n.description
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            var mantissa = String(text[..<e])
            if mantissa.hasSuffix(".0") { mantissa.removeLast(2) }
            var exponent = String(text[text.index(after: e)...])
            if !exponent.hasPrefix("-") && !exponent.hasPrefix("+") { exponent = "+" + exponent }
            let sign = exponent.first!
            let digits = exponent.dropFirst().drop { $0 == "0" }
            text = mantissa + "e" + String(sign) + (digits.isEmpty ? "0" : String(digits))
        } else if text.hasSuffix(".0") {
            text.removeLast(2)
        }
        return text
    }

    // MARK: Math

    /// `Math.round`: halves round up (toward +∞), NaN stays NaN.
    public static func round(_ x: Double) -> Double {
        if x.isNaN || x.isInfinite { return x }
        let floor = x.rounded(.down)
        return x - floor >= 0.5 ? floor + 1 : floor
    }

    /// `Math.max(a, b)` (NaN wins).
    public static func max(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        return Swift.max(a, b)
    }

    /// `Math.min(a, b)` (NaN wins).
    public static func min(_ a: Double, _ b: Double) -> Double {
        if a.isNaN || b.isNaN { return .nan }
        return Swift.min(a, b)
    }

    /// JS `a || b` for numbers: `a` unless it is 0 or NaN.
    public static func or(_ a: Double, _ b: @autoclosure () -> Double) -> Double {
        (a != 0 && !a.isNaN) ? a : b()
    }

    // MARK: String helpers

    /// `String.prototype.trim()` white space (Unicode spaces + line terminators + BOM).
    public static let jsWhitespace: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{FEFF}\u{00A0}\u{2028}\u{2029}")
        return set
    }()

    public static func trim(_ s: String) -> String { s.trimmingCharacters(in: jsWhitespace) }

    // MARK: localeCompare

    /// `a.localeCompare(b)` as V8 / JavaScriptCore compute it with ICU's root collation (no options): -1, 0 or 1.
    ///
    /// For printable ASCII (every real course code) this is an exact table-driven reimplementation of the CLDR root
    /// order — white space < punctuation `_ - , ; : ! ? . ' " ( ) [ ] { } @ * / \ & # % ` ^ + < = > | ~ $` < digits <
    /// letters — compared on the primary level first (case-insensitive, over the whole string), then the tertiary
    /// level (lowercase before uppercase). Digits are NOT numeric ("math10" < "math2"), like JS. The order was
    /// checked against JavaScriptCore's `localeCompare` (tools/golden). Strings with other characters fall back to
    /// Foundation's ICU-backed `compare(_:locale:)` in `en_US`, which agrees for ordinary text.
    public static func localeCompare(_ a: String, _ b: String) -> Int {
        if let pa = asciiKeys(a), let pb = asciiKeys(b) {
            // Primary: the whole string, case-folded.
            for (x, y) in zip(pa, pb) where x.primary != y.primary { return x.primary < y.primary ? -1 : 1 }
            if pa.count != pb.count { return pa.count < pb.count ? -1 : 1 }
            // Tertiary: first case difference (lowercase first).
            for (x, y) in zip(pa, pb) where x.tertiary != y.tertiary { return x.tertiary < y.tertiary ? -1 : 1 }
            return 0
        }
        switch a.compare(b, options: [], range: nil, locale: Locale(identifier: "en_US")) {
        case .orderedAscending: return -1
        case .orderedDescending: return 1
        case .orderedSame: return 0
        }
    }

    private struct CollationKey { var primary: Int; var tertiary: Int }

    /// ICU root order of the ASCII characters that carry weight (controls other than white space are ignorable).
    private static let asciiOrder: [Character] = Array("\t\n\u{0B}\u{0C}\r _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789abcdefghijklmnopqrstuvwxyz")

    private static let primaryWeight: [UInt8: Int] = {
        var table: [UInt8: Int] = [:]
        for (index, ch) in asciiOrder.enumerated() {
            let byte = ch.asciiValue!
            table[byte] = index
            if ch.isLetter { table[Character(ch.uppercased()).asciiValue!] = index }
        }
        return table
    }()

    /// nil when the string has a non-ASCII scalar (use the Foundation fallback).
    private static func asciiKeys(_ s: String) -> [CollationKey]? {
        var keys: [CollationKey] = []
        keys.reserveCapacity(s.utf8.count)
        for byte in s.utf8 {
            guard byte < 0x80 else { return nil }
            guard let weight = primaryWeight[byte] else { continue } // ignorable control character
            let isUpper = byte >= 0x41 && byte <= 0x5A
            keys.append(CollationKey(primary: weight, tertiary: isUpper ? 1 : 0))
        }
        return keys
    }
}
