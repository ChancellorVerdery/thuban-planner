import SwiftUI
import ThubanPlannerCore

/// "Add PHYS 4242 and 2 prerequisites?": the requirement tree (PHYS 4242 ← PHYS 4241 ← PHYS 3141 ← PHYS 2102 ✓ in
/// plan), a picker on every OR-group the plan doesn't already satisfy, the classes and credits that will be added,
/// warnings (not offered recently, not in the catalog, cycles) and the catalog's notes. Add all / Cancel.
struct ElectivesConfirmView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var code: String

    var body: some View {
        let tools = app.degreeTools
        let plan = tools.chainPlan(for: code)
        let target = plan?.additions.first { $0.isTarget }
        let prereqs = plan?.prerequisiteAdditions ?? []
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Technical elective · prerequisites")
                Text(prereqs.isEmpty ? "Add \(code)?" : "Add \(code) and \(prereqs.count) prerequisite\(prereqs.count == 1 ? "" : "s")?")
                    .font(ThubanFont.display(26))
                    .kerning(-0.26)
                    .foregroundStyle(theme.inkColor)
                    .accessibilityAddTraits(.isHeader)
                Text("\(target?.title ?? "") · \(app.creditsText(target?.credits ?? 3)) cr. " +
                     (prereqs.isEmpty ? "Its requirements are in your plan." : "Some of what it needs isn’t in your plan yet. Everything below marked Add goes in as To take, and the route recalculates."))
                    .font(ThubanFont.body(13.5))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let plan {
                        if !plan.choices.isEmpty { choicesSection(plan) }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("Requirement chain")
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(plan.roots) { root in ElectivesTreeRows(node: root, depth: 0, plan: plan) }
                            }
                            .padding(.vertical, 6)
                            .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                        }
                        additionsSection(plan)
                        if !plan.warnings.isEmpty || !notes(plan).isEmpty { warningsSection(plan) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            HStack(spacing: 10) {
                if let plan {
                    Text("Adds \(plan.additions.count) class\(plan.additions.count == 1 ? "" : "es") · \(app.creditsText(plan.credits)) credits")
                        .font(ThubanFont.body(13, weight: .semibold))
                        .foregroundStyle(theme.inkDimColor)
                        .monospacedDigit()
                }
                Spacer()
                Button("Cancel") { tools.cancelStage() }
                    .buttonStyle(.thubanGhost)
                    .keyboardShortcut(.cancelAction)
                Button(prereqs.isEmpty ? "Add \(code)" : "Add all") { tools.confirmAdd() }
                    .buttonStyle(.thubanPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan?.isEmpty ?? true)
            }
            .padding(.horizontal, 24)
            .frame(height: 58)
        }
    }

    private func choicesSection(_ plan: ChainPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Choose one of", count: plan.choices.count)
            ForEach(plan.choices) { choice in
                ElectivesChoiceRow(choice: choice)
            }
        }
    }

    private func additionsSection(_ plan: ChainPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Will be added (To take)", count: plan.additions.count)
            ForEach(plan.additions) { a in
                HStack(spacing: 12) {
                    Text(a.code).font(ThubanFont.mono(13, weight: .semibold)).foregroundStyle(theme.inkColor).frame(width: 84, alignment: .leading)
                    Text(a.title.isEmpty ? "Not in the catalog" : a.title).font(ThubanFont.body(13.5)).foregroundStyle(theme.inkColor).lineLimit(1)
                    Spacer(minLength: 8)
                    let reqs = (a.prereqs.map { $0 } + a.coreqs.map { "\($0) (same term ok)" })
                    if !reqs.isEmpty {
                        Text("after " + reqs.joined(separator: ", "))
                            .font(ThubanFont.body(12))
                            .foregroundStyle(theme.inkFaintColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text("\(app.creditsText(a.credits)) cr").font(ThubanFont.mono(12)).foregroundStyle(theme.inkDimColor).frame(width: 36, alignment: .trailing)
                    if a.isTarget { Chip("Elective", kind: .accent) } else { Chip("Prerequisite", kind: .neutral) }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            }
        }
    }

    private func notes(_ plan: ChainPlan) -> [String] {
        plan.additions.flatMap { a in
            a.notes.filter { !$0.lowercased().contains("grade") }.map { "\(a.code): \($0)" }
        }
    }

    private func warningsSection(_ plan: ChainPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Check")
            ForEach(plan.warnings, id: \.self) { w in
                PlannerNotice(text: w, tone: .warn) { EmptyView() }
            }
            ForEach(notes(plan), id: \.self) { note in
                HStack(alignment: .top, spacing: 8) {
                    Icon(.info, size: 13).foregroundStyle(theme.inkFaintColor).padding(.top, 2)
                    Text(note).font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One OR-group: "PHYS 4241 needs one of PHYS 3220 · MATH 2241" with a menu.
private struct ElectivesChoiceRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var choice: ChainChoice

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(choice.owner) \(choice.kind == .prereq ? "needs" : "needs, same term or earlier,") one of")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
                Text(choice.options.joined(separator: " · "))
                    .font(ThubanFont.mono(12.5))
                    .foregroundStyle(theme.inkFaintColor)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(choice.options, id: \.self) { option in
                    Button {
                        app.degreeTools.setChoice(choice.key, option)
                    } label: {
                        Text("\(option)\(title(option).map { " — \($0)" } ?? "")  (\(costText(choice.costs[option] ?? 1)))")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(choice.chosen).font(ThubanFont.mono(13, weight: .semibold))
                    Text(costText(choice.costs[choice.chosen] ?? 1)).font(ThubanFont.body(12)).foregroundStyle(theme.inkDimColor)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
            .accessibilityLabel("Option for \(choice.owner)")
        }
        .padding(12)
        .background(theme.accentTintColor.opacity(0.45), in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
    }

    private func title(_ code: String) -> String? { app.degreeTools.dataset?.course(code)?.title }

    private func costText(_ n: Int) -> String {
        n == 0 ? "in plan" : (n >= 1000 ? "cycle" : "+\(n) class\(n == 1 ? "" : "es")")
    }
}

/// The requirement tree, one row per node, indented by depth.
private struct ElectivesTreeRows: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var node: ChainNode
    var depth: Int
    var plan: ChainPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if depth > 0 {
                    Text("←")
                        .font(ThubanFont.body(13))
                        .foregroundStyle(theme.inkFaintColor)
                        .padding(.leading, CGFloat(depth - 1) * 22)
                }
                Text(node.code)
                    .font(ThubanFont.mono(13, weight: .semibold))
                    .foregroundStyle(isAdd ? theme.inkColor : theme.inkDimColor)
                Text(node.title)
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
                if node.kind == .coreq {
                    Text("same term or earlier").font(ThubanFont.body(11.5)).foregroundStyle(theme.inkFaintColor)
                }
                if node.alternatives.count > 1 {
                    Text("or " + node.alternatives.filter { $0 != node.code }.joined(separator: ", "))
                        .font(ThubanFont.body(11.5))
                        .foregroundStyle(theme.inkFaintColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                stateChip
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            ForEach(node.children) { child in
                ElectivesTreeRows(node: child, depth: depth + 1, plan: plan)
            }
        }
    }

    private var isAdd: Bool { node.isAddition }

    @ViewBuilder
    private var stateChip: some View {
        switch node.state {
        case .inPlan(_, let term):
            Chip(term.map { "In plan · \(app.termLabel($0))" } ?? "In plan · to take", kind: .pos, icon: .check)
        case .add:
            Chip("Add", kind: .accent, icon: .plus)
        case .addedAbove:
            Chip("Added above", kind: .neutral)
        case .unknown:
            Chip("Add · not in catalog", kind: .warn)
        case .cycle:
            Chip("Cycle", kind: .neg)
        }
    }
}

// MARK: - Remove

/// "Remove PHYS 4242?" — with the To-take prerequisites that were added only for it, ticked by default.
struct ElectivesRemoveView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var code: String

    var body: some View {
        let tools = app.degreeTools
        let removal = tools.removal(of: code)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Technical elective")
                Text("Remove \(code)?")
                    .font(ThubanFont.display(26))
                    .foregroundStyle(theme.inkColor)
                Text(removal.prerequisites.isEmpty
                     ? "It goes back to the list. Nothing else changes."
                     : "These classes were added only for \(code). Untick any you want to keep.")
                    .font(ThubanFont.body(13.5))
                    .foregroundStyle(theme.inkDimColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(removal.prerequisites) { course in
                        Toggle(isOn: Binding(get: { tools.removalSelection.contains(course.id) },
                                             set: { on in if on { tools.removalSelection.insert(course.id) } else { tools.removalSelection.remove(course.id) } })) {
                            HStack(spacing: 10) {
                                Text(course.code).font(ThubanFont.mono(13, weight: .semibold)).foregroundStyle(theme.inkColor)
                                Text(course.title).font(ThubanFont.body(13.5)).foregroundStyle(theme.inkDimColor)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 4)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            HStack {
                Spacer()
                Button("Cancel") { tools.cancelStage() }
                    .buttonStyle(.thubanGhost)
                    .keyboardShortcut(.cancelAction)
                Button("Remove \(1 + removal.prerequisites.filter { tools.removalSelection.contains($0.id) }.count) class\(removal.prerequisites.filter { tools.removalSelection.contains($0.id) }.isEmpty ? "" : "es")") {
                    tools.confirmRemove()
                }
                .buttonStyle(.thubanPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .frame(height: 58)
        }
    }
}
