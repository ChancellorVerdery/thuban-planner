import SwiftUI
import ThubanPlannerCore

/// Schedule colour roles, built only from theme tokens.
///
/// | Meaning | Fill | Stripe / ink |
/// |---|---|---|
/// | Class meeting (course n) | the course hue mixed 80–84 % into `panel` | the hue itself; text `ink` |
/// | Blocked time | `panel2` with `line2` hatching | `inkDim` label |
/// | Block being drawn | `accentTint` | `accent` dashed border |
/// Course hues cycle through accent, pos, neg, the accent turned round the colour wheel (so the scheme's own
/// saturation and lightness carry over), accentDeep and signal, then repeat.
struct ScheduleCourseColors {
    var fill: Color
    var stripe: Color
    var ink: Color
    var dot: Color
}

extension ResolvedTheme {
    private var scheduleHues: [String] {
        func turned(_ degrees: Double) -> String {
            (try? ColorMath.hslToHex(ColorMath.hexToHSL(accent).rotated(by: degrees))) ?? accentDeep
        }
        return [accent, pos, neg, turned(215), turned(140), accentDeep, turned(275), signal]
    }

    func scheduleCourseColors(_ index: Int) -> ScheduleCourseColors {
        let hues = scheduleHues
        let hue = hues[((index % hues.count) + hues.count) % hues.count]
        let fill = (try? ColorMath.mix(hue, panel, isDark ? 0.78 : 0.84)) ?? panel2
        let stripe = (try? ColorMath.legible(hue, on: fill, target: 3.0)) ?? hue
        return ScheduleCourseColors(fill: Color(hex: fill), stripe: Color(hex: stripe), ink: inkColor, dot: Color(hex: hue))
    }
}
