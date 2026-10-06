import SwiftUI
import ThubanPlannerCore

/// The board drawing: column cards, ribbons, boxes — one `Canvas`, in board points under a zoom / pan transform, so
/// text and strokes stay vector-sharp at every zoom and 60+ classes redraw in well under a frame. `scale` and `offset`
/// are animatable, so Fit / toolbar zoom glide instead of jumping. Pure drawing: no state, no hit testing (that is
/// `RouteLayout.box(at:)`). OWNER: Engineer B.
struct RouteCanvasLayer: View, Animatable {
    var layout: RouteLayout
    var labels: [String: RouteBoxLabel]
    var scale: CGFloat
    var offset: CGSize
    /// The class whose chain is emphasized (hovered, keyboard-focused or selected); nil = no emphasis.
    var focusId: String?
    var selectedId: String?
    var chain: RouteChain?
    var gradKey: String?
    var theme: ResolvedTheme

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(scale, AnimatablePair(offset.width, offset.height)) }
        set {
            scale = newValue.first
            offset = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        let palette = RoutePalette(theme)
        Canvas(rendersAsynchronously: false) { context, size in
            guard !layout.isEmpty, scale > 0 else { return }
            var ctx = context
            ctx.translateBy(x: offset.width, y: offset.height)
            ctx.scaleBy(x: scale, y: scale)
            let visible = CGRect(x: -offset.width / scale, y: -offset.height / scale,
                                 width: size.width / scale, height: size.height / scale).insetBy(dx: -40, dy: -40)
            let hair = 1 / scale
            drawColumns(ctx, palette: palette, visible: visible, hair: hair)
            drawRibbons(ctx, palette: palette, hair: hair)
            drawBoxes(ctx, palette: palette, visible: visible, hair: hair)
        }
        .accessibilityHidden(true)
    }

    // MARK: Columns

    private func drawColumns(_ ctx: GraphicsContext, palette: RoutePalette, visible: CGRect, hair: CGFloat) {
        for column in layout.columns where column.frame.intersects(visible) {
            let kind = column.term.kind
            let card = Path(roundedRect: column.frame, cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
            ctx.fill(card, with: .color(palette.columnFill(kind)))
            ctx.stroke(card, with: .color(palette.columnBorder(kind)), lineWidth: kind == .current ? 1.5 * hair : hair)

            let x = column.frame.minX + 14
            let y = column.frame.minY + 13
            let labelInk = kind == .past ? palette.inkDim : (kind == .transfer ? palette.posText : palette.ink)
            ctx.draw(Text(column.term.label).font(ThubanFont.display(16)).foregroundColor(labelInk),
                     at: CGPoint(x: x, y: y), anchor: .topLeading)
            ctx.draw(Text(theme.termCaption(column.term)).font(.system(size: 12)).monospacedDigit()
                        .foregroundColor(kind == .current ? palette.signalText : (kind == .transfer ? palette.posText : palette.inkDim)),
                     at: CGPoint(x: x, y: y + 23), anchor: .topLeading)

            // A quiet tag on the right: NOW on the current term, GRADUATE on the last planned one.
            let tag: (String, Color)? = kind == .current ? ("NOW", palette.signalText)
                : (column.term.key == gradKey && kind == .future ? ("FINISH", palette.brassInk) : nil)
            if let (text, color) = tag {
                let tx = column.frame.maxX - 14
                ctx.draw(Text(text).font(.system(size: 10.5, weight: .semibold)).kerning(0.8).foregroundColor(color),
                         at: CGPoint(x: tx, y: y + 4), anchor: .topTrailing)
                if kind == .current {
                    let dot = CGRect(x: tx - 40, y: y + 7, width: 6, height: 6)
                    ctx.fill(Path(ellipseIn: dot), with: .color(palette.signal))
                }
            }
        }
    }

    // MARK: Ribbons

    private func drawRibbons(_ ctx: GraphicsContext, palette: RoutePalette, hair: CGFloat) {
        let emphasis = chain != nil
        // Dimmed ribbons first, the chain's on top.
        for pass in 0..<(emphasis ? 2 : 1) {
            for (index, ribbon) in layout.ribbons.enumerated() {
                let onChain = chain?.ribbons.contains(index) ?? false
                if emphasis, (pass == 0) == onChain { continue }
                var path = Path()
                path.move(to: ribbon.start)
                for segment in ribbon.segments {
                    path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
                }
                let color: Color
                var style = theme.ribbonStyle(ribbon.kind, scale: hair)
                if emphasis && onChain {
                    color = palette.ribbonEmphasis(ribbon.kind)
                    style.lineWidth *= 1.35
                } else if emphasis {
                    color = palette.ribbon(ribbon.kind).opacity(0.25)
                } else {
                    color = palette.ribbon(ribbon.kind)
                }
                ctx.stroke(path, with: .color(color), style: style)
                // A small arrowhead where the ribbon meets the class that needs it.
                let dx = ribbon.end.x - ribbon.arrowControl.x
                let dir: CGFloat = dx >= 0 ? 1 : -1
                let head = 5 * min(1.4, max(0.9, hair * 1.1))
                var arrow = Path()
                arrow.move(to: ribbon.end)
                arrow.addLine(to: CGPoint(x: ribbon.end.x - dir * head * 1.2, y: ribbon.end.y - head * 0.75))
                arrow.addLine(to: CGPoint(x: ribbon.end.x - dir * head * 1.2, y: ribbon.end.y + head * 0.75))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(color))
            }
        }
    }

    // MARK: Boxes

    private func drawBoxes(_ ctx: GraphicsContext, palette: RoutePalette, visible: CGRect, hair: CGFloat) {
        let pad = RouteText.boxPadding
        for box in layout.boxes where box.rect.intersects(visible) {
            guard let label = labels[box.courseId] else { continue }
            let r = box.rect
            let isFocus = box.courseId == focusId || box.courseId == selectedId
            let dimmed = chain.map { !$0.courseIds.contains(box.courseId) } ?? false
            let shape = Path(roundedRect: r, cornerRadius: 7, style: .continuous)
            // The fill is always opaque, so ribbons running beneath never show through a box (faded or not). A faded
            // box blends its fill into the column card and fades only its border and text.
            var c = ctx
            if dimmed {
                ctx.fill(shape, with: .color(palette.columnFill(box.kind)))
                var tint = ctx
                tint.opacity = 0.5
                tint.fill(shape, with: .color(palette.boxFill(box.kind)))
                c.opacity = palette.fadedOpacity
            } else {
                ctx.fill(shape, with: .color(palette.opaqueBase))
                c.fill(shape, with: .color(isFocus ? palette.accentTint : palette.boxFill(box.kind)))
            }
            c.stroke(shape, with: .color(isFocus ? palette.accent : palette.boxBorder(box.kind)),
                     lineWidth: isFocus ? 1.5 * hair : hair)
            if box.kind == .current && !isFocus {
                // The current term's classes carry a signal bar on the leading edge.
                var bar = c
                bar.clip(to: shape)
                bar.fill(Path(CGRect(x: r.minX, y: r.minY, width: 3, height: r.height)), with: .color(palette.signal))
            }

            let top = r.minY + (r.height < 50 ? 6 : 9)
            c.draw(Text(label.code).font(RouteText.codeFont).foregroundColor(palette.code(box.kind)),
                   at: CGPoint(x: r.minX + pad, y: top), anchor: .topLeading)

            // Credits, right-aligned: an accent badge on planned classes, plain text otherwise (a check when done).
            let creditPoint = CGPoint(x: r.maxX - pad, y: top + 0.5)
            if box.kind == .future {
                let w = RouteText.width(label.credits, .monospacedSystemFont(ofSize: RouteText.creditSize, weight: .semibold)) + 12
                let badge = CGRect(x: r.maxX - pad + 4 - w, y: top - 2, width: w, height: 17)
                c.fill(Path(roundedRect: badge, cornerRadius: 5, style: .continuous), with: .color(palette.accentTint))
                c.draw(Text(label.credits).font(RouteText.creditFont).foregroundColor(palette.brassInk),
                       at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)
            } else {
                c.draw(Text(label.credits).font(RouteText.creditFont)
                        .foregroundColor(box.kind == .current ? palette.signalText : palette.inkFaint),
                       at: creditPoint, anchor: .topTrailing)
            }

            let titleY = top + (r.height < 50 ? 16 : 19)
            c.draw(Text(label.title).font(RouteText.titleFont).foregroundColor(palette.title(box.kind)),
                   at: CGPoint(x: r.minX + pad, y: titleY), anchor: .topLeading)

            if let needs = label.needs, r.height >= 66 {
                c.draw(Text(needs).font(RouteText.needsFont).foregroundColor(palette.inkFaint),
                       at: CGPoint(x: r.minX + pad, y: r.maxY - 8), anchor: .bottomLeading)
            }
        }
    }
}

