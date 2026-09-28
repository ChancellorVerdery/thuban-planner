import SwiftUI
import ThubanPlannerCore

/// The class detail sheet, presented by the shell when `app.presentedCourseId` is set (Route box click, Planner row,
/// unplaceable chip). Status chip, serif code + credits, title; prerequisites and corequisites resolved to classes
/// (click one to follow it — "‹ Back" returns); "Required by"; facts; "Edit in Planner" and Done. Esc closes.
/// Spec: ARCHITECTURE.md ▸ "Class detail sheet". OWNER: Engineer B.
struct ClassDetailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var courseId: String

    /// Classes followed from this sheet (requirement / dependent clicks); the last one is shown.
    @State private var trail: [String] = []

    init(courseId: String) { self.courseId = courseId }

    private var shownId: String { trail.last ?? courseId }

    var body: some View {
        Group {
            if let course = app.course(shownId) {
                content(course)
            } else {
                EmptyState(icon: .info, title: "Class not found", message: "It may have been removed from your plan.") {
                    Button("Done") { dismiss() }.buttonStyle(.thubanPrimary).keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 600, height: 520)
        .background(theme.panelColor)
        .background {
            // Esc closes (the sheet has no Cancel button).
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).hidden()
        }
    }

    private func content(_ course: Course) -> some View {
        VStack(spacing: 0) {
            header(course)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 16)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        ClassDetailRequirementList(title: "Prerequisites", caption: "earlier term",
                                                   requirements: app.requirements(of: course).filter { $0.kind == .prereq },
                                                   open: follow)
                        ClassDetailRequirementList(title: "Corequisites", caption: "same term or earlier",
                                                   requirements: app.requirements(of: course).filter { $0.kind == .coreq },
                                                   open: follow)
                    }
                    requiredBy(course)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.automatic)
            Hairline()
            footer(course)
                .padding(.horizontal, 24)
                .frame(height: 64)
        }
    }

    // MARK: Header

    private func header(_ course: Course) -> some View {
        let chip = theme.statusChip(app.status(of: course.id))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !trail.isEmpty {
                    Button { trail.removeLast() } label: {
                        HStack(spacing: 4) {
                            Glyph(.chevronLeft, size: 11)
                            Text(app.course(trail.count > 1 ? trail[trail.count - 2] : courseId)?.displayCode ?? "Back")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.brassInkColor)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                Chip(chip.text, kind: chip.kind, dot: true)
                if course.summerOk {
                    Chip("Summer", kind: .neutral, icon: .sun)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(course.displayCode)
                    .font(ThubanFont.display(28))
                    .kerning(-0.28)
                    .foregroundStyle(theme.inkColor)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                Text("\(app.creditsText(course.credits)) credit\(course.credits == 1 ? "" : "s")")
                    .font(ThubanFont.body(15))
                    .foregroundStyle(theme.inkDimColor)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            Text(course.title.isEmpty ? "Untitled class" : course.title)
                .font(ThubanFont.body(15))
                .foregroundStyle(course.title.isEmpty ? theme.inkFaintColor : theme.inkColor)
                .lineLimit(2)
                .textSelection(.enabled)
            facts(course)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Taken in Fall 2024 · Offered in summer" and friends.
    private func facts(_ course: Course) -> some View {
        let when: String
        switch app.status(of: course.id) {
        case .taken(let key): when = "Taken in \(app.termLabel(key))"
        case .inProgress(let key): when = "In progress this term, \(app.termLabel(key))"
        case .planned(let key): when = "Planned for \(app.termLabel(key))"
        case .unplaceable: when = "Can’t be placed — check its prerequisites"
        case .unscheduled: when = "Taken in \(course.term.map(app.termLabel) ?? "an unlisted term") (not on your semester list)"
        }
        return HStack(spacing: 8) {
            Text(when)
            Text("·").foregroundStyle(theme.inkFaintColor)
            Text(course.summerOk ? "Offered in summer" : "Not offered in summer")
        }
        .font(ThubanFont.body(13))
        .foregroundStyle(theme.inkDimColor)
        .lineLimit(1)
    }

    // MARK: Required by

    @ViewBuilder
    private func requiredBy(_ course: Course) -> some View {
        let dependents = app.dependents(of: course)
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Required by", count: dependents.isEmpty ? nil : dependents.count)
            if dependents.isEmpty {
                Text("No class in your plan lists \(course.displayCode) as a requirement.")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkFaintColor)
            } else {
                ClassDetailFlow(spacing: 6) {
                    ForEach(dependents, id: \.course.id) { dependent in
                        ClassDetailDependentChip(course: dependent.course, kind: dependent.kind) { follow(dependent.course.id) }
                    }
                }
            }
        }
    }

    // MARK: Footer

    private func footer(_ course: Course) -> some View {
        HStack(spacing: 10) {
            Button {
                app.selectedCourseId = course.id
                // The Planner consumes the request: widens a filter / clears a search that hides the row, scrolls to
                // it and focuses its Code field.
                app.editRequestCourseId = course.id
                app.section = .planner
                app.presentedCourseId = nil
                dismiss()
            } label: {
                HStack(spacing: 7) { Icon(.edit, size: 15); Text("Edit in Planner") }
            }
            .buttonStyle(.thubanSecondary)
            .help("Show this class in the Planner's table")
            if app.routeTerm(of: course.id) != nil {
                Button {
                    app.selectedCourseId = course.id
                    app.presentedCourseId = nil
                    if app.section != .route { app.showRoute() }
                    dismiss()
                } label: {
                    HStack(spacing: 7) { Icon(.route, size: 15); Text("Show on route") }
                }
                .buttonStyle(.thubanGhost)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.thubanPrimary)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func follow(_ id: String) {
        guard id != shownId else { return }
        trail.append(id)
    }
}

// MARK: - Requirement list

/// "Prerequisites · earlier term" with one row per ref: code, title, status chip (click → that class); a ref that
/// names no class reads "not in your plan".
private struct ClassDetailRequirementList: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var caption: String
    var requirements: [ResolvedRequirement]
    var open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Eyebrow(title)
                Text(caption)
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkFaintColor)
                Spacer(minLength: 0)
            }
            if requirements.isEmpty {
                Text("None")
                    .font(ThubanFont.body(13))
                    .foregroundStyle(theme.inkFaintColor)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.lineColor, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            } else {
                VStack(spacing: 6) {
                    ForEach(requirements) { requirement in
                        ClassDetailRequirementRow(requirement: requirement, open: open)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ClassDetailRequirementRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var requirement: ResolvedRequirement
    var open: (String) -> Void
    @State private var hovering = false

    var body: some View {
        if let course = requirement.course {
            let chip = theme.statusChip(app.status(of: course.id))
            Button { open(course.id) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            // The ref as written in the class's list (Atlas shows it verbatim), not the match's code.
                            Text(requirement.ref)
                                .font(ThubanFont.mono(12.5, weight: .semibold))
                                .foregroundStyle(theme.inkColor)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Chip(chip.text, kind: chip.kind)
                                .fixedSize()
                        }
                        Text(course.title.isEmpty ? "Untitled class" : course.title)
                            .font(ThubanFont.body(12.5))
                            .foregroundStyle(theme.inkDimColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Glyph(.chevronRight, size: 10)
                        .foregroundStyle(theme.inkFaintColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(hovering ? theme.panel2Color : theme.bgColor,
                            in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Show \(course.displayCode)")
            .accessibilityLabel("\(course.displayName), \(chip.text)")
            .accessibilityHint("Shows this class")
        } else {
            HStack(spacing: 10) {
                Text(requirement.ref)
                    .font(ThubanFont.mono(12.5, weight: .semibold))
                    .italic()
                    .foregroundStyle(theme.inkFaintColor)
                Spacer(minLength: 6)
                Text("not in your plan")
                    .font(ThubanFont.body(12))
                    .italic()
                    .foregroundStyle(theme.inkFaintColor)
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(theme.lineColor, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(requirement.ref), not in your plan — ignored by the route")
        }
    }
}

// MARK: - Required by

private struct ClassDetailDependentChip: View {
    @Environment(\.thubanTheme) private var theme
    var course: Course
    var kind: RequirementKind
    var open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Text(course.displayCode).font(ThubanFont.mono(12, weight: .semibold)).foregroundStyle(theme.inkColor)
                if !course.title.isEmpty {
                    Text(course.title)
                        .font(ThubanFont.body(12.5))
                        .foregroundStyle(theme.inkDimColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 190, alignment: .leading)
                }
                Text(kind == .prereq ? "prereq" : "coreq")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(kind == .prereq ? theme.brassInkColor : theme.signalTextColor)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(hovering ? theme.panel2Color : theme.bgColor,
                        in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous)
                .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(course.displayName)
        .accessibilityLabel("\(course.displayName), needs this as a \(kind == .prereq ? "prerequisite" : "corequisite")")
    }
}

/// A simple wrapping row layout.
struct ClassDetailFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
