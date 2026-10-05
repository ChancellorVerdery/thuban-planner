import SwiftUI
import ThubanPlannerCore

/// "Technical electives" (Planner toolbar, ⇧⌘T): requirement progress, the electives UNC Charlotte actually scheduled
/// (last two years or an upcoming term) with their offered terms and prerequisite status, and Add / Remove. Adding an
/// elective whose requirements are all in the plan happens at once; otherwise the sheet switches to the
/// confirmation (`ElectivesConfirmView`). Nothing changes without a click on Add / Add all / Remove.
struct ElectivesSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let tools = app.degreeTools
        VStack(spacing: 0) {
            switch tools.stage {
            case .list:
                ElectivesListView()
            case .confirmAdd(let code):
                ElectivesConfirmView(code: code)
            case .confirmRemove(let code):
                ElectivesRemoveView(code: code)
            }
        }
        .frame(width: 880, height: 780)
        .background(theme.panelColor)
    }
}

// MARK: - List

private struct ElectivesListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        @Bindable var tools = app.degreeTools
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            Hairline()
            controls
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            Hairline()
            if let added = tools.lastAdd {
                ElectivesAddedBanner(result: added)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }
            list
            Hairline()
            footer
                .padding(.horizontal, 24)
                .frame(height: 58)
        }
    }

    // MARK: Header + progress

    private var header: some View {
        let tools = app.degreeTools
        let rule = tools.dataset?.program.techElectives
        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Technical electives · \(tools.dataset?.program.name ?? "BSME") \(tools.dataset?.program.catalogYear ?? "")")
                Text("Choose your technical electives")
                    .font(ThubanFont.display(26))
                    .kerning(-0.26)
                    .foregroundStyle(theme.inkColor)
                    .accessibilityAddTraits(.isHeader)
                Text("\(rule.map { "\($0.count) classes (\(app.creditsText($0.credits)) credits), at least \($0.minimumMEGR) MEGR." } ?? "") Listed: what UNC Charlotte scheduled in the last two years or has on an upcoming schedule.")
                    .font(ThubanFont.body(13.5))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let progress = tools.progress { ElectivesProgressCard(progress: progress) }
        }
    }

    // MARK: Controls

    private var controls: some View {
        @Bindable var tools = app.degreeTools
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SearchField(text: $tools.search, placeholder: "Search electives")
                    .frame(width: 230)
                SegmentedPicker(selection: $tools.filter,
                                options: DegreeToolsModel.ElectiveFilter.allCases.map { SegmentOption($0, $0.label) },
                                segmentHeight: SegmentedPickerHeight.toolbar)
                Spacer(minLength: 8)
                ToggleChip(label: "Not offered recently (\(tools.hiddenNotOfferedCount))", symbol: "eye.slash", isOn: $tools.showNotOffered, height: 30)
                    .help("Show electives with no sections in the last two years and none upcoming")
            }
            HStack(spacing: 6) {
                if case .fetching = tools.offeringsPhase { ProgressView().controlSize(.mini) }
                Text(tools.offeringsCaption)
                    .font(ThubanFont.body(12))
                    .foregroundStyle(isFailed ? theme.negTextColor : theme.inkFaintColor)
                    .lineLimit(1)
                if !tools.offline, !isFetching {
                    Button("Refresh") { tools.refreshOfferingsIfNeeded(force: true) }
                        .buttonStyle(GhostButtonStyle(height: 22, horizontalPadding: 6))
                        .font(ThubanFont.body(12))
                        .help("Re-read the current and upcoming terms from Banner’s public class search")
                }
            }
        }
    }

    private var isFetching: Bool { if case .fetching = app.degreeTools.offeringsPhase { return true }; return false }
    private var isFailed: Bool { if case .failed = app.degreeTools.offeringsPhase { return true }; return false }

    // MARK: List

    private var list: some View {
        let rows = app.degreeTools.visibleStatuses
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if rows.isEmpty {
                    Text(app.degreeTools.search.isEmpty ? "No electives to show." : "No electives match “\(app.degreeTools.search)”.")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
                ForEach(rows) { status in
                    ElectivesRow(status: status)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let dataset = app.degreeTools.dataset {
                Text("Catalog \(dataset.program.catalogYear) · \(dataset.electives.count) electives (catalog + DegreeWorks)")
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkFaintColor)
                if let url = URL(string: dataset.program.catalogURL) {
                    Link("Open catalog page", destination: url)
                        .font(ThubanFont.body(12, weight: .semibold))
                        .foregroundStyle(theme.brassInkColor)
                }
            }
            Spacer()
            Button("Done") { app.degreeTools.closeSheet() }
                .buttonStyle(.thubanPrimary)
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Progress card

struct ElectivesProgressCard: View {
    @Environment(\.thubanTheme) private var theme
    var progress: TechElectives.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(min(progress.chosen.count, progress.required)) of \(progress.required)")
                    .font(ThubanFont.display(26))
                    .foregroundStyle(theme.inkColor)
                    .monospacedDigit()
                Text("chosen").font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor)
            }
            HStack(spacing: 4) {
                ForEach(0 ..< progress.required, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(i < progress.chosen.count ? theme.accentColor : theme.panel2Color)
                        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(theme.lineColor, lineWidth: i < progress.chosen.count ? 0 : ThubanMetrics.hairline))
                        .frame(width: 30, height: 6)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(progress.megr >= progress.requiredMEGR ? theme.posColor : theme.inkFaintColor).frame(width: 6, height: 6)
                Text("\(min(progress.megr, progress.requiredMEGR)) of \(progress.requiredMEGR) MEGR")
                    .font(ThubanFont.body(12.5, weight: .semibold))
                    .foregroundStyle(theme.inkDimColor)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .frame(width: 168, alignment: .leading)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.text)
    }
}

