import SwiftUI
import ThubanPlannerCore

/// Settings ▸ About: the mark, version, what the app does, where data lives, and the Atlas rule. OWNER: Engineer C.
struct AboutSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center, spacing: 20) {
                AppArtView(size: 72, theme: theme)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thuban Planner")
                        .font(ThubanFont.display(32))
                        .foregroundStyle(theme.inkColor)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your route to graduation. A sibling of Thuban Gym, Study and Canvas.")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                    Text("Version \(version)")
                        .font(ThubanFont.mono(12.5))
                        .foregroundStyle(theme.inkFaintColor)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }

            Text("Record the semesters you have taken and the classes in them, list the classes still to take with their credits, prerequisites (an earlier term), corequisites (the same term or earlier) and whether they run in summer. The planner lays out the fastest — or the evenest — route to graduation under your per-term credit caps, and skips any summer you switch off.")
                .font(ThubanFont.body(15))
                .foregroundStyle(theme.inkColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 640, alignment: .leading)

            SettingsGroup("How it works") {
                VStack(spacing: 0) {
                    fact("Route", "The scheduler is Atlas's Course Planner ported line for line, and checked against Atlas's own code on thousands of plans, so both give the same route.")
                    fact("Local", "Everything lives on this Mac in one file, planner.json, saved after every change with daily backups. Settings ▸ Data shows where it is.")
                    fact("Atlas", "Read over ssh with one read-only query, and only when you ask. Atlas is never written to.", last: true)
                }
                .thubanPanel(padding: 0)
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private func fact(_ title: String, _ text: String, last: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(ThubanFont.body(14, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .frame(width: 70, alignment: .leading)
            Text(text)
                .font(ThubanFont.body(14))
                .foregroundStyle(theme.inkDimColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { if !last { Hairline() } }
    }
}
