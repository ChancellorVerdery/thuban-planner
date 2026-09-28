import Foundation

/// Where a board column comes from: a recorded past term, the current term, or a term the scheduler planned.
public enum TermKind: String, Codable, Hashable, Sendable {
    case past, current, future
}

/// One column of the route: a term and the classes in it (Atlas `board[]` entry).
public struct BoardTerm: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var season: Season
    public var year: Double
    public var current: Bool
    public var kind: TermKind
    /// Course ids in the column, top to bottom (recorded terms: document order; planned terms: placement order).
    public var courseIds: [String]
    /// Sum of the column's credits.
    public var credits: Double

    public var id: String { key }
    /// "Fall 2027".
    public var label: String { TermKey.label(key) }

    public init(key: String, season: Season, year: Double, current: Bool, kind: TermKind, courseIds: [String], credits: Double) {
        self.key = key
        self.season = season
        self.year = year
        self.current = current
        self.kind = kind
        self.courseIds = courseIds
        self.credits = credits
    }
}

public enum RequirementKind: String, Codable, Hashable, Sendable {
    /// Must be in an EARLIER term.
    case prereq
    /// Same term or earlier.
    case coreq
}

/// A requirement ribbon between two placed classes: `from` is required by `to`.
public struct RouteEdge: Codable, Hashable, Sendable {
    public var from: String
    public var to: String
    public var kind: RequirementKind

    public init(from: String, to: String, kind: RequirementKind) {
        self.from = from
        self.to = to
        self.kind = kind
    }
}

/// The scheduler's answer (Atlas `scheduleDegree` return value).
public struct Schedule: Codable, Hashable, Sendable {
    /// Recorded terms + planned terms, chronological. Includes recorded terms with no classes.
    public var board: [BoardTerm]
    /// Prereq / coreq ribbons between placed classes (document order; duplicates kept like Atlas).
    public var edges: [RouteEdge]
    /// Ids of classes still to take that could not be placed (missing prerequisites, a cycle, no summer…).
    public var unplaceable: [String]
    /// Plain-text warnings ("Couldn't place: … — check for missing prerequisites or a prerequisite cycle.").
    public var warnings: [String]
    /// Planned terms needed to finish.
    public var termsToFinish: Int
    /// The last column's key (nil when the board is empty).
    public var gradTerm: String?

    public init(board: [BoardTerm] = [], edges: [RouteEdge] = [], unplaceable: [String] = [], warnings: [String] = [],
                termsToFinish: Int = 0, gradTerm: String? = nil) {
        self.board = board
        self.edges = edges
        self.unplaceable = unplaceable
        self.warnings = warnings
        self.termsToFinish = termsToFinish
        self.gradTerm = gradTerm
    }

    public static let empty = Schedule()

    // MARK: Queries

    /// Columns that have classes (what the Route map draws — Atlas filters empty terms out of the board).
    public var columns: [BoardTerm] { board.filter { !$0.courseIds.isEmpty } }

    /// Planned (future) columns only.
    public var plannedTerms: [BoardTerm] { board.filter { $0.kind == .future } }

    /// The board column holding `courseId` (the latest one, like Atlas's `termOfCourse`).
    public func boardTerm(of courseId: String) -> BoardTerm? { board.last { $0.courseIds.contains(courseId) } }

    public func boardTerm(key: String) -> BoardTerm? { board.first { $0.key == key } }

    /// Where a class stands in the route.
    public func status(of courseId: String) -> CourseStatus {
        if unplaceable.contains(courseId) { return .unplaceable }
        guard let column = boardTerm(of: courseId) else { return .unscheduled }
        switch column.kind {
        case .past: return .taken(column.key)
        case .current: return .inProgress(column.key)
        case .future: return .planned(column.key)
        }
    }

    /// Edges into / out of a class (its requirements that are placed / the placed classes that need it).
    public func edges(into courseId: String) -> [RouteEdge] { edges.filter { $0.to == courseId } }
    public func edges(outOf courseId: String) -> [RouteEdge] { edges.filter { $0.from == courseId } }

    /// "Spring 2028" or nil.
    public var gradTermLabel: String? { gradTerm.map(TermKey.label) }
}

/// A class's place in the route.
public enum CourseStatus: Hashable, Sendable {
    /// In a past recorded term.
    case taken(String)
    /// In the current term.
    case inProgress(String)
    /// Placed by the scheduler in a future term.
    case planned(String)
    /// Still to take but the scheduler could not place it.
    case unplaceable
    /// Recorded in a term key that has no Term row (Atlas counts it as done but draws it nowhere).
    case unscheduled

    /// The term key, when there is one.
    public var termKey: String? {
        switch self {
        case .taken(let k), .inProgress(let k), .planned(let k): return k
        case .unplaceable, .unscheduled: return nil
        }
    }
}
