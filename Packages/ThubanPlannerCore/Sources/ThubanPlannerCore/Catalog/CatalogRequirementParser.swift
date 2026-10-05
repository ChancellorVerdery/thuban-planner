import Foundation

/// Course codes as UNC Charlotte writes them ("MEGR 3090", "PHYS 2101L"): normalization, matching and the small table
/// of equivalent codes the university itself treats as the same requirement.
public enum CourseCode {
    /// "megr3090" / " MEGR  3090 " → "MEGR 3090"; anything that is not SUBJ + number is trimmed and upper-cased.
    public static func normalize(_ code: String) -> String {
        BannerText.canonicalCourseCode(code) ?? BannerText.collapse(code).uppercased()
    }

    /// Case- and space-insensitive key ("MEGR3090").
    public static func key(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace }
    }

    /// "MEGR 3090" → "MEGR".
    public static func subject(_ code: String) -> String {
        BannerText.splitCourseCode(code)?.subject ?? ""
    }

    /// Codes UNC Charlotte counts as the same requirement.
    /// - PHYS 2101L ↔ PHYS 1101L: a DegreeWorks audit (BSME, 2025-26) satisfies "Introductory Physics I Lab" (catalog:
    ///   PHYS 2101L) with PHYS 1101L.
    /// - The BSME curriculum change: the 2025-26 catalog itself lists each old / new pair as interchangeable
    ///   requirements — "MEGR 3122 or MEGR 3123" (MEGR 4143, 4211, 4235, 4237), "either MEGR 2240 or MEGR 2242" (MEGR
    ///   3225, 4213, 4281 …), "MEGR 3171L or MEGR 3174" (MEGR 3152, 3255), "MEGR 2156 or MEGR 2157" — while other
    ///   pages still name only the old code (MEGR 3237: "MEGR 3122"; MEGR 3251: "MEGR 3171L").
    public static let equivalents: [[String]] = [
        ["PHYS 2101L", "PHYS 1101L"],
        ["MEGR 3123", "MEGR 3122"],
        ["MEGR 2242", "MEGR 2240"],
        ["MEGR 3174", "MEGR 3171L"],
        ["MEGR 2157", "MEGR 2156"],
    ]

    /// `code` and every code equivalent to it (normalized; `code` first).
    public static func equivalentCodes(_ code: String) -> [String] {
        let n = normalize(code)
        var out = [n]
        for set in equivalents where set.map(key).contains(key(n)) {
            for other in set where key(other) != key(n) { out.append(normalize(other)) }
        }
        return out
    }
}

/// Parses catalog requirement text — "MATH 2171, MEGR 2144, and either MEGR 2240 or MEGR 2242 with grades of C or
/// above" — into an AND of OR-groups ([["MATH 2171"], ["MEGR 2144"], ["MEGR 2240", "MEGR 2242"]]) plus notes for the
/// conditions that are not courses (grades, permission, asides). Mirrors tools/catalog/reqparse.py rule for rule; the
/// tests check both agree on every course in the bundled dataset.
///
/// Rules: grade phrases ("with grades of C or above") and waivers ("or permission of department") are cut first and
/// kept as notes; a parenthetical with words beyond course codes and connectives is an aside (a note); bare numbers
/// after a separator take the last subject ("MEGR 3112, 3114, and 3116"); ";" is the weakest AND; within a part,
/// commas take the list's conjunction ("A, B, and C" = all; "A, B, or C" = one of), AND binds looser than OR
/// ("A and either B or C" = A ∧ (B ∨ C)); parentheses group; the result is distributed into CNF (capped at 64 groups),
/// de-duplicated, with groups that contain another group dropped (A ∧ (A ∨ B) = A).
public enum CatalogRequirementParser {
    public struct Result: Hashable, Sendable {
        public var groups: [[String]]
        public var notes: [String]
    }

    indirect enum Expr: Hashable {
        case code(String)
        case and([Expr])
        case or([Expr])
    }

