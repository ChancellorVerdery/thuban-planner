import AppKit
import SwiftUI
import ThubanPlannerCore

/// One class in the table: Code · Title · Cr · Prerequisites · Corequisites · Summer · Term · Route status · remove.
/// Text cells edit in place (draft committed on Return / focus loss, Esc reverts). Click selects; double-click opens
/// the class detail sheet.
struct PlannerClassRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var course: Course
    var columns: PlannerColumns
    var isSelected: Bool
    var focus: FocusState<PlannerFocus?>.Binding
    var state: PlannerViewState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: PlannerColumns.gap) {
            PlannerTextCell(value: course.code, placeholder: "CODE", mono: true, weight: .semibold,
                            focusValue: .cell(course.id, .code), focus: focus, rowActive: hovering || isSelected,
                            accessibility: "Code") { text in
                app.updateCourse(course.id, CoursePatch(code: text))
            }
            .frame(width: columns.code)

            PlannerTextCell(value: course.title, placeholder: "Title", focusValue: .cell(course.id, .title), focus: focus,
                            rowActive: hovering || isSelected, accessibility: "Title") { text in
                app.updateCourse(course.id, CoursePatch(title: text))
            }
            .overlay(alignment: .trailing) {
                // A class chosen in Technical electives (tagged "tech-elective").
                if course.tags?.contains(TechElectives.electiveTag) == true, focus.wrappedValue != .cell(course.id, .title) {
                    Text("TE")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(theme.brassInkColor)
                        .padding(.horizontal, 5)
                        .frame(height: 17)
                        .background(theme.accentTintColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.trailing, 6)
                        .allowsHitTesting(false)
                        .help("Technical elective")
                        .accessibilityLabel("Technical elective")
                }
            }
            .frame(width: columns.title)

            PlannerTextCell(value: app.creditsText(course.credits), placeholder: "0", mono: true, alignment: .trailing,
                            focusValue: .cell(course.id, .credits), focus: focus, rowActive: hovering || isSelected,
                            accessibility: "Credits",
                            validate: { AppModel.plannerParseCredits($0) != nil }) { text in
                if let value = AppModel.plannerParseCredits(text) { app.updateCourse(course.id, CoursePatch(credits: value)) }
            }
            .frame(width: columns.credits)

            PlannerRefsCell(refs: course.prereqs, kind: .prereq, focusValue: .cell(course.id, .prereqs), focus: focus,
                            rowActive: hovering || isSelected, width: columns.prereqs) { text in
                app.setPrereqs(of: course.id, text: text)
            }
            .frame(width: columns.prereqs)
            .zIndex(focus.wrappedValue == .cell(course.id, .prereqs) ? 1 : 0)

            PlannerRefsCell(refs: course.coreqs, kind: .coreq, focusValue: .cell(course.id, .coreqs), focus: focus,
                            rowActive: hovering || isSelected, width: columns.coreqs) { text in
                app.setCoreqs(of: course.id, text: text)
            }
            .frame(width: columns.coreqs)
            .zIndex(focus.wrappedValue == .cell(course.id, .coreqs) ? 1 : 0)

            PlannerCheckbox(isOn: course.summerOk, label: "Offered in summer") {
                app.updateCourse(course.id, CoursePatch(summerOk: !course.summerOk))
            }
            .frame(width: columns.summer)

            PlannerTermMenu(course: course)
                .frame(width: columns.term, alignment: .leading)

            statusChip
                .frame(width: columns.status, alignment: .leading)

            removeButton
                .frame(width: columns.remove)
        }
        .padding(.horizontal, PlannerColumns.inset)
        .frame(height: PlannerColumns.rowHeight)
        .background(rowFill)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(theme.accentColor).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            select()
            app.presentCourse(course.id)
        }
        .onTapGesture { select() }
        .onHover { hovering = $0 }
        .plannerCardSides()
        .thubanHairline(.top, color: theme.lineColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(course.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu {
            Button("Show details") { app.presentCourse(course.id) }
            Button("Edit code") { select(); focus.wrappedValue = .cell(course.id, .code) }
            Menu("Term") {
                Button("To take") { app.setTerm(of: course.id, to: nil) }
                Divider()
                Button("Transfer credit") { app.setTerm(of: course.id, to: TermKey.transfer) }
                if !app.terms.isEmpty { Divider() }
                ForEach(app.terms) { term in Button(term.label) { app.setTerm(of: course.id, to: term.key) } }
            }
            Divider()
            Button("Remove class…", role: .destructive) { state.pendingRemovalCourseId = course.id }
        }
    }

    private var rowFill: Color {
        if isSelected { return theme.accentTintColor }
        if hovering { return theme.panel2Color.opacity(0.5) }
        return theme.panelColor
    }

    private func select() {
        app.selectedCourseId = course.id
        if focus.wrappedValue?.courseId != course.id { focus.wrappedValue = .table }
    }

    private var statusChip: some View {
        let status = theme.statusChip(app.status(of: course.id))
        return Button { app.presentCourse(course.id) } label: {
            Chip(status.text, kind: status.kind, dot: status.kind == .signal)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .help("Show \(course.displayName)")
        .accessibilityLabel("Route status: \(status.text). Show details")
    }

    private var removeButton: some View {
        IconButton(.trash, label: "Remove \(course.displayName)", size: 28, iconSize: 15) {
            state.pendingRemovalCourseId = course.id
        }
        .opacity(hovering || isSelected ? 1 : 0)
    }
}

// MARK: - Text cell

/// A table cell that reads as text and edits in place: plain until the row is hovered (faint border) or the cell is
/// focused (panel fill, accent border). Keeps a local draft; commits on Return / focus loss; Esc reverts.
struct PlannerTextCell: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var value: String
    var placeholder: String
    var mono: Bool = false
    var weight: Font.Weight = .regular
    var alignment: TextAlignment = .leading
    var focusValue: PlannerFocus
    var focus: FocusState<PlannerFocus?>.Binding
    var rowActive: Bool
    var accessibility: String
    var validate: (String) -> Bool = { _ in true }
    /// Put the cursor at the end (and scroll there) when the cell takes focus, instead of selecting from the start.
    var cursorAtEnd: Bool = false
    var commit: (String) -> Void
    @State private var draft = ""
    @State private var loaded = false

    private var isFocused: Bool { focus.wrappedValue == focusValue }

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .font(mono ? ThubanFont.mono(13 * textScale, weight: weight) : ThubanFont.body(14 * textScale, weight: weight))
            .monospacedDigit()
            .multilineTextAlignment(alignment)
            .foregroundStyle(theme.inkColor)
            .lineLimit(1)
            .focused(focus, equals: focusValue)
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(isFocused ? theme.panelColor : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(border, lineWidth: isFocused ? 1.5 : ThubanMetrics.hairline))
            .accessibilityLabel(accessibility)
            .onAppear {
                if !loaded { draft = value; loaded = true }
            }
            .onChange(of: value) { _, fresh in
                if !isFocused { draft = fresh }
            }
            .onChange(of: isFocused) { was, now in
                if was && !now { commitDraft() }
                if now && !was && cursorAtEnd { PlannerFieldEditor.moveCursorToEnd() }
            }
            // A section switch, "Calculate route", ⌘R… removes the Planner while a cell may still be first responder:
            // its focus-loss commit would never run. Commit whatever was typed when the cell goes away or the app quits.
            .onDisappear { commitDraft() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                commitDraft()
            }
            .onSubmit {
                commitDraft()
                focus.wrappedValue = .table
            }
            .onExitCommand {
                draft = value
                focus.wrappedValue = .table
            }
    }

    private var border: Color {
        if isFocused { return validate(draft) ? theme.accentColor : theme.negColor }
        return rowActive ? theme.line2Color : .clear
    }

    private func commitDraft() {
        guard loaded, draft != value else { return }
        if validate(draft) { commit(draft) } else { draft = value }
    }
}

