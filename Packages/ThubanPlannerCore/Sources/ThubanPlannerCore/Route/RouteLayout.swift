import CoreGraphics
import Foundation

/// The Route board's geometry, in board points (zoom = 1), from a `Schedule` and the plan's classes: one column per
/// non-empty board term, one box per class stacked top-down with height ∝ credits (Atlas's `boardSVG`), and one ribbon
/// per edge from the source box's right edge to the target's left edge as a cubic bezier with both control points at
/// the horizontal midpoint (Atlas's `M x1,y1 C mx,y1 mx,y2 x2,y2`). Pure; the view only draws it.
///
/// Two refinements over Atlas's SVG: when a box has several ribbons on one side their ends are spread over the box's
/// middle band (sorted by the other end's height, so ribbons do not cross at the box), and a ribbon between two boxes of
/// the SAME column (a same-term corequisite) is a bracket on the right-hand side instead of a backwards loop; and a
/// ribbon that skips one or more columns runs through the gaps between the boxes of the columns it crosses (or below
/// their last box) instead of straight through unrelated classes (`Ribbon.waypoints`).
public struct RouteLayout: Hashable, Sendable {
    public struct Metrics: Hashable, Sendable {
        /// Outer margin around the board.
        public var padding: CGFloat = 24
        /// Width of a column's card.
        public var columnWidth: CGFloat = 212
        /// Space between two column cards (where the ribbons run).
        public var gutter: CGFloat = 44
        /// Height of the column header (term label + caption) inside the card.
        public var headerHeight: CGFloat = 58
        /// Horizontal inset of the boxes inside the column card.
        public var boxInset: CGFloat = 12
        /// Box height per credit hour, and the minimum box height.
        public var pointsPerCredit: CGFloat = 24
        public var minBoxHeight: CGFloat = 42
        /// Vertical gap between boxes.
        public var boxGap: CGFloat = 14
        /// Space below the last box inside the card.
        public var bottomInset: CGFloat = 14
        /// Share of a box's height over which several ribbon ends are spread (centered).
        public var portBand: CGFloat = 0.6
        /// How far a same-column bracket bulges right of the boxes.
        public var bracketReach: CGFloat = 20

        public init() {}

        public var boxWidth: CGFloat { columnWidth - 2 * boxInset }
        public var columnPitch: CGFloat { columnWidth + gutter }

        public func boxHeight(credits: Double) -> CGFloat {
            let c = credits.isFinite ? max(0, credits) : 0
            return max(minBoxHeight, CGFloat(c) * pointsPerCredit)
        }
    }

    public struct Column: Hashable, Sendable, Identifiable {
        public var index: Int
        public var term: BoardTerm
        /// The column card (header included).
        public var frame: CGRect
        public var id: String { term.key }
    }

    public struct Box: Hashable, Sendable, Identifiable {
        public var courseId: String
        public var columnIndex: Int
        public var kind: TermKind
        public var rect: CGRect
        public var id: String { courseId }
    }

    public struct Ribbon: Hashable, Sendable {
        /// Index into `Schedule.edges`.
        public var edgeIndex: Int
        public var from: String
        public var to: String
        public var kind: RequirementKind
        /// True when both classes sit in the same column (drawn as a bracket on the right).
        public var sameColumn: Bool
        public var start: CGPoint
        public var control1: CGPoint
        public var control2: CGPoint
        public var end: CGPoint
        /// For a ribbon that skips columns: an (entry, exit) pair per column it crosses, both at one height inside a
        /// free lane of that column (between two boxes, or below its last box). The ribbon runs straight from entry
        /// to exit and curves in the gutters (controls at each gutter's middle). Empty = the single bezier
        /// `start → control1 → control2 → end`.
        public var waypoints: [CGPoint] = []

        /// The drawn path as cubic segments (straight runs are cubics with collinear controls).
        public var segments: [(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)] {
            guard !waypoints.isEmpty else { return [(start, control1, control2, end)] }
            let points = [start] + waypoints + [end]
            var out: [(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)] = []
            for i in 0..<(points.count - 1) {
                let p = points[i], q = points[i + 1]
                if i % 2 == 0 {
                    let mx = (p.x + q.x) / 2
                    out.append((p, CGPoint(x: mx, y: p.y), CGPoint(x: mx, y: q.y), q))
                } else {
                    out.append((p, p, q, q))
                }
            }
            return out
        }

        /// The x where the last curve's control sits (for the arrowhead direction).
        public var arrowControl: CGPoint { segments.last?.control2 ?? control2 }
    }

