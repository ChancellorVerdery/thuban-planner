import SwiftUI
import ThubanPlannerCore

/// 12 pt uppercase eyebrow ("THURSDAY, SEPTEMBER 24 · CYCLE DAY 2 OF 4").
struct Eyebrow: View {
    @Environment(\.thubanTheme) private var theme
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(ThubanFont.micro)
            .kerning(0.9)
            .foregroundStyle(theme.inkDimColor)
    }
}

/// "RECENT · 5" section heading with an optional trailing accessory.
struct SectionHeader<Accessory: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var count: Int?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, count: Int? = nil, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.count = count
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            Eyebrow(title)
            if let count {
                Text(String(count))
                    .font(ThubanFont.micro)
                    .foregroundStyle(theme.inkFaintColor)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            accessory()
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// The design's page header: eyebrow, 32 pt serif title, one dim subtitle line.
struct PageHeader: View {
    @Environment(\.thubanTheme) private var theme
    var eyebrow: String?
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow { Eyebrow(eyebrow) }
            Text(title)
                .font(ThubanFont.display(32))
                .foregroundStyle(theme.inkColor)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A number tile: small label, big serif value (+ optional unit), dim caption ("Strength score · 117.3 · +1.6 in 4 weeks").
struct StatTile: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var value: String
    var unit: String?
    var caption: String?
    var captionTone: ChipKind = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(ThubanFont.body(13, weight: .semibold))
                .foregroundStyle(theme.inkDimColor)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(ThubanFont.display(30))
                    .foregroundStyle(theme.inkColor)
                    .monospacedDigit()
                if let unit {
                    Text(unit).font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor)
                }
            }
            if let caption {
                Text(caption)
                    .font(ThubanFont.small)
                    .foregroundStyle(captionTone == .neutral ? theme.inkDimColor : captionTone.colors(theme).text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A row card with hover highlight, used by lists across the app.
struct ListRowCard<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var isSelected: Bool = false
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    init(isSelected: Bool = false, action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var row: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.accentTintColor : (hovering && action != nil ? theme.panel2Color : theme.panelColor),
                        in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? theme.accentColor : theme.lineColor, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
    }
}

/// A 1 px horizontal rule in `line`.
struct Hairline: View {
    @Environment(\.thubanTheme) private var theme
    var body: some View { Rectangle().fill(theme.lineColor).frame(height: ThubanMetrics.hairline) }
}

/// A search field in the Thuban style.
struct SearchField: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: 6) {
            Glyph(.search, size: 14).foregroundStyle(theme.inkFaintColor)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(ThubanFont.body(13))
                .foregroundStyle(theme.inkColor)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Glyph(.close, size: 12).foregroundStyle(theme.inkDimColor).frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
    }
}

/// Placeholder body for a section that has not been built yet (removed as each area lands).
struct SectionPlaceholder: View {
    @Environment(\.thubanTheme) private var theme
    var icon: IconName
    var title: String
    var todo: String

    var body: some View {
        EmptyState(icon: icon, title: title, message: todo)
            .background(theme.bgColor)
    }
}

// MARK: - Section toolbar

/// The section bar's action buttons ("+ Semester" ghost, "Add class" secondary, "Calculate route" primary): 32 pt, icon +
/// label. Every section toolbar uses these so the bar reads as one row.
struct ToolbarButton: View {
    enum Kind { case ghost, secondary, primary }
    var icon: IconName?
    var label: String
    var kind: Kind = .ghost
    var action: () -> Void

    init(_ label: String, icon: IconName? = nil, kind: Kind = .ghost, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.kind = kind
        self.action = action
    }

    var body: some View {
        let content = HStack(spacing: 7) {
            if let icon { Icon(icon, size: 15) }
            Text(label).lineLimit(1)
        }
        switch kind {
        case .ghost: Button(action: action) { content }.buttonStyle(GhostButtonStyle(height: 32, horizontalPadding: 14))
        case .secondary: Button(action: action) { content }.buttonStyle(SecondaryButtonStyle(height: 32))
        case .primary: Button(action: action) { content }.buttonStyle(PrimaryButtonStyle(height: 32))
        }
    }
}

/// The 1 × 20 pt rule between toolbar groups.
struct ToolbarDivider: View {
    @Environment(\.thubanTheme) private var theme
    var body: some View {
        Rectangle().fill(theme.line2Color).frame(width: ThubanMetrics.hairline, height: 20).padding(.horizontal, 4)
    }
}
