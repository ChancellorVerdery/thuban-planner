import SwiftUI
import ThubanPlannerCore

// Shared settings chrome (copied from Thuban Canvas). Use these in every pane.

struct SettingsGroup<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var caption: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(ThubanFont.display(18))
                    .foregroundStyle(theme.inkColor)
                if let caption {
                    Text(caption)
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label on the left, control on the right, inside a panel row.
struct SettingsRow<Control: View>: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    init(_ label: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor)
                if let detail {
                    Text(detail).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .thubanPanel(padding: 0)
    }
}

struct SettingsNote: View {
    @Environment(\.thubanTheme) private var theme
    enum Tone { case neutral, positive, negative }
    var text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(ThubanFont.small)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch tone {
        case .neutral: return theme.inkDimColor
        case .positive: return theme.posTextColor
        case .negative: return theme.negTextColor
        }
    }
}

// ThubanToggle and .thubanField live in Views/Components/Fields.swift (shared and frozen: the Planner uses them too).
