import SwiftUI
import ThubanPlannerCore

/// Settings ▸ About. OWNER: Engineer C. PLACEHOLDER — spec: ARCHITECTURE.md ▸ "Settings".
struct AboutSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsPaneHeader(eyebrow: nil, title: "About", caption: "Thuban Planner, a sibling of the Thuban apps.")
        SettingsNote(text: "TODO(C): mark, version, where data lives, the Atlas rule.")
    }
}
