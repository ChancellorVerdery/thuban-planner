import SwiftUI

/// A 32 pt icon + label toggle (Graph / Calculator / Keyboard). ON: `accentTint` fill, brass text, 1 px accent border.
/// Takes either an `IconName` or an SF Symbol (`symbol:`) and an optional compact `height`.
struct ToggleChip: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var icon: IconName? = nil
    var symbol: String? = nil
    @Binding var isOn: Bool
    var shortcut: KeyboardShortcut?
    var height: CGFloat = 32
    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Icon(icon, size: 16)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(label)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? theme.brassInkColor : theme.inkDimColor)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(
                isOn ? theme.accentTintColor : (hovering ? theme.panel2Color : .clear),
                in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(isOn ? theme.accentColor : theme.line2Color, lineWidth: ThubanMetrics.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .help(label)
    }
}
