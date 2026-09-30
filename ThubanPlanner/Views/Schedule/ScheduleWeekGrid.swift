import SwiftUI
import ThubanPlannerCore

/// The week: Monday–Friday (Saturday / Sunday only when something meets then), 7 AM–10 PM in 30-minute rows
/// (widened when a class starts earlier or ends later). Class meetings are coloured blocks (course colour, code +
/// section, room, time); blocked times are hatched. In "Block times" mode a drag draws a new block and a click on a
/// block opens its editor.
struct ScheduleWeekGrid: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var option: TimetableOption?
    var blocks: [TimetableBlock]
    var blockMode: Bool

    @State private var draft: (day: BannerWeekday, start: Int, end: Int)?
    @State private var editingBlockId: String?

    private static let gutter: CGFloat = 58
    private static let headerHeight: CGFloat = 30

    private struct Placed: Identifiable {
        var id: String
        var course: String
        var section: BannerSection
        var meeting: BannerMeeting
        var day: BannerWeekday
        var column: Int
        var columns: Int
    }

    var body: some View {
        let range = hourRange
        let days = visibleDays
        let placed = placedMeetings(days: days)
        GeometryReader { geo in
            let width = geo.size.width
            let hourHeight = max(34, (geo.size.height - Self.headerHeight - 8) / CGFloat(range.upperBound - range.lowerBound))
            let dayWidth = (width - Self.gutter) / CGFloat(days.count)
            let gridHeight = Self.headerHeight + hourHeight * CGFloat(range.upperBound - range.lowerBound)
            ScrollView(.vertical, showsIndicators: gridHeight > geo.size.height + 1) {
                ZStack(alignment: .topLeading) {
                    gridLines(days: days, range: range, dayWidth: dayWidth, hourHeight: hourHeight, width: width)
                    if blockMode {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: width, height: gridHeight)
                            .gesture(drawGesture(days: days, range: range, dayWidth: dayWidth, hourHeight: hourHeight))
                    }
                    ForEach(blocks) { block in
                        if let index = days.firstIndex(of: block.day) {
                            blockView(block, rect: rect(day: index, start: block.start, end: block.end, range: range, dayWidth: dayWidth,
                                                        hourHeight: hourHeight))
                        }
                    }
                    ForEach(placed) { item in
                        if let index = days.firstIndex(of: item.day), let b = item.meeting.begin, let e = item.meeting.end {
                            let base = rect(day: index, start: b, end: e, range: range, dayWidth: dayWidth, hourHeight: hourHeight)
                            let sub = (base.width) / CGFloat(item.columns)
                            ScheduleMeetingBlock(section: item.section, meeting: item.meeting,
                                                 colors: theme.scheduleCourseColors(app.scheduleTab.colorIndex(of: item.course)),
                                                 height: base.height - 2, narrow: sub < 90)
                                .frame(width: max(0, sub - 2), height: max(0, base.height - 2))
                                .offset(x: base.minX + sub * CGFloat(item.column) + 1, y: base.minY + 1)
                                .opacity(blockMode ? 0.35 : 1)
                                .allowsHitTesting(!blockMode)
                        }
                    }
                    if let draft, let index = days.firstIndex(of: draft.day) {
                        let r = rect(day: index, start: draft.start, end: draft.end, range: range, dayWidth: dayWidth, hourHeight: hourHeight)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.accentTintColor)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(theme.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                            .overlay(alignment: .topLeading) {
                                Text(BannerClock.range(draft.start, draft.end))
                                    .font(ThubanFont.mono(11, weight: .semibold))
                                    .foregroundStyle(theme.brassInkColor)
                                    .padding(6)
                            }
                            .frame(width: r.width - 4, height: max(4, r.height))
                            .offset(x: r.minX + 2, y: r.minY)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: width, height: gridHeight, alignment: .topLeading)
                .coordinateSpace(name: "schedule-grid")
            }
        }
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
            .strokeBorder(blockMode ? theme.accentColor : theme.lineColor, lineWidth: ThubanMetrics.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(blockMode ? "Week grid, block times mode" : "Week grid")
    }

    // MARK: Geometry

    /// 7 AM–10 PM, widened to fit anything outside it.
    private var hourRange: Range<Int> {
        var low = 7, high = 22
        for m in option?.sections.flatMap(\.timedMeetings) ?? [] {
            if let b = m.begin { low = min(low, b / 60) }
            if let e = m.end { high = max(high, (e + 59) / 60) }
        }
        for b in blocks {
            low = min(low, b.start / 60)
            high = max(high, (b.end + 59) / 60)
        }
        return max(0, low)..<min(24, max(high, low + 1))
    }

    private var visibleDays: [BannerWeekday] {
        var days: [BannerWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let used = Set((option?.sections.flatMap(\.timedMeetings).flatMap(\.days) ?? []) + blocks.map(\.day))
        if used.contains(.saturday) || blockMode { days.append(.saturday) }
        if used.contains(.sunday) || blockMode { days.append(.sunday) }
        return days
    }

    private func rect(day: Int, start: Int, end: Int, range: Range<Int>, dayWidth: CGFloat, hourHeight: CGFloat) -> CGRect {
        let y0 = Self.headerHeight + CGFloat(start - range.lowerBound * 60) / 60 * hourHeight
        let y1 = Self.headerHeight + CGFloat(end - range.lowerBound * 60) / 60 * hourHeight
        return CGRect(x: Self.gutter + CGFloat(day) * dayWidth, y: y0, width: dayWidth, height: y1 - y0)
    }

    /// Meetings per day; overlapping meetings of one timetable (none, normally) share the column side by side.
    private func placedMeetings(days: [BannerWeekday]) -> [Placed] {
        guard let option else { return [] }
        var items: [Placed] = []
        for pick in option.picks {
            for section in pick.choice.sections {
                for (mi, meeting) in section.timedMeetings.enumerated() {
                    for day in meeting.days where days.contains(day) {
                        items.append(Placed(id: "\(section.crn)-\(mi)-\(day.rawValue)", course: pick.course, section: section, meeting: meeting,
                                            day: day, column: 0, columns: 1))
                    }
                }
            }
        }
        // Side-by-side lanes for any overlap on the same day (e.g. two meetings of one section, different dates).
        for day in days {
            let indices = items.indices.filter { items[$0].day == day }.sorted { (items[$0].meeting.begin ?? 0) < (items[$1].meeting.begin ?? 0) }
            var lanes: [Int] = []
            var cluster: [Int] = []
            var clusterEnd = -1
            func flush() {
                let n = (cluster.map { items[$0].column }.max() ?? 0) + 1
                for i in cluster { items[i].columns = n }
                cluster = []
                lanes = []
            }
            for i in indices {
                let b = items[i].meeting.begin ?? 0, e = items[i].meeting.end ?? 0
                if b >= clusterEnd { flush() }
                if let lane = lanes.firstIndex(where: { $0 <= b }) { lanes[lane] = e; items[i].column = lane } else { lanes.append(e); items[i].column = lanes.count - 1 }
                cluster.append(i)
                clusterEnd = max(clusterEnd, e)
            }
            flush()
        }
        return items
    }

    // MARK: Drawing

    private func gridLines(days: [BannerWeekday], range: Range<Int>, dayWidth: CGFloat, hourHeight: CGFloat, width: CGFloat) -> some View {
        let height = Self.headerHeight + hourHeight * CGFloat(range.count)
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                // Header rule and hour / half-hour rules.
                var hours = Path()
                var halves = Path()
                for (i, _) in range.enumerated() {
                    let y = Self.headerHeight + CGFloat(i) * hourHeight
                    hours.move(to: CGPoint(x: Self.gutter - 6, y: y)); hours.addLine(to: CGPoint(x: width, y: y))
                    let h = y + hourHeight / 2
                    halves.move(to: CGPoint(x: Self.gutter, y: h)); halves.addLine(to: CGPoint(x: width, y: h))
                }
                context.stroke(hours, with: .color(theme.lineColor), lineWidth: 1)
                context.stroke(halves, with: .color(theme.lineColor.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                var columns = Path()
                for i in 0...days.count {
                    let x = Self.gutter + CGFloat(i) * dayWidth
                    columns.move(to: CGPoint(x: x, y: 0)); columns.addLine(to: CGPoint(x: x, y: height))
                }
                context.stroke(columns, with: .color(theme.lineColor), lineWidth: 1)
                // Weekend columns are tinted.
                for (i, day) in days.enumerated() where day == .saturday || day == .sunday {
                    context.fill(Path(CGRect(x: Self.gutter + CGFloat(i) * dayWidth, y: Self.headerHeight, width: dayWidth,
                                             height: height - Self.headerHeight)), with: .color(theme.panel2Color.opacity(0.5)))
                }
            }
            .frame(width: width, height: height)
            .allowsHitTesting(false)

            ForEach(Array(days.enumerated()), id: \.element) { i, day in
                Text(dayWidth > 110 ? day.fullLabel : day.shortLabel)
                    .font(ThubanFont.body(12, weight: .semibold))
                    .foregroundStyle(theme.inkDimColor)
                    .frame(width: dayWidth, height: Self.headerHeight)
                    .offset(x: Self.gutter + CGFloat(i) * dayWidth)
            }
            ForEach(Array(range.enumerated()), id: \.element) { i, hour in
                Text(BannerClock.hourLabel(hour))
                    .font(ThubanFont.mono(11))
                    .foregroundStyle(theme.inkFaintColor)
                    .frame(width: Self.gutter - 12, alignment: .trailing)
                    .offset(x: 0, y: Self.headerHeight + CGFloat(i) * hourHeight + 3)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(theme.panelColor)
        .thubanHairline(.bottom, color: .clear)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.lineColor).frame(height: 1).offset(y: Self.headerHeight - 1)
        }
    }

    private func blockView(_ block: TimetableBlock, rect r: CGRect) -> some View {
        ScheduleBlockTile(block: block, blockMode: blockMode, isEditing: Binding(
            get: { editingBlockId == block.id },
            set: { editingBlockId = $0 ? block.id : nil }))
            .frame(width: max(0, r.width - 4), height: max(0, r.height))
            .offset(x: r.minX + 2, y: r.minY)
    }

    // MARK: Drawing a block

    private func drawGesture(days: [BannerWeekday], range: Range<Int>, dayWidth: CGFloat, hourHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("schedule-grid"))
            .onChanged { value in
                guard let day = dayAt(value.startLocation.x, days: days, dayWidth: dayWidth) else { return }
                let a = minutesAt(value.startLocation.y, range: range, hourHeight: hourHeight)
                let b = minutesAt(value.location.y, range: range, hourHeight: hourHeight)
                draft = (day, min(a, b), max(max(a, b), min(a, b) + 15))
            }
            .onEnded { _ in
                defer { draft = nil }
                guard let d = draft else { return }
                if let block = app.scheduleTab.addBlock(day: d.day, start: d.start, end: d.end) { editingBlockId = block.id }
            }
    }

    private func dayAt(_ x: CGFloat, days: [BannerWeekday], dayWidth: CGFloat) -> BannerWeekday? {
        let i = Int(floor((x - Self.gutter) / dayWidth))
        return days.indices.contains(i) ? days[i] : nil
    }

    /// Minutes at a y position, snapped to 15 minutes and clamped to the visible hours.
    private func minutesAt(_ y: CGFloat, range: Range<Int>, hourHeight: CGFloat) -> Int {
        let raw = Double(range.lowerBound * 60) + Double((y - Self.headerHeight) / hourHeight) * 60
        let snapped = Int((raw / 15).rounded()) * 15
        return min(max(snapped, range.lowerBound * 60), range.upperBound * 60)
    }
}