// MARK: - Row

private struct ElectivesRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var status: TechElectives.Status
    @State private var hovering = false

    var body: some View {
        let dim = !status.isOffered && status.planState == .notInPlan
        HStack(alignment: .center, spacing: 14) {
            Text(status.code)
                .font(ThubanFont.mono(13, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(status.title.isEmpty ? "Not in the \(app.degreeTools.dataset?.program.catalogYear ?? "") catalog" : status.title)
                        .font(ThubanFont.body(14, weight: .medium))
                        .foregroundStyle(status.title.isEmpty ? theme.inkFaintColor : theme.inkColor)
                        .lineLimit(1)
                    if !status.elective.inCatalog {
                        Text("DegreeWorks only").font(ThubanFont.body(11, weight: .semibold)).foregroundStyle(theme.inkFaintColor)
                    }
                }
                Text(subtitle)
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(app.creditsText(status.credits)) cr")
                .font(ThubanFont.mono(12))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 36, alignment: .trailing)
            statusChip
                .frame(width: 196, alignment: .leading)
            action
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(hovering ? theme.panel2Color.opacity(0.6) : theme.panelColor,
                    in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
            .strokeBorder(status.counts ? theme.accentColor : theme.lineColor, lineWidth: ThubanMetrics.hairline))
        .opacity(dim ? 0.55 : 1)
        .onHover { hovering = $0 }
        .help(status.notes.joined(separator: "\n"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status.code) \(status.title)")
    }

    private var subtitle: String {
        var parts = [app.degreeTools.offeringText(status.offering)]
        if let condition = status.elective.condition { parts.append(condition.prefix(1).uppercased() + condition.dropFirst()) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusChip: some View {
        switch status.planState {
        case .taken(let term):
            Chip("Taken · \(app.termLabel(term))", kind: .pos, icon: .check)
        case .planned:
            let id = PlanCourseIndex(app.data).find(status.code)?.id
            let term = id.flatMap { app.routeTerm(of: $0)?.label }
            if status.counts {
                Chip(term.map { "Chosen · \($0)" } ?? "Chosen", kind: .accent)
            } else {
                Chip(term.map { "In plan · \($0)" } ?? "In plan", kind: .neutral)
                    .help("In your plan, but it only counts as a technical elective when its condition is met.")
            }
        case .notInPlan:
            switch status.readiness {
            case .ready, .inPlan:
                Chip("Ready", kind: .pos, dot: true)
            case .needs(let count, let chain):
                Chip(count == 1 ? "Needs \(chain.first ?? "1 class")" : (chain.count > 1 && chain.count <= 2 ? "Needs \(chain.joined(separator: " → "))" : "Needs \(count) classes"), kind: .warn)
                    .lineLimit(1)
                    .help("Missing: \(status.missing.joined(separator: ", "))")
            }
        }
    }

    @ViewBuilder
    private var action: some View {
        switch status.planState {
        case .notInPlan:
            Button { app.degreeTools.choose(status.code) } label: {
                HStack(spacing: 5) { Icon(.plus, size: 13); Text("Add") }
            }
            .buttonStyle(SecondaryButtonStyle(height: 28))
            .accessibilityLabel("Add \(status.code)")
        case .planned:
            // Only electives chosen here (tagged) can be removed from this panel — never e.g. the design elective.
            if PlanCourseIndex(app.data).find(status.code)?.tags?.contains(TechElectives.electiveTag) == true,
               app.degreeTools.removal(of: status.code).elective != nil {
                Button("Remove") { app.degreeTools.beginRemove(status.code) }
                    .buttonStyle(GhostButtonStyle(height: 28, horizontalPadding: 8))
                    .accessibilityLabel("Remove \(status.code)")
            }
        case .taken:
            EmptyView()
        }
    }
}

// MARK: - Added banner

struct ElectivesAddedBanner: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var result: DegreeToolsModel.AddResult

    var body: some View {
        let elective = result.placements.first { $0.isElective } ?? result.placements.last
        let others = result.placements.filter { $0.id != elective?.id }
        HStack(alignment: .top, spacing: 10) {
            Icon(.check, size: 15).foregroundStyle(theme.posTextColor).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                if let elective {
                    Text("Added \(elective.code)\(elective.term.map { " · planned \($0)" } ?? "")")
                        .font(ThubanFont.body(13.5, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                } else {
                    Text("Nothing new to add — \(result.target) is already covered.").font(ThubanFont.body(13.5, weight: .semibold))
                }
                if !others.isEmpty {
                    Text("With " + others.map { "\($0.code)\($0.term.map { " (\($0))" } ?? "")" }.joined(separator: ", "))
                        .font(ThubanFont.body(12.5))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button {
                if let id = elective?.id { app.selectedCourseId = id }
                app.degreeTools.closeSheet()
                app.showRoute()
            } label: { HStack(spacing: 6) { Icon(.route, size: 14); Text("Show on route") } }
                .buttonStyle(SecondaryButtonStyle(height: 28))
        }
        .padding(12)
        .background(theme.posSoftColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
    }
}
