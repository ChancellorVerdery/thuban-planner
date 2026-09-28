import SwiftUI
import ThubanPlannerCore

// MARK: - Group card chrome

/// A Planner group card: eyebrow title, one dim caption line, optional trailing accessory, then content.
struct PlannerGroupCard<Accessory: View, Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var caption: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(_ title: String, caption: String, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.caption = caption
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(title).accessibilityAddTraits(.isHeader)
                    Text(caption)
                        .font(ThubanFont.body(13))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                accessory()
            }
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        // Each card is as tall as its own content (the row top-aligns them), not stretched to its neighbour.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }
}

// MARK: - Semesters

/// "Semesters": a wrapping row of term chips in rank order (label, credits, current dot; a menu each), a dashed
/// "Add semester" chip, and the inline add form.
struct PlannerSemestersCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Bindable var state: PlannerViewState

    var body: some View {
        PlannerGroupCard("Semesters", caption: "Your past & current terms — the classes you’ve taken.") {
            if !app.terms.isEmpty {
                Text("\(app.terms.count) · \(app.creditsText(app.creditsTaken)) cr")
                    .font(ThubanFont.mono(12))
                    .foregroundStyle(theme.inkFaintColor)
                    .monospacedDigit()
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PlannerFlowLayout(spacing: 8) {
                    if app.terms.isEmpty && !state.isAddingSemesterInline {
                        Text("No semesters yet — add your past and current terms.")
                            .font(ThubanFont.body(13))
                            .foregroundStyle(theme.inkFaintColor)
                            .frame(height: 32)
                    }
                    ForEach(app.plannerSemesterChips, id: \.term.key) { item in
                        PlannerTermChip(term: item.term, credits: item.credits, count: item.count, state: state)
                    }
                    if !state.isAddingSemesterInline {
                        PlannerAddChip(label: "Add semester") { state.isAddingSemesterInline = true }
                    }
                }
                if state.isAddingSemesterInline {
                    PlannerAddSemesterForm(layout: .inline) { state.isAddingSemesterInline = false }
                        .transition(.opacity)
                }
            }
        }
    }
}

