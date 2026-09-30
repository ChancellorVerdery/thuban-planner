import SwiftUI
import ThubanPlannerCore

/// Left column: term, the classes (each expandable to its sections
/// with include toggles and a pin), "add a class", and the filters.
struct ScheduleSidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let model = app.scheduleTab
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                termSection(model)
                coursesSection(model)
                filtersSection(model)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.panelColor)
        .thubanHairline(.trailing, color: theme.lineColor)
    }

    // MARK: Term

    private func termSection(_ model: ScheduleModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Semester") {
                if model.termsPhase == .loading { ProgressView().controlSize(.mini) }
            }
            Menu {
                ForEach(model.pickerTerms) { term in
                    Button {
                        model.selectTerm(term.code)
                    } label: {
                        let text = term.viewOnly ? "\(term.description)  (view only)" : term.description
                        if term.code == model.selectedTermCode { Label(text, systemImage: "checkmark") } else { Text(text) }
                    }
                }
                if !model.offline {
                    Divider()
                    Button("Reload term list") { model.loadTerms(force: true) }
                }
            } label: {
                HStack(spacing: 10) {
                    Icon(.calendar, size: 16).foregroundStyle(theme.brassInkColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.selectedTermLabel)
                            .font(ThubanFont.display(18))
                            .foregroundStyle(theme.inkColor)
                        if let term = model.selectedTerm {
                            Text("Banner term \(term.code)\(term.viewOnly ? " · view only" : "")")
                                .font(ThubanFont.mono(11))
                                .foregroundStyle(theme.inkFaintColor)
                        }
                    }
                    Spacer(minLength: 4)
                    Icon(.chevronDown, size: 13).foregroundStyle(theme.inkDimColor)
                }
                .padding(.horizontal, 12)
                .frame(height: 52)
                .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(model.pickerTerms.isEmpty)
            .accessibilityLabel("Semester: \(model.selectedTermLabel)")
            if case .failed(let message) = model.termsPhase, !model.pickerTerms.isEmpty {
                Text("Couldn’t refresh the term list — showing the saved one. \(message)")
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkFaintColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Courses

    private func coursesSection(_ model: ScheduleModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Classes", count: model.rows.count) {
                if !model.fetching.isEmpty { ProgressView().controlSize(.mini) }
            }
            Text("The classes Thuban’s route places in \(model.selectedTermLabel), plus any you add. Sections come from UNC Charlotte’s public class search — no sign-in.")
                .font(ThubanFont.body(12))
                .foregroundStyle(theme.inkFaintColor)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(model.rows) { row in
                    ScheduleCourseCard(row: row, colors: theme.scheduleCourseColors(model.colorIndex(of: row.code)))
                }
            }
            ScheduleAddCourseField()
            if !model.state.removedCourses.isEmpty {
                Button {
                    model.restoreRemovedCourses()
                } label: {
                    Text("\(model.state.removedCourses.count) removed · Restore")
                        .font(ThubanFont.body(12, weight: .semibold))
                        .foregroundStyle(theme.brassInkColor)
                }
                .buttonStyle(.plain)
                .help(model.state.removedCourses.joined(separator: ", "))
            }
        }
    }

    static func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: Filters

    private func filtersSection(_ model: ScheduleModel) -> some View {
        let f = model.state.filters
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader("Filters")
                .padding(.bottom, 4)
            filterRow("Open seats only", detail: "Sections with a seat left", isOn: f.openSeatsOnly) { v in model.setFilters { $0.openSeatsOnly = v } }
            filterRow("Hide full or wait-listed", detail: "No seat, or someone is waiting", isOn: f.hideFullOrWaitlisted) { v in model.setFilters { $0.hideFullOrWaitlisted = v } }
            filterRow("Allow online", detail: "Online and no-set-time sections", isOn: f.allowOnline) { v in model.setFilters { $0.allowOnline = v } }
            let campuses = model.campuses
            if campuses.count > 1 || !f.campuses.isEmpty {
                HStack {
                    Text("Campus").font(ThubanFont.body(13, weight: .medium)).foregroundStyle(theme.inkColor)
                    Spacer()
                    Menu {
                        Button("Any campus") { model.setFilters { $0.campuses = [] } }
                        Divider()
                        ForEach(campuses, id: \.self) { campus in
                            Button {
                                model.setFilters { filters in
                                    if filters.campuses.contains(campus) { filters.campuses.removeAll { $0 == campus } } else { filters.campuses.append(campus) }
                                }
                            } label: {
                                if f.campuses.contains(campus) { Label(campus, systemImage: "checkmark") } else { Text(campus) }
                            }
                        }
                    } label: {
                        Text(f.campuses.isEmpty ? "Any" : f.campuses.joined(separator: ", "))
                            .font(ThubanFont.body(12, weight: .semibold))
                            .foregroundStyle(theme.brassInkColor)
                            .lineLimit(1)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
                .frame(height: 34)
            }
        }
    }

    private func filterRow(_ title: String, detail: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(ThubanFont.body(13, weight: .medium)).foregroundStyle(theme.inkColor)
                Text(detail).font(ThubanFont.body(11.5)).foregroundStyle(theme.inkFaintColor)
            }
            Spacer(minLength: 8)
            ThubanToggle(isOn: Binding(get: { isOn }, set: set), label: title)
                .controlSize(.small)
        }
        .frame(minHeight: 38)
    }
}

// MARK: - Add a class

private struct ScheduleAddCourseField: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Add a class, e.g. MEGR 2144", text: $text)
                    .thubanField(invalid: error != nil, mono: true, height: 32)
                    .onSubmit(add)
                    .onChange(of: text) { _, _ in error = nil }
                    .accessibilityLabel("Add a class by code")
                Button(action: add) {
                    Icon(.plus, size: 15)
                        .foregroundStyle(theme.inkColor)
                        .frame(width: 32, height: 32)
                        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                            .strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || app.scheduleTab.selectedTermCode == nil)
                .accessibilityLabel("Add class")
            }
            if let error {
                Text(error).font(ThubanFont.body(12)).foregroundStyle(theme.negTextColor)
            }
        }
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let problem = app.scheduleTab.addCourse(trimmed) { error = problem } else { text = "" }
    }
}
