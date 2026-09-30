import SwiftUI
import ThubanPlannerCore

/// "Export to Banner…": the confirmation (plan name, term, the exact sections that will be added, what it does and
/// doesn't do, plan count / Banner's limit), then progress, then success (with "Open Plan Ahead") or a precise
/// failure. Nothing is written to Banner until "Create plan".
struct ScheduleExportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var draft: ScheduleExportDraft

    var body: some View {
        let model = app.scheduleTab
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stage(model)
                    if case .full = draft.phase {
                        sections
                    } else if showsDetails {
                        nameField(model); sections; notes
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
            footer(model)
                .padding(.horizontal, 24)
                .frame(height: 60)
        }
        .frame(width: 680, height: 720)
        .background(theme.panelColor)
        .interactiveDismissDisabled(true)
    }

    private var showsDetails: Bool {
        switch draft.phase {
        case .ready, .checking, .working, .full: return true
        case .failed(_, let wroteNothing): return wroteNothing
        case .done: return false
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Export to Banner · Plan Ahead\(draft.dryRun ? " · dry run" : "")")
                Text(title)
                    .font(ThubanFont.display(26))
                    .kerning(-0.26)
                    .foregroundStyle(theme.inkColor)
                    .accessibilityAddTraits(.isHeader)
                Text("\(draft.termLabel) · Banner term \(draft.termCode) · Schedule \(draft.scheduleNumber)")
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
            }
            Spacer(minLength: 12)
            if let who = signedInText {
                HStack(spacing: 6) {
                    Circle().fill(theme.posColor).frame(width: 7, height: 7)
                    Text(who).font(ThubanFont.body(12)).foregroundStyle(theme.inkDimColor)
                }
                .padding(.top, 4)
            }
        }
    }

    private var title: String {
        switch draft.phase {
        case .done(let outcome): return outcome.dryRun ? "Dry run finished" : "Plan created"
        case .failed(_, let wroteNothing): return wroteNothing ? "Nothing was created" : "The export didn’t finish"
        case .full: return "Plan Ahead is full"
        default: return "Create a plan in Banner"
        }
    }

    private var signedInText: String? {
        switch app.scheduleTab.auth {
        case .signedIn(let name?): return "Signed in as \(name)"
        case .signedIn(nil): return "Signed in"
        default: return nil
        }
    }

    // MARK: Stage banner

    @ViewBuilder
    private func stage(_ model: ScheduleModel) -> some View {
        switch draft.phase {
        case .checking:
            progress("Checking your Plan Ahead plans…", detail: "Reading only — nothing is created yet.")
        case .working(let step):
            progress(step, detail: "Creating one new plan. Please keep this open.")
        case .ready:
            EmptyView()
        case .full(let count, let max):
            card(tone: .neg, icon: .info, title: "You already have \(count) of \(max) plans for \(draft.termLabel)",
                 text: "Banner allows \(max) Plan Ahead plans a term, so a new one can’t be created. Delete a plan you no longer need in Banner’s Plan Ahead, then export again.")
        case .failed(let message, let wroteNothing):
            card(tone: .neg, icon: .info, title: wroteNothing ? "Banner wasn’t changed" : "Check Plan Ahead",
                 text: message + (wroteNothing ? "" : " Banner may have saved part of the plan — open Plan Ahead to see what’s there before exporting again."))
        case .done(let outcome):
            done(outcome)
        }
    }

    private func progress(_ text: String, detail: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor)
                Text(detail).font(ThubanFont.body(12)).foregroundStyle(theme.inkDimColor)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
    }

    private enum Tone { case neg, pos }

    private func card(tone: Tone, icon: IconName, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(icon, size: 20).foregroundStyle(tone == .neg ? theme.negTextColor : theme.posTextColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(ThubanFont.body(15, weight: .semibold)).foregroundStyle(theme.inkColor)
                Text(text).font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(tone == .neg ? theme.negSoftColor : theme.posSoftColor,
                    in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func done(_ outcome: BannerExportOutcome) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Icon(.check, size: 22)
                    .foregroundStyle(theme.onAccentColor)
                    .frame(width: 40, height: 40)
                    .background(outcome.dryRun ? theme.inkFaintColor : theme.posColor, in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(outcome.dryRun ? "“\(outcome.planName)” — not sent"
                                        : "Plan “\(outcome.planName)” created with \(outcome.classCount) class\(outcome.classCount == 1 ? "" : "es")")
                        .font(ThubanFont.display(20))
                        .foregroundStyle(theme.inkColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(outcome.dryRun ? "The exact requests are in the log (Console, subsystem org.thuban.planner). Banner wasn’t contacted."
                                        : "It’s in Plan Ahead for \(draft.termLabel)\(outcome.verified ? ", checked against Banner" : ""). You still register yourself in Banner when registration opens.")
                        .font(ThubanFont.body(13))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let note = outcome.note, !outcome.dryRun {
                card(tone: .neg, icon: .info, title: "Worth a look", text: note)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(draft.items) { item in row(item, last: item.id == draft.items.last?.id) }
            }
            .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
        }
    }

    // MARK: Name

    private func nameField(_ model: ScheduleModel) -> some View {
        let editable = draft.phase == .ready
        let problem = draft.nameProblem
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Eyebrow("Plan name")
                Spacer()
                Text("\(BannerPlanExport.cleanName(draft.name).count) / \(draft.nameLimit)")
                    .font(ThubanFont.mono(11))
                    .foregroundStyle(problem != nil ? theme.negTextColor : theme.inkFaintColor)
                    .monospacedDigit()
            }
            TextField("Plan name", text: Binding(get: { model.exportDraft?.name ?? draft.name },
                                                 set: { v in model.updateDraft { $0.name = v } }))
                .thubanField(invalid: problem != nil, height: 34)
                .disabled(!editable)
                .onSubmit { model.confirmExport() }
                .accessibilityLabel("Plan name")
            if let problem, editable {
                Text(problem).font(ThubanFont.body(12)).foregroundStyle(theme.negTextColor)
            }
        }
    }

    // MARK: Sections

    private var sections: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow("Sections to add · \(draft.items.count)")
                Spacer()
                Text("\(app.creditsText(draft.credits)) credits")
                    .font(ThubanFont.body(12, weight: .semibold))
                    .foregroundStyle(theme.inkDimColor)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(draft.items) { item in row(item, last: item.id == draft.items.last?.id) }
            }
            .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
        }
    }

    private func row(_ item: BannerPlanExportItem, last: Bool) -> some View {
        let colors = theme.scheduleCourseColors(app.scheduleTab.colorIndex(of: item.courseCode))
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(colors.dot).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.courseCode).font(ThubanFont.mono(13, weight: .semibold)).foregroundStyle(theme.inkColor)
                    Text(item.section).font(ThubanFont.mono(12)).foregroundStyle(theme.inkDimColor)
                    Text(item.title).font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
                Text(item.times).font(ThubanFont.body(12)).foregroundStyle(theme.inkFaintColor).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.credits.map { "\(app.creditsText($0)) cr" } ?? "— cr")
                .font(ThubanFont.mono(12))
                .foregroundStyle(theme.inkFaintColor)
            Text(item.crn)
                .font(ThubanFont.mono(13, weight: .semibold))
                .foregroundStyle(theme.brassInkColor)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(theme.lineColor).frame(height: ThubanMetrics.hairline) } }
        .accessibilityElement(children: .combine)
    }

    // MARK: Notes

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            note("Creates a NEW plan in Plan Ahead. Does not register you or change existing plans.", strong: true)
            if let p = draft.preflight, let count = p.planCount, let max = p.maxPlans {
                note("You have \(count) of \(max) plans for \(draft.termLabel); this makes \(count + 1).")
            } else if !draft.dryRun, draft.phase != .checking {
                note("Banner allows \(BannerPlanExport.documentedMaxPlans) plans a term.")
            }
            note("Banner keeps the sections as planned CRNs; you register yourself when registration opens.")
            if draft.dryRun { note("Dry run (THUBAN_PLANNER_EXPORT_DRY_RUN=1): the requests are built and logged, never sent.", strong: true) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
    }

    private func note(_ text: String, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(strong ? theme.accentColor : theme.inkFaintColor).frame(width: 5, height: 5).offset(y: -2)
            Text(text)
                .font(ThubanFont.body(13, weight: strong ? .semibold : .regular))
                .foregroundStyle(strong ? theme.inkColor : theme.inkDimColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(_ model: ScheduleModel) -> some View {
        HStack(spacing: 10) {
            switch draft.phase {
            case .done(let outcome):
                Spacer()
                if !outcome.dryRun {
                    Button("Open Plan Ahead") { model.openPlanAhead() }.buttonStyle(.thubanSecondary)
                }
                Button("Done") { model.closeExport() }.buttonStyle(.thubanPrimary).keyboardShortcut(.defaultAction)
            case .failed(_, let wroteNothing):
                Spacer()
                if !wroteNothing { Button("Open Plan Ahead") { model.openPlanAhead() }.buttonStyle(.thubanSecondary) }
                Button("Close") { model.closeExport() }.buttonStyle(.thubanSecondary).keyboardShortcut(.cancelAction)
                if wroteNothing { Button("Try again") { model.retryExport() }.buttonStyle(.thubanPrimary).keyboardShortcut(.defaultAction) }
            case .full:
                Spacer()
                Button("Open Plan Ahead") { model.openPlanAhead() }.buttonStyle(.thubanSecondary)
                Button("Close") { model.closeExport() }.buttonStyle(.thubanPrimary).keyboardShortcut(.defaultAction)
            case .working:
                Text("Don’t close the app until this finishes.").font(ThubanFont.body(12)).foregroundStyle(theme.inkFaintColor)
                Spacer()
                Button("Create plan") {}.buttonStyle(.thubanPrimary).disabled(true)
            case .checking, .ready:
                Text("Nothing is written to Banner until you click Create plan.")
                    .font(ThubanFont.body(12)).foregroundStyle(theme.inkFaintColor)
                Spacer()
                Button("Cancel") { model.closeExport() }.buttonStyle(.thubanSecondary).keyboardShortcut(.cancelAction)
                Button(draft.dryRun ? "Create plan (dry run)" : "Create plan") { model.confirmExport() }
                    .buttonStyle(.thubanPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.phase != .ready || draft.nameProblem != nil || draft.items.isEmpty)
            }
        }
    }
}