    public var metrics: Metrics
    public var columns: [Column]
    /// Boxes in drawing order (column by column, top to bottom).
    public var boxes: [Box]
    /// Ribbons in `Schedule.edges` order; edges whose ends are not on the board are skipped.
    public var ribbons: [Ribbon]
    /// The whole board, margins included.
    public var size: CGSize
    private var boxIndex: [String: Int]

    public static let empty = RouteLayout(metrics: Metrics(), columns: [], boxes: [], ribbons: [], size: .zero, boxIndex: [:])

    public var isEmpty: Bool { boxes.isEmpty }

    public func box(_ courseId: String) -> Box? { boxIndex[courseId].map { boxes[$0] } }

    // MARK: Building

    /// Lays out `schedule.columns` with the credits of `courses` (a class missing from `courses` is skipped, like
    /// Atlas's `byId.get(id)` miss; a class listed twice keeps its LAST box, like Atlas's `Map.set`).
    public static func make(schedule: Schedule, courses: [Course], metrics: Metrics = Metrics()) -> RouteLayout {
        var creditsById: [String: Double] = [:]
        creditsById.reserveCapacity(courses.count)
        for course in courses where creditsById[course.id] == nil { creditsById[course.id] = course.credits }

        let terms = schedule.columns
        guard !terms.isEmpty else { return .empty }

        var boxes: [Box] = []
        var boxIndex: [String: Int] = [:]
        var maxBottom: CGFloat = 0
        let top = metrics.padding + metrics.headerHeight
        for (ci, term) in terms.enumerated() {
            let x = metrics.padding + CGFloat(ci) * metrics.columnPitch + metrics.boxInset
            var y = top
            for id in term.courseIds {
                guard let credits = creditsById[id] else { continue }
                let h = metrics.boxHeight(credits: credits)
                let box = Box(courseId: id, columnIndex: ci, kind: term.kind,
                              rect: CGRect(x: x, y: y, width: metrics.boxWidth, height: h))
                if let existing = boxIndex[id] { boxes[existing] = box } else {
                    boxIndex[id] = boxes.count
                    boxes.append(box)
                }
                y += h + metrics.boxGap
            }
            maxBottom = max(maxBottom, y - metrics.boxGap)
        }
        maxBottom = max(maxBottom, top)
        let cardBottom = maxBottom + metrics.bottomInset
        let columns = terms.enumerated().map { ci, term in
            Column(index: ci, term: term,
                   frame: CGRect(x: metrics.padding + CGFloat(ci) * metrics.columnPitch, y: metrics.padding,
                                 width: metrics.columnWidth, height: cardBottom - metrics.padding))
        }
        let width = 2 * metrics.padding + CGFloat(terms.count) * metrics.columnWidth + CGFloat(terms.count - 1) * metrics.gutter
        let size = CGSize(width: width, height: cardBottom + metrics.padding)

        var ribbons = makeRibbons(edges: schedule.edges, boxes: boxes, boxIndex: boxIndex, metrics: metrics)
        routeThroughLanes(&ribbons, boxes: boxes, columns: columns, boxIndex: boxIndex)
        return RouteLayout(metrics: metrics, columns: columns, boxes: boxes, ribbons: ribbons, size: size, boxIndex: boxIndex)
    }

