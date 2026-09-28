import SwiftUI
import ThubanPlannerCore

/// Settings ▸ Data. OWNER: Engineer C. PLACEHOLDER — spec: ARCHITECTURE.md ▸ "Settings".
struct DataSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsPaneHeader(eyebrow: nil, title: "Data", caption: "planner.json, backups, export.")
        SettingsNote(text: "TODO(C): data folder (reveal), backups list with Restore (confirm), Export…")
    }
}
