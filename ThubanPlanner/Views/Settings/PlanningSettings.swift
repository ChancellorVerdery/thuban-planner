import SwiftUI
import ThubanPlannerCore

/// Settings ▸ Planning. OWNER: Engineer C. PLACEHOLDER — spec: ARCHITECTURE.md ▸ "Settings".
struct PlanningSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsPaneHeader(eyebrow: nil, title: "Planning", caption: "Max credits per semester, max credits in summer, route strategy.")
        SettingsNote(text: "TODO(C): max credits (1–30), summer max (0–30), strategy (three options with Atlas's labels).")
    }
}
