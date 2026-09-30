import SwiftUI
import ThubanPlannerCore

/// A class in the sidebar: colour dot, code, title, credits, "8 sections · 5 open", its pin; expands to the section
/// list, where each section can be included / excluded and pinned. Hover shows remove.
struct ScheduleCourseCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var row: ScheduleCourseRow
    var colors: ScheduleCourseColors
    @State private var hovering = false

    private var expanded: Bool { app.scheduleTab.expandedCourse == row.code }

    var body: some View {
        let model = app.scheduleTab
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { model.expandedCourse = expanded ? nil : row.code }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.code), \(row.title). \(status). \(expanded ? "Collapse" : "Show") sections")
            if expanded, let sections = row.sections, !sections.isEmpty {
                Hairline()
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        let excludedAll = sections.allSatisfy { model.isExcluded($0.crn) }
                        Button(excludedAll ? "Include all" : "Exclude all") { model.setAllIncluded(row, excludedAll) }
                            .buttonStyle(.plain)
                            .font(ThubanFont.body(11.5, weight: .semibold))
                            .foregroundStyle(theme.brassInkColor)
                        Spacer()
                        if let fetched = row.fetchedAt {
                            Text("Updated \(ScheduleSidebar.relative(fetched))")
                                .font(ThubanFont.body(11))
                                .foregroundStyle(theme.inkFaintColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    ForEach(sections.sorted { $0.sequenceNumber != $1.sequenceNumber ? $0.sequenceNumber < $1.sequenceNumber : $0.crn < $1.crn }) { section in
                        ScheduleSectionRow(row: row, section: section)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(expanded ? theme.bgColor : (hovering ? theme.panel2Color.opacity(0.6) : theme.bgColor.opacity(0.0)),
                    in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
            .strokeBorder(expanded ? theme.line2Color : theme.lineColor, lineWidth: ThubanMetrics.hairline))
        .onHover { hovering = $0 }
    }

    private var status: String {
        if row.isFetching && row.sections == nil { return "Finding sections…" }
        if let error = row.error, row.sections == nil { return error }
        guard let sections = row.sections else { return "Waiting" }
        if sections.isEmpty { return "Not offered this term" }
        let excluded = sections.filter { app.scheduleTab.isExcluded($0.crn) }.count
        var text = "\(sections.count) section\(sections.count == 1 ? "" : "s") · \(row.openCount) open"
        if excluded > 0 { text += " · \(excluded) excluded" }
        return text
    }

    private var header: some View {
        let model = app.scheduleTab
        return HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(colors.dot).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.code).font(ThubanFont.mono(13, weight: .semibold)).foregroundStyle(theme.inkColor)
                    if let credits = row.credits {
                        Text("\(app.creditsText(credits)) cr").font(ThubanFont.mono(11)).foregroundStyle(theme.inkFaintColor)
                    }
                    if row.pinnedCRN != nil {
                        Image(systemName: "pin.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                            .help("Pinned to CRN \(row.pinnedCRN ?? "")")
                    }
                    if row.origin == .added {
                        Text("added").font(ThubanFont.body(10.5, weight: .semibold)).foregroundStyle(theme.inkFaintColor)
                    }
                }
                if !row.title.isEmpty {
                    Text(row.title).font(ThubanFont.body(12)).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
                HStack(spacing: 4) {
                    if row.isFetching { ProgressView().controlSize(.mini).scaleEffect(0.8) }
                    Text(status)
                        .font(ThubanFont.body(11.5))
                        .foregroundStyle(row.error != nil && row.sections == nil || row.sections?.isEmpty == true ? theme.negTextColor : theme.inkFaintColor)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if row.error != nil, !row.isFetching {
                IconButton(.history, label: "Retry \(row.code)", size: 26, iconSize: 14) { model.retryCourse(row.code) }
            }
            if hovering || expanded {
                IconButton(.close, label: "Remove \(row.code) from this term", size: 26, iconSize: 13) { model.removeCourse(row.code) }
            }
            Icon(expanded ? .chevronDown : .chevronRight, size: 13).foregroundStyle(theme.inkFaintColor)
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// One section: include checkbox, number, times, instructor, seats, pin.
private struct ScheduleSectionRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var row: ScheduleCourseRow
    var section: BannerSection

    var body: some View {
        let model = app.scheduleTab
        let included = !model.isExcluded(section.crn)
        let pinned = row.pinnedCRN == section.crn
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: Binding(get: { included }, set: { model.setIncluded(section.crn, $0) })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .tint(theme.accentColor)
                .accessibilityLabel("Include section \(section.sequenceNumber)")
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(section.sequenceNumber).font(ThubanFont.mono(12, weight: .semibold))
                    Text(section.crn).font(ThubanFont.mono(11)).foregroundStyle(theme.inkFaintColor)
                    Spacer(minLength: 2)
                    seats
                }
                Text(section.timeSummary)
                    .font(ThubanFont.body(11.5))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
                let who = section.instructors.first ?? (section.instructionalMethod == "Face-to-Face Instruction" ? nil : section.instructionalMethod)
                if let who {
                    Text(who).font(ThubanFont.body(11)).foregroundStyle(theme.inkFaintColor).lineLimit(1)
                }
            }
            .foregroundStyle(theme.inkColor)
            .opacity(included ? 1 : 0.5)
            Button {
                model.setPin(row, crn: pinned ? nil : section.crn)
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(pinned ? theme.brassInkColor : theme.inkFaintColor)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(pinned ? (row.planCRN == section.crn ? "Pinned by your Banner plan — click to unpin" : "Unpin") : "Pin: always use this section")
            .accessibilityLabel(pinned ? "Unpin section \(section.sequenceNumber)" : "Pin section \(section.sequenceNumber)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(pinned ? theme.accentTintColor : .clear)
    }

    private var seats: some View {
        let s = section.seatsAvailable
        let text = s > 0 ? "\(s) open" : (section.waitCount > 0 ? "Full · \(section.waitCount) waiting" : (s < 0 ? "Full (\(s))" : "Full"))
        return Text(text)
            .font(ThubanFont.body(11, weight: .semibold))
            .foregroundStyle(s > 0 ? theme.posTextColor : theme.negTextColor)
            .monospacedDigit()
    }
}
