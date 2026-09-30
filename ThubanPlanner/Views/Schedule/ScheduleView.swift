import SwiftUI
import ThubanPlannerCore

/// The Schedule section (⌘3): pick a Banner term, take the classes from the Banner plan or Thuban's route, fetch
/// their sections, and page through every timetable that fits (with blocked times). Sidebar on the left, the week
/// grid on the right. Read-only against Banner: the user registers in Banner themselves with the copied CRNs.
struct ScheduleView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @FocusState private var gridFocused: Bool

    var body: some View {
        let model = app.scheduleTab
        HStack(spacing: 0) {
            ScheduleSidebar()
            VStack(spacing: 0) {
                ScheduleHeader()
                content(model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.currentOption != nil, !model.blockMode {
                    ScheduleCRNStrip()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onKeyPress(.leftArrow) { model.previousOption(); return .handled }
            .onKeyPress(.rightArrow) { model.nextOption(); return .handled }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
        .onAppear {
            model.activate()
            gridFocused = true
        }
        .sheet(isPresented: Binding(get: { model.showSignIn }, set: { model.showSignIn = $0 }),
               onDismiss: { model.afterSignInSheet() }) {
            ScheduleSignInSheet()
                .environment(app)
                .environment(\.thubanTheme, app.theme)
                .environment(\.thubanTextScale, app.preferences.textSize.scale)
                .preferredColorScheme(app.theme.isDark ? .dark : .light)
        }
    }

    @ViewBuilder
    private func content(_ model: ScheduleModel) -> some View {
        if model.selectedTermCode == nil {
            if model.termsPhase == .loading || (!model.isActivated) {
                ScheduleProgress(text: "Loading terms from Banner…")
            } else {
                EmptyState(icon: .schedule, title: "Can’t reach Banner",
                           message: model.networkError ?? "The term list couldn’t be loaded. Check your connection and try again.") {
                    Button("Try again") { model.loadTerms(force: true) }.buttonStyle(.thubanPrimary)
                }
            }
        } else if model.state.source == .bannerPlan, model.plans.isEmpty, model.planPhase == .loading || model.auth == .checking {
            ScheduleProgress(text: "Reading your Banner plan…")
        } else if model.state.source == .bannerPlan, model.plans.isEmpty, model.state.addedCourses.isEmpty,
                  model.auth == .signedOut || model.auth == .expired || model.auth == .unknown {
            ScheduleSignInPrompt()
        } else if model.rows.isEmpty {
            ScheduleNoCourses()
        } else if model.result.options.isEmpty, model.result.problems.isEmpty, !model.missingCourses.isEmpty,
                  model.rows.allSatisfy({ $0.sections == nil }) {
            if model.rows.contains(where: { $0.error != nil }) && model.fetching.isEmpty {
                EmptyState(icon: .schedule, title: "Couldn’t load sections",
                           message: model.networkError ?? model.rows.compactMap(\.error).first ?? "Banner didn’t answer.") {
                    Button("Try again") { model.refreshAllSections() }.buttonStyle(.thubanPrimary)
                }
            } else {
                let done = model.rows.filter { $0.sections != nil }.count
                ScheduleProgress(text: "Finding sections… \(done) of \(model.rows.count)")
            }
        } else {
            ScheduleWeekGrid(option: model.currentOption, blocks: model.blocks, blockMode: model.blockMode)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .overlay {
                    if model.currentOption == nil, !model.blockMode, !model.result.problems.isEmpty || !model.rows.isEmpty {
                        ScheduleNoResultsCard()
                    }
                }
        }
    }
}

// MARK: - Header

private struct ScheduleHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale

    var body: some View {
        let model = app.scheduleTab
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow("\(model.selectedTermLabel) · \(model.state.source.label)")
                Text(title(model))
                    .font(ThubanFont.display(28))
                    .kerning(-0.28)
                    .foregroundStyle(theme.inkColor)
                    .monospacedDigit()
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle(model))
                    .font(ThubanFont.scaled(14, scale: textScale))
                    .foregroundStyle(theme.inkDimColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if model.blockMode {
                Text("Drag on the grid to block a time · click a block to rename or delete it")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.brassInkColor)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            } else if model.optionCount > 0 {
                navigation(model)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private func title(_ model: ScheduleModel) -> String {
        if model.blockMode { return "Block out times" }
        let n = model.optionCount
        if n == 0 { return model.rows.isEmpty ? "Schedule" : (model.fetching.isEmpty ? "No schedules fit" : "Building schedules…") }
        return "Schedule \((model.selectedIndex + 1).formatted()) of \(n.formatted())\(model.result.capped ? "+" : "")"
    }

    private func subtitle(_ model: ScheduleModel) -> String {
        if model.blockMode {
            let n = model.blocks.count
            return n == 0 ? "No blocked times yet — sections that meet in a blocked time are left out." : "\(n) blocked time\(n == 1 ? "" : "s") — sections that meet in one are left out."
        }
        guard let option = model.currentOption else {
            let n = model.rows.count
            if n == 0 {
                return model.state.source == .bannerPlan && model.plans.isEmpty
                    ? "Your Banner plan’s classes appear here once you’re signed in."
                    : "Add classes in the sidebar to build schedules."
            }
            return "\(n) class\(n == 1 ? "" : "es") · \(model.result.problems.isEmpty ? "waiting for sections" : "see why below")"
        }
        var parts: [String] = []
        // One credit value per course (a linked lab would double count).
        let credits = option.picks.reduce(0.0) { $0 + ($1.choice.sections.first?.credits ?? 0) }
        parts.append("\(app.creditsText(credits)) credits")
        let m = option.metrics
        parts.append("\(m.classDays) class day\(m.classDays == 1 ? "" : "s")")
        if let start = m.earliestStart, let end = m.latestEnd {
            parts.append("\(BannerClock.label(start)) – \(BannerClock.label(end))")
        }
        parts.append(m.gapMinutes == 0 ? "no gaps" : "\(Self.duration(m.gapMinutes)) between classes")
        if model.result.capped { parts.append("showing the first \(model.result.limit.formatted())") }
        if !model.missingCourses.isEmpty { parts.append("\(model.missingCourses.count) without sections") }
        return parts.joined(separator: " · ")
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    private func navigation(_ model: ScheduleModel) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(TimetableSort.allCases) { sort in
                    Button {
                        model.setSort(sort)
                    } label: {
                        if sort == model.state.sort { Label(sort.label, systemImage: "checkmark") } else { Text(sort.label) }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Icon(.sliders, size: 15)
                    Text(model.state.sort.label)
                    Icon(.chevronDown, size: 12)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Sort schedules: \(model.state.sort.label)")
            .padding(.trailing, 6)

            IconButton(.chevronLeft, label: "Previous schedule (←)", size: 32, iconSize: 16) { model.previousOption() }
                .disabled(model.optionCount < 2)
            Text("\((model.selectedIndex + 1).formatted()) / \(model.optionCount.formatted())")
                .font(ThubanFont.mono(12, weight: .medium))
                .foregroundStyle(theme.inkDimColor)
                .frame(minWidth: 74)
                .monospacedDigit()
            IconButton(.chevronRight, label: "Next schedule (→)", size: 32, iconSize: 16) { model.nextOption() }
                .disabled(model.optionCount < 2)
        }
    }
}

// MARK: - CRN strip

/// The current timetable's sections as chips (course colour dot, code, section, CRN) and "Copy CRNs"; online / TBA
/// sections are listed separately since they are not on the grid.
private struct ScheduleCRNStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var copied = false

    var body: some View {
        let model = app.scheduleTab
        if let option = model.currentOption {
            let untimed = option.sections.filter(\.hasNoSetTime)
            HStack(alignment: .center, spacing: 12) {
                Text("CRNs")
                    .font(ThubanFont.body(13, weight: .semibold))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(option.picks, id: \.course) { pick in
                            ForEach(pick.choice.sections) { section in
                                chip(section, colors: theme.scheduleCourseColors(model.colorIndex(of: pick.course)))
                            }
                        }
                    }
                }
                if !untimed.isEmpty {
                    Text("Online / TBA: " + untimed.map { "\($0.courseCode) \($0.sequenceNumber)" }.joined(separator: ", "))
                        .font(ThubanFont.body(12))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                        .fixedSize()
                        .help("These sections have no set meeting time, so they are not on the grid.")
                }
                Button {
                    model.copyCRNs()
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_600_000_000); copied = false }
                } label: {
                    HStack(spacing: 7) { Icon(copied ? .check : .file, size: 15); Text(copied ? "Copied" : "Copy CRNs") }
                }
                .buttonStyle(SecondaryButtonStyle(height: 32))
                .help("Copies \(model.currentCRNText) — paste them into Banner’s registration yourself.")
            }
            .padding(.horizontal, 28)
            .frame(height: 52)
            .background(theme.panelColor)
            .thubanHairline(.top, color: theme.lineColor)
        }
    }

    private func chip(_ section: BannerSection, colors: ScheduleCourseColors) -> some View {
        HStack(spacing: 6) {
            Circle().fill(colors.dot).frame(width: 7, height: 7)
            Text(section.courseCode).font(ThubanFont.mono(12, weight: .semibold))
            Text(section.sequenceNumber).font(ThubanFont.mono(12))
                .foregroundStyle(theme.inkDimColor)
            Text(section.crn).font(ThubanFont.mono(12, weight: .semibold))
                .foregroundStyle(theme.brassInkColor)
        }
        .foregroundStyle(theme.inkColor)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        .textSelection(.enabled)
        .help("\(section.courseCode) \(section.sequenceNumber) · \(section.title) · CRN \(section.crn)")
    }
}

