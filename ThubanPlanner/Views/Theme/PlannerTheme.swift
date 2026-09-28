import SwiftUI
import ThubanPlannerCore

/// Planner-specific colour roles, built ONLY from theme tokens, so the Planner table, the Route board and the class
/// detail sheet speak one visual language. FROZEN (shared): add new roles in your own folder as another extension.
///
/// | Meaning | Fill | Ink / stroke |
/// |---|---|---|
/// | Past term / taken class | `panel2` | `inkDim` (muted, done) |
/// | Current term / in progress | `signalSoft` | `signalText`, border `signal` |
/// | Planned (future) term / class | `panel` | `ink`, border `line2`, accent credit badge |
/// | Unplaceable class | `negSoft` | `negText` |
/// | Disabled term (summer off) | `bg` with a dashed `line2` border | `inkFaint` |
/// | Prerequisite ribbon | — | `accent` at 45 % opacity, 2 pt, solid |
/// | Corequisite ribbon | — | `signal` at 70 % opacity, 1.5 pt, dashed 4 / 3 |
/// | Selected / hovered class | `accentTint` | border `accent` |
extension ResolvedTheme {
    func termFill(_ kind: TermKind) -> Color {
        switch kind {
        case .past: return panel2Color
        case .current: return signalSoftColor
        case .future: return panelColor
        }
    }

    func termInk(_ kind: TermKind) -> Color {
        switch kind {
        case .past: return inkDimColor
        case .current: return signalTextColor
        case .future: return inkColor
        }
    }

    func termBorder(_ kind: TermKind) -> Color {
        switch kind {
        case .past: return lineColor
        case .current: return signalColor
        case .future: return line2Color
        }
    }

    /// Column caption under a term label: "15 cr · done" / "· current" / "· planned" (Atlas's wording).
    func termCaption(_ term: BoardTerm) -> String {
        let credits = JS.numberString(term.credits)
        switch term.kind {
        case .past: return "\(credits) cr · done"
        case .current: return "\(credits) cr · current"
        case .future: return "\(credits) cr · planned"
        }
    }

    func ribbonColor(_ kind: RequirementKind) -> Color {
        switch kind {
        case .prereq: return accentColor.opacity(0.45)
        case .coreq: return signalColor.opacity(0.7)
        }
    }

    func ribbonStyle(_ kind: RequirementKind, scale: CGFloat = 1) -> StrokeStyle {
        switch kind {
        case .prereq: return StrokeStyle(lineWidth: 2 * scale, lineCap: .round)
        case .coreq: return StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, dash: [4 * scale, 3 * scale])
        }
    }

    /// Chip for a class's route status (Planner rows, class detail).
    func statusChip(_ status: CourseStatus) -> (text: String, kind: ChipKind) {
        switch status {
        case .taken(let key): return ("Taken \(TermKey.label(key))", .pos)
        case .inProgress(let key): return ("\(TermKey.label(key)) · now", .signal)
        case .planned(let key): return (TermKey.label(key), .accent)
        case .unplaceable: return ("Can’t place", .neg)
        case .unscheduled: return ("Taken (term not listed)", .neutral)
        }
    }
}
