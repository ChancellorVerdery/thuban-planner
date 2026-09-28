import SwiftUI
import ThubanPlannerCore

/// The zoomable, pannable board: the canvas drawing, the AppKit input surface on top of it (scroll / ⌘-scroll /
/// pinch / drag / click / hover / arrows), the hover tooltip, and the zoom state. `app.routeZoom` mirrors the level
/// relative to "fitted" (1 = the whole board fits); `app.routeFitRequest` bumps glide back to fitted. OWNER: Engineer B.
struct RouteBoard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var layout: RouteLayout
    var labels: [String: RouteBoxLabel]

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var viewport: CGSize = .zero
    /// True while the board shows the fitted view (window resizes keep it fitted).
    @State private var fitted = true
    @State private var hoverId: String?
    @State private var focusId: String?
    /// The last `routeZoom` this view wrote, to tell its own writes from the toolbar's.
    @State private var writtenZoom: Double = 1

    private static let fitAnimation = Animation.smooth(duration: 0.38)

    var body: some View {
        GeometryReader { geometry in
            let emphasisId = hoverId ?? focusId ?? boardSelection
            let chain = emphasisId.map { layout.chain(of: $0) }
            ZStack(alignment: .topLeading) {
                RouteCanvasLayer(layout: layout, labels: labels, scale: scale, offset: offset,
                                 focusId: hoverId ?? focusId, selectedId: boardSelection,
                                 chain: chain, gradKey: app.schedule.gradTerm, theme: theme)
                RouteInputView(handlers: handlers)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Route board")
                    .accessibilityChildren { accessibilityBoxes }
                tooltip
            }
            .clipped()
            .onAppear { viewport = geometry.size; fit(animated: false); applyExternalZoom(animated: false) }
            .onChange(of: geometry.size) { _, size in
                viewport = size
                if fitted {
                    fit(animated: false)
                } else {
                    clampOffset()
                    // The fitted scale moved with the window: keep the toolbar's level (relative to it) true.
                    syncZoomLevel()
                }
            }
        }
        .onChange(of: app.routeFitRequest) { _, _ in fit(animated: true) }
        .onChange(of: app.routeZoom) { _, _ in applyExternalZoom(animated: true) }
        .onChange(of: layout.size) { _, _ in if fitted { fit(animated: true) } else { clampOffset() } }
        .onChange(of: layout) { _, newLayout in
            if let id = hoverId, newLayout.box(id) == nil { hoverId = nil }
            if let id = focusId, newLayout.box(id) == nil { focusId = nil }
        }
    }

    /// The Planner's selection, when that class is on the board.
    private var boardSelection: String? {
        guard let id = app.selectedCourseId, layout.box(id) != nil else { return nil }
        return id
    }

    // MARK: Geometry

    /// Board scale below which box text (12–12.5 pt) drops under ~10 pt on screen.
    private static let minReadableScale: CGFloat = 0.8

    /// The "fitted" scale: the whole board when that stays readable; otherwise the smallest readable scale, and the
    /// board scrolls (starting at the current term). Zooming out further still shows the whole board.
    private var fitScale: CGFloat {
        max(Self.minReadableScale, layout.fitScale(in: viewport, maxScale: 1))
    }

    private func boardPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.width) / scale, y: (p.y - offset.height) / scale)
    }

    private func viewRect(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX * scale + offset.width, y: r.minY * scale + offset.height,
               width: r.width * scale, height: r.height * scale)
    }

    private func fittedTransform() -> (CGFloat, CGSize) {
        let s = fitScale
        let w = layout.size.width * s, h = layout.size.height * s
        var x = max(0, (viewport.width - w) / 2)
        if w > viewport.width {
            // Wider than the window: start at the current term (or the first planned one) so "now" and the road
            // ahead are on screen; past terms are a scroll to the left.
            let anchor = layout.columns.first { $0.term.kind == .current } ?? layout.columns.first { $0.term.kind == .future }
            if let anchor { x = min(0, max(viewport.width - w, -(anchor.frame.minX - layout.metrics.padding) * s)) }
        }
        return (s, CGSize(width: x, height: max(0, min(24, (viewport.height - h) / 2))))
    }

    private func fit(animated: Bool) {
        guard viewport.width > 0, !layout.isEmpty else { return }
        let (s, o) = fittedTransform()
        if animated {
            withAnimation(Self.fitAnimation) { scale = s; offset = o }
        } else {
            scale = s; offset = o
        }
        fitted = true
        writtenZoom = 1
        if app.routeZoom != 1 { app.routeZoom = 1 }
        if abs(app.routeScale - Double(s)) > 0.0001 { app.routeScale = Double(s) }
    }

    /// Zooms by `factor` around `anchor` (view points), clamped to `AppModel.routeZoomRange` × the fitted scale.
    private func zoom(by factor: CGFloat, around anchor: CGPoint, animated: Bool = false) {
        let base = fitScale
        guard base > 0, scale > 0 else { return }
        let range = AppModel.routeZoomRange
        let target = min(base * range.upperBound, max(base * range.lowerBound, scale * factor))
        let ratio = target / scale
        var o = CGSize(width: anchor.x - (anchor.x - offset.width) * ratio,
                       height: anchor.y - (anchor.y - offset.height) * ratio)
        o = clamped(o, scale: target)
        if animated {
            withAnimation(.smooth(duration: 0.25)) { scale = target; offset = o }
        } else {
            scale = target; offset = o
        }
        fitted = abs(target - base) < 0.0001 && o == fittedTransform().1
        let z = Double(target / base)
        writtenZoom = z
        if abs(app.routeZoom - z) > 0.0001 { app.routeZoom = z }
        if abs(app.routeScale - Double(target)) > 0.0001 { app.routeScale = Double(target) }
    }

    /// Re-derives `routeZoom` (relative to the fitted scale) from the current scale.
    private func syncZoomLevel() {
        let base = fitScale
        guard base > 0, scale > 0 else { return }
        let range = AppModel.routeZoomRange
        let z = min(range.upperBound, max(range.lowerBound, Double(scale / base)))
        writtenZoom = z
        if abs(app.routeZoom - z) > 0.0001 { app.routeZoom = z }
    }

    /// Follows `app.routeZoom` when someone else (toolbar, a smoke scene) changed it: zoom around the centre.
    private func applyExternalZoom(animated: Bool) {
        guard abs(app.routeZoom - writtenZoom) > 0.0001, fitScale > 0, scale > 0 else { return }
        let factor = CGFloat(app.routeZoom) * fitScale / scale
        writtenZoom = app.routeZoom
        zoom(by: factor, around: CGPoint(x: viewport.width / 2, y: viewport.height / 2), animated: animated)
    }

    private func pan(_ delta: CGSize) {
        offset = clamped(CGSize(width: offset.width + delta.width, height: offset.height + delta.height), scale: scale)
        fitted = false
    }

    private func clampOffset() { offset = clamped(offset, scale: scale) }

    /// Keeps at least part of the board on screen: it may scroll to its edges plus a small overscroll.
    private func clamped(_ o: CGSize, scale s: CGFloat) -> CGSize {
        let slack: CGFloat = 60
        let w = layout.size.width * s, h = layout.size.height * s
        let loX = min(0, viewport.width - w) - slack, hiX = max(0, viewport.width - w) + slack
        let loY = min(0, viewport.height - h) - slack, hiY = max(0, viewport.height - h) + slack
        return CGSize(width: min(hiX, max(loX, o.width)), height: min(hiY, max(loY, o.height)))
    }

    /// Pans just enough to bring a box fully into view (keyboard navigation).
    private func reveal(_ id: String) {
        guard let box = layout.box(id) else { return }
        let r = viewRect(box.rect).insetBy(dx: -24, dy: -24)
        var dx: CGFloat = 0, dy: CGFloat = 0
        if r.minX < 0 { dx = -r.minX } else if r.maxX > viewport.width { dx = viewport.width - r.maxX }
        if r.minY < 0 { dy = -r.minY } else if r.maxY > viewport.height { dy = viewport.height - r.maxY }
        if dx != 0 || dy != 0 {
            withAnimation(.smooth(duration: 0.2)) { pan(CGSize(width: dx, height: dy)) }
        }
    }

    // MARK: Input

    private var handlers: RouteInputView.Handlers {
        var h = RouteInputView.Handlers()
        h.hover = { point in
            let id = point.flatMap { layout.box(at: boardPoint($0))?.courseId }
            if id != hoverId { hoverId = id }
        }
        h.click = { point in
            if let id = layout.box(at: boardPoint(point))?.courseId {
                focusId = nil
                app.selectedCourseId = id
                app.presentCourse(id)
            } else {
                focusId = nil
                app.selectedCourseId = nil
            }
        }
        h.pan = { delta in pan(delta) }
        h.zoom = { factor, anchor in zoom(by: factor, around: anchor) }
        h.isBox = { point in layout.box(at: boardPoint(point)) != nil }
        h.key = { key in handleKey(key) }
        return h
    }

    private func handleKey(_ key: RouteKey) -> Bool {
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        switch key {
        case .zoomIn: zoom(by: 1.25, around: center, animated: true); return true
        case .zoomOut: zoom(by: 0.8, around: center, animated: true); return true
        case .clear:
            if focusId == nil && app.selectedCourseId == nil { return false }
            focusId = nil
            app.selectedCourseId = nil
            return true
        case .open:
            guard let id = focusId ?? boardSelection else { return false }
            app.selectedCourseId = id
            app.presentCourse(id)
            return true
        case .up, .down, .left, .right:
            let direction: RouteDirection = key == .up ? .up : key == .down ? .down : key == .left ? .left : .right
            let next: String?
            if let current = focusId ?? boardSelection {
                next = layout.neighbor(of: current, direction)
            } else {
                next = layout.boxes.first?.courseId
            }
            guard let next else { return true }
            focusId = next
            app.selectedCourseId = next
            reveal(next)
            return true
        }
    }

    // MARK: Tooltip

    @ViewBuilder
    private var tooltip: some View {
        if let id = hoverId, let box = layout.box(id) {
            let r = viewRect(box.rect)
            let text = app.routeTooltip(id)
            let width = min(420, RouteText.width(text, .systemFont(ofSize: 12, weight: .medium)) + 22)
            let below = r.maxY + 8 + 30 < viewport.height
            let x = min(max(8, r.minX), max(8, viewport.width - width - 8))
            let y = below ? r.maxY + 6 : r.minY - 6 - 28
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkColor)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(width: width, height: 28)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                .offset(x: x, y: y)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    // MARK: Accessibility

    /// One accessible element per class (the canvas itself is a picture): label = the tooltip, press = open.
    private var accessibilityBoxes: some View {
        ForEach(layout.boxes) { box in
            let r = viewRect(box.rect)
            Rectangle()
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .accessibilityLabel(app.routeTooltip(box.courseId))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { app.selectedCourseId = box.courseId; app.presentCourse(box.courseId) }
        }
    }
}
