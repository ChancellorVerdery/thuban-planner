import SwiftUI
import ThubanPlannerCore

// MARK: - Columns

/// Fixed column widths of the class table (nothing reflows when a value changes). Title, Prerequisites and
/// Corequisites share the flexible width.
struct PlannerColumns: Equatable {
    static let gap: CGFloat = 10
    static let inset: CGFloat = 14
    static let rowHeight: CGFloat = 42

    let code: CGFloat = 116
    let credits: CGFloat = 46
    let summer: CGFloat = 58
    let term: CGFloat = 132
    let status: CGFloat = 160
    let remove: CGFloat = 28
    var title: CGFloat
    var prereqs: CGFloat
    var coreqs: CGFloat

    init(width: CGFloat) {
        let fixed: CGFloat = 116 + 46 + 58 + 132 + 160 + 28
        let flexible = max(420, width - PlannerColumns.inset * 2 - fixed - PlannerColumns.gap * 8)
        title = (flexible * 0.38).rounded(.down)
        prereqs = (flexible * 0.31).rounded(.down)
        coreqs = (flexible * 0.31).rounded(.down)
    }
}

// MARK: - Header (pinned)

/// The table card's pinned top: "CLASSES" + caption, filter and search on the right, then the column labels.
struct PlannerClassTableHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var state: PlannerViewState
    var columns: PlannerColumns

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: ThubanMetrics.cardRadius,
                                                      topTrailingRadius: ThubanMetrics.cardRadius, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Eyebrow("Classes").accessibilityAddTraits(.isHeader)
                        Text(String(app.courses.count))
                            .font(ThubanFont.micro)
                            .foregroundStyle(theme.inkFaintColor)
                            .monospacedDigit()
                    }
                    Text("Set the term for taken classes; leave “To take” for the planner to place.")
                        .font(ThubanFont.body(13))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                SegmentedPicker(selection: $state.filter,
                                options: PlannerClassFilter.allCases.map { SegmentOption($0, "\($0.label)  \(app.plannerCount($0))") },
                                segmentHeight: SegmentedPickerHeight.toolbar)
                    .fixedSize()
                    .accessibilityLabel("Show")
                SearchField(text: $state.search, placeholder: "Filter by code or title")
                    .frame(width: 220)
                    .accessibilityLabel("Filter classes")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            columnLabels
        }
        .background(Self.shape.fill(theme.panelColor))
        .overlay(Self.shape.strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
        // Rows scroll beneath the pinned header: fill its rounded corners with the page colour.
        .background(alignment: .top) { theme.bgColor.padding(.top, -1) }
    }

    private var columnLabels: some View {
        HStack(spacing: PlannerColumns.gap) {
            label("Code", width: columns.code)
            label("Title", width: columns.title)
            label("Cr", width: columns.credits, alignment: .trailing)
                .help("Credit hours")
            label("Prerequisites", width: columns.prereqs)
                .help("Codes, comma-separated — must be done in an EARLIER term")
            label("Corequisites", width: columns.coreqs)
                .help("Codes, comma-separated — same term or earlier")
            label("Summer", width: columns.summer, alignment: .center)
                .help("Offered in summer")
            label("Term", width: columns.term)
                .help("Which term you took it in, or To take")
            label("Route", width: columns.status)
            Color.clear.frame(width: columns.remove, height: 1)
        }
        .padding(.horizontal, PlannerColumns.inset)
        .frame(height: 30)
        .background(theme.panel2Color.opacity(0.55))
        .thubanHairline(.top, color: theme.lineColor)
        .thubanHairline(.bottom, color: theme.lineColor)
        .padding(.horizontal, ThubanMetrics.hairline)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func label(_ text: String, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(theme.inkFaintColor)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }
}

// MARK: - Card edges for rows

/// Rows between the pinned header and the footer draw the card's side hairlines themselves.
struct PlannerCardSides: ViewModifier {
    @Environment(\.thubanTheme) private var theme
    var fill: Color?

    func body(content: Content) -> some View {
        content
            .background(fill ?? theme.panelColor)
            .thubanHairline(.leading, color: theme.lineColor)
            .thubanHairline(.trailing, color: theme.lineColor)
    }
}

extension View {
    func plannerCardSides(fill: Color? = nil) -> some View { modifier(PlannerCardSides(fill: fill)) }
}

// MARK: - Group header row

/// "● Fall 2026  Current   6 classes · 16 cr" between groups.
struct PlannerGroupHeaderRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var group: PlannerClassGroup

    var body: some View {
        let isCurrent = app.plannerGroupIsCurrent(group)
        HStack(spacing: 8) {
            if isCurrent {
                Circle().fill(theme.signalColor).frame(width: 7, height: 7)
            } else if group.termKey == nil {
                Icon(.route, size: 13).foregroundStyle(theme.brassInkColor)
            } else {
                Icon(.check, size: 12).foregroundStyle(theme.posTextColor)
            }
            Text(app.plannerGroupTitle(group))
                .font(ThubanFont.body(13, weight: .semibold))
                .foregroundStyle(isCurrent ? theme.signalTextColor : theme.inkColor)
            if isCurrent {
                Text("Current")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.signalTextColor)
            }
            Text(app.plannerGroupCaption(group))
                .font(ThubanFont.mono(12))
                .monospacedDigit()
                .foregroundStyle(theme.inkFaintColor)
            if group.termKey == nil {
                Text("· the route places these")
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkFaintColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PlannerColumns.inset + 2)
        .frame(height: 32)
        .plannerCardSides(fill: isCurrent ? theme.signalSoftColor.opacity(0.55) : theme.panel2Color.opacity(0.35))
        .thubanHairline(.top, color: theme.lineColor)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Footer

/// The card's bottom: totals and the keyboard hint.
struct PlannerClassTableFooter: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var shown: Int

    private static let shape = UnevenRoundedRectangle(bottomLeadingRadius: ThubanMetrics.cardRadius,
                                                      bottomTrailingRadius: ThubanMetrics.cardRadius, style: .continuous)

    var body: some View {
        HStack(spacing: 10) {
            Text(summary)
                .font(ThubanFont.body(12.5))
                .foregroundStyle(theme.inkDimColor)
                .monospacedDigit()
            Spacer(minLength: 12)
            Text("↑ ↓ select  ·  Return edit  ·  Tab next field  ·  ⌫ remove  ·  double-click for details")
                .font(ThubanFont.body(12))
                .foregroundStyle(theme.inkFaintColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 38)
        .background(Self.shape.fill(theme.panelColor))
        .overlay(Self.shape.strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }

    private var summary: String {
        let total = app.courses.count
        let base = "\(app.taken.count) taken · \(app.toTake.count) to take · \(app.creditsText(app.creditsTotal)) credits in all"
        return shown == total ? base : "Showing \(shown) of \(total) · " + base
    }
}

// MARK: - Empty rows

/// A message row inside the table ("No classes yet", "No classes match").
struct PlannerTableMessageRow<Actions: View>: View {
    @Environment(\.thubanTheme) private var theme
    var icon: IconName
    var text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 10) {
            Icon(icon, size: 22).foregroundStyle(theme.brassInkColor)
            Text(text)
                .font(ThubanFont.body(14))
                .foregroundStyle(theme.inkDimColor)
            actions()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .plannerCardSides()
    }
}
