import SwiftUI
import ThubanPlannerCore

/// The main window: 52 pt title bar, 50 pt section bar (section tabs + the section's own toolbar on the right), then
/// the section's content. Also hosts the class detail sheet and the load / save error banner. Sections live in
/// Views/<Area>/ and are only referenced here. FROZEN (shared): areas never edit this file.
struct ShellView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let theme = app.theme
        VStack(spacing: 0) {
            TitleBar()
            SectionBar()
            if let problem = app.loadError ?? app.saveError {
                ProblemBanner(text: problem, isLoadError: app.loadError != nil)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Technical electives / Import degree requirements (App/DegreeTools, Views/Electives, Views/DegreeImport).
                .sheet(item: Binding(get: { app.degreeTools.sheet }, set: { if $0 == nil { app.degreeTools.closeSheet() } })) { sheet in
                    Group {
                        switch sheet {
                        case .electives: ElectivesSheet()
                        case .degreeImport: DegreeImportSheet()
                        }
                    }
                    .environment(app)
                    .environment(\.thubanTheme, app.theme)
                    .environment(\.thubanTextScale, app.preferences.textSize.scale)
                    .preferredColorScheme(app.theme.isDark ? .dark : .light)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
        .environment(\.thubanTheme, theme)
        .environment(\.thubanTextScale, app.preferences.textSize.scale)
        .ignoresSafeArea()
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(item: Binding(get: { app.presentedCourseId.map(CourseSheetItem.init) },
                             set: { app.presentedCourseId = $0?.id })) { item in
            ClassDetailSheet(courseId: item.id)
                .environment(app)
                .environment(\.thubanTheme, app.theme)
                .environment(\.thubanTextScale, app.preferences.textSize.scale)
                .preferredColorScheme(app.theme.isDark ? .dark : .light)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !app.isLoaded {
            Color.clear
        } else {
            switch app.section {
            case .planner: PlannerView()
            case .route: RouteView()
            case .schedule: ScheduleView()
            case .settings: SettingsView()
            }
        }
    }
}

private struct CourseSheetItem: Identifiable {
    var id: String
}

// MARK: - Title bar

/// [traffic lights] mark + serif "Thuban Planner" ……… status chip. (Settings is a section: ⌘4 / ⌘,.)
struct TitleBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: ThubanMetrics.trafficLightInset - 16)
            HStack(spacing: 9) {
                AppArtView(size: 20, theme: theme)
                Text("Thuban Planner")
                    .font(ThubanFont.display(18))
                    .kerning(-0.18)
                    .foregroundStyle(theme.inkColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Thuban Planner")

            Spacer(minLength: 8)

            StatusChip()
        }
        .padding(.horizontal, 16)
        .frame(height: ThubanMetrics.titleBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.panelColor)
        .thubanHairline(.bottom, color: theme.lineColor)
        .gesture(WindowDragGesture())
    }
}

/// "Importing from Atlas…" during an import; otherwise where the route ends ("Finishes Spring 2028", click → Route)
/// or how many classes cannot be placed.
struct StatusChip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        if app.importPhase.isBusy {
            chip(dot: theme.accentColor, text: "Importing from Atlas…")
        } else if !app.schedule.unplaceable.isEmpty {
            let n = app.schedule.unplaceable.count
            Button { app.showRoute() } label: { chip(dot: theme.negColor, text: "\(n) class\(n == 1 ? "" : "es") can’t be placed") }
                .buttonStyle(.plain)
                .help(app.warnings.joined(separator: "\n"))
        } else if !app.toTake.isEmpty, let grad = app.gradTermLabel {
            Button { app.showRoute() } label: { chip(dot: theme.signalColor, text: "Finishes \(grad)") }
                .buttonStyle(.plain)
                .help(app.planStatus)
        }
    }

    private func chip(dot: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.inkDimColor)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section bar

/// Section tabs (Planner / Route / Schedule / Settings) on the left, the current section's toolbar on the right.
struct SectionBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            SectionTabs()
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                switch app.section {
                case .planner: PlannerToolbar()
                case .route: RouteToolbar()
                case .schedule: ScheduleToolbar()
                case .settings: SettingsToolbar()
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: ThubanMetrics.sectionBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }
}

/// The segmented section nav: `panel2` track (padding 3, radius 9); active tab is a `panel` card with a `line2`
/// border and `ink` text; icons 15 pt.
struct SectionTabs: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                SectionTab(section: section, isActive: app.section == section) { app.section = section }
            }
        }
        .padding(3)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }
}

private struct SectionTab: View {
    @Environment(\.thubanTheme) private var theme
    var section: AppSection
    var isActive: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Icon(section.icon, size: 15)
                Text(section.label)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isActive ? theme.inkColor : theme.inkDimColor)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(isActive ? theme.panelColor : (hovering ? theme.panelColor.opacity(0.5) : .clear),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isActive ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(section.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .help("\(section.label) (⌘\(String(section.shortcut)))")
    }
}

// MARK: - Banner

private struct ProblemBanner: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var text: String
    var isLoadError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(theme.negColor).frame(width: 7, height: 7)
            Text(isLoadError ? "Your data could not be read, so nothing will be saved until it is fixed. \(text)" : "Could not save: \(text)")
                .font(ThubanFont.small)
                .foregroundStyle(theme.negTextColor)
                .lineLimit(2)
            Spacer(minLength: 8)
            if isLoadError {
                ToolbarButton("Restore a backup", icon: .history) { app.openSettings(.data) }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 36)
        .background(theme.negSoftColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }
}
