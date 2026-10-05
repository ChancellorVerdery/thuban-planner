import SwiftUI
import ThubanPlannerCore
import UniformTypeIdentifiers

/// "Import degree requirements…" (Planner toolbar menu, Settings ▸ Import, ⇧⌘I): pick a UNC Charlotte degree
/// document (catalog program page as PDF / HTML / MHTML, a DegreeWorks audit, a checksheet as text / Markdown /
/// Word), preview what it requires against the plan, tick what to add, pick options in choice groups, then ONE write
/// that only adds classes (a snapshot is made first). Existing classes are never changed.
struct DegreeImportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let tools = app.degreeTools
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            Hairline()
            Group {
                switch tools.importPhase {
                case .choose: DegreeImportChooseView()
                case .loading(let name):
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.regular)
                        Text("Reading \(name)…").font(ThubanFont.body(14)).foregroundStyle(theme.inkDimColor)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .preview(let draft): DegreeImportPreviewView(draft: draft)
                case .done(let result): DegreeImportDoneView(result: result)
                case .failed(let message):
                    VStack(spacing: 14) {
                        PlannerNotice(text: message, tone: .neg) { EmptyView() }
                        Button("Choose another file…") { tools.chooseDocument() }.buttonStyle(.thubanSecondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Hairline()
            footer
                .padding(.horizontal, 24)
                .frame(height: 58)
        }
        .frame(width: 860, height: 780)
        .background(theme.panelColor)
    }

    private var title: String {
        switch app.degreeTools.importPhase {
        case .preview(let draft): return draft.plan.programName ?? draft.fileName
        case .done: return "Added to your plan"
        default: return "Import degree requirements"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(eyebrow)
            Text(title)
                .font(ThubanFont.display(26))
                .kerning(-0.26)
                .foregroundStyle(theme.inkColor)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(ThubanFont.body(13.5))
                .foregroundStyle(theme.inkDimColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrow: String {
        switch app.degreeTools.importPhase {
        case .preview(let draft):
            let kind: String
            switch draft.plan.kind {
            case .catalog: kind = "Catalog page"
            case .degreeWorks: kind = "DegreeWorks audit"
            case .checksheet: kind = "Checksheet"
            }
            return "Import degree requirements · \(kind) · \(draft.fileName)"
        default: return "Import degree requirements"
        }
    }

    private var subtitle: String {
        switch app.degreeTools.importPhase {
        case .preview(let draft):
            let p = draft.plan
            return "\(p.requiredCount) required · \(p.alreadyInPlan.count) already in your plan · \(p.toAdd.count) to add · \(p.choices.count) choice\(p.choices.count == 1 ? "" : "s")"
        case .done(let result): return "From \(result.fileName). Your existing classes weren’t changed."
        default: return "Adds the required classes you haven’t taken or planned. Classes already in your plan — taken or to take — are never changed."
        }
    }

    @ViewBuilder
    private var footer: some View {
        let tools = app.degreeTools
        HStack(spacing: 10) {
            switch tools.importPhase {
            case .preview(let draft):
                Text("\(draft.addCount) class\(draft.addCount == 1 ? "" : "es") · \(app.creditsText(draft.addCredits)) credits")
                    .font(ThubanFont.body(13, weight: .semibold))
                    .foregroundStyle(theme.inkDimColor)
                    .monospacedDigit()
                Spacer()
                Button("Choose another file…") { tools.chooseDocument() }.buttonStyle(.thubanGhost)
                Button("Cancel") { tools.closeSheet(); tools.resetImport() }
                    .buttonStyle(.thubanGhost)
                    .keyboardShortcut(.cancelAction)
                Button(draft.addCount == 0 ? "Nothing to add" : "Add \(draft.addCount) class\(draft.addCount == 1 ? "" : "es")") { tools.applyImport() }
                    .buttonStyle(.thubanPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.addCount == 0)
            case .done:
                Spacer()
                Button("Import another…") { tools.resetImport(); tools.chooseDocument() }.buttonStyle(.thubanGhost)
                Button {
                    tools.closeSheet(); tools.resetImport(); app.showRoute()
                } label: { HStack(spacing: 6) { Icon(.route, size: 14); Text("Show route") } }
                    .buttonStyle(.thubanSecondary)
                Button("Done") { tools.closeSheet(); tools.resetImport() }
                    .buttonStyle(.thubanPrimary)
                    .keyboardShortcut(.defaultAction)
            default:
                Spacer()
                Button("Cancel") { tools.closeSheet(); tools.resetImport() }
                    .buttonStyle(.thubanGhost)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

// MARK: - Choose

private struct DegreeImportChooseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Icon(.file, size: 34).foregroundStyle(theme.brassInkColor)
                Text("Drop a degree document here").font(ThubanFont.display(20)).foregroundStyle(theme.inkColor)
                Text("A UNC Charlotte catalog program page for any major or minor (saved as PDF, HTML or MHTML), a DegreeWorks audit, or a checksheet (text, Markdown or Word).")
                    .font(ThubanFont.body(13.5))
                    .foregroundStyle(theme.inkDimColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Button("Choose a file…") { app.degreeTools.chooseDocument() }
                    .buttonStyle(.thubanPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .background(targeted ? theme.accentTintColor : theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                .strokeBorder(targeted ? theme.accentColor : theme.line2Color, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in app.degreeTools.loadDocument(url) }
                }
                return true
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("How it merges")
                rule("Only adds. A class already in your plan — taken or still to take — is never changed: not its term, credits, requirements or title.")
                rule("Matches codes ignoring case and spaces, plus UNC Charlotte’s equivalents (PHYS 1101L counts for PHYS 2101L).")
                rule("“Select one of…” groups and elective lists are never added on their own — you pick in the preview.")
                rule("Credits, titles and prerequisites the document leaves out are filled from the bundled catalog when it knows the class.")
                rule("A backup of your plan is made first (Settings ▸ Data).")
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(.check, size: 13).foregroundStyle(theme.posTextColor).padding(.top, 2)
            Text(text).font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

private struct DegreeImportPreviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var draft: DegreeToolsModel.ImportDraft
    @State private var showInPlan = false
    @State private var showWarnings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stats
                toAdd
                if !draft.plan.choices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Choices — pick what to add", count: draft.plan.choices.count)
                        ForEach(draft.plan.choices) { choice in
                            DegreeImportChoiceCard(choice: choice, picked: draft.picks[choice.id] ?? [])
                        }
                    }
                }
                inPlan
                if !draft.plan.warnings.isEmpty { warnings }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stats: some View {
        let p = draft.plan
        return HStack(spacing: 10) {
            stat("\(p.requiredCount)", "required")
            stat("\(p.alreadyInPlan.count)", "already in plan")
            stat("\(p.toAdd.count)", "to add")
            stat("\(p.choices.count)", p.choices.count == 1 ? "choice" : "choices")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(ThubanFont.display(24)).foregroundStyle(theme.inkColor).monospacedDigit()
            Text(label).font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }

    @ViewBuilder
    private var toAdd: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Required, not in your plan", count: draft.plan.toAdd.count)
            if draft.plan.toAdd.isEmpty {
                Text("Every required class is already in your plan.")
                    .font(ThubanFont.body(13.5))
                    .foregroundStyle(theme.inkDimColor)
                    .padding(.vertical, 6)
            }
            ForEach(draft.plan.toAdd) { c in
                DegreeImportCandidateRow(candidate: c, isOn: draft.include.contains(c.code)) {
                    app.degreeTools.toggleInclude(c.code)
                }
            }
        }
    }

    @ViewBuilder
    private var inPlan: some View {
        if !draft.plan.alreadyInPlan.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button { showInPlan.toggle() } label: {
                    HStack(spacing: 6) {
                        Glyph(showInPlan ? .chevronDown : .chevronRight, size: 11)
                        Text("Already in your plan · \(draft.plan.alreadyInPlan.count)").font(ThubanFont.body(13, weight: .semibold))
                    }
                    .foregroundStyle(theme.inkDimColor)
                }
                .buttonStyle(.plain)
                if showInPlan {
                    let text = draft.plan.alreadyInPlan.map { $0.documentCode == $0.planCode ? $0.planCode : "\($0.documentCode) (as \($0.planCode))" }
                    Text(text.joined(separator: " · "))
                        .font(ThubanFont.mono(12))
                        .foregroundStyle(theme.inkFaintColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { showWarnings.toggle() } label: {
                HStack(spacing: 6) {
                    Glyph(showWarnings ? .chevronDown : .chevronRight, size: 11)
                    Text("Lines not read as requirements · \(draft.plan.warnings.count)").font(ThubanFont.body(13, weight: .semibold))
                }
                .foregroundStyle(theme.inkDimColor)
            }
            .buttonStyle(.plain)
            if showWarnings {
                ForEach(draft.plan.warnings, id: \.self) { w in
                    Text(w).font(ThubanFont.body(12)).foregroundStyle(theme.inkFaintColor).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct DegreeImportCandidateRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var candidate: DegreeImportPlan.Candidate
    var isOn: Bool
    var toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Add \(candidate.code)")
            Text(candidate.code).font(ThubanFont.mono(13, weight: .semibold)).foregroundStyle(theme.inkColor).frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title.isEmpty ? "Untitled" : candidate.title).font(ThubanFont.body(13.5)).foregroundStyle(theme.inkColor).lineLimit(1)
                let reqs = candidate.prereqs + candidate.coreqs.map { "\($0) (same term ok)" }
                if !reqs.isEmpty || candidate.filledFromCatalog {
                    Text((reqs.isEmpty ? "" : "after " + reqs.joined(separator: ", ")) + (candidate.filledFromCatalog ? (reqs.isEmpty ? "" : " · ") + "details from the catalog" : ""))
                        .font(ThubanFont.body(12))
                        .foregroundStyle(theme.inkFaintColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text("\(app.creditsText(candidate.credits)) cr").font(ThubanFont.mono(12)).foregroundStyle(theme.inkDimColor)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(isOn ? theme.panelColor : theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
        .opacity(isOn ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

/// A choice group: label, "pick 1 · 1 already in your plan", and its options as toggles (long lists collapse).
private struct DegreeImportChoiceCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var choice: DegreeImportPlan.Choice
    var picked: Set<String>
    @State private var expanded = false

    var body: some View {
        let limit = 8
        let options = choice.available
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(choice.group.label).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor).lineLimit(2)
                Spacer(minLength: 8)
                if choice.group.options.isEmpty {
                    Chip("Plan these yourself", kind: .neutral)
                } else if choice.isSatisfied {
                    Chip("Satisfied", kind: .pos, icon: .check)
                } else {
                    Chip("Pick \(choice.remaining) more", kind: .warn)
                }
            }
            Text(caption).font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
            if !options.isEmpty {
                let shown = expanded ? options : Array(options.prefix(limit))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 6) {
                    ForEach(shown) { option in
                        let on = picked.contains(option.code)
                        Button { app.degreeTools.togglePick(choice.id, option.code) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: on ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 13))
                                    .foregroundStyle(on ? theme.accentColor : theme.inkFaintColor)
                                Text(option.code).font(ThubanFont.mono(12.5, weight: .semibold)).foregroundStyle(theme.inkColor)
                                Text(option.title).font(ThubanFont.body(12.5)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(on ? theme.accentTintColor : theme.panelColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? theme.accentColor : theme.lineColor, lineWidth: ThubanMetrics.hairline))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(on ? "Don’t add" : "Add") \(option.code)")
                    }
                }
                if options.count > limit {
                    Button(expanded ? "Show fewer" : "Show all \(options.count) options") { expanded.toggle() }
                        .buttonStyle(GhostButtonStyle(height: 24, tinted: true, horizontalPadding: 6))
                        .font(ThubanFont.body(12.5, weight: .semibold))
                }
            }
            ForEach(choice.group.notes, id: \.self) { note in
                Text((note.contains("XXX") ? (choice.group.options.isEmpty ? "• " : "Or any: ") : "") + note)
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkFaintColor)
            }
        }
        .padding(14)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }

    private var caption: String {
        if choice.group.options.isEmpty { return "Choose \(choice.group.pick) — any class of the kinds below; not added automatically." }
        var parts = ["Choose \(choice.group.pick) of \(choice.group.options.count)"]
        if !choice.inPlan.isEmpty { parts.append("in your plan: " + choice.inPlan.joined(separator: ", ")) }
        if picked.count > 0 { parts.append("\(picked.count) picked to add") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Done

private struct DegreeImportDoneView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var result: DegreeToolsModel.ImportResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Icon(.check, size: 18).foregroundStyle(theme.posTextColor)
                    Text("Added \(result.placements.count) class\(result.placements.count == 1 ? "" : "es") from \(result.program)")
                        .font(ThubanFont.body(15, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.posSoftColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
                SectionHeader("Where they landed", count: result.placements.count)
                ForEach(result.placements) { p in
                    HStack(spacing: 12) {
                        Text(p.code).font(ThubanFont.mono(13, weight: .semibold)).foregroundStyle(theme.inkColor).frame(width: 84, alignment: .leading)
                        Text(p.title).font(ThubanFont.body(13.5)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                        Spacer(minLength: 8)
                        if let term = p.term { Chip(term, kind: .accent) } else { Chip("Can’t place yet", kind: .neg) }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                }
                Text(app.planStatus).font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor)
                if let backup = result.backup {
                    Text("Backup of the plan before this import: \(backup.lastPathComponent) (Settings ▸ Data)")
                        .font(ThubanFont.body(12))
                        .foregroundStyle(theme.inkFaintColor)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