// MARK: - Requirement refs cell

/// Prerequisites / corequisites: shown as chips (a resolved ref as a small mono chip, an unknown one in faint
/// italic); click or Tab in → a comma-separated text field.
struct PlannerRefsCell: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var refs: [String]
    var kind: RequirementKind
    var focusValue: PlannerFocus
    var focus: FocusState<PlannerFocus?>.Binding
    var rowActive: Bool
    var width: CGFloat
    var commit: (String) -> Void

    private var isFocused: Bool { focus.wrappedValue == focusValue }

    var body: some View {
        ZStack(alignment: .leading) {
            PlannerTextCell(value: AppModel.plannerRefsText(refs), placeholder: kind == .prereq ? "MATH 1241, …" : "Codes, …",
                            mono: true, focusValue: focusValue, focus: focus, rowActive: rowActive && refs.isEmpty,
                            accessibility: kind == .prereq ? "Prerequisites" : "Corequisites", cursorAtEnd: true,
                            commit: commit)
                // While editing, the field widens over the next columns to show the whole list.
                .frame(width: isFocused ? editWidth : width, alignment: .leading)
                .opacity(isFocused ? 1 : 0)
            if !isFocused {
                chips
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { focus.wrappedValue = focusValue }
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: 30, alignment: .leading)
        .zIndex(isFocused ? 1 : 0)
    }

    /// Room for the whole comma-separated list (monospaced), up to the cell plus about two more columns.
    private var editWidth: CGFloat {
        let text = AppModel.plannerRefsText(refs)
        let needed = CGFloat(text.count + 4) * 7.9 * textScale + 16
        return min(max(width, needed), width + 300)
    }

    @ViewBuilder
    private var chips: some View {
        if refs.isEmpty {
            Text(rowActive ? "Add…" : "—")
                .font(ThubanFont.body(13 * textScale))
                .foregroundStyle(theme.inkFaintColor)
                .padding(.horizontal, 7)
        } else {
            let fit = fitting
            HStack(spacing: 4) {
                ForEach(Array(refs.prefix(fit).enumerated()), id: \.offset) { _, ref in
                    refChip(ref)
                }
                if fit < refs.count {
                    Text("+\(refs.count - fit)")
                        .font(ThubanFont.mono(11.5 * textScale, weight: .semibold))
                        .foregroundStyle(theme.inkDimColor)
                        .help(refs.dropFirst(fit).joined(separator: ", "))
                }
            }
            .padding(.horizontal, 5)
            .overlay(alignment: .leading) {
                if rowActive {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline)
                        .frame(width: width, height: 28)
                }
            }
        }
    }

    @ViewBuilder
    private func refChip(_ ref: String) -> some View {
        if let target = app.course(forRef: ref) {
            Text(ref)
                .font(ThubanFont.mono(11.5 * textScale, weight: .medium))
                .foregroundStyle(chipInk(target))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(chipFill(target), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .help("\(target.displayName) · \(theme.statusChip(app.status(of: target.id)).text)")
        } else {
            Text(ref)
                .font(ThubanFont.mono(11.5 * textScale).italic())
                .foregroundStyle(theme.inkFaintColor)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 2)
                .help("\(ref) isn’t in your plan, so it’s ignored")
        }
    }

    private func chipFill(_ target: Course) -> Color {
        target.isTaken ? theme.posSoftColor : theme.panel2Color
    }

    private func chipInk(_ target: Course) -> Color {
        target.isTaken ? theme.posTextColor : theme.inkDimColor
    }

    /// How many chips fit the cell (monospaced text makes the estimate exact enough); the rest become "+N".
    private var fitting: Int {
        let charWidth = 6.95 * textScale
        var used: CGFloat = 10
        for (index, ref) in refs.enumerated() {
            let w = CGFloat(ref.count) * charWidth + 12 + (index > 0 ? 4 : 0)
            let reserve: CGFloat = index < refs.count - 1 ? 30 : 0
            if used + w + reserve > width { return max(index, 1) }
            used += w
        }
        return refs.count
    }
}

