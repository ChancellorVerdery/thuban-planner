import SwiftUI
import ThubanPlannerCore

/// The Planner's section-bar toolbar: `+ Semester` (ghost; popover with season, year, "current") · `Add class`
/// (secondary; the new row scrolls into view with its Code field focused) | `Calculate route` (primary →
/// `app.showRoute()`). OWNER: Engineer A.
struct PlannerToolbar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable private var state = PlannerViewState.shared

    var body: some View {
        ToolbarButton("Add semester", icon: .calendar, kind: .ghost) { state.isAddingSemesterPopover.toggle() }
            .help("Add a semester you’ve taken or are taking")
            .popover(isPresented: $state.isAddingSemesterPopover, arrowEdge: .bottom) {
                PlannerAddSemesterForm(layout: .popover) { state.isAddingSemesterPopover = false }
                    .environment(app)
                    .environment(\.thubanTheme, theme)
            }
        ToolbarButton("Add class", icon: .plus, kind: .secondary) { app.addCourse() }
            .help("Add a class (⌘N)")
        ToolbarDivider()
        ToolbarButton("Calculate route", icon: .route, kind: .primary) { app.showRoute() }
            .help("Compute the route and open it (⌘R)")
            .disabled(app.courses.isEmpty)
    }
}