// MARK: - States

private struct ScheduleProgress: View {
    @Environment(\.thubanTheme) private var theme
    var text: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(ThubanFont.body(14))
                .foregroundStyle(theme.inkDimColor)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScheduleSignInPrompt: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.scheduleTab
        let expired = model.auth == .expired
        EmptyState(icon: .schedule,
                   title: expired ? "Your Banner session ended" : "Sign in to read your Banner plan",
                   message: expired
                       ? "Sign in again to read your Plan Ahead classes for \(model.selectedTermLabel)."
                       : "Your plan is read from UNC Charlotte’s Plan Ahead. You sign in on UNC Charlotte’s own page — Thuban Planner never sees your password and never registers or changes anything.") {
            HStack(spacing: 10) {
                Button { model.showSignIn = true } label: {
                    Text(expired ? "Sign in again" : "Sign in to Banner")
                }
                .buttonStyle(.thubanPrimary)
                Button { model.setSource(.route) } label: {
                    HStack(spacing: 7) { Icon(.route, size: 15); Text("Use Thuban route") }
                }
                .buttonStyle(.thubanSecondary)
            }
        }
    }
}

private struct ScheduleNoCourses: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.scheduleTab
        let fromPlan = model.state.source == .bannerPlan
        EmptyState(icon: .schedule, title: "No classes for \(model.selectedTermLabel)",
                   message: fromPlan
                       ? "Your Banner plan has no classes in this term. Add one by code in the sidebar, pick another plan or term, or use Thuban’s route."
                       : "Thuban’s route has no classes in this term. Add one by code in the sidebar, or pick another term.") {
            HStack(spacing: 10) {
                if !model.state.removedCourses.isEmpty {
                    Button("Restore removed classes") { model.restoreRemovedCourses() }.buttonStyle(.thubanSecondary)
                }
                if fromPlan {
                    Button { model.setSource(.route) } label: {
                        HStack(spacing: 7) { Icon(.route, size: 15); Text("Use Thuban route") }
                    }
                    .buttonStyle(.thubanSecondary)
                }
            }
        }
    }
}

