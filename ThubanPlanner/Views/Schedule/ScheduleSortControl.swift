import SwiftUI
import ThubanPlannerCore

/// The header's sort control: a button showing the active criteria in priority order ("Fewest days → Highest
/// rating"; the full list in the tooltip) that opens a popover with a checkbox per criterion. Checking appends it
/// to the priority list, unchecking removes it (never the last one); active criteria are numbered and can be moved
/// up or down; "Reset to default". Choosing "Highest professor rating" (anywhere in the list) or "Look up professor
/// ratings" looks up every instructor of the term on Rate My Professors (cache first).
struct ScheduleSortControl: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        @Bindable var model = app.scheduleTab
        let sorts = model.state.sorts
        Button {
            model.sortMenuOpen.toggle()
        } label: {
            HStack(spacing: 7) {
                Icon(.sliders, size: 15)
                Text(sorts.count == 1 ? sorts[0].label : sorts.map(\.shortLabel).joined(separator: " → "))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 300, alignment: .leading)
                    .fixedSize(horizontal: sorts.count == 1, vertical: false)
                Icon(.chevronDown, size: 12)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.inkColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(sorts.count > 1 ? theme.accentTintColor : theme.panelColor,
                        in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(sorts.count > 1 ? theme.accentColor : theme.line2Color, lineWidth: ThubanMetrics.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by: " + sorts.enumerated().map { "\($0.offset + 1). \($0.element.label)" }.joined(separator: ", "))
        .accessibilityLabel("Sort schedules by " + sorts.map(\.label).joined(separator: ", then "))
        .popover(isPresented: $model.sortMenuOpen, arrowEdge: .bottom) {
            ScheduleSortPopover()
                .environment(app)
                .environment(\.thubanTheme, theme)
        }
    }
}

/// The popover: every criterion with a checkbox, the active ones first in priority order.
struct ScheduleSortPopover: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let model = app.scheduleTab
        let active = model.state.sorts
        let inactive = TimetableSort.allCases.filter { !active.contains($0) }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow("Sort schedules by")
                Text("Check several to combine them — ties on the first are broken by the second, and so on.")
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Hairline()
            VStack(spacing: 2) {
                ForEach(Array(active.enumerated()), id: \.element) { index, sort in
                    row(sort, rank: index + 1, count: active.count)
                }
                if !inactive.isEmpty, !active.isEmpty { Hairline().padding(.vertical, 4) }
                ForEach(inactive) { sort in row(sort, rank: nil, count: active.count) }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            Hairline()
            ratingsFooter(model)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 360)
        .background(theme.panelColor)
    }

    private func row(_ sort: TimetableSort, rank: Int?, count: Int) -> some View {
        let model = app.scheduleTab
        let isActive = rank != nil
        return HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isActive }, set: { _ in model.toggleSort(sort) })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .tint(theme.accentColor)
                .disabled(isActive && count == 1)
                .accessibilityLabel(sort.label)
            Text(rank.map(String.init) ?? "")
                .font(ThubanFont.mono(11, weight: .semibold))
                .foregroundStyle(theme.onAccentColor)
                .frame(width: 18, height: 18)
                .background(isActive ? theme.accentColor : .clear, in: Circle())
                .accessibilityHidden(true)
            Text(sort.label)
                .font(ThubanFont.body(13.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? theme.inkColor : theme.inkDimColor)
            Spacer(minLength: 6)
            if let rank, count > 1 {
                moveButton("chevron.up", label: "Move \(sort.label) up") { model.moveSort(sort, by: -1) }
                    .disabled(rank == 1)
                moveButton("chevron.down", label: "Move \(sort.label) down") { model.moveSort(sort, by: 1) }
                    .disabled(rank == count)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(isActive ? theme.accentTintColor.opacity(0.55) : .clear,
                    in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if !(isActive && count == 1) { model.toggleSort(sort) } }
    }

    private func moveButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(GhostButtonStyle(height: 24, horizontalPadding: 0))
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func ratingsFooter(_ model: ScheduleModel) -> some View {
        HStack(spacing: 8) {
            if let p = model.ratings.progress {
                ProgressView().controlSize(.mini)
                Text("Rating professors \(p.done) / \(p.total)")
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkDimColor)
                    .monospacedDigit()
            } else {
                Button("Look up ratings") { model.lookUpAllProfessors() }
                    .buttonStyle(GhostButtonStyle(height: 28, tinted: true, horizontalPadding: 8))
                    .fixedSize()
                    .help("Looks up every instructor of this term on Rate My Professors (UNC Charlotte pages, cached for a week).")
            }
            Spacer(minLength: 6)
            Button("Reset to default") { model.resetSorts() }
                .buttonStyle(GhostButtonStyle(height: 28, horizontalPadding: 8))
                .fixedSize()
                .disabled(model.state.sorts == TimetableSort.defaultList)
        }
    }
}
