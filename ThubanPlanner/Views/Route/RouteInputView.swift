import AppKit
import SwiftUI
import ThubanPlannerCore

/// The board's pointer / keyboard surface: a transparent AppKit view laid over the drawing, because SwiftUI on macOS
/// has no scroll-wheel events. Scroll (trackpad or wheel) pans; ⌘-scroll and pinch zoom around the pointer; dragging
/// the background pans; a click (no drag) reports the point; hover reports the point; arrows / Return / Esc go to
/// `onKey`. Coordinates are view points, y down. OWNER: Engineer B.
struct RouteInputView: NSViewRepresentable {
    struct Handlers {
        var hover: (CGPoint?) -> Void = { _ in }
        var click: (CGPoint) -> Void = { _ in }
        var pan: (CGSize) -> Void = { _ in }
        /// (factor, anchor)
        var zoom: (CGFloat, CGPoint) -> Void = { _, _ in }
        /// true when the key was handled.
        var key: (RouteKey) -> Bool = { _ in false }
        /// Is there a box under this point (pointing-hand cursor)?
        var isBox: (CGPoint) -> Bool = { _ in false }
    }

    var handlers: Handlers

    func makeNSView(context: Context) -> RouteInputNSView {
        let view = RouteInputNSView()
        view.handlers = handlers
        return view
    }

    func updateNSView(_ view: RouteInputNSView, context: Context) {
        view.handlers = handlers
    }
}

enum RouteKey { case up, down, left, right, open, clear, zoomIn, zoomOut }

final class RouteInputNSView: NSView {
    var handlers = RouteInputView.Handlers()
    private var dragStart: CGPoint?
    private var lastDrag: CGPoint?
    private var dragging = false
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    // MARK: Hover

    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        handlers.hover(p)
        updateCursor(at: p)
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        handlers.hover(nil)
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(at: point(event)) }

    private func updateCursor(at p: CGPoint) {
        if dragging { NSCursor.closedHand.set() } else if handlers.isBox(p) { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }

    // MARK: Click / drag

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = point(event)
        lastDrag = dragStart
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let last = lastDrag else { return }
        let p = point(event)
        if !dragging, hypot(p.x - start.x, p.y - start.y) > 3 {
            dragging = true
            handlers.hover(nil)
            NSCursor.closedHand.set()
        }
        if dragging { handlers.pan(CGSize(width: p.x - last.x, height: p.y - last.y)) }
        lastDrag = p
    }

    override func mouseUp(with event: NSEvent) {
        let p = point(event)
        if !dragging, dragStart != nil { handlers.click(p) }
        dragging = false
        dragStart = nil
        lastDrag = nil
        updateCursor(at: p)
        handlers.hover(p)
    }

    // MARK: Scroll / pinch

    override func scrollWheel(with event: NSEvent) {
        let p = point(event)
        if event.modifierFlags.contains(.command) {
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
            handlers.zoom(exp(dy * 0.01), p)
        } else {
            var dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas { dx *= 10; dy *= 10 }
            // A plain mouse wheel with ⇧ scrolls sideways (AppKit already swaps the deltas); keep both axes.
            handlers.pan(CGSize(width: dx, height: dy))
        }
        handlers.hover(p)
    }

    override func magnify(with event: NSEvent) {
        handlers.zoom(1 + event.magnification, point(event))
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let key: RouteKey?
        switch event.keyCode {
        case 126: key = .up
        case 125: key = .down
        case 123: key = .left
        case 124: key = .right
        case 36, 76, 49: key = .open       // Return, Enter, Space
        case 53: key = .clear              // Esc
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": key = .zoomIn
            case "-", "_": key = .zoomOut
            default: key = nil
            }
        }
        if let key, handlers.key(key) { return }
        super.keyDown(with: event)
    }
}
