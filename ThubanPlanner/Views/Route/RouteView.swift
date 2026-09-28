import SwiftUI
import ThubanPlannerCore

/// The Route section (⌘2): the zoomable board. OWNER: Engineer B. PLACEHOLDER — replace the body; keep the type
/// name. Spec: ARCHITECTURE.md ▸ "Route".
struct RouteView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(eyebrow: "Route", title: app.gradTermLabel.map { "Finishing \($0)" } ?? "Your route", subtitle: app.planStatus)
            if app.schedule.columns.isEmpty {
                EmptyState(icon: .route, title: "No route yet", message: "Add classes on the Planner — the route draws here.")
            } else {
                Text("TODO(B): the board. " + app.schedule.columns.map { "\($0.label) (\($0.courseIds.count))" }.joined(separator: " → "))
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
                Spacer(minLength: 0)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
