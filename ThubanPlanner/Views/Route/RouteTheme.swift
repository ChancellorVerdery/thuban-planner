import SwiftUI
import ThubanPlannerCore

/// Route-board colour roles, built only from theme tokens and the shared `PlannerTheme` roles (OWNER: Engineer B).
///
/// | Element | Past (taken) | Current | Future (planned) |
/// |---|---|---|---|
/// | Column card | `panel2`, `line` border | `signalSoft`, `signal` hairline | `panel`, `line2` border |
/// | Box | `panel`, `line` border, `inkDim` code | `panel`, `signal` border, `signalText` code | `bg`, `line2` border, `ink` code, accent credit badge |
/// | Selected / hovered box | `accentTint`, `accent` border | same | same |
extension ResolvedTheme {
    func routeColumnFill(_ kind: TermKind) -> Color { termFill(kind) }

    func routeColumnBorder(_ kind: TermKind) -> Color { termBorder(kind) }

    func routeBoxFill(_ kind: TermKind) -> Color {
        switch kind {
        case .past, .current: return panelColor
        case .future: return bgColor
        }
    }

    func routeBoxBorder(_ kind: TermKind) -> Color {
        switch kind {
        case .past: return lineColor
        case .current: return signalColor.opacity(0.75)
        case .future: return line2Color
        }
    }

    func routeBoxCodeInk(_ kind: TermKind) -> Color { termInk(kind) }

    func routeBoxTitleInk(_ kind: TermKind) -> Color {
        switch kind {
        case .past: return inkFaintColor
        case .current, .future: return inkDimColor
        }
    }

    /// Emphasized ribbon (on the hovered / selected class's chain): the ribbon's own hue at full strength.
    func routeRibbonEmphasis(_ kind: RequirementKind) -> Color {
        switch kind {
        case .prereq: return accentColor
        case .coreq: return signalColor
        }
    }
}
