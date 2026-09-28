import SwiftUI
import ThubanPlannerCore

/// The Route section (⌘2): a header strip (where the route ends, the plan status, a graduation summary, warnings),
/// the zoomable board, and a strip of classes that can't be placed. Spec: ARCHITECTURE.md ▸ "Route".
/// OWNER: Engineer B.
struct RouteView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let layout = RouteLayout.make(schedule: app.schedule, courses: app.courses, metrics: Self.metrics)
        VStack(spacing: 0) {
            RouteHeaderStrip()
            if layout.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .thubanHairline(.top, color: theme.lineColor)
            } else {
                RouteBoard(layout: layout, labels: RouteText.labels(layout: layout, app: app))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.bgColor)
                    .thubanHairline(.top, color: theme.lineColor)
            }
            if !app.routeUnplaceable.isEmpty {
                RouteUnplaceableStrip(courses: app.routeUnplaceable)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bgColor)
    }

    /// Board metrics: a little narrower than the core defaults so a four-year plan fits a laptop screen legibly.
    static let metrics: RouteLayout.Metrics = {
        var m = RouteLayout.Metrics()
        m.columnWidth = 200
        m.gutter = 40
        m.boxInset = 10
        m.headerHeight = 56
        m.padding = 28
        return m
    }()

    @ViewBuilder
    private var emptyState: some View {
        if app.routeUnplaceable.isEmpty {
            EmptyState(icon: .route, title: "No route yet", message: "Add classes on the Planner — the route draws here.") {
                Button { app.section = .planner } label: {
                    HStack(spacing: 7) { Icon(.planner, size: 15); Text("Open Planner") }
                }
                .buttonStyle(.thubanSecondary)
            }
        } else {
            EmptyState(icon: .route, title: "Nothing could be placed",
                       message: "None of your classes to take fit a term — check for missing prerequisites or a prerequisite cycle.") {
                Button { app.section = .planner } label: {
                    HStack(spacing: 7) { Icon(.planner, size: 15); Text("Open Planner") }
                }
                .buttonStyle(.thubanSecondary)
            }
        }
    }
}

// MARK: - Header strip

/// Serif "Finishing Spring 2028" + the plan status on the left, the graduation summary on the right, warnings below.
private struct RouteHeaderStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow("Route")
                    Text(app.routeTitle)
                        .font(ThubanFont.display(28))
                        .kerning(-0.28)
                        .foregroundStyle(theme.inkColor)
                        .accessibilityAddTraits(.isHeader)
                    Text(app.planStatus)
                        .font(ThubanFont.scaled(14, scale: textScale))
                        .foregroundStyle(theme.inkDimColor)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 16)
                if app.creditsTotal > 0 { summary }
            }
            ForEach(Array(app.warnings.enumerated()), id: \.offset) { _, warning in
                HStack(spacing: 10) {
                    Circle().fill(theme.negColor).frame(width: 7, height: 7)
                    Text(warning)
                        .font(ThubanFont.scaled(13, scale: textScale))
                        .foregroundStyle(theme.negTextColor)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(theme.negSoftColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// Graduation summary: credits done (with a bar), terms left, finish term.
    private var summary: some View {
        HStack(alignment: .top, spacing: 0) {
            metric(label: "Credits done", value: app.creditsText(app.creditsTaken), unit: "of \(app.creditsText(app.creditsTotal))") {
                ProgressBar(value: app.routeCreditsDoneFraction, height: 4).frame(width: 128).padding(.top, 2)
            }
            divider
            metric(label: "Terms left", value: String(app.schedule.termsToFinish),
                   unit: app.schedule.termsToFinish == 1 ? "term" : "terms") { EmptyView() }
            divider
            metric(label: app.toTake.isEmpty ? "Finished" : "Finishes", value: app.gradTermLabel ?? "—", unit: nil) {
                if !app.toTake.isEmpty {
                    Text("\(app.creditsText(app.creditsToTake)) credits to go")
                        .font(ThubanFont.body(12))
                        .foregroundStyle(theme.inkFaintColor)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }

    private var divider: some View {
        Rectangle().fill(theme.lineColor).frame(width: ThubanMetrics.hairline, height: 44).padding(.horizontal, 18)
    }

    private func metric<Footer: View>(label: String, value: String, unit: String?, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(ThubanFont.body(12, weight: .semibold))
                .foregroundStyle(theme.inkDimColor)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(ThubanFont.display(22))
                    .foregroundStyle(theme.inkColor)
                    .monospacedDigit()
                if let unit {
                    Text(unit).font(ThubanFont.body(13)).foregroundStyle(theme.inkDimColor).monospacedDigit()
                }
            }
            footer()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Unplaceable strip

/// "Can't be placed" + one `neg` chip per class (click → class detail sheet).
private struct RouteUnplaceableStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var courses: [Course]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Can’t be placed")
                .font(ThubanFont.body(13, weight: .semibold))
                .foregroundStyle(theme.negTextColor)
                .fixedSize()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(courses) { course in
                        Button { app.presentCourse(course.id) } label: {
                            HStack(spacing: 6) {
                                Text(course.displayCode).font(ThubanFont.mono(12, weight: .semibold))
                                Text(course.title).font(.system(size: 12))
                                    .opacity(0.85)
                            }
                            .lineLimit(1)
                            .thubanChip(kind: .neg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(app.routeTooltip(course.id))
                        .accessibilityLabel("\(course.displayName), can’t be placed")
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Check for missing prerequisites or a cycle")
                .font(ThubanFont.body(12))
                .foregroundStyle(theme.inkFaintColor)
                .fixedSize()
        }
        .padding(.horizontal, 28)
        .frame(height: 48)
        .background(theme.panelColor)
        .thubanHairline(.top, color: theme.lineColor)
    }
}
