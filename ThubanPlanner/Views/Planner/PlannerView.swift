import AppKit
import SwiftUI
import ThubanPlannerCore

/// The Planner section (⌘1). OWNER: Engineer A. The working surface: header with the plan status and three stat
/// tiles, scheduler warnings and unknown-ref notes, Semesters and Summer terms, then the class table (pinned header,
/// grouped by term, sorted by code). Keyboard: ↑ ↓ select, Return edits, Tab moves between fields, ⌫ removes.
struct PlannerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @FocusState private var focus: PlannerFocus?
    /// True while the page is taller than the window. With legacy (always-visible) scroll bars the scroller then
    /// takes a gutter from the content width; the fixed-width table rows subtract it too, so rows, cards and the
    /// pinned header share one right edge whether or not the page scrolls.
    @State private var overflows = false
    private let state = PlannerViewState.shared

    var body: some View {
        Group {
            if app.courses.isEmpty && app.terms.isEmpty {
                PlannerEmptyState()
            } else {
                page
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bgColor)
        .modifier(PlannerConfirmations(state: state))
    }

    // MARK: Page

    private var page: some View {
        GeometryReader { geometry in
            let columns = PlannerColumns(width: geometry.size.width - scrollerGutter - Self.sidePadding * 2)
            let groups = app.plannerClassGroups(filter: state.filter, search: state.search)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        header
                            .padding(.bottom, 20)
                        notices
                        groupsRow
                            .padding(.bottom, 10)
                        Section {
                            tableBody(groups: groups, columns: columns)
                        } header: {
                            // A page-coloured band above the card: once pinned, the header keeps a top margin
                            // under the section bar and rows scrolling up disappear behind it.
                            PlannerClassTableHeader(state: state, columns: columns)
                                .padding(.top, 12)
                                .background(alignment: .top) { theme.bgColor.frame(height: 12 + ThubanMetrics.cardRadius) }
                        }
                    }
                    .padding(.horizontal, Self.sidePadding)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.automatic)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentSize.height > geo.containerSize.height + 0.5
                } action: { _, value in
                    if value != overflows { overflows = value }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focus, equals: .table)
                .onKeyPress(.upArrow) { move(-1, proxy: proxy) }
                .onKeyPress(.downArrow) { move(1, proxy: proxy) }
                .onKeyPress(.return) { editSelected() }
                .onKeyPress(.delete) { removeSelected() }
                .onKeyPress(.deleteForward) { removeSelected() }
                .onKeyPress(.escape) {
                    guard focus == .table, app.selectedCourseId != nil else { return .ignored }
                    app.selectedCourseId = nil
                    return .handled
                }
                .onChange(of: app.editRequestCourseId, initial: true) { _, id in
                    guard let id else { return }
                    beginEditing(id, proxy: proxy)
                }
                .onChange(of: state.focusRequest) { _, request in
                    guard let request else { return }
                    state.focusRequest = nil
                    if let id = request.courseId { proxy.scrollTo(id, anchor: .center) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focus = request }
                }
                .onChange(of: focus) { _, now in
                    if let id = now?.courseId, app.selectedCourseId != id { app.selectedCourseId = id }
                }
            }
        }
    }

    private static let sidePadding: CGFloat = 28

    private var scrollerGutter: CGFloat {
        guard overflows, NSScroller.preferredScrollerStyle == .legacy else { return 0 }
        return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            PageHeader(eyebrow: "Planner", title: "Your degree", subtitle: app.planStatus)
            HStack(spacing: 12) {
                creditsTile
                PlannerStatCard {
                    StatTile(label: "To take", value: String(app.toTake.count), unit: app.toTake.count == 1 ? "class" : "classes",
                             caption: "\(app.creditsText(app.creditsToTake)) credits left")
                }
                finishTile
            }
            .fixedSize(horizontal: true, vertical: true)
        }
    }

    private var creditsTile: some View {
        let total = app.creditsTotal
        let done = app.creditsTaken
        return PlannerStatCard {
            VStack(alignment: .leading, spacing: 8) {
                StatTile(label: "Credits done", value: app.creditsText(done), unit: "of \(app.creditsText(total))")
                ProgressBar(value: total > 0 ? done / total : 0, height: 5)
                    .accessibilityLabel("Credits done")
            }
        }
    }

    private var finishTile: some View {
        let tile = app.plannerFinishTile
        return PlannerStatCard {
            StatTile(label: "Finishes", value: tile.value, caption: tile.caption.isEmpty ? nil : tile.caption, captionTone: tile.tone)
        }
        .onTapGesture { if !app.courses.isEmpty { app.showRoute() } }
        .help("Show the route")
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        let warnings = app.warnings
        let unknown = app.plannerUnknownRefsNote
        if !warnings.isEmpty || unknown != nil {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(warnings, id: \.self) { warning in
                    PlannerNotice(text: warning, tone: .neg) {
                        Button { app.showRoute() } label: {
                            HStack(spacing: 6) { Icon(.route, size: 14); Text("Show on route") }
                        }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                    }
                }
                if let unknown {
                    PlannerNotice(text: unknown, tone: .warn) { EmptyView() }
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: Semesters + summers

    private var groupsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            PlannerSemestersCard(state: state)
            if !app.upcomingSummers.isEmpty {
                PlannerSummersCard()
                    .frame(width: 430)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Table body

    @ViewBuilder
    private func tableBody(groups: [PlannerClassGroup], columns: PlannerColumns) -> some View {
        if app.courses.isEmpty {
            PlannerTableMessageRow(icon: .planner, text: "No classes yet — add the ones you’ve taken and the ones left.") {
                Button { app.addCourse() } label: { HStack(spacing: 6) { Icon(.plus, size: 14); Text("Add class") } }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
            }
        } else if groups.isEmpty {
            PlannerTableMessageRow(icon: .search, text: emptyFilterText) {
                Button("Show all classes") { state.filter = .all; state.search = "" }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
            }
        } else {
            ForEach(groups) { group in
                PlannerGroupHeaderRow(group: group)
                ForEach(group.courses) { course in
                    PlannerClassRow(course: course, columns: columns, isSelected: app.selectedCourseId == course.id,
                                    focus: $focus, state: state)
                        .id(course.id)
                }
            }
        }
        PlannerClassTableFooter(shown: groups.reduce(0) { $0 + $1.courses.count })
    }

    private var emptyFilterText: String {
        let search = state.search.trimmingCharacters(in: .whitespaces)
        if !search.isEmpty { return "No classes match “\(search)”." }
        return state.filter == .taken ? "No taken classes yet — set a class’s term to record it." : "Nothing left to take."
    }

    // MARK: Keyboard

    private var visibleIds: [String] { app.plannerVisibleCourseIds(filter: state.filter, search: state.search) }

    private func move(_ delta: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard focus == .table else { return .ignored }
        let ids = visibleIds
        guard !ids.isEmpty else { return .ignored }
        let next: String
        if let current = app.selectedCourseId, let index = ids.firstIndex(of: current) {
            next = ids[max(0, min(ids.count - 1, index + delta))]
        } else {
            next = delta > 0 ? ids[0] : ids[ids.count - 1]
        }
        app.selectedCourseId = next
        proxy.scrollTo(next)
        return .handled
    }

    private func editSelected() -> KeyPress.Result {
        guard focus == .table, let id = app.selectedCourseId else { return .ignored }
        focus = .cell(id, .code)
        return .handled
    }

    private func removeSelected() -> KeyPress.Result {
        guard focus == .table, let id = app.selectedCourseId else { return .ignored }
        state.pendingRemovalCourseId = id
        return .handled
    }

    /// A new (or requested) class: make it visible, scroll to it, focus its Code field, then clear the request.
    private func beginEditing(_ id: String, proxy: ScrollViewProxy) {
        if let course = app.course(id) {
            if (state.filter == .taken && !course.isTaken) || (state.filter == .toTake && course.isTaken) { state.filter = .all }
            if !state.search.isEmpty { state.search = "" }
        }
        app.selectedCourseId = id
        // Lazy rows far below may not exist yet: scroll once the new row is in the list, then again once laid out.
        DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .center)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                proxy.scrollTo(id, anchor: .center)
                focus = .cell(id, .code)
                if app.editRequestCourseId == id { app.editRequestCourseId = nil }
            }
        }
    }
}

