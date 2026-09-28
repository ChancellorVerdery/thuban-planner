import SwiftUI
import ThubanPlannerCore

/// A soft status chip (pos / neg / warn / signal / neutral / accent), optionally with a leading dot or icon.
struct Chip: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var kind: ChipKind = .neutral
    var dot: Bool = false
    var icon: IconName?

    init(_ text: String, kind: ChipKind = .neutral, dot: Bool = false, icon: IconName? = nil) {
        self.text = text
        self.kind = kind
        self.dot = dot
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) {
            if dot {
                Circle().fill(kind.colors(theme).text).frame(width: 6, height: 6)
            }
            if let icon { Icon(icon, size: 13) }
            Text(text)
        }
        .thubanChip(kind: kind)
    }
}