// MARK: - Checkbox

/// A 16 pt check box in theme colours.
struct PlannerCheckbox: View {
    @Environment(\.thubanTheme) private var theme
    var isOn: Bool
    var label: String
    var toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isOn ? theme.accentColor : (hovering ? theme.panel2Color.opacity(0.7) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isOn ? theme.accentColor : theme.inkFaintColor.opacity(0.7), lineWidth: 1))
                .overlay { if isOn { Icon(.check, size: 12).foregroundStyle(theme.onAccentColor) } }
                .frame(width: 16, height: 16)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "yes" : "no")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .help(label)
    }
}

// MARK: - Term menu

/// "To take", "Transfer credit", then every recorded semester.
struct PlannerTermMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var course: Course
    @State private var hovering = false

    var body: some View {
        Menu {
            Button { app.setTerm(of: course.id, to: nil) } label: {
                if course.term == nil { Label("To take", systemImage: "checkmark") } else { Text("To take") }
            }
            Divider()
            Button { app.setTerm(of: course.id, to: TermKey.transfer) } label: {
                if course.isTransfer { Label("Transfer credit", systemImage: "checkmark") } else { Text("Transfer credit") }
            }
            if !app.terms.isEmpty { Divider() }
            ForEach(app.terms) { term in
                Button { app.setTerm(of: course.id, to: term.key) } label: {
                    let title = term.label + (term.current ? " (current)" : "")
                    if course.term == term.key { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if course.term.flatMap(app.term)?.current == true {
                    Circle().fill(theme.signalColor).frame(width: 6, height: 6)
                } else if course.isTransfer {
                    Icon(.transfer, size: 12).foregroundStyle(theme.posTextColor)
                }
                Text(labelText)
                    .font(ThubanFont.body(13, weight: course.term == nil ? .regular : .medium))
                    .foregroundStyle(course.term == nil ? theme.inkDimColor : theme.inkColor)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Glyph(.chevronDown, size: 10).foregroundStyle(theme.inkFaintColor)
            }
            .padding(.horizontal, 8)
            .frame(width: 124, height: 28)
            .background(hovering ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(hovering ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .accessibilityLabel("Term")
        .accessibilityValue(labelText)
        .help("Which term you took it in, Transfer credit (AP, dual enrollment, another college) — or To take, for the planner to place")
    }

    private var labelText: String {
        guard let key = course.term else { return "To take" }
        return TermKey.isTransfer(key) ? "Transfer" : app.termLabel(key)
    }
}

// MARK: - Field editor

enum PlannerFieldEditor {
    /// Moves the key window's field editor cursor to the end of its text and scrolls it into view (the list fields
    /// otherwise open scrolled to the start, cutting the last code in half).
    @MainActor
    static func moveCursorToEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
            let end = (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: end, length: 0))
            editor.scrollRangeToVisible(NSRange(location: end, length: 0))
        }
    }
}
