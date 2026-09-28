import Foundation
import ThubanPlannerCore

/// Read-only Route helpers (OWNER: Engineer B). Derived from `data` / `schedule`; no caches, no writes.
extension AppModel {
    /// Zoom limits for `routeZoom` (1 = fitted).
    static let routeZoomRange: ClosedRange<Double> = 0.25...6

    /// "planned Spring 2027" / "taken Fall 2024" / "in progress Fall 2026" / "can’t be placed".
    func routeStatusPhrase(_ courseId: String) -> String {
        switch status(of: courseId) {
        case .taken(let key): return "taken \(termLabel(key))"
        case .inProgress(let key): return "in progress \(termLabel(key))"
        case .planned(let key): return "planned \(termLabel(key))"
        case .unplaceable: return "can’t be placed"
        case .unscheduled: return "taken (term not listed)"
        }
    }

    /// Hover tooltip / accessibility label: "MEGR 3114 · Fluid Mechanics · 3 cr · planned Spring 2027".
    func routeTooltip(_ courseId: String) -> String {
        guard let course = course(courseId) else { return "" }
        return "\(course.displayName) · \(creditsText(course.credits)) cr · \(routeStatusPhrase(courseId))"
    }

    /// The header title: "Finishing Spring 2028", or "Your route" when nothing is left to plan / the board is empty.
    var routeTitle: String {
        guard let grad = gradTermLabel, !toTake.isEmpty || !schedule.columns.isEmpty else { return "Your route" }
        if toTake.isEmpty { return "Finished \(grad)" }
        let unplaced = schedule.unplaceable.count
        return unplaced == 0 ? "Finishing \(grad)" : "Finishing \(grad) · \(unplaced) class\(unplaced == 1 ? "" : "es") unplaced"
    }

    /// Classes the scheduler could not place, in plan order.
    var routeUnplaceable: [Course] { schedule.unplaceable.compactMap { course($0) } }

    /// Share of all credits already done (taken + current), 0…1.
    var routeCreditsDoneFraction: Double {
        creditsTotal > 0 ? min(1, max(0, creditsTaken / creditsTotal)) : 0
    }

    /// Zooms by `factor` (toolbar ± and ⌘+ / ⌘−), clamped to `routeZoomRange`.
    func routeZoom(by factor: Double) {
        routeZoom = min(Self.routeZoomRange.upperBound, max(Self.routeZoomRange.lowerBound, routeZoom * factor))
    }
}
