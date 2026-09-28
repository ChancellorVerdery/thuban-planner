import AppKit
import SwiftUI
import ThubanPlannerCore

/// Settings ▸ Import from Atlas. The card follows `app.importPhase`: Check Atlas (ssh, one read-only SELECT) or a saved
/// JSON file → the counts preview with every warning (re-minted ids included) → Replace my plan (a backup first;
/// confirmation when it replaces something) → done / failed. Below: the ssh host + email and the exact command.
/// OWNER: Engineer C.
struct ImportSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneHeader(eyebrow: eyebrow, title: "Import",
                               caption: "Bring your plan over from Atlas. Read-only: Atlas is never changed, and nothing here is replaced until you have seen the counts.")
            SettingsImportCard()
            SettingsImportConnection()
        }
    }

    private var eyebrow: String? {
        if app.isFirstRun && app.data.isEmpty { return "First run · one-time import" }
        guard let at = app.data.importedAt else { return "Import · re-runnable" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Last imported \(formatter.string(from: at)) · re-runnable"
    }
}

// MARK: - Import card

struct SettingsImportCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var confirmReplace = false

    var body: some View {
        VStack(spacing: 0) {
            top
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)
            ForEach(rows) { row in
                SettingsImportRow(row: row)
            }
            if !warnings.isEmpty {
                SettingsImportWarnings(warnings: warnings)
            }
            if let note = footnote {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Icon(.info, size: 14)
                        .foregroundStyle(theme.inkDimColor)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                    Text(note)
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(theme.bgColor)
                .thubanHairline(.top, color: theme.lineColor)
            }
        }
        .thubanPanel(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .confirmationDialog("Replace your plan?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Back up and replace", role: .destructive) { app.applyImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(replaceMessage)
        }
    }

    // MARK: Top row per phase

    @ViewBuilder
    private var top: some View {
        switch app.importPhase {
        case .idle:
            topRow(title: "Check Atlas first", detail: "Reads your Course Planner and shows what would come over.") {
                Button("Import a file…") { app.chooseImportFile() }.buttonStyle(SecondaryButtonStyle(height: 32))
                Button("Check Atlas") { app.fetchAtlasPreview() }
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                    .disabled(!app.settingsImportConnectionIsValid)
                    .keyboardShortcut(.defaultAction)
            }
        case .fetching:
            VStack(alignment: .leading, spacing: 12) {
                topRow(title: "Reading Atlas", detail: "ssh \(app.preferences.atlasHost) · one read-only query", mono: true) {
                    Button("Cancel") { app.cancelImport() }.buttonStyle(SecondaryButtonStyle(height: 32))
                }
                SettingsIndeterminateBar()
            }
        case .preview(let preview):
            topRow(title: "Ready to import", detail: previewDetail(preview), mono: true) {
                Button("Cancel") { app.cancelImport() }.buttonStyle(SecondaryButtonStyle(height: 32))
                Button(preview.replacesExisting ? "Replace my plan" : "Import plan") {
                    if preview.replacesExisting { confirmReplace = true } else { app.applyImport() }
                }
                .buttonStyle(PrimaryButtonStyle(height: 32))
                .disabled(preview.summary.isEmpty && !preview.replacesExisting)
                .keyboardShortcut(.defaultAction)
            }
        case .applying:
            VStack(alignment: .leading, spacing: 12) {
                topRow(title: "Importing", detail: "saving a backup, then replacing your plan", mono: true) { EmptyView() }
                ProgressBar(value: 0.66)
            }
        case .done(_, let backup):
            VStack(alignment: .leading, spacing: 12) {
                topRow(title: "Imported", titleColor: theme.posTextColor,
                       detail: backup.map(backupLine) ?? "Nothing was here to back up.", oneLine: true) {
                    if let backup {
                        Button("Show backup") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                            .buttonStyle(GhostButtonStyle(height: 32, horizontalPadding: 10))
                            .help(backup.lastPathComponent)
                    }
                    Button("Done") { app.cancelImport() }.buttonStyle(SecondaryButtonStyle(height: 32))
                    Button("Open Planner") {
                        app.cancelImport()
                        app.section = .planner
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                    .keyboardShortcut(.defaultAction)
                }
                ProgressBar(value: 1, tint: theme.posColor)
            }
        case .failed(let message):
            if let source = app.lastImportSource, source.hasPrefix("file:") {
                topRow(title: "The file could not be imported", titleColor: theme.negTextColor,
                       detail: "\(String(source.dropFirst("file:".count))): \(message)") {
                    Button("Check Atlas instead") { app.fetchAtlasPreview() }
                        .buttonStyle(SecondaryButtonStyle(height: 32))
                        .disabled(!app.settingsImportConnectionIsValid)
                    Button("Choose another file…") { app.chooseImportFile() }
                        .buttonStyle(PrimaryButtonStyle(height: 32))
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                topRow(title: "Atlas could not be read", titleColor: theme.negTextColor, detail: message) {
                    Button("Import a file…") { app.chooseImportFile() }.buttonStyle(SecondaryButtonStyle(height: 32))
                    Button("Try again") { app.fetchAtlasPreview() }
                        .buttonStyle(PrimaryButtonStyle(height: 32))
                        .disabled(!app.settingsImportConnectionIsValid)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    /// "Backup: Before import · Mon Sep 28, 6:12 PM" (the file name is on Show backup's tooltip).
    private func backupLine(_ url: URL) -> String {
        let info = app.backups().first { $0.url.lastPathComponent == url.lastPathComponent }
        let label = SettingsFormat.backupLabel(info?.label ?? "before-import")
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? info?.created
        return "Backup: \(label)" + (date.map { " · \(SettingsFormat.dateTime($0))" } ?? "")
    }

    private func topRow<Actions: View>(title: String, titleColor: Color? = nil, detail: String, mono: Bool = false, oneLine: Bool = false,
                                       @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(titleColor ?? theme.inkColor)
                Text(detail)
                    .font(mono ? ThubanFont.mono(12.5) : ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(oneLine ? 1 : 3)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: !oneLine)
                    .help(detail)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { actions() }
        }
    }

    private func previewDetail(_ preview: ImportPreview) -> String {
        let source = SettingsFormat.source(preview.source).replacingOccurrences(of: "the file ", with: "")
        if let email = preview.summary.email { return "\(source) · \(email)" }
        return source
    }

    private var replaceMessage: String {
        guard case .preview(let p) = app.importPhase else { return "" }
        return "This replaces \(p.localCourses) class\(p.localCourses == 1 ? "" : "es") and \(p.localTerms) semester\(p.localTerms == 1 ? "" : "s"). A backup is made first and can be restored from Settings ▸ Data."
    }

    // MARK: Rows

    private var summary: ImportSummary? {
        switch app.importPhase {
        case .preview(let preview): return preview.summary
        case .done(let summary, _): return summary
        default: return nil
        }
    }

    private var warnings: [String] { summary?.warnings ?? [] }

    private var rows: [SettingsImportRowModel] {
        guard let s = summary else {
            let fetching = app.importPhase == .fetching
            return SettingsImportRowModel.placeholders.enumerated().map { index, row in
                var row = row
                row.state = fetching && index == 0 ? .active : .pending
                return row
            }
        }
        func state(_ n: Int) -> SettingsImportRowModel.State { n > 0 ? .done : .empty }
        let credits = { (c: Double) in "\(JS.numberString(c)) credit\(c == 1 ? "" : "s")" }
        let semesters: String = {
            guard let first = s.termLabels.first, let last = s.termLabels.last else { return "none recorded" }
            let range = first == last ? first : "\(first) – \(last)"
            return s.currentTerm.map { "\(range) · current \($0)" } ?? range
        }()
        let off = s.disabledTerms.map(TermKey.label)
        let finish: String = {
            if s.toTake == 0 { return "nothing left to schedule" }
            guard let grad = s.gradTerm, s.termsToFinish > 0 else { return "no route yet" }
            return "finishes \(grad)"
        }()
        return [
            SettingsImportRowModel(title: "Classes taken", detail: s.taken == 0 ? "none yet" : "\(credits(s.creditsTaken)) done or in progress",
                                   value: String(s.taken), state: state(s.taken)),
            SettingsImportRowModel(title: "Classes to take", detail: s.toTake == 0 ? "none" : "\(credits(s.creditsToTake)) left",
                                   value: String(s.toTake), state: state(s.toTake)),
            SettingsImportRowModel(title: "Semesters", detail: semesters, value: String(s.terms), state: state(s.terms)),
            SettingsImportRowModel(title: "Switched-off terms", detail: off.isEmpty ? "none — every summer is available" : off.joined(separator: ", "),
                                   value: String(off.count), state: state(off.count)),
            SettingsImportRowModel(title: "Settings",
                                   detail: "\(JS.numberString(s.settings.maxCredits)) per term · summer \(JS.numberString(s.settings.summerMax)) · \(s.settings.strategy.label)",
                                   value: "\(JS.numberString(s.settings.maxCredits)) / \(JS.numberString(s.settings.summerMax))", state: .done),
            SettingsImportRowModel(title: "Unknown requirements",
                                   detail: s.unknownRefs.isEmpty ? "every prerequisite names a class in the plan" : "\(s.unknownRefs.joined(separator: ", ")) — ignored, as in Atlas",
                                   value: String(s.unknownRefs.count), state: s.unknownRefs.isEmpty ? .done : .warn),
            SettingsImportRowModel(title: "Route", detail: finish,
                                   value: s.toTake == 0 ? "–" : SettingsFormat.terms(s.termsToFinish).replacingOccurrences(of: " more", with: ""),
                                   state: s.toTake == 0 || s.gradTerm != nil ? .done : .empty),
        ]
    }

    private var footnote: String? {
        switch app.importPhase {
        case .preview(let preview):
            if preview.summary.isEmpty {
                return "Atlas has no Course Planner data for this account yet. Check the email below."
            }
            if preview.replacesExisting {
                return "Replaces the \(preview.localCourses) classes and \(preview.localTerms) semesters here, after a backup. Your appearance and Atlas connection are kept."
            }
            return "Nothing is here yet, so nothing is replaced. Your appearance and Atlas connection are kept."
        case .done:
            return "Your classes, semesters, switched-off summers and planning settings are on this Mac now. Atlas was not changed."
        case .failed:
            if app.lastImportSource?.hasPrefix("file:") == true {
                return "Choose a course-planner document saved from Atlas (JSON, or the psql output of the import query)."
            }
            return "Check that “ssh \(app.preferences.atlasHost)” works in Terminal without a password prompt, or import a saved Atlas JSON file."
        case .idle, .fetching, .applying:
            return nil
        }
    }
}

struct SettingsImportRowModel: Identifiable, Hashable {
    enum State { case done, active, pending, empty, warn }
    var title: String
    var detail: String
    var value: String
    var state: State = .pending
    var id: String { title }

    static let placeholders: [SettingsImportRowModel] = [
        SettingsImportRowModel(title: "Classes taken", detail: "code, title, credits and the semester", value: "–"),
        SettingsImportRowModel(title: "Classes to take", detail: "prerequisites, corequisites, offered in summer", value: "–"),
        SettingsImportRowModel(title: "Semesters", detail: "your past and current terms", value: "–"),
        SettingsImportRowModel(title: "Switched-off terms", detail: "summers kept out of the plan", value: "–"),
        SettingsImportRowModel(title: "Settings", detail: "credit caps and route strategy", value: "–"),
        SettingsImportRowModel(title: "Route", detail: "recomputed here, exactly as Atlas does", value: "–"),
    ]
}

/// A 42 pt row: state mark, title (190 pt), detail, value (right-aligned mono).
private struct SettingsImportRow: View {
    @Environment(\.thubanTheme) private var theme
    var row: SettingsImportRowModel

    var body: some View {
        HStack(spacing: 14) {
            SettingsImportMark(state: row.state)
            Text(row.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.state == .pending || row.state == .empty ? theme.inkDimColor : theme.inkColor)
                .frame(width: 180, alignment: .leading)
            Text(row.detail)
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(row.detail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.value)
                .font(ThubanFont.body(13, weight: .medium))
                .foregroundStyle(row.state == .pending || row.state == .empty ? theme.inkFaintColor : theme.inkColor)
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 42)
        .thubanHairline(.top, color: theme.lineColor)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsImportMark: View {
    @Environment(\.thubanTheme) private var theme
    var state: SettingsImportRowModel.State

    var body: some View {
        Group {
            switch state {
            case .done:
                Circle().fill(theme.posSoftColor)
                    .overlay(Icon(.check, size: 13).foregroundStyle(theme.posTextColor))
            case .warn:
                Circle().fill(theme.warnSoftColor)
                    .overlay(Text("!").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.brassInkColor))
            case .active:
                TimelineView(.animation) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
                    ZStack {
                        Circle().strokeBorder(theme.lineColor, lineWidth: 2)
                        Circle().trim(from: 0, to: 0.75)
                            .stroke(theme.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .padding(1)
                            .rotationEffect(.degrees(angle))
                    }
                }
            case .pending:
                Circle().strokeBorder(theme.inkFaintColor, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            case .empty:
                Circle().fill(theme.panel2Color)
                    .overlay(Rectangle().fill(theme.inkFaintColor).frame(width: 8, height: 1.5))
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// The importer's notes (rows dropped or repaired, re-minted ids and what that does to the route), one per line.
private struct SettingsImportWarnings: View {
    @Environment(\.thubanTheme) private var theme
    var warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(warnings.count == 1 ? "1 note from the import" : "\(warnings.count) notes from the import")
                .font(ThubanFont.micro)
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(theme.brassInkColor)
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(theme.brassInkColor).frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                    Text(Self.sentence(warning))
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(theme.warnSoftColor)
        .thubanHairline(.top, color: theme.lineColor)
        .accessibilityElement(children: .combine)
    }

    /// "1 class shared an id …" → "1 class shared an id ….": capitalised, with a full stop.
    static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        let capped = first.uppercased() + text.dropFirst()
        return capped.hasSuffix(".") ? capped : capped + "."
    }
}

/// An accent segment sliding along a `panel2` track while ssh runs.
private struct SettingsIndeterminateBar: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let segment = geometry.size.width * 0.3
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.panel2Color)
                    Capsule().fill(theme.accentColor)
                        .frame(width: segment)
                        .offset(x: (geometry.size.width + segment) * t - segment)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Reading Atlas")
    }
}

// MARK: - Connection

struct SettingsImportConnection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsGroup("Connection", caption: "Signs in with your ssh key (no password is stored) and runs one SELECT inside a read-only transaction. Nothing is ever written to Atlas.") {
            HStack(alignment: .top, spacing: 12) {
                field(label: "ssh host", text: Binding(get: { app.preferences.atlasHost },
                                                       set: { app.preferences.atlasHost = $0.trimmingCharacters(in: .whitespaces) }),
                      prompt: Preferences.defaultAtlasHost, invalid: hostError != nil)
                    .frame(width: 200)
                field(label: "Atlas account email", text: Binding(get: { app.preferences.atlasEmail },
                                                                  set: { app.preferences.atlasEmail = $0.trimmingCharacters(in: .whitespaces) }),
                      prompt: Preferences.defaultAtlasEmail, invalid: emailError != nil)
                    .frame(maxWidth: 340)
                Spacer(minLength: 0)
            }
            .disabled(app.importPhase.isBusy)
            if let problem = hostError ?? emailError {
                SettingsNote(text: problem, tone: .negative)
            }
            HStack(spacing: 8) {
                Text(app.atlasImporter.commandDescription)
                    .font(ThubanFont.mono(12))
                    .foregroundStyle(theme.inkDimColor)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if app.preferences.atlasHost != Preferences.defaultAtlasHost || app.preferences.atlasEmail != Preferences.defaultAtlasEmail {
                    Button("Reset") {
                        app.preferences.atlasHost = Preferences.defaultAtlasHost
                        app.preferences.atlasEmail = Preferences.defaultAtlasEmail
                    }
                    .buttonStyle(GhostButtonStyle(height: 26, horizontalPadding: 8))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Command: \(app.atlasImporter.commandDescription)")
        }
    }

    private var hostError: String? {
        do { try AtlasImporter.validateHost(app.preferences.atlasHost); return nil } catch { return error.localizedDescription }
    }

    private var emailError: String? {
        do { try AtlasImporter.validateEmail(app.preferences.atlasEmail); return nil } catch { return error.localizedDescription }
    }

    private func field(label: String, text: Binding<String>, prompt: String, invalid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.inkDimColor)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(theme.inkFaintColor))
                .labelsHidden()
                .autocorrectionDisabled()
                .thubanField(invalid: invalid, mono: true, height: 32)
                .accessibilityLabel(label)
        }
    }
}