// MARK: - Pieces

/// A stat tile on a panel card, fixed width so the header never reflows.
struct PlannerStatCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: 176, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .thubanPanel(padding: 14)
    }
}

/// A notice line: `negSoft` for scheduler warnings (with an action), `warnSoft` for unknown refs.
struct PlannerNotice<Action: View>: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var tone: ChipKind
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if tone == .neg {
                    Circle().fill(theme.negColor).frame(width: 7, height: 7)
                } else {
                    Icon(.info, size: 15).foregroundStyle(theme.brassInkColor)
                }
            }
            .frame(width: 16)
            Text(text)
                .font(ThubanFont.body(13.5, weight: tone == .neg ? .medium : .regular))
                .foregroundStyle(tone == .neg ? theme.negTextColor : theme.inkColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action()
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 40)
        .background(tone == .neg ? theme.negSoftColor : theme.warnSoftColor,
                    in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Remove-class and remove-semester confirmations.
private struct PlannerConfirmations: ViewModifier {
    @Environment(AppModel.self) private var app
    var state: PlannerViewState

    func body(content: Content) -> some View {
        let course = state.pendingRemovalCourseId.flatMap { app.course($0) }
        let termKey = state.pendingRemovalTermKey
        content
            .confirmationDialog("Remove \(course?.displayName ?? "this class")?",
                                isPresented: Binding(get: { course != nil }, set: { if !$0 { state.pendingRemovalCourseId = nil } }),
                                titleVisibility: .visible) {
                Button("Remove class", role: .destructive) {
                    if let id = state.pendingRemovalCourseId { app.removeCourse(id) }
                    state.pendingRemovalCourseId = nil
                }
                Button("Cancel", role: .cancel) { state.pendingRemovalCourseId = nil }
            } message: {
                Text(course.map(app.plannerRemoveCourseMessage) ?? "")
            }
            .confirmationDialog("Remove \(termKey.map(app.termLabel) ?? "this semester")?",
                                isPresented: Binding(get: { termKey != nil }, set: { if !$0 { state.pendingRemovalTermKey = nil } }),
                                titleVisibility: .visible) {
                Button("Remove semester", role: .destructive) {
                    if let key = state.pendingRemovalTermKey { app.removeTerm(key) }
                    state.pendingRemovalTermKey = nil
                }
                Button("Cancel", role: .cancel) { state.pendingRemovalTermKey = nil }
            } message: {
                Text(termKey.flatMap(app.plannerRemoveTermMessage) ?? "")
            }
    }
}

// MARK: - Empty / first run

/// Nothing recorded yet: the page header, then "Plan your degree" with Add class / Add semester and, on first run,
/// the Atlas import offer.
struct PlannerEmptyState: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var addingSemester = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(eyebrow: "Planner", title: "Your degree", subtitle: "Nothing planned yet")
            EmptyState(icon: .planner, title: "Plan your degree",
                       message: "Add the semesters you’ve taken and the classes left, and Thuban Planner lays out the fastest route to graduation.") {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Button { app.addCourse() } label: { HStack(spacing: 7) { Icon(.plus, size: 15); Text("Add class") } }
                            .buttonStyle(.thubanSecondary)
                        Button { addingSemester = true } label: { HStack(spacing: 7) { Icon(.calendar, size: 15); Text("Add semester") } }
                            .buttonStyle(.thubanSecondary)
                            .popover(isPresented: $addingSemester, arrowEdge: .bottom) {
                                PlannerAddSemesterForm(layout: .popover) { addingSemester = false }
                                    .environment(app)
                                    .environment(\.thubanTheme, theme)
                            }
                    }
                    if app.shouldOfferImport {
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Rectangle().fill(theme.lineColor).frame(width: 60, height: 1)
                                Text("or").font(ThubanFont.body(13)).foregroundStyle(theme.inkFaintColor)
                                Rectangle().fill(theme.lineColor).frame(width: 60, height: 1)
                            }
                            Text("Already planning in Atlas? Bring it over — Atlas is never changed.")
                                .font(ThubanFont.body(13))
                                .foregroundStyle(theme.inkDimColor)
                            HStack(spacing: 8) {
                                ImportFromAtlasButton()
                                Button("Not now") { app.dismissImportOffer() }
                                    .buttonStyle(.thubanGhost)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, 60)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }
}
