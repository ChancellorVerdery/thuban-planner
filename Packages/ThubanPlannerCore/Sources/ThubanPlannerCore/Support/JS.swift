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

    /// Number → text exactly as JavaScript's `Number::toString` prints it: the shortest round-trip digits (Swift's
    /// `description` computes the same shortest digit string), laid out by ECMA-262's rules — plain integers up to
    /// 21 digits ("123456789012345680000"), plain decimals down to 1e-6 ("0.000001"), exponent form outside that
    /// ("1e+21", "1e-7", "1.5e-10"); "NaN", "Infinity", and -0 → "0".
    public static func numberString(_ n: Double) -> String {
        if n.isNaN { return "NaN" }
        if n.isInfinite { return n > 0 ? "Infinity" : "-Infinity" }
        if n == 0 { return "0" }
        if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
        let sign = n < 0 ? "-" : ""
        // Shortest digits D and exponent p with |n| = D × 10^p, from Swift's shortest round-trip description.
        let text = abs(n).description
        var mantissa = Substring(text)
        var p = 0
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = text[..<e]
            p = Int(text[text.index(after: e)...].replacingOccurrences(of: "+", with: "")) ?? 0
        }
        var digits = ""
        if let dot = mantissa.firstIndex(of: ".") {
            let fraction = mantissa[mantissa.index(after: dot)...]
            digits = String(mantissa[..<dot]) + fraction
            p -= fraction.count
        } else {
            digits = String(mantissa)
        }
        digits = String(digits.drop { $0 == "0" })
        while digits.hasSuffix("0") { digits.removeLast(); p += 1 }
        let k = digits.count
        let point = k + p // ECMA-262's n: |value| = 0.d1…dk × 10^point
        if k <= point && point <= 21 { return sign + digits + String(repeating: "0", count: point - k) }
        if 0 < point && point <= 21 {
            let head = digits.prefix(point)
            return sign + head + "." + digits.dropFirst(point)
        }
        if -6 < point && point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + digits }
        let exponent = point - 1
        let expText = "e" + (exponent < 0 ? "-" : "+") + String(abs(exponent))
        if k == 1 { return sign + digits + expText }
        return sign + digits.prefix(1) + "." + digits.dropFirst() + expText
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

    /// `String.prototype.trim()` / StringToNumber white space, exactly ECMA-262's WhiteSpace + LineTerminator:
    /// TAB, VT, FF, ZWNBSP (BOM), the Zs space separators (U+0020, U+00A0, U+1680, U+2000–U+200A, U+202F, U+205F,
    /// U+3000), LF, CR, LS and PS. Deliberately NOT Foundation's `whitespacesAndNewlines`, which also strips NEL
    /// (U+0085) and other controls that JavaScript keeps.
    public static let jsWhitespace: CharacterSet = {
        var set = CharacterSet(charactersIn: "\u{0009}\u{000B}\u{000C}\u{FEFF}\u{0020}\u{00A0}\u{1680}\u{202F}\u{205F}\u{3000}")
        set.insert(charactersIn: "\u{2000}" ... "\u{200A}")
        set.insert(charactersIn: "\u{000A}\u{000D}\u{2028}\u{2029}")
        return set
    }()

    public static func trim(_ s: String) -> String { s.trimmingCharacters(in: jsWhitespace) }

    /// `String.prototype.toLowerCase()`: Unicode's default full lowercase mapping PLUS the one context-sensitive
    /// rule JavaScript applies and Swift's `lowercased()` does not — Final_Sigma ("ΦΥΣ 101" → "φυς 101", not
    /// "φυσ 101"; also "Α.Σ" → "α.ς").
    public static func toLowerCase(_ s: String) -> String {
        guard s.unicodeScalars.contains("\u{03A3}") else { return s.lowercased() }
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        for (i, u) in scalars.enumerated() {
            if u == "\u{03A3}" && isFinalSigma(scalars, i) { out.append("\u{03C2}") }
            else { out.append(contentsOf: String(u).lowercased().unicodeScalars) }
        }
        return String(out)
    }

    /// Unicode Final_Sigma: preceded by a cased letter (skipping case-ignorables) and not followed by one.
    private static func isFinalSigma(_ scalars: [Unicode.Scalar], _ i: Int) -> Bool {
        var j = i - 1
        while j >= 0 && scalars[j].properties.isCaseIgnorable { j -= 1 }
        guard j >= 0 && scalars[j].properties.isCased else { return false }
        var k = i + 1
        while k < scalars.count && scalars[k].properties.isCaseIgnorable { k += 1 }
        return !(k < scalars.count && scalars[k].properties.isCased)
    }

    // MARK: localeCompare

    /// `a.localeCompare(b)` as V8 / JavaScriptCore compute it with ICU's root collation (no options): -1, 0 or 1.
    ///
    /// For printable ASCII (every real course code) this is an exact table-driven reimplementation of the CLDR root
    /// order — white space < punctuation `_ - , ; : ! ? . ' " ( ) [ ] { } @ * / \ & # % ` ^ + < = > | ~ $` < digits <
    /// letters — compared on the primary level first (case-insensitive, over the whole string), then the tertiary
    /// level (lowercase before uppercase). Digits are NOT numeric ("math10" < "math2"), like JS. The order was
    /// checked against JavaScriptCore's `localeCompare` (tools/golden, DifferentialParityTests). Strings with other
    /// characters go to ICU itself (`ICUCollator`: the system's libicucore, root collation, default attributes — what
    /// both JS engines call). Foundation's `compare(_:locale:)` is only the last resort if ICU cannot be loaded: it
    /// is NOT the same order (it ties "ﬁn"/"fin" and "φυς"/"φυσ", which ICU separates at the tertiary level).
    public static func localeCompare(_ a: String, _ b: String) -> Int {
        if let pa = asciiKeys(a), let pb = asciiKeys(b) {
            // Primary: the whole string, case-folded.
            for (x, y) in zip(pa, pb) where x.primary != y.primary { return x.primary < y.primary ? -1 : 1 }
            if pa.count != pb.count { return pa.count < pb.count ? -1 : 1 }
            // Tertiary: first case difference (lowercase first).
            for (x, y) in zip(pa, pb) where x.tertiary != y.tertiary { return x.tertiary < y.tertiary ? -1 : 1 }
            return 0
        }
        if let result = ICUCollator.root?.compare(a, b) { return result }
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

/// A string compared and hashed by its UTF-16 code units — JavaScript's `===`, `Map` and `Set` key semantics.
/// Swift's `String ==` uses Unicode canonical equivalence ("é" == "e\u{301}"), which would merge ids, codes and
/// term keys that Atlas keeps apart, so every id / code / key lookup in the scheduler goes through this.
public struct JSKey: Hashable, Sendable {
    public let text: String
    public init(_ text: String) { self.text = text }

    public static func == (a: JSKey, b: JSKey) -> Bool { a.text.utf16.elementsEqual(b.text.utf16) }

    public func hash(into hasher: inout Hasher) {
        for unit in text.utf16 { hasher.combine(unit) }
        hasher.combine(text.utf16.count)
    }
}

/// ICU's collator from the system's libicucore (the library JavaScriptCore itself uses for `localeCompare`),
/// loaded dynamically: root locale, default attributes (tertiary strength), which is what `a.localeCompare(b)` with
/// no arguments uses for English locales. nil when the library or its symbols cannot be found.
final class ICUCollator: @unchecked Sendable {
    private typealias Open = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<Int32>) -> OpaquePointer?
    private typealias StrColl = @convention(c) (OpaquePointer?, UnsafePointer<UInt16>?, Int32, UnsafePointer<UInt16>?, Int32) -> Int32

    private let collator: OpaquePointer
    private let strcoll: StrColl

    static let root: ICUCollator? = ICUCollator(locale: "")

    private init?(locale: String) {
        guard let lib = dlopen("/usr/lib/libicucore.A.dylib", RTLD_NOW),
              let openSym = dlsym(lib, "ucol_open"), let collSym = dlsym(lib, "ucol_strcoll") else { return nil }
        let open = unsafeBitCast(openSym, to: Open.self)
        var status: Int32 = 0
        guard let collator = locale.withCString({ open($0, &status) }), status <= 0 else { return nil }
        self.collator = collator
        self.strcoll = unsafeBitCast(collSym, to: StrColl.self)
    }

    /// -1, 0 or 1 (ICU's UCOL_LESS / EQUAL / GREATER). Collation is a const operation, safe from any thread.
    func compare(_ a: String, _ b: String) -> Int {
        let x = Array(a.utf16), y = Array(b.utf16)
        let r = x.withUnsafeBufferPointer { px in
            y.withUnsafeBufferPointer { py in
                strcoll(collator, px.baseAddress, Int32(px.count), py.baseAddress, Int32(py.count))
            }
        }
        return r < 0 ? -1 : (r > 0 ? 1 : 0)
    }
}