/// One class meeting on the grid: course-colour fill with a stripe; code + section, room, time.
private struct ScheduleMeetingBlock: View {
    @Environment(\.thubanTheme) private var theme
    var section: BannerSection
    var meeting: BannerMeeting
    var colors: ScheduleCourseColors
    var height: CGFloat
    var narrow: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(colors.stripe).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(section.courseCode).font(ThubanFont.mono(11.5, weight: .semibold))
                    if !narrow { Text(section.sequenceNumber).font(ThubanFont.mono(11)).foregroundStyle(theme.inkDimColor) }
                    // Short meetings (50 minutes on a compact grid) keep the time on the first line.
                    if height < 36, !narrow, let b = meeting.begin, let e = meeting.end {
                        Text(BannerClock.range(b, e)).font(ThubanFont.body(11)).foregroundStyle(theme.inkDimColor)
                    }
                }
                .lineLimit(1)
                if height >= 36, let b = meeting.begin, let e = meeting.end {
                    Text(BannerClock.range(b, e))
                        .font(ThubanFont.body(11))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                }
                if height >= 50, let place = meeting.location {
                    Text(place)
                        .font(ThubanFont.body(11))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(colors.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, height >= 36 ? 4 : 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(colors.fill)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tooltip)
    }

    private var tooltip: String {
        var lines = ["\(section.courseCode) \(section.sequenceNumber) · \(section.title)", "CRN \(section.crn) · \(meeting.summary)"]
        if let place = meeting.buildingDescription ?? meeting.location { lines.append([place, meeting.room].compactMap { $0 }.joined(separator: " ")) }
        if !section.instructors.isEmpty { lines.append(section.instructors.joined(separator: ", ")) }
        lines.append(section.seatsAvailable > 0 ? "\(section.seatsAvailable) open seats" : "Full (\(section.seatsAvailable) seats)")
        return lines.joined(separator: "\n")
    }
}