    private static func makeRibbons(edges: [RouteEdge], boxes: [Box], boxIndex: [String: Int], metrics: Metrics) -> [Ribbon] {
        // Which side of which box each edge attaches to. Same-column edges attach to the RIGHT side of both boxes.
        struct Port: Hashable { var box: Int; var right: Bool }
        struct End { var edge: Int; var otherY: CGFloat }
        var placed: [(edge: Int, a: Int, b: Int)] = []
        var ports: [Port: [End]] = [:]
        for (ei, edge) in edges.enumerated() {
            guard let a = boxIndex[edge.from], let b = boxIndex[edge.to] else { continue }
            placed.append((ei, a, b))
            let same = boxes[a].columnIndex == boxes[b].columnIndex
            ports[Port(box: a, right: true), default: []].append(End(edge: ei, otherY: boxes[b].rect.midY))
            ports[Port(box: b, right: same), default: []].append(End(edge: ei, otherY: boxes[a].rect.midY))
        }
        // y of each (edge, box, side) end: spread across the box's middle band, ordered by where the other end is.
        struct EndKey: Hashable { var edge: Int; var port: Port }
        var yOf: [EndKey: CGFloat] = [:]
        for (port, ends) in ports {
            let rect = boxes[port.box].rect
            // Duplicate edges (same other box) share one slot, so they overlap instead of fanning.
            let sorted = ends.sorted { $0.otherY != $1.otherY ? $0.otherY < $1.otherY : $0.edge < $1.edge }
            var slots: [CGFloat] = []
            for end in sorted where slots.last != end.otherY { slots.append(end.otherY) }
            let band = rect.height * metrics.portBand
            for end in sorted {
                let slot = slots.firstIndex(of: end.otherY) ?? 0
                let y = slots.count == 1 ? rect.midY
                    : rect.midY - band / 2 + band * CGFloat(slot) / CGFloat(slots.count - 1)
                yOf[EndKey(edge: end.edge, port: port)] = y
            }
        }
        return placed.map { ei, a, b in
            let edge = edges[ei]
            let ra = boxes[a].rect, rb = boxes[b].rect
            let same = boxes[a].columnIndex == boxes[b].columnIndex
            let y1 = yOf[EndKey(edge: ei, port: Port(box: a, right: true))] ?? ra.midY
            let y2 = yOf[EndKey(edge: ei, port: Port(box: b, right: same))] ?? rb.midY
            if same {
                let x = ra.maxX
                let reach = x + metrics.bracketReach
                return Ribbon(edgeIndex: ei, from: edge.from, to: edge.to, kind: edge.kind, sameColumn: true,
                              start: CGPoint(x: x, y: y1), control1: CGPoint(x: reach, y: y1),
                              control2: CGPoint(x: reach, y: y2), end: CGPoint(x: x, y: y2))
            }
            let x1 = ra.maxX, x2 = rb.minX
            let mx = (x1 + x2) / 2
            return Ribbon(edgeIndex: ei, from: edge.from, to: edge.to, kind: edge.kind, sameColumn: false,
                          start: CGPoint(x: x1, y: y1), control1: CGPoint(x: mx, y: y1),
                          control2: CGPoint(x: mx, y: y2), end: CGPoint(x: x2, y: y2))
        }
    }

    /// Gives every ribbon that skips columns a lane through each column it crosses: the gap between two boxes nearest
    /// to where a straight line would pass, or the free space below the column's last box. Ribbons sharing one gap are
    /// spread across it in the order of their ends, so they do not cross inside it.
    private static func routeThroughLanes(_ ribbons: inout [Ribbon], boxes: [Box], columns: [Column],
                                          boxIndex: [String: Int]) {
        guard columns.count > 2 else { return }
        // Free vertical intervals per column, top to bottom.
        var lanes: [[(range: ClosedRange<CGFloat>, below: Bool)]] = Array(repeating: [], count: columns.count)
        var columnBoxes: [[CGRect]] = Array(repeating: [], count: columns.count)
        for box in boxes { columnBoxes[box.columnIndex].append(box.rect) }
        for ci in columns.indices {
            let rects = columnBoxes[ci].sorted { $0.minY < $1.minY }
            var free: [(range: ClosedRange<CGFloat>, below: Bool)] = []
            for (a, b) in zip(rects, rects.dropFirst()) where b.minY - a.maxY >= 6 {
                free.append(((a.maxY + 3)...(b.minY - 3), false))
            }
            let bottom = columns[ci].frame.maxY - 4
            let lastBottom = (rects.last?.maxY ?? columns[ci].frame.minY) + 3
            if bottom > lastBottom { free.append((lastBottom...bottom, true)) }
            lanes[ci] = free
        }
        struct Pick { var ribbon: Int; var lane: Int; var y: CGFloat; var order: CGFloat }
        var picks: [Int: [Pick]] = [:]   // key = column * 10_000 + lane (inter-box gaps only)
        var waypointsY: [Int: [Int: CGFloat]] = [:]   // ribbon → column → y
        for (ri, r) in ribbons.enumerated() where !r.sameColumn {
            guard let a = boxIndex[r.from], let b = boxIndex[r.to] else { continue }
            let ca = boxes[a].columnIndex, cb = boxes[b].columnIndex
            guard cb - ca > 1 else { continue }
            for ci in (ca + 1)..<cb {
                let frame = columns[ci].frame
                let t = (frame.midX - r.start.x) / max(1, r.end.x - r.start.x)
                let target = r.start.y + (r.end.y - r.start.y) * t
                var best: (lane: Int, y: CGFloat, d: CGFloat)?
                for (li, lane) in lanes[ci].enumerated() {
                    let y = min(lane.range.upperBound, max(lane.range.lowerBound, target))
                    let d = abs(y - target)
                    if best == nil || d < best!.d { best = (li, y, d) }
                }
                guard let best else { continue }
                if !lanes[ci][best.lane].below {
                    picks[ci * 10_000 + best.lane, default: []].append(Pick(ribbon: ri, lane: best.lane, y: best.y,
                                                                          order: r.start.y + r.end.y))
                }
                waypointsY[ri, default: [:]][ci] = best.y
            }
        }
        // Spread ribbons sharing a narrow gap evenly across it (ordered by their ends).
        for (key, list) in picks where list.count > 1 {
            let lane = lanes[key / 10_000][key % 10_000].range
            let sorted = list.sorted { $0.order != $1.order ? $0.order < $1.order : $0.ribbon < $1.ribbon }
            for (i, pick) in sorted.enumerated() {
                let y = lane.lowerBound + (lane.upperBound - lane.lowerBound) * CGFloat(i + 1) / CGFloat(sorted.count + 1)
                waypointsY[pick.ribbon]?[key / 10_000] = y
            }
        }
        for (ri, byColumn) in waypointsY {
            var points: [CGPoint] = []
            for ci in byColumn.keys.sorted() {
                let frame = columns[ci].frame, y = byColumn[ci]!
                points.append(CGPoint(x: frame.minX, y: y))
                points.append(CGPoint(x: frame.maxX, y: y))
            }
            ribbons[ri].waypoints = points
        }
    }

