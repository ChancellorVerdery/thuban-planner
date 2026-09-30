import Foundation

/// A class in the degree: taken (in a recorded term) or still to take (`term == nil`).
public struct Course: Codable, Hashable, Sendable, Identifiable {
    /// Client-minted "c-…". Requirement refs never use it — they match on `code`.
    public var id: String
    /// "MEGR 2144" — may be empty (a title-only class). NOT unique; refs match it case- and space-insensitively.
    public var code: String
    public var title: String
    /// Credit hours (≥ 0; may be fractional).
    public var credits: Double
    /// Codes that must be done in an EARLIER term.
    public var prereqs: [String]
    /// Codes that must be done in the SAME term or earlier (absorbs Atlas's retired "pre-or-co" bucket).
    public var coreqs: [String]
    /// Offered in summer.
    public var summerOk: Bool
    /// The past / current term key it was taken in; nil = still to take (the scheduler places it).
    public var term: String?

    public init(id: String, code: String, title: String = "", credits: Double = 3, prereqs: [String] = [], coreqs: [String] = [],
                summerOk: Bool = false, term: String? = nil) {
        self.id = id
        self.code = code
        self.title = title
        self.credits = credits
        self.prereqs = prereqs
        self.coreqs = coreqs
        self.summerOk = summerOk
        self.term = term
    }

    public var isTaken: Bool { term != nil }

    /// What the UI shows for a class with no code: "—".
    public var displayCode: String { code.isEmpty ? "—" : code }

    /// "MEGR 2144 · Solid Mechanics" (or whichever part exists).
    public var displayName: String {
        switch (code.isEmpty, title.isEmpty) {
        case (false, false): return "\(code) · \(title)"
        case (false, true): return code
        case (true, false): return title
        case (true, true): return "Untitled class"
        }
    }

    /// Case- and space-insensitive form used to match requirement refs (Atlas `norm`).
    public static func normalizeRef(_ text: String) -> String { JS.toLowerCase(JS.trim(text)) }
}

/// Route strategies (Atlas `STRATEGIES`, same keys and labels).
public enum Strategy: String, Codable, CaseIterable, Sendable, Identifiable {
    case soonestSummer = "soonest-summer"
    case soonestOptionalSummer = "soonest-optional-summer"
    case even

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .soonestSummer: return "Graduate soonest (use summers)"
        case .soonestOptionalSummer: return "Soonest — summers only if they save a term"
        case .even: return "Lighter, even load"
        }
    }
}

/// Planning settings (Atlas `settings`).
public struct PlannerSettings: Codable, Hashable, Sendable {
    public static let defaultMaxCredits: Double = 15

    /// Most credit hours in a fall or spring term (> 0 after normalization; default 15).
    public var maxCredits: Double
    /// Most credit hours in a summer term (≥ 0; default min(9, maxCredits)).
    public var summerMax: Double
    public var strategy: Strategy
    /// Fewest credit hours a planned fall or spring term should carry (≥ 0; 0 = no minimum). Not an Atlas setting.
    public var minCredits: Double
    /// Fewest credit hours worth taking a summer term for (≥ 0; 0 = no minimum). A planned summer that would carry
    /// less is skipped. Not an Atlas setting.
    public var summerMin: Double

    public init(maxCredits: Double = 15, summerMax: Double = 9, strategy: Strategy = .soonestSummer,
                minCredits: Double = 0, summerMin: Double = 0) {
        self.maxCredits = maxCredits
        self.summerMax = summerMax
        self.strategy = strategy
        self.minCredits = minCredits
        self.summerMin = summerMin
    }

    /// The minimum the scheduler applies to a term: the setting, never above that term's cap.
    public func effectiveMin(summer: Bool) -> Double {
        summer ? Swift.min(summerMin, summerMax) : Swift.min(minCredits, maxCredits)
    }

    public static let `default` = PlannerSettings()
}

/// Every writable setting (Atlas `setSetting(key, value)`).
public enum PlannerSetting: Hashable, Sendable {
    case maxCredits(Double)
    case summerMax(Double)
    case strategy(Strategy)
    case minCredits(Double)
    case summerMin(Double)
}

/// Ids like Atlas's `uid(p)`: "<prefix>-<ms since 1970 in base 36><5 random base-36 chars>".
public enum PlannerID {
    public static func make(_ prefix: String = "c", now: Date = Date()) -> String {
        let ms = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let random = String((0 ..< 5).map { _ in alphabet[Int.random(in: 0 ..< alphabet.count)] })
        return "\(prefix)-\(String(ms, radix: 36))\(random)"
    }
}