/// A blocked time: hatched `panel2` with its label and time; clickable (editor popover) in "Block times" mode.
private struct ScheduleBlockTile: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var block: TimetableBlock
    var blockMode: Bool
    @Binding var isEditing: Bool
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.panel2Color)
            Canvas { context, size in
                var hatch = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    hatch.move(to: CGPoint(x: x, y: size.height)); hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 8
                }
                context.stroke(hatch, with: .color(theme.line2Color), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(blockMode && (hovering || isEditing) ? theme.accentColor : theme.line2Color, lineWidth: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.label.isEmpty ? "Blocked" : block.label)
                    .font(ThubanFont.body(11.5, weight: .semibold))
                    .foregroundStyle(theme.inkDimColor)
                Text(BannerClock.range(block.start, block.end))
                    .font(ThubanFont.mono(10.5))
                    .foregroundStyle(theme.inkFaintColor)
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(theme.panel2Color.opacity(0.85), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(3)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if blockMode { isEditing = true } }
        .allowsHitTesting(blockMode)
        .popover(isPresented: $isEditing, arrowEdge: .trailing) {
            ScheduleBlockEditor(block: block) { isEditing = false }
                .environment(app)
                .environment(\.thubanTheme, theme)
        }
        .help("\(block.label.isEmpty ? "Blocked" : block.label) · \(block.summary)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blocked time \(block.label) \(block.summary)")
        .accessibilityAddTraits(blockMode ? .isButton : [])
    }
}

