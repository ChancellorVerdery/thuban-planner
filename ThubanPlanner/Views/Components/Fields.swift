import SwiftUI
import ThubanPlannerCore

// Shared form controls (moved out of the Settings chrome so every area can rely on them). FROZEN: the Planner
// (class table, "+ Semester" popover), Route and Settings all use these; do not rename or change signatures.

/// A toggle drawn in the Thuban style (accent when on).
struct ThubanToggle: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(theme.accentColor)
            .accessibilityLabel(label)
    }
}

// MARK: - Fields

struct ThubanFieldStyle: ViewModifier {
    @Environment(\.thubanTheme) private var theme
    var invalid: Bool = false
    var mono: Bool = false
    var height: CGFloat = ThubanMetrics.buttonHeight

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? ThubanFont.mono(13) : ThubanFont.body(14))
            .foregroundStyle(theme.inkColor)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(invalid ? theme.negColor : theme.line2Color, lineWidth: invalid ? 1.5 : ThubanMetrics.hairline)
            )
    }
}

extension View {
    func thubanField(invalid: Bool = false, mono: Bool = false, height: CGFloat = ThubanMetrics.buttonHeight) -> some View {
        modifier(ThubanFieldStyle(invalid: invalid, mono: mono, height: height))
    }
}