/// One recorded semester: "Fall 2025  15 cr", with a signal dot and "Current" on the current one. Click → menu.
struct PlannerTermChip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var term: Term
    var credits: Double
    var count: Int
    @Bindable var state: PlannerViewState
    @State private var hovering = false

    var body: some View {
        Menu {
            Button("Mark as current") { app.setCurrentTerm(term.key) }
                .disabled(term.current)
            Divider()
            Button("Remove semester…", role: .destructive) {
                if count > 0 { state.pendingRemovalTermKey = term.key } else { app.removeTerm(term.key) }
            }
        } label: {
            chip
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .accessibilityLabel("\(term.label), \(app.creditsText(credits)) credits\(term.current ? ", current semester" : "")")
        .help("\(count) class\(count == 1 ? "" : "es") recorded · click for options")
    }

    private var chip: some View {
        HStack(spacing: 8) {
            if term.current {
                Circle().fill(theme.signalColor).frame(width: 7, height: 7)
            }
            Text(term.label)
                .font(ThubanFont.body(13, weight: .semibold))
                .foregroundStyle(term.current ? theme.signalTextColor : theme.inkColor)
            Text("\(app.creditsText(credits)) cr")
                .font(ThubanFont.mono(12))
                .monospacedDigit()
                .foregroundStyle(term.current ? theme.signalTextColor.opacity(0.8) : theme.inkDimColor)
            if term.current {
                Text("Current")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.signalTextColor)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(theme.signalColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Glyph(.chevronDown, size: 10)
                .foregroundStyle(term.current ? theme.signalTextColor : theme.inkFaintColor)
        }
        .padding(.leading, 11)
        .padding(.trailing, 9)
        .frame(height: 32)
        .background(fill, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
            .strokeBorder(term.current ? theme.signalColor : theme.line2Color, lineWidth: ThubanMetrics.hairline))
        .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
    }

    private var fill: Color {
        if term.current { return theme.signalSoftColor }
        return hovering ? theme.panel2Color : theme.panelColor
    }
}

/// A dashed "+ Add …" chip.
struct PlannerAddChip: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(.plus, size: 13)
                Text(label)
            }
            .font(ThubanFont.body(13, weight: .semibold))
            .foregroundStyle(hovering ? theme.brassInkColor : theme.inkDimColor)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(hovering ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(theme.line2Color, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

// MARK: - Add semester form

/// Season (segmented), year (field + stepper), "This is my current semester", Add. Used inline in the Semesters
/// card and in the toolbar's "+ Semester" popover. Defaults from the calendar term (or the term after the last
/// recorded one when that one already exists).
struct PlannerAddSemesterForm: View {
    enum Layout { case inline, popover }

    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var layout: Layout
    var onClose: () -> Void

    @State private var season: Season = .fall
    @State private var year: Int = 2026
    @State private var yearText = "2026"
    @State private var current = false
    @State private var seeded = false
    @FocusState private var yearFocused: Bool

    private var exists: Bool { parsedYear.map { app.plannerTermExists(season: season, year: $0) } ?? false }
    /// Atlas's year input range (HTML min / max).
    private static let yearRange = 2000 ... 2100
    /// The year the field shows, or nil when its text is not a year in range (then Add is disabled).
    private var parsedYear: Int? {
        guard let value = Int(yearText.trimmingCharacters(in: .whitespaces)), Self.yearRange.contains(value) else { return nil }
        return value
    }
    private var yearValid: Bool { parsedYear != nil }

    var body: some View {
        Group {
            switch layout {
            case .inline: inlineBody
            case .popover: popoverBody
            }
        }
        .onAppear(perform: seed)
    }

    private var inlineBody: some View {
        HStack(spacing: 12) {
            seasonPicker
            yearField
            HStack(spacing: 8) {
                ThubanToggle(isOn: $current, label: "This is my current semester")
                    .controlSize(.small)
                Text("Current semester")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
            }
            Spacer(minLength: 8)
            if exists {
                Text("\(TermKey.label(TermKey.make(season, year))) is already listed")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkFaintColor)
            }
            Button("Cancel", action: onClose)
                .buttonStyle(GhostButtonStyle(height: 30))
                .keyboardShortcut(.cancelAction)
            Button("Add semester", action: add)
                .buttonStyle(PrimaryButtonStyle(height: 30))
                .disabled(exists || !yearValid)
        }
        .padding(10)
        .background(theme.panel2Color.opacity(0.6), in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
            .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a semester")
                    .font(ThubanFont.display(18))
                    .foregroundStyle(theme.inkColor)
                Text("A term you’ve taken or are taking now.")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                caption("Season")
                seasonPicker
            }
            VStack(alignment: .leading, spacing: 6) {
                caption("Year")
                yearField
            }
            HStack(spacing: 10) {
                Text("This is my current semester")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkColor)
                Spacer(minLength: 8)
                ThubanToggle(isOn: $current, label: "This is my current semester")
                    .controlSize(.small)
            }
            if exists {
                Text("\(TermKey.label(TermKey.make(season, year))) is already in your semesters.")
                    .font(ThubanFont.body(12.5))
                    .foregroundStyle(theme.inkFaintColor)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onClose)
                    .buttonStyle(SecondaryButtonStyle(height: 30))
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .buttonStyle(PrimaryButtonStyle(height: 30))
                    .disabled(exists || !yearValid)
            }
        }
        .padding(18)
        .frame(width: 300)
        .background(theme.panelColor)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(ThubanFont.body(12, weight: .semibold))
            .foregroundStyle(theme.inkDimColor)
    }

    private var seasonPicker: some View {
        SegmentedPicker(selection: $season,
                        options: Season.allCases.map { SegmentOption($0, $0.label) },
                        segmentHeight: 24)
            .fixedSize()
            .accessibilityLabel("Season")
    }

    private var yearField: some View {
        HStack(spacing: 4) {
            TextField("Year", text: $yearText)
                .focused($yearFocused)
                .multilineTextAlignment(.leading)
                .thubanField(invalid: !yearValid, mono: true, height: 30)
                .frame(width: 72)
                .accessibilityLabel("Year")
                .onChange(of: yearText) { _, text in
                    if let value = parsedYear { year = value }
                }
                .onSubmit(add)
            Stepper("Year", value: Binding(get: { year }, set: { year = $0; yearText = String($0) }), in: Self.yearRange)
                .labelsHidden()
                .accessibilityLabel("Change year")
        }
    }

    private func seed() {
        guard !seeded else { return }
        seeded = true
        var d = app.plannerDefaultNewTerm
        // When the calendar term is already recorded, suggest the term after the latest recorded one.
        if app.plannerTermExists(season: d.season, year: d.year), let last = app.terms.last {
            var key = TermKey.next(last.key)
            while TermKey.season(key) == .summer { key = TermKey.next(key) }
            let p = TermKey.parse(key)
            d = (p.season ?? .fall, Int(p.year))
        }
        season = d.season
        year = d.year
        yearText = String(d.year)
        // Atlas starts unchecked; suggest "current" only when nothing is current and the term is today's.
        current = app.currentTerm == nil && TermKey.make(d.season, d.year) == app.calendarTermKey
    }

    private func add() {
        guard !exists, let year = parsedYear else { return }
        app.addTerm(season: season, year: year, current: current)
        onClose()
    }
}

// MARK: - Summer terms

/// "Summer terms": one toggle per upcoming summer (on = the planner may use it; off = switched off).
struct PlannerSummersCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        PlannerGroupCard("Summer terms", caption: "Switch a summer off (internship, travel) to keep the planner out of it.") {
            PlannerFlowLayout(spacing: 8) {
                ForEach(app.upcomingSummers, id: \.self) { key in
                    let on = !app.isDisabled(key)
                    ToggleChip(label: app.termLabel(key) + (on ? "" : " · off"), icon: .sun,
                               isOn: Binding(get: { on }, set: { _ in app.toggleDisabledTerm(key) }))
                        .accessibilityLabel("\(app.termLabel(key)) summer")
                        .accessibilityValue(on ? "planned" : "switched off")
                        .help(on ? "The planner may use \(app.termLabel(key)). Click to switch it off."
                                 : "\(app.termLabel(key)) is switched off. Click to let the planner use it.")
                }
            }
        }
    }
}

// MARK: - Flow layout

/// Wraps children onto new lines (chips).
struct PlannerFlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : width } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                let y = row.y + row.height + spacing
                rows.append(Row(indices: [index], y: y, width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
