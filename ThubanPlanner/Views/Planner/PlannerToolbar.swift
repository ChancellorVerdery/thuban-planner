import SwiftUI
import ThubanPlannerCore

/// The Planner's section-bar toolbar: `+ Semester` (ghost; popover with season, year, "current") · `Add class`
/// (secondary; the new row scrolls into view with its Code field focused) | `Calculate route` (primary →
/// `app.showRoute()`). OWNER: Engineer A.
struct PlannerToolbar: View {
    /// "Tech electives 2/4".
    private var electivesLabel: String {
        guard let progress = app.degreeTools.progress else { return "Tech electives" }
        return "Tech electives \(min(progress.chosen.count, progress.required))/\(progress.required)"
    }

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
        ToolbarButton(electivesLabel, icon: .graduation, kind: .ghost) { app.degreeTools.openElectives() }
            .help("Choose technical electives from the classes UNC Charlotte actually offers (⇧⌘T)")
            .disabled(app.degreeTools.dataset == nil)
        Menu {
            Button("Technical electives…") { app.degreeTools.openElectives() }
            Button("Import degree requirements…") { app.degreeTools.openImport() }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 15, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 32, height: 32)
        .foregroundStyle(theme.inkDimColor)
        .help("More: import a major or minor’s requirements from a catalog page, DegreeWorks audit or checksheet")
        .accessibilityLabel("More planner actions")
        ToolbarDivider()
        ToolbarButton("Calculate route", icon: .route, kind: .primary) { app.showRoute() }
            .help("Compute the route and open it (⌘R)")
            .disabled(app.courses.isEmpty)
    }
}
