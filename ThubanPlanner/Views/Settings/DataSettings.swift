import AppKit
import SwiftUI
import ThubanPlannerCore

/// Settings ▸ Data: where planner.json lives and what is in it, the backups (restore after confirming), and Export.
/// OWNER: Engineer C.
struct DataSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var backups: [PlannerStore.Backup] = []
    @State private var pendingRestore: PlannerStore.Backup?
    @State private var message: (text: String, tone: SettingsNote.Tone)?

    static let backupsShown = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneHeader(eyebrow: nil, title: "Data",
                               caption: "Your plan is one file on this Mac, saved after every change. Nothing is sent anywhere.")

            SettingsGroup("On this Mac") {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Icon(.file, size: 16).foregroundStyle(theme.inkDimColor)
                        Text(app.store.fileURL.path(percentEncoded: false))
                            .font(ThubanFont.mono(12.5))
                            .foregroundStyle(theme.inkColor)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(app.store.fileURL.path(percentEncoded: false))
                        Spacer(minLength: 8)
                        Button("Reveal in Finder") { app.revealDataFolder() }.buttonStyle(SecondaryButtonStyle(height: 30))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    HStack(spacing: 0) {
                        count(String(app.courses.count), "classes")
                        count(String(app.terms.count), "semesters")
                        count(app.creditsText(app.creditsTotal), "credits in the plan")
                        count(app.settingsLastSaved.map(Self.relative) ?? "Not yet", "last saved")
                    }
                    .padding(.vertical, 12)
                    .thubanHairline(.top, color: theme.lineColor)
                    if let source = app.data.importSource {
                        HStack(spacing: 8) {
                            Icon(.download, size: 14).foregroundStyle(theme.inkDimColor)
                            Text(importLine(source))
                                .font(ThubanFont.small)
                                .foregroundStyle(theme.inkDimColor)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .thubanHairline(.top, color: theme.lineColor)
                    }
                }
                .thubanPanel(padding: 0)
            }

            SettingsGroup("Backups", caption: "A copy is saved before the first change of each day (the last \(PlannerStore.dailyBackupsKept) are kept) and before every import or restore (the last \(PlannerStore.snapshotsKept)).") {
                if backups.isEmpty {
                    HStack(spacing: 12) {
                        Icon(.history, size: 18).foregroundStyle(theme.inkFaintColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No backups yet")
                                .font(ThubanFont.body(14, weight: .semibold))
                                .foregroundStyle(theme.inkColor)
                            Text("The first one is made before tomorrow's first change, or before an import.")
                                .font(ThubanFont.small)
                                .foregroundStyle(theme.inkDimColor)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .thubanPanel(padding: 0)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(backups.prefix(Self.backupsShown).enumerated()), id: \.element.id) { index, backup in
                            SettingsBackupRow(backup: backup) { pendingRestore = backup }
                                .thubanHairline(.top, color: index == 0 ? .clear : theme.lineColor)
                        }
                    }
                    .thubanPanel(padding: 0)
                    if backups.count > Self.backupsShown {
                        SettingsNote(text: "\(backups.count - Self.backupsShown) older backups are in the backups folder.")
                    }
                }
            }

            SettingsGroup("Export", caption: "Saves your plan as one JSON file — the same format as planner.json, readable by this app and by any text editor.") {
                HStack(spacing: 12) {
                    Button(action: export) {
                        HStack(spacing: 7) { Icon(.download, size: 15); Text("Export…") }
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
                    if let message { SettingsNote(text: message.text, tone: message.tone) }
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: app.data) { _, _ in reload() }
        .confirmationDialog("Restore this backup?",
                            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible, presenting: pendingRestore) { backup in
            Button("Restore", role: .destructive) { restore(backup) }
            Button("Cancel", role: .cancel) {}
        } message: { backup in
            Text("Replaces your plan with the copy from \(SettingsFormat.dateTime(backup.created)). What is here now is saved as a backup first.")
        }
    }

    private func count(_ value: String, _ label: String, mono: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(mono ? ThubanFont.display(20) : ThubanFont.body(15, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .monospacedDigit()
                .lineLimit(1)
                .frame(height: 26, alignment: .bottomLeading)
            Text(label).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    private func importLine(_ source: String) -> String {
        let from = SettingsFormat.source(source)
        guard let at = app.data.importedAt else { return "Imported from \(from)." }
        return "Imported from \(from) on \(SettingsFormat.dateTime(at))."
    }

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let text = formatter.localizedString(for: date, relativeTo: Date())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func reload() { backups = app.backups() }

    private func restore(_ backup: PlannerStore.Backup) {
        do {
            try app.restoreBackup(backup.url)
            message = ("Restored the copy from \(SettingsFormat.dateTime(backup.created)).", .positive)
        } catch {
            message = (error.localizedDescription, .negative)
        }
        reload()
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Thuban Planner \(formatter.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try app.exportData(to: url)
            message = ("Saved \(url.lastPathComponent).", .positive)
        } catch {
            message = (error.localizedDescription, .negative)
        }
    }
}

struct SettingsBackupRow: View {
    @Environment(\.thubanTheme) private var theme
    var backup: PlannerStore.Backup
    var restore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Chip(SettingsFormat.backupLabel(backup.label), kind: backup.label == "daily" ? .neutral : .accent)
                .frame(width: 130, alignment: .leading)
            Text(SettingsFormat.dateTime(backup.created))
                .font(ThubanFont.body(14))
                .foregroundStyle(theme.inkColor)
                .monospacedDigit()
            Spacer(minLength: 8)
            Text(SettingsFormat.bytes(backup.size))
                .font(ThubanFont.mono(12.5))
                .foregroundStyle(theme.inkFaintColor)
                .frame(width: 70, alignment: .trailing)
            Button("Restore…", action: restore)
                .buttonStyle(GhostButtonStyle(height: 28, tinted: true, horizontalPadding: 10))
                .accessibilityLabel("Restore backup from \(SettingsFormat.dateTime(backup.created))")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .accessibilityElement(children: .contain)
    }
}
