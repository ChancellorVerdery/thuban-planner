import AppKit
import SwiftUI
import ThubanPlannerCore

/// A class in the current timetable, opened from a grid block, an Online / TBA entry or a CRN chip: code, title,
/// section, CRN (copy), credits, type, method, campus, seats and waitlist; every meeting (days, time, place, dates
/// when they differ from the course's usual range); each instructor with a Rate My Professors card (UNC Charlotte
/// pages only, fetched when the sheet opens, cache first). A sheet rather than a popover: meetings plus one or more
/// rating cards (with a per-page breakdown) are too tall for a popover anchored to a 50-minute block, and the sheet
/// matches the app's other class detail. Esc or Done closes.
struct ScheduleClassDetailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var item: ScheduleClassDetailItem
    @State private var copied = false

    private var section: BannerSection { item.section }

    var body: some View {
        let model = app.scheduleTab
        let colors = theme.scheduleCourseColors(model.colorIndex(of: item.course))
        VStack(spacing: 0) {
            header(colors)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    facts
                    meetings(model)
                    instructors
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            Hairline()
            footer
                .padding(.horizontal, 24)
                .frame(height: 60)
        }
        .frame(width: 640, height: 700)
        .background(theme.panelColor)
        .background {
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).hidden()
        }
        .onAppear {
            for raw in section.instructors {
                if let name = RMPPersonName.parse(raw) { model.ratings.request(name) }
            }
        }
    }

    // MARK: Header

    private func header(_ colors: ScheduleCourseColors) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2).fill(colors.dot).frame(width: 5, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(["Section \(section.sequenceNumber)", section.scheduleType, app.scheduleTab.selectedTermLabel]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(section.courseCode)
                        .font(ThubanFont.display(28))
                        .kerning(-0.28)
                        .foregroundStyle(theme.inkColor)
                        .accessibilityAddTraits(.isHeader)
                    if let credits = section.credits {
                        Text("\(app.creditsText(credits)) cr")
                            .font(ThubanFont.mono(13))
                            .foregroundStyle(theme.inkFaintColor)
                    }
                }
                Text(section.title)
                    .font(ThubanFont.body(15))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text("CRN")
                    .font(ThubanFont.micro)
                    .foregroundStyle(theme.inkFaintColor)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(section.crn, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                } label: {
                    HStack(spacing: 7) {
                        Text(section.crn).font(ThubanFont.mono(16, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                        Icon(copied ? .check : .file, size: 14).foregroundStyle(theme.inkDimColor)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(copied ? "Copied" : "Copy CRN \(section.crn)")
                .accessibilityLabel(copied ? "CRN \(section.crn) copied" : "Copy CRN \(section.crn)")
                Text(copied ? "Copied" : "Click to copy")
                    .font(ThubanFont.body(11))
                    .foregroundStyle(theme.inkFaintColor)
            }
        }
    }

    // MARK: Facts

    private var facts: some View {
        let columns = [GridItem(.flexible(), spacing: 16, alignment: .topLeading), GridItem(.flexible(), spacing: 16, alignment: .topLeading),
                       GridItem(.flexible(), spacing: 16, alignment: .topLeading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            fact("Credits", section.credits.map { app.creditsText($0) } ?? "—")
            fact("Schedule type", section.scheduleType.isEmpty ? "—" : section.scheduleType)
            fact("Instruction", section.instructionalMethod.isEmpty ? "—" : section.instructionalMethod)
            fact("Campus", section.campus.isEmpty ? "—" : section.campus)
            fact("Seats", seatsText, tone: section.seatsAvailable > 0 ? theme.posTextColor : theme.negTextColor)
            fact("Waitlist", waitText, tone: section.waitCount > 0 ? theme.negTextColor : nil)
        }
    }

    private var seatsText: String {
        let open = section.seatsAvailable
        let cap = section.maximumEnrollment
        if open > 0 { return "\(open) open of \(cap)" }
        return open < 0 ? "Full (\(open)) of \(cap)" : "Full · \(cap) seats"
    }

    private var waitText: String {
        if section.waitCapacity == 0 && section.waitCount == 0 { return "None" }
        return "\(section.waitCount) waiting · \(max(0, section.waitAvailable)) of \(section.waitCapacity) open"
    }

    private func fact(_ label: String, _ value: String, tone: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(ThubanFont.body(10.5, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(theme.inkFaintColor)
            Text(value)
                .font(ThubanFont.body(13.5, weight: .medium))
                .foregroundStyle(tone ?? theme.inkColor)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Meetings

    private func meetings(_ model: ScheduleModel) -> some View {
        let usual = model.typicalDates(course: item.course)
        let list = section.meetings.isEmpty ? [BannerMeeting(days: [], begin: nil, end: nil)] : section.meetings
        return VStack(alignment: .leading, spacing: 8) {
            ScheduleDetailSectionTitle(list.count == 1 ? "Meets" : "Meets · \(list.count) patterns")
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, meeting in
                    if index > 0 { Hairline() }
                    meetingRow(meeting, usual: usual)
                }
            }
            .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
        }
    }

    private func meetingRow(_ meeting: BannerMeeting, usual: (start: Int?, end: Int?)) -> some View {
        let differentDates = (meeting.startDate != nil || meeting.endDate != nil)
            && (meeting.startDate != usual.start || meeting.endDate != usual.end)
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(meeting.days.isEmpty ? "—" : meeting.days.map(\.shortLabel).joined(separator: " · "))
                .font(ThubanFont.body(13.5, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .frame(width: 150, alignment: .leading)
            Text(timeText(meeting))
                .font(ThubanFont.mono(13))
                .foregroundStyle(meeting.isTimed ? theme.inkColor : theme.inkDimColor)
                .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(placeText(meeting))
                    .font(ThubanFont.body(13.5))
                    .foregroundStyle(theme.inkColor)
                    .fixedSize(horizontal: false, vertical: true)
                if differentDates {
                    Text(Self.dateRange(meeting.startDate, meeting.endDate))
                        .font(ThubanFont.body(12, weight: .medium))
                        .foregroundStyle(theme.brassInkColor)
                } else if let type = meeting.meetingType, type != "Class" {
                    Text(type).font(ThubanFont.body(12)).foregroundStyle(theme.inkFaintColor)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private func timeText(_ meeting: BannerMeeting) -> String {
        guard meeting.isTimed, let b = meeting.begin, let e = meeting.end else { return "No set time" }
        return BannerClock.range(b, e)
    }

    /// "Duke Centennial Hall 276"; "Online" / "TBA" when Banner gives no place.
    private func placeText(_ meeting: BannerMeeting) -> String {
        let building = meeting.buildingDescription ?? meeting.building
        switch (building, meeting.room) {
        case let (b?, r?): return "\(b) \(r)"
        case let (b?, nil): return b
        case let (nil, r?): return "Room \(r)"
        default:
            let method = section.instructionalMethod.lowercased()
            return method.contains("online") || meeting.building?.uppercased() == "ONLINE" ? "Online" : "TBA"
        }
    }

    /// 20270111 … 20270506 → "Jan 11 – May 6, 2027".
    static func dateRange(_ start: Int?, _ end: Int?) -> String {
        func parts(_ n: Int) -> (Int, Int, Int) { (n / 10000, (n / 100) % 100, n % 100) }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        func label(_ n: Int, year: Bool) -> String {
            let (y, m, d) = parts(n)
            return "\(months[max(0, min(11, m - 1))]) \(d)" + (year ? ", \(y)" : "")
        }
        switch (start, end) {
        case let (s?, e?) where s == e: return label(s, year: true)
        case let (s?, e?): return "\(label(s, year: s / 10000 != e / 10000)) – \(label(e, year: true))"
        case let (s?, nil): return "From \(label(s, year: true))"
        case let (nil, e?): return "Until \(label(e, year: true))"
        default: return ""
        }
    }

    // MARK: Instructors

    private var instructors: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScheduleDetailSectionTitle(section.instructors.count > 1 ? "Instructors" : "Instructor")
            if section.instructors.isEmpty {
                HStack(spacing: 12) {
                    Icon(.info, size: 18).foregroundStyle(theme.inkFaintColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Instructor not assigned yet")
                            .font(ThubanFont.body(14, weight: .semibold))
                            .foregroundStyle(theme.inkColor)
                        Text("Banner often names instructors closer to the term. Check back later for a Rate My Professors score.")
                            .font(ThubanFont.body(12.5))
                            .foregroundStyle(theme.inkDimColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            } else {
                ForEach(Array(section.instructors.enumerated()), id: \.offset) { index, raw in
                    ScheduleRatingCard(rawName: raw, subject: section.subject, isPrimary: index == 0 && section.instructors.count > 1)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Ratings from Rate My Professors, UNC Charlotte pages only. Community-submitted; weigh them with care.")
                .font(ThubanFont.body(11.5))
                .foregroundStyle(theme.inkFaintColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle(height: 32))
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Small uppercase heading inside the class detail sheet.
struct ScheduleDetailSectionTitle: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(ThubanFont.micro)
            .kerning(0.6)
            .foregroundStyle(theme.inkDimColor)
            .accessibilityAddTraits(.isHeader)
    }
}
