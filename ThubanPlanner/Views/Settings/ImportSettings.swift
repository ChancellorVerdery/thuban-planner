import SwiftUI
import ThubanPlannerCore

/// Settings ▸ Import from Atlas. OWNER: Engineer C. PLACEHOLDER — spec: ARCHITECTURE.md ▸ "Settings".
struct ImportSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsPaneHeader(eyebrow: nil, title: "Import from Atlas", caption: "Bring your Course Planner over, read-only.")
        SettingsNote(text: "TODO(C): host / email, command line, Check Atlas → preview counts → Replace (confirm), file import, states.")
    }
}
