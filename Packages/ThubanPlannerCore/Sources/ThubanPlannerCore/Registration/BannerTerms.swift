import Foundation

/// A term as UNC Charlotte's Banner Student Registration lists it (`classSearch/getTerms`): a six-digit code and a
/// description ("Spring 2027 (View Only)" → "Spring 2027").
public struct BannerTerm: Codable, Hashable, Sendable, Identifiable {
    /// "202710".
    public var code: String
    /// Banner's description without the " (View Only)" suffix: "Spring 2027".
    public var description: String
    /// Banner marked the term "(View Only)" (registration closed; class search and planning still work).
    public var viewOnly: Bool

    public var id: String { code }

    public init(code: String, description: String, viewOnly: Bool = false) {
        self.code = code
        self.description = description
        self.viewOnly = viewOnly
    }

    /// The Thuban term key ("spring-2027"), when the code follows the YYYY + season convention.
    public var termKey: String? { BannerTermCode.termKey(code) }

    /// Decodes `getTerms` output (`[{code, description}]`), tolerant of extra fields and odd rows.
    public static func decodeList(_ data: Data) throws -> [BannerTerm] {
        guard let rows = try JSONValue.parse(data).arrayValue else {
            throw ThubanError.decoding("The term list was not a JSON array.")
        }
        return rows.compactMap { row -> BannerTerm? in
            guard let code = row["code"]?.bannerString, !code.isEmpty else { return nil }
            let raw = row["description"]?.bannerString ?? code
            let (description, viewOnly) = BannerTermCode.cleanDescription(raw)
            return BannerTerm(code: code, description: description.isEmpty ? (BannerTermCode.termKey(code).map(TermKey.label) ?? code) : description,
                              viewOnly: viewOnly)
        }
    }
}

/// Banner term codes ↔ Thuban term keys. UNC Charlotte: `YYYY` + `10` spring, `60` summer, `80` fall (older years
/// split summer into `50` / `70`; both read as summer). The year is the calendar year of the term.
public enum BannerTermCode {
    public static func season(ofSuffix suffix: String) -> Season? {
        switch suffix {
        case "10": return .spring
        case "50", "60", "70": return .summer
        case "80": return .fall
        default: return nil
        }
    }

    /// "202710" → "spring-2027"; nil for anything that is not six digits with a known season suffix.
    public static func termKey(_ code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber),
              let year = Int(trimmed.prefix(4)), let season = season(ofSuffix: String(trimmed.suffix(2))) else { return nil }
        return TermKey.make(season, year)
    }

    /// "spring-2027" → "202710" (summer maps to the current `60`); nil for malformed keys.
    public static func code(forTermKey key: String) -> String? {
        let p = TermKey.parse(key)
        guard let season = p.season, p.year.isFinite, p.year == p.year.rounded(), p.year >= 1000, p.year <= 9999 else { return nil }
        let suffix: String
        switch season {
        case .spring: suffix = "10"
        case .summer: suffix = "60"
        case .fall: suffix = "80"
        }
        return "\(Int(p.year))\(suffix)"
    }

    /// Strips Banner's " (View Only)" marker (any case, any spacing) and collapses white space.
    public static func cleanDescription(_ raw: String) -> (description: String, viewOnly: Bool) {
        var text = raw
        var viewOnly = false
        if let range = text.range(of: #"\s*\(\s*view\s+only\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
            viewOnly = true
        }
        return (BannerText.collapse(text), viewOnly)
    }
}

/// Small text helpers for Banner payloads.
public enum BannerText {
    /// Trims and collapses runs of white space ("Hybrid:  F2F & Online (Sync)" → "Hybrid: F2F & Online (Sync)").
    public static func collapse(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Splits a course code into Banner's subject and course number: "MEGR 2144" → ("MEGR", "2144"),
    /// "megr2144" → ("MEGR", "2144"), "PHYS 2101L" → ("PHYS", "2101L"). Nil when there is no subject or number.
    public static func splitCourseCode(_ code: String) -> (subject: String, number: String)? {
        let compact = code.uppercased().filter { !$0.isWhitespace }
        guard let firstDigit = compact.firstIndex(where: { $0.isNumber }) else { return nil }
        let subject = String(compact[..<firstDigit])
        let number = String(compact[firstDigit...])
        guard !subject.isEmpty, subject.allSatisfy({ $0.isLetter && $0.isASCII }),
              !number.isEmpty, number.allSatisfy({ ($0.isLetter || $0.isNumber) && $0.isASCII }) else { return nil }
        return (subject, number)
    }

    /// The canonical display form "MEGR 2144" (nil when the code cannot be split).
    public static func canonicalCourseCode(_ code: String) -> String? {
        splitCourseCode(code).map { "\($0.subject) \($0.number)" }
    }
}

// MARK: - Tolerant JSON accessors for Banner payloads

extension JSONValue {
    /// A string, or a number / bool printed as text (Banner mixes them: CRNs are strings, ids numbers).
    var bannerString: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// A number, or a numeric string.
    var bannerDouble: Double? {
        switch self {
        case .number(let n): return n.isFinite ? n : nil
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    var bannerInt: Int? { bannerDouble.map { Int($0.rounded()) } }

    /// true / "true" / "Y" / 1.
    var bannerBool: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s):
            switch s.lowercased().trimmingCharacters(in: .whitespaces) {
            case "true", "y", "yes", "1": return true
            case "false", "n", "no", "0", "": return false
            default: return nil
            }
        default: return nil
        }
    }

    var bannerObject: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}
