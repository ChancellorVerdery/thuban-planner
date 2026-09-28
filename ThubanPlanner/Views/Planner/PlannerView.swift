import SwiftUI
import ThubanPlannerCore

/// The Planner section (⌘1). OWNER: Engineer A. PLACEHOLDER — replace the body; keep the type name (the shell
/// references it). Spec: ARCHITECTURE.md ▸ "Planner". Semesters strip, summer toggles, class table, warnings,
/// first-run import offer.
struct PlannerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(eyebrow: "Planner", title: "Your degree", subtitle: app.planStatus)
            if app.courses.isEmpty {
                EmptyState(icon: .planner, title: "No classes yet",
                           message: "Add the semesters you have taken and the classes still to take, or bring your plan over from Atlas.") {
                    HStack(spacing: 10) {
                        Button("Add class") { app.addCourse() }.buttonStyle(.thubanSecondary)
                        ImportFromAtlasButton()
                    }
                }
            } else {
                Text("TODO(A): semesters, summer toggles and the class table. \(app.terms.count) semesters · \(app.courses.count) classes.")
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
                Spacer(minLength: 0)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