    public static func parse(_ text: String?) -> Result {
        guard var t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Result(groups: [], notes: []) }
        var notes: [String] = []
        t = t.replacingOccurrences(of: "\u{00a0}", with: " ")
        t = cut(grade, from: t, into: &notes)
        t = cut(waiver, from: t, into: &notes)
        t = cutAsides(t, into: &notes)
        var index = 0
        let expr = parseSequence(tokens(t), &index)
        return Result(groups: cnf(expr), notes: notes)
    }

    // MARK: Phrases

    private static let grade = try! NSRegularExpression(pattern:
        #"\b(?:all\s+|both\s+|each\s+)?(?:with\s+)?(?:an?\s+)?(?:minimum\s+)?(?:grades?\s+of\s+)?(?:at\s+least\s+)?(?:an?\s+)?"?[A-D][+-]?"?\s+or\s+(?:above|better|higher)\b"#,
        options: [.caseInsensitive])
    private static let waiver = try! NSRegularExpression(pattern:
        #"\bor\s+(?:the\s+)?(?:permission|consent|approval)\s+of\s+(?:the\s+)?(?:instructor|department|program director|department chair|chair)\b|\bor\s+(?:the\s+)?(?:equivalent|permission|consent)\b"#,
        options: [.caseInsensitive])
    private static let codePattern = try! NSRegularExpression(pattern: #"\b([A-Z]{3,4})\s?(\d{4}[A-Z]?)\b"#)
    private static let connective = try! NSRegularExpression(pattern: #"\b(and|or|either|both|one|of|the|following)\b|[,;]"#,
                                                            options: [.caseInsensitive])
    private static let parenthetical = try! NSRegularExpression(pattern: #"\(([^()]*)\)"#)
    private static let token = try! NSRegularExpression(pattern:
        #"\b([A-Z]{3,4})\s?(\d{4}[A-Z]?)\b|\b(\d{4}[A-Z]?)\b|\b((?i:and|or))\b|([,;()])"#)

    private static func collapse(_ s: String) -> String { BannerText.collapse(s) }

    private static func cut(_ regex: NSRegularExpression, from text: String, into notes: inout [String]) -> String {
        let ns = text as NSString
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            notes.append(collapse(ns.substring(with: m.range)))
        }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
    }

    /// Parentheticals without a course code — or with more than one word beyond codes and connectives — are notes.
    private static func cutAsides(_ text: String, into notes: inout [String]) -> String {
        var out = ""
        let ns = text as NSString
        var last = 0
        for m in parenthetical.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: m.range(at: 1))
            let innerNS = inner as NSString
            let hasCode = codePattern.firstMatch(in: inner, range: NSRange(location: 0, length: innerNS.length)) != nil
            var rest = codePattern.stringByReplacingMatches(in: inner, range: NSRange(location: 0, length: innerNS.length), withTemplate: " ")
            rest = connective.stringByReplacingMatches(in: rest, range: NSRange(location: 0, length: (rest as NSString).length), withTemplate: " ")
            let words = rest.split(whereSeparator: { $0.isWhitespace }).count
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            if hasCode && words <= 1 {
                out += ns.substring(with: m.range)
            } else {
                notes.append(inner.trimmingCharacters(in: .whitespacesAndNewlines))
                out += " "
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    // MARK: Tokens

    enum Token: Hashable {
        case code(String)
        case and, or, comma, semicolon, open, close

        var isSeparator: Bool {
            switch self {
            case .and, .or, .comma, .semicolon, .open: return true
            default: return false
            }
        }
    }

    static func tokens(_ text: String) -> [Token] {
        var out: [Token] = []
        var subject: String?
        let ns = text as NSString
        for m in token.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            if let subj = group(1), let number = group(2) {
                subject = subj
                out.append(.code("\(subj) \(number)"))
            } else if let number = group(3) {
                if let subject, out.last?.isSeparator == true { out.append(.code("\(subject) \(number)")) }
            } else if let word = group(4) {
                out.append(word.lowercased() == "and" ? .and : .or)
            } else if let punct = group(5) {
                switch punct {
                case ",": out.append(.comma)
                case ";": out.append(.semicolon)
                case "(": out.append(.open)
                default: out.append(.close)
                }
            }
        }
        return out
    }

    // MARK: Grammar

    enum Sep: Hashable { case semicolon, and, or, comma }

    static func parseSequence(_ toks: [Token], _ i: inout Int) -> Expr? {
        var items: [Expr] = []
        var seps: [Sep] = []
        var pending: [Token] = []
        func push(_ item: Expr) {
            if !items.isEmpty, seps.count < items.count { seps.append(strongest(pending)) }
            items.append(item)
            pending = []
        }
        while i < toks.count {
            let t = toks[i]
            switch t {
            case .close:
                i += 1
                return combine(items, seps)
            case .open:
                i += 1
                if let sub = parseSequence(toks, &i) { push(sub) }
                continue
            case .code(let code):
                push(.code(code))
            default:
                pending.append(t)
            }
            i += 1
        }
        return combine(items, seps)
    }

    static func strongest(_ pending: [Token]) -> Sep {
        if pending.contains(.semicolon) { return .semicolon }
        if pending.contains(.and) { return .and }
        if pending.contains(.or) { return .or }
        if pending.contains(.comma) { return .comma }
        return .and // codes with only words between: conservatively both
    }

    static func combine(_ items: [Expr], _ seps: [Sep]) -> Expr? {
        guard let first = items.first else { return nil }
        if items.count == 1 { return first }
        if seps.contains(.semicolon) {
            var parts: [Expr] = []
            var cur = [first], curSeps: [Sep] = []
            for (s, item) in zip(seps, items.dropFirst()) {
                if s == .semicolon {
                    if let e = combine(cur, curSeps) { parts.append(e) }
                    cur = [item]
                    curSeps = []
                } else {
                    cur.append(item)
                    curSeps.append(s)
                }
            }
            if let e = combine(cur, curSeps) { parts.append(e) }
            return .and(parts)
        }
        let comma: Sep = seps.contains(.and) ? .and : (seps.contains(.or) ? .or : .and)
        let resolved = seps.map { $0 == .comma ? comma : $0 }
        var groups: [[Expr]] = []
        var cur = [first]
        for (s, item) in zip(resolved, items.dropFirst()) {
            if s == .and {
                groups.append(cur)
                cur = [item]
            } else {
                cur.append(item)
            }
        }
        groups.append(cur)
        let ands = groups.map { $0.count == 1 ? $0[0] : Expr.or($0) }
        return ands.count == 1 ? ands[0] : .and(ands)
    }

    static func cnf(_ expr: Expr?) -> [[String]] {
        guard let expr else { return [] }
        switch expr {
        case .code(let c): return [[c]]
        case .and(let parts): return dedupe(parts.flatMap { cnf($0) })
        case .or(let parts):
            var acc: [[String]] = [[]]
            for part in parts {
                let sub = cnf(part)
                if sub.isEmpty { continue }
                var next: [[String]] = []
                outer: for a in acc {
                    for b in sub {
                        next.append(a + b)
                        if next.count >= 64 { break outer }
                    }
                }
                acc = next
            }
            return dedupe(acc)
        }
    }

    static func dedupe(_ groups: [[String]]) -> [[String]] {
        var out: [[String]] = []
        var seen = Set<[String]>()
        for g in groups {
            var unique: [String] = []
            for c in g where !unique.contains(c) { unique.append(c) }
            guard !unique.isEmpty, seen.insert(unique.sorted()).inserted else { continue }
            out.append(unique)
        }
        return out.filter { g in
            let set = Set(g)
            return !out.contains { h in let hs = Set(h); return hs.count < set.count && hs.isSubset(of: set) }
        }
    }
}
