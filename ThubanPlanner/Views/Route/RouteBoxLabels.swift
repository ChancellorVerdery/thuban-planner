import AppKit
import SwiftUI
import ThubanPlannerCore

/// The text drawn in one board box, prepared once per plan change (not per frame): the code, the title truncated to
/// the box width with an ellipsis, the credits and a short "needs …" line for tall boxes. OWNER: Engineer B.
struct RouteBoxLabel: Hashable {
    var code: String
    var title: String
    var credits: String
    var needs: String?
}

enum RouteText {
    /// Board fonts (board points; the canvas scales them with the zoom, so they stay vector-sharp).
    static let codeSize: CGFloat = 12
    static let titleSize: CGFloat = 12.5
    static let creditSize: CGFloat = 11
    static let needsSize: CGFloat = 11
    static let boxPadding: CGFloat = 10

    static var codeFont: Font { .system(size: codeSize, weight: .semibold, design: .monospaced) }
    static var titleFont: Font { .system(size: titleSize) }
    static var creditFont: Font { .system(size: creditSize, weight: .semibold, design: .monospaced) }
    static var needsFont: Font { .system(size: needsSize) }

    /// Labels for every box on the board.
    @MainActor
    static func labels(layout: RouteLayout, app: AppModel) -> [String: RouteBoxLabel] {
        var out: [String: RouteBoxLabel] = [:]
        out.reserveCapacity(layout.boxes.count)
        let credit = NSFont.monospacedSystemFont(ofSize: creditSize, weight: .semibold)
        for box in layout.boxes {
            guard let course = app.course(box.courseId) else { continue }
            let credits = "\(app.creditsText(course.credits)) cr"
            let creditWidth = width(credits, credit) + (box.kind == .future ? 12 : 0)
            let codeRoom = box.rect.width - 2 * boxPadding - creditWidth - 8
            let code = truncate(course.displayCode, font: NSFont.monospacedSystemFont(ofSize: codeSize, weight: .semibold), width: codeRoom)
            let room = box.rect.width - 2 * boxPadding
            let title = truncate(course.title.isEmpty ? "Untitled class" : course.title, font: .systemFont(ofSize: titleSize), width: room)
            var needs: String?
            let refs = course.prereqs + course.coreqs
            if !refs.isEmpty {
                needs = truncate("Needs " + refs.joined(separator: ", "), font: .systemFont(ofSize: needsSize), width: room)
            }
            out[box.courseId] = RouteBoxLabel(code: code, title: title, credits: credits, needs: needs)
        }
        return out
    }

    // MARK: Measuring

    private static var widthCache: [String: CGFloat] = [:]
    private static var truncateCache: [String: String] = [:]

    static func width(_ text: String, _ font: NSFont) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)|\(text)"
        if let w = widthCache[key] { return w }
        let w = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        if widthCache.count > 4000 { widthCache.removeAll() }
        widthCache[key] = w
        return w
    }

    /// `text`, or its longest prefix + "…" that fits `width`.
    static func truncate(_ text: String, font: NSFont, width room: CGFloat) -> String {
        let key = "\(font.fontName)|\(font.pointSize)|\(Int(room))|\(text)"
        if let hit = truncateCache[key] { return hit }
        var result = text
        if width(text, font) > room {
            let chars = Array(text)
            var lo = 0, hi = chars.count
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                let candidate = String(chars[0..<mid]).trimmingCharacters(in: .whitespaces) + "…"
                if width(candidate, font) <= room { lo = mid } else { hi = mid - 1 }
            }
            result = String(chars[0..<lo]).trimmingCharacters(in: .whitespaces) + "…"
        }
        if truncateCache.count > 4000 { truncateCache.removeAll() }
        truncateCache[key] = result
        return result
    }
}