/// Theme colours resolved once per render (the token accessors parse hex strings).
struct RoutePalette {
    let ink, inkDim, inkFaint, accent, accentTint, brassInk, signal, signalText, posText: Color
    /// An opaque colour laid under every box fill.
    let opaqueBase: Color
    /// Border / text opacity of a box off the emphasized chain (higher in dark mode, where dim ink sinks into the bg).
    let fadedOpacity: Double
    private let columnFills: [TermKind: Color]
    private let columnBorders: [TermKind: Color]
    private let boxFills: [TermKind: Color]
    private let boxBorders: [TermKind: Color]
    private let codes: [TermKind: Color]
    private let titles: [TermKind: Color]
    private let prereq, coreq, prereqStrong, coreqStrong: Color

    init(_ theme: ResolvedTheme) {
        ink = theme.inkColor
        inkDim = theme.inkDimColor
        inkFaint = theme.inkFaintColor
        accent = theme.accentColor
        accentTint = theme.accentTintColor
        brassInk = theme.brassInkColor
        signal = theme.signalColor
        signalText = theme.signalTextColor
        posText = theme.posTextColor
        opaqueBase = theme.bgColor
        fadedOpacity = theme.isDark ? 0.5 : 0.36
        let kinds: [TermKind] = [.past, .current, .future, .transfer]
        columnFills = Dictionary(uniqueKeysWithValues: kinds.map { ($0, theme.routeColumnFill($0)) })
        columnBorders = Dictionary(uniqueKeysWithValues: kinds.map { ($0, theme.routeColumnBorder($0)) })
        boxFills = Dictionary(uniqueKeysWithValues: kinds.map { ($0, theme.routeBoxFill($0)) })
        boxBorders = Dictionary(uniqueKeysWithValues: kinds.map { ($0, theme.routeBoxBorder($0)) })
        codes = Dictionary(uniqueKeysWithValues: kinds.map { ($0, theme.routeBoxCodeInk($0)) })
        titles = Dictionary(uniqueKeysWithValues: kinds.map { ($0, theme.routeBoxTitleInk($0)) })
        prereq = theme.ribbonColor(.prereq)
        coreq = theme.ribbonColor(.coreq)
        prereqStrong = theme.routeRibbonEmphasis(.prereq)
        coreqStrong = theme.routeRibbonEmphasis(.coreq)
    }

    func columnFill(_ k: TermKind) -> Color { columnFills[k]! }
    func columnBorder(_ k: TermKind) -> Color { columnBorders[k]! }
    func boxFill(_ k: TermKind) -> Color { boxFills[k]! }
    func boxBorder(_ k: TermKind) -> Color { boxBorders[k]! }
    func code(_ k: TermKind) -> Color { codes[k]! }
    func title(_ k: TermKind) -> Color { titles[k]! }
    func ribbon(_ k: RequirementKind) -> Color { k == .prereq ? prereq : coreq }
    func ribbonEmphasis(_ k: RequirementKind) -> Color { k == .prereq ? prereqStrong : coreqStrong }
}