    // MARK: Queries

    /// The box under a board point (nil = background).
    public func box(at point: CGPoint) -> Box? {
        // Columns are regular, so find the column first, then scan its boxes.
        guard !boxes.isEmpty else { return nil }
        let column = Int(((point.x - metrics.padding) / metrics.columnPitch).rounded(.down))
        guard column >= 0, column < columns.count else { return nil }
        return boxes.first { $0.columnIndex == column && $0.rect.contains(point) }
    }

    /// The column card under a board point.
    public func column(at point: CGPoint) -> Column? {
        columns.first { $0.frame.contains(point) }
    }

    /// A class's whole requirement chain on the board: everything it transitively needs (upstream along the edges)
    /// and everything that transitively needs it (downstream), itself included, plus the ribbons along those paths.
    public func chain(of courseId: String) -> RouteChain {
        guard boxIndex[courseId] != nil else { return RouteChain(courseIds: [], ribbons: []) }
        var into: [String: [Int]] = [:], outOf: [String: [Int]] = [:]
        for (ri, ribbon) in ribbons.enumerated() {
            into[ribbon.to, default: []].append(ri)
            outOf[ribbon.from, default: []].append(ri)
        }
        var ids: Set<String> = [courseId]
        var ribbonSet: Set<Int> = []
        func walk(_ start: String, _ next: [String: [Int]], _ other: (Ribbon) -> String) {
            var stack = [start], seen: Set<String> = [start]
            while let id = stack.popLast() {
                for ri in next[id] ?? [] {
                    ribbonSet.insert(ri)
                    let o = other(ribbons[ri])
                    ids.insert(o)
                    if seen.insert(o).inserted { stack.append(o) }
                }
            }
        }
        walk(courseId, into, { $0.from })
        walk(courseId, outOf, { $0.to })
        return RouteChain(courseIds: ids, ribbons: ribbonSet)
    }

    /// The scale that shows the whole board inside `viewport` (never above `maxScale`).
    public func fitScale(in viewport: CGSize, maxScale: CGFloat = 1) -> CGFloat {
        guard size.width > 0, size.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        return min(maxScale, viewport.width / size.width, viewport.height / size.height)
    }

    /// Neighbour for keyboard navigation: ←/→ move to the nearest box (by vertical centre) in the previous / next
    /// column, ↑/↓ to the box above / below in the same column. Nil at the edges.
    public func neighbor(of courseId: String, _ direction: RouteDirection) -> String? {
        guard let box = box(courseId) else { return nil }
        switch direction {
        case .up, .down:
            let same = boxes.filter { $0.columnIndex == box.columnIndex }
            guard let i = same.firstIndex(where: { $0.courseId == courseId }) else { return nil }
            let j = direction == .up ? i - 1 : i + 1
            return same.indices.contains(j) ? same[j].courseId : nil
        case .left, .right:
            var ci = box.columnIndex
            while true {
                ci += direction == .left ? -1 : 1
                guard ci >= 0, ci < columns.count else { return nil }
                let candidates = boxes.filter { $0.columnIndex == ci }
                if let best = candidates.min(by: { abs($0.rect.midY - box.rect.midY) < abs($1.rect.midY - box.rect.midY) }) {
                    return best.courseId
                }
            }
        }
    }
}

public enum RouteDirection: Sendable { case up, down, left, right }

/// The classes and ribbons along one class's requirement chain (see `RouteLayout.chain(of:)`).
public struct RouteChain: Hashable, Sendable {
    public var courseIds: Set<String>
    /// Indices into `RouteLayout.ribbons`.
    public var ribbons: Set<Int>

    public init(courseIds: Set<String>, ribbons: Set<Int>) {
        self.courseIds = courseIds
        self.ribbons = ribbons
    }
}