/// Shown over the empty grid: why nothing fits and what to try.
private struct ScheduleNoResultsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let model = app.scheduleTab
        let problems = model.result.problems
        if !problems.isEmpty || !model.fetching.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Icon(.info, size: 20).foregroundStyle(theme.negTextColor)
                    Text(model.fetching.isEmpty ? "Why nothing fits" : "Still finding sections…")
                        .font(ThubanFont.display(20))
                        .foregroundStyle(theme.inkColor)
                }
                ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(theme.negColor).frame(width: 6, height: 6).offset(y: -2)
                        Text(problem.message)
                            .font(ThubanFont.body(14))
                            .foregroundStyle(theme.inkColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !problems.isEmpty {
                    Text("Try loosening a filter, including more sections, removing a class, or clearing a blocked time.")
                        .font(ThubanFont.body(13))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if !model.blocks.isEmpty {
                            Button { model.blockMode = true } label: {
                                HStack(spacing: 7) { Icon(.clock, size: 15); Text("Edit blocked times") }
                            }
                            .buttonStyle(SecondaryButtonStyle(height: 32))
                        }
                        if model.state.filters != TimetableFilters() {
                            Button("Reset filters") { model.setFilters { $0 = TimetableFilters() } }
                                .buttonStyle(SecondaryButtonStyle(height: 32))
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 520, alignment: .leading)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
            .accessibilityElement(children: .combine)
        }
    }
}
