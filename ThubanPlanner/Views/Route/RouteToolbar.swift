import SwiftUI
import ThubanPlannerCore

/// The Route's section-bar toolbar: legend (Taken · Current · Planned; prerequisite solid, corequisite dashed) | zoom
/// − / level / + · Fit (⌘0). OWNER: Engineer B.
struct RouteToolbar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 14) {
                if app.schedule.transferColumn != nil {
                    RouteLegendSwatch(kind: .transfer, label: "Transfer")
                }
                RouteLegendSwatch(kind: .past, label: "Taken")
                RouteLegendSwatch(kind: .current, label: "Current")
                RouteLegendSwatch(kind: .future, label: "Planned")
                RouteLegendRibbon(kind: .prereq, label: "Prerequisite")
                RouteLegendRibbon(kind: .coreq, label: "Corequisite")
            }
            .padding(.trailing, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Legend: transfer credit, taken, current and planned terms; prerequisites solid, corequisites dashed")

            ToolbarDivider()

            IconButton(.zoomOut, label: "Zoom out", size: 30, iconSize: 16) { app.routeZoom(by: 0.8) }
                .disabled(app.routeZoom <= AppModel.routeZoomRange.lowerBound + 0.0001)
            Button { app.routeFitRequest += 1 } label: {
                Text("\(Int((app.routeScale * 100).rounded()))%")
                    .font(ThubanFont.mono(12, weight: .medium))
                    .foregroundStyle(theme.inkDimColor)
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Board scale (100% = actual size). Click to fit.")
            .accessibilityLabel("Zoom \(Int((app.routeScale * 100).rounded())) percent")
            IconButton(.zoomIn, label: "Zoom in", size: 30, iconSize: 16) { app.routeZoom(by: 1.25) }
                .disabled(app.routeZoom >= AppModel.routeZoomRange.upperBound - 0.0001)
            ToolbarButton("Fit", icon: .fit) { app.routeFitRequest += 1 }
                .help("Fit the whole route (⌘0)")
        }
        .disabled(app.schedule.columns.isEmpty)
    }
}

/// A term-kind swatch: a tiny column card in the term's fill and border.
private struct RouteLegendSwatch: View {
    @Environment(\.thubanTheme) private var theme
    var kind: TermKind
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            // A column in miniature: the term's fill with a box in the board's box colours inside, framed by the
            // term border at full strength so every kind reads against the section bar.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(theme.termFill(kind))
                .overlay(
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(kind == .current ? theme.signalColor : kind == .transfer ? theme.posColor
                              : (kind == .past ? theme.inkFaintColor : theme.brassInkColor))
                        .padding(3.5)
                )
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(kind == .current ? theme.signalColor : kind == .transfer ? theme.posColor.opacity(0.6) : theme.line2Color, lineWidth: 1))
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkDimColor)
        }
    }
}

/// A ribbon sample: a short stroke in the ribbon's colour and dash.
private struct RouteLegendRibbon: View {
    @Environment(\.thubanTheme) private var theme
    var kind: RequirementKind
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            Path { p in
                p.move(to: CGPoint(x: 1, y: 7))
                p.addCurve(to: CGPoint(x: 21, y: 3), control1: CGPoint(x: 11, y: 7), control2: CGPoint(x: 11, y: 3))
            }
            .stroke(theme.routeRibbonEmphasis(kind).opacity(kind == .prereq ? 0.75 : 0.9), style: theme.ribbonStyle(kind))
            .frame(width: 22, height: 10)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkDimColor)
        }
    }
}