/// Popover: rename, adjust or delete a blocked time.
private struct ScheduleBlockEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var block: TimetableBlock
    var dismiss: () -> Void
    @State private var label = ""
    @State private var day: BannerWeekday = .monday
    @State private var start = 0
    @State private var end = 0
    @FocusState private var labelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Blocked time")
            TextField("Label (e.g. Work)", text: $label)
                .thubanField(height: 32)
                .focused($labelFocused)
                .onSubmit { commit(); dismiss() }
            HStack(spacing: 8) {
                Picker("Day", selection: $day) {
                    ForEach(BannerWeekday.allCases) { Text($0.fullLabel).tag($0) }
                }
                .labelsHidden()
                .frame(width: 118)
                timePicker($start, label: "Start")
                Text("–").foregroundStyle(theme.inkDimColor)
                timePicker($end, label: "End")
            }
            HStack {
                Button(role: .destructive) {
                    app.scheduleTab.removeBlock(block.id)
                    dismiss()
                } label: {
                    HStack(spacing: 6) { Icon(.trash, size: 14); Text("Delete") }
                }
                .buttonStyle(GhostButtonStyle(height: 30))
                Spacer()
                Button("Done") { commit(); dismiss() }
                    .buttonStyle(PrimaryButtonStyle(height: 30))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(theme.panelColor)
        .onAppear {
            label = block.label
            day = block.day
            start = block.start
            end = block.end
            labelFocused = true
        }
        .onDisappear { commit() }
    }

    private func timePicker(_ value: Binding<Int>, label: String) -> some View {
        Picker(label, selection: value) {
            ForEach(Array(stride(from: 6 * 60, through: 23 * 60, by: 15)), id: \.self) { m in
                Text(BannerClock.label(m)).tag(m)
            }
            if value.wrappedValue % 15 != 0 || value.wrappedValue < 6 * 60 || value.wrappedValue > 23 * 60 {
                Text(BannerClock.label(value.wrappedValue)).tag(value.wrappedValue)
            }
        }
        .labelsHidden()
        .frame(width: 96)
        .accessibilityLabel(label)
    }

    private func commit() {
        guard app.scheduleTab.blocks.contains(where: { $0.id == block.id }) else { return }
        let updated = TimetableBlock(id: block.id, day: day, start: start, end: max(end, start + 15),
                                     label: label.trimmingCharacters(in: .whitespacesAndNewlines))
        if updated != block { app.scheduleTab.updateBlock(updated) }
    }
}
