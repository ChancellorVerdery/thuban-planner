import SwiftUI
import ThubanPlannerCore

/// The Schedule's section-bar toolbar: "Block times" (toggle, ⌘B) | Refresh sections (⇧⌘R). Copy CRNs lives in the CRN strip under the grid (⇧⌘C).
struct ScheduleToolbar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.scheduleTab
        HStack(spacing: 6) {
            ToggleChip(label: "Block times", icon: .clock,
                       isOn: Binding(get: { model.blockMode }, set: { model.blockMode = $0 }))
                .help("Drag on the grid to keep a time free (⌘B)")
                .disabled(model.selectedTermCode == nil)
            ToolbarDivider()
            ToolbarButton("Refresh sections", icon: .history, kind: .secondary) { model.refreshAllSections() }
                .help("Fetch every class’s sections from Banner again (⇧⌘R)")
                .disabled(model.selectedTermCode == nil || model.rows.isEmpty || model.offline)
        }
    }
}
