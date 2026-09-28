import SwiftUI
import ThubanPlannerCore

/// The Planner's section-bar toolbar. OWNER: Engineer A. PLACEHOLDER — spec: `+ Semester` (ghost; popover with
/// season, year, "Current semester") · `Add class` (secondary) | `Calculate route` (primary → `app.showRoute()`).
struct PlannerToolbar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ToolbarButton("Add class", icon: .plus, kind: .secondary) { app.addCourse() }
        ToolbarDivider()
        ToolbarButton("Calculate route", icon: .route, kind: .primary) { app.showRoute() }
    }
}
