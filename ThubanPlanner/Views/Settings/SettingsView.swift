import SwiftUI
import ThubanPlannerCore

/// The Settings section (⌘3 / ⌘,): a 260 pt pane list on the left, the pane on the right. OWNER: Engineer C (the
/// chrome may be restyled; keep the type name). Each pane lives in its own file. The selected pane is
/// `app.settingsPane` so `app.openSettings(.importAtlas)` can jump straight to one.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let theme = app.theme
        HStack(spacing: 0) {
            SettingsNav()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch app.settingsPane {
                    case .planning: PlanningSettings()
                    case .appearance: AppearanceSettings()
                    case .importAtlas: ImportSettings()
                    case .data: DataSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 26)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
    }
}

private struct SettingsNav: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsPane.allCases) { pane in
                SettingsNavRow(pane: pane, isSelected: pane == app.settingsPane) { app.settingsPane = pane }
            }
            Spacer(minLength: 16)
            Text("Your plan lives on this Mac. Atlas is only read, never written to.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkFaintColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(16)
        .padding(.top, 10)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.panelColor)
        .thubanHairline(.trailing, color: theme.lineColor)
    }
}

private struct SettingsNavRow: View {
    @Environment(\.thubanTheme) private var theme
    var pane: SettingsPane
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(pane.icon, size: 16)
                    .foregroundStyle(isSelected ? theme.brassInkColor : theme.inkDimColor)
                Text(pane.rawValue)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? theme.inkColor : theme.inkDimColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(isSelected ? theme.panel2Color : (hovering ? theme.panel2Color.opacity(0.5) : .clear),
                        in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(isSelected ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(pane.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
