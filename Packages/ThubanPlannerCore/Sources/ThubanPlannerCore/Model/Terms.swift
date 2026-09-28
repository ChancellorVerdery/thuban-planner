import Foundation

/// The three academic seasons, in calendar order within a year.
public enum Season: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case spring, summer, fall

    public var id: String { rawValue }

    /// "Spring" / "Summer" / "Fall".
    public var label: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .fall: return "Fall"
        }
    }

    /// 0 / 1 / 2 (Atlas's `seasonOrder`).
    public var order: Int {
        switch self {
        case .spring: return 0
        case .summer: return 1
        case .fall: return 2
        }
    }

    public static func < (a: Season, b: Season) -> Bool { a.order < b.order }
}

/// Term keys are plain strings, exactly as Atlas stores them: `"<season>-<year>"` (`"fall-2025"`). Courses point at
/// terms by key and disabled terms are keys, so a key may name a term that has no `Term` row (e.g. a summer switched
/// off before it was planned). These are Atlas's `course.js` helpers, with its JavaScript semantics.
public enum TermKey {
    /// `termKey(season, year)` → "fall-2025" (the year as JavaScript prints it: 2025, 2025.5).
    public static func make(_ season: Season, _ year: Double) -> String { "\(season.rawValue)-\(JS.numberString(year))" }
    public static func make(_ season: Season, _ year: Int) -> String { make(season, Double(year)) }

    /// `parseTerm(key)`: the text before the first "-" and `Number(<text after it>)` (up to a second "-"), so a
    /// malformed key gives an unknown season (nil) and / or a NaN year rather than failing.
    public static func parse(_ key: String) -> (seasonText: String, season: Season?, year: Double) {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        let seasonText = parts.first ?? ""
        let year = parts.count > 1 ? JS.number(fromString: parts[1]) : .nan
        return (seasonText, Season(rawValue: seasonText), year)
    }

    /// `termLabel(key)` → "Fall 2025" (an unknown season keeps its raw text).
    public static func label(_ key: String) -> String {
        let p = parse(key)
        return "\(p.season?.label ?? p.seasonText) \(JS.numberString(p.year))"
    }

    /// `termRank(key)` = year · 3 + season order (unknown season counts as 0; NaN year → NaN).
    public static func rank(_ key: String) -> Double {
        let p = parse(key)
        return p.year * 3 + Double(p.season?.order ?? 0)
    }

    /// `nextTermKey`: spring → summer → fall → next spring.
    public static func next(_ key: String) -> String {
        let p = parse(key)
        switch p.season {
        case .fall: return make(.spring, p.year + 1)
        case .spring: return make(.summer, p.year)
        case .summer: return make(.fall, p.year)
        case nil: return "undefined-\(JS.numberString(p.year))" // what Atlas's SEASONS[NaN] would give
        }
    }

    /// `prevTermKey`: the term before (spring → previous fall).
    public static func previous(_ key: String) -> String {
        let p = parse(key)
        switch p.season {
        case .spring: return make(.fall, p.year - 1)
        case .summer: return make(.spring, p.year)
        case .fall: return make(.summer, p.year)
        case nil: return "undefined-\(JS.numberString(p.year))"
        }
    }

    /// `currentTermKey(now)`: the academic term containing a date in `calendar`'s time zone — Jan–May spring,
    /// Jun–Aug summer, Sep–Dec fall. (Atlas uses the browser's local time; pass `.current` for the same.) Only the
    /// calendar's TIME ZONE is used: JavaScript's `getMonth` / `getFullYear` are always Gregorian, so a user whose
    /// system calendar is Buddhist or Japanese still gets "fall-2026", not "fall-2569" or "fall-8".
    public static func current(now: Date = Date(), calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month], from: now)
        let month = parts.month ?? 1
        let season: Season = month <= 5 ? .spring : (month <= 8 ? .summer : .fall)
        return make(season, parts.year ?? 2000)
    }

    /// The season of a key, when it is one of the three.
    public static func season(_ key: String) -> Season? { parse(key).season }
}

/// A past or current semester the user recorded (Atlas `terms` row).
public struct Term: Codable, Hashable, Sendable, Identifiable {
    /// Always `TermKey.make(season, year)` after normalization.
    public var key: String
    public var season: Season
    /// A JS number: normally a whole year, but Atlas's loader accepts any finite number.
    public var year: Double
    /// The semester in progress. At most one term is current.
    public var current: Bool

    public var id: String { key }

    public init(season: Season, year: Double, current: Bool = false) {
        self.key = TermKey.make(season, year)
        self.season = season
        self.year = year
        self.current = current
    }

    public init(season: Season, year: Int, current: Bool = false) {
        self.init(season: season, year: Double(year), current: current)
    }

    /// "Fall 2025".
    public var label: String { TermKey.label(key) }
    public var rank: Double { TermKey.rank(key) }
}
