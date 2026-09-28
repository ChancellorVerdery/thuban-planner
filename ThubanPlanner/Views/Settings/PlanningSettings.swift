import SwiftUI
import ThubanPlannerCore

/// Settings ▸ Planning: the two credit caps and the route strategy (Atlas's wording), with a live preview of the
/// route those settings produce. The caps are typed into drafts that commit on Return / focus loss (one write); the
/// preview follows the drafts as you type, computed on a copy of the plan (`app.settingsPreviewSchedule`).
/// OWNER: Engineer C.
struct PlanningSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var maxDraft = ""
    @State private var summerDraft = ""

    static let maxRange: ClosedRange<Double> = 1 ... 30
    static let summerRange: ClosedRange<Double> = 0 ... 30

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneHeader(eyebrow: nil, title: "Planning",
                               caption: "How the planner packs the classes you have left into terms.")

            SettingsPlanningPreview(settings: previewSettings, isDraft: previewSettings != app.settings)

            SettingsGroup("Credit caps", caption: "Changes apply when you press Return or leave the field.") {
                VStack(spacing: 0) {
                    capRow("Max credits per semester",
                           detail: "The most credit hours the planner will pack into a fall or spring term.",
                           draft: $maxDraft, range: Self.maxRange, stored: app.settings.maxCredits) { app.setMaxCredits($0) }
                    capRow("Max credits in summer",
                           detail: "Summers usually carry a lighter cap. 0 keeps the planner out of summers.",
                           draft: $summerDraft, range: Self.summerRange, stored: app.settings.summerMax) { app.setSummerMax($0) }
                        .thubanHairline(.top, color: theme.lineColor)
                }
                .thubanPanel(padding: 0)
            }

            SettingsGroup("Route strategy", caption: "How the planner trades off finishing fast against a lighter load.") {
                VStack(spacing: 8) {
                    ForEach(Strategy.allCases) { strategy in
                        SettingsStrategyRow(strategy: strategy,
                                            isSelected: app.settings.strategy == strategy,
                                            finish: finishText(for: strategy)) {
                            app.setStrategy(strategy)
                        }
                    }
                }
            }
        }
        .onAppear(perform: syncDrafts)
        // Only the draft whose stored value changed follows it, so a cap being typed survives a strategy click or the
        // other cap's stepper.
        .onChange(of: app.settings) { old, new in
            if old.maxCredits != new.maxCredits { maxDraft = JS.numberString(new.maxCredits) }
            if old.summerMax != new.summerMax { summerDraft = JS.numberString(new.summerMax) }
        }
    }

    private func capRow(_ label: String, detail: String, draft: Binding<String>, range: ClosedRange<Double>, stored: Double,
                        commit: @escaping (Double) -> Void) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor)
                Text(detail).font(ThubanFont.small).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                if Self.parse(draft.wrappedValue, in: range) == nil {
                    Text("Enter a number from \(JS.numberString(range.lowerBound)) to \(JS.numberString(range.upperBound)).")
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.negTextColor)
                }
            }
            Spacer(minLength: 12)
            SettingsCreditField(label: label, draft: draft, range: range, stored: stored, commit: commit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Drafts & preview

    private func syncDrafts() {
        maxDraft = JS.numberString(app.settings.maxCredits)
        summerDraft = JS.numberString(app.settings.summerMax)
    }

    /// The saved settings with any valid draft applied (what the preview shows).
    private var previewSettings: PlannerSettings {
        var s = app.settings
        if let v = Self.parse(maxDraft, in: Self.maxRange) { s.maxCredits = v }
        if let v = Self.parse(summerDraft, in: Self.summerRange) { s.summerMax = v }
        return s
    }

    private func finishText(for strategy: Strategy) -> String {
        var s = previewSettings
        s.strategy = strategy
        if app.toTake.isEmpty { return "–" }
        return SettingsFormat.finish(app.settingsPreviewSchedule(s), remaining: app.toTake.count)
    }

    static func parse(_ text: String, in range: ClosedRange<Double>) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value.isFinite, range.contains(value) else { return nil }
        return value
    }
}

// MARK: - Credit field

/// [−] [ 16 ] [+] credits — a numeric draft that commits on Return or focus loss; the steppers commit at once.
struct SettingsCreditField: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    @Binding var draft: String
    var range: ClosedRange<Double>
    var stored: Double
    var commit: (Double) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            step(-1, glyph: .minus, name: "Decrease \(label.lowercased())")
            TextField(label, text: $draft)
                .labelsHidden()
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { _, isFocused in if !isFocused { apply() } }
                // Leaving Settings (or quitting) while the field is still first responder never reports focus loss.
                .onDisappear(perform: apply)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in apply() }
                .thubanField(invalid: parsed == nil, mono: true, height: 32)
                .frame(width: 64)
                .accessibilityLabel(label)
            step(1, glyph: .plus, name: "Increase \(label.lowercased())")
            Text("credits")
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 44, alignment: .leading)
        }
    }

    private var parsed: Double? { PlanningSettings.parse(draft, in: range) }

    private func apply() {
        guard let value = parsed else { return }
        if value != stored { commit(value) }
    }

    private func step(_ delta: Double, glyph: IconName, name: String) -> some View {
        let base = parsed ?? stored
        let next = min(range.upperBound, max(range.lowerBound, (base + delta).rounded(delta > 0 ? .down : .up)))
        return IconButton(glyph, label: name, size: 30, iconSize: 14) {
            draft = JS.numberString(next)
            commit(next)
        }
        .disabled(next == base)
        .opacity(next == base ? 0.4 : 1)
    }
}

// MARK: - Strategy row

struct SettingsStrategyRow: View {
    @Environment(\.thubanTheme) private var theme
    var strategy: Strategy
    var isSelected: Bool
    var finish: String
    var action: () -> Void

    var body: some View {
        ListRowCard(isSelected: isSelected, action: action) {
            HStack(alignment: .center, spacing: 14) {
                SettingsRadioMark(isOn: isSelected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(strategy.label)
                        .font(ThubanFont.body(14, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.brassInkColor : theme.inkColor)
                    Text(Self.explanation(strategy))
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Text(finish)
                    .font(ThubanFont.body(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.inkColor : theme.inkDimColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 180, alignment: .trailing)
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(strategy.label). \(Self.explanation(strategy)) Finishes \(finish).")
        .accessibilityAddTraits(.isButton)
    }

    static func explanation(_ strategy: Strategy) -> String {
        switch strategy {
        case .soonestSummer:
            return "Fills every term to its cap, summers included, to finish as early as possible."
        case .soonestOptionalSummer:
            return "Plans fall and spring first, and uses a summer only when it moves the finish earlier."
        case .even:
            return "Spreads the credits evenly over the same number of fall and spring terms; uses summers only if the plan can’t finish without them."
        }
    }
}

/// A radio circle: accent ring + dot when on.
struct SettingsRadioMark: View {
    @Environment(\.thubanTheme) private var theme
    var isOn: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? theme.accentColor : theme.line2Color, lineWidth: isOn ? 1.5 : 1)
            if isOn { Circle().fill(theme.accentColor).frame(width: 8, height: 8) }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview card

/// "WITH THESE SETTINGS · Finishes Spring 2028 · 3 more terms" and the planned terms as a load strip (credits per
/// term against its cap), so the strategy's shape is visible.
struct SettingsPlanningPreview: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var settings: PlannerSettings
    var isDraft: Bool

    var body: some View {
        let schedule = app.settingsPreviewSchedule(settings)
        let planned = schedule.plannedTerms
        let remaining = app.toTake
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Eyebrow(isDraft ? "Preview · not applied yet" : "With these settings")
                }
                Text(headline(schedule, remaining: remaining.count))
                    .font(ThubanFont.display(26))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption(schedule, remaining: remaining))
                    .font(ThubanFont.small)
                    .foregroundStyle(schedule.unplaceable.isEmpty ? theme.inkDimColor : theme.negTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 250, alignment: .leading)

            if planned.isEmpty {
                Text(remaining.isEmpty ? "Each planned term shows here with its credits against the cap."
                                       : "No term could be planned with these caps.")
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkFaintColor)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            } else {
                SettingsLoadStrip(terms: planned, settings: settings)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .thubanPanel(padding: 0)
        .accessibilityElement(children: .combine)
    }

    private func headline(_ schedule: Schedule, remaining: Int) -> String {
        if app.courses.isEmpty { return "No classes yet" }
        if remaining == 0 { return "Nothing left to take" }
        if !schedule.unplaceable.isEmpty { return "Can't finish yet" }
        guard let grad = schedule.gradTermLabel, schedule.termsToFinish > 0 else { return "Nothing left to take" }
        return "Finishes \(grad)"
    }

    private func caption(_ schedule: Schedule, remaining: [Course]) -> String {
        if app.courses.isEmpty { return "Add your classes on the Planner to see when you finish." }
        if remaining.isEmpty { return "\(app.courses.count) classes · every one is taken or in progress." }
        let credits = remaining.reduce(0) { $0 + $1.credits }
        let base = "\(remaining.count) to take · \(app.creditsText(credits)) credits"
        if !schedule.unplaceable.isEmpty {
            let n = schedule.unplaceable.count
            return "\(base) · \(n) class\(n == 1 ? "" : "es") can't be placed — check prerequisites on the Planner."
        }
        return "\(base) · \(SettingsFormat.terms(schedule.termsToFinish))"
    }
}

/// One column per planned term: the credits, a bar filled to credits ÷ cap, and the term.
struct SettingsLoadStrip: View {
    @Environment(\.thubanTheme) private var theme
    var terms: [BoardTerm]
    var settings: PlannerSettings

    private let barHeight: CGFloat = 62

    var body: some View {
        let peak = max(settings.maxCredits, settings.summerMax, terms.map(\.credits).max() ?? 1, 1)
        ViewThatFits(in: .horizontal) {
            strip(terms, peak: peak)
            strip(Array(terms.prefix(8)), peak: peak, more: terms.count - 8)
            strip(Array(terms.prefix(6)), peak: peak, more: terms.count - 6)
        }
    }

    private func strip(_ shown: [BoardTerm], peak: Double, more: Int = 0) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(shown) { term in column(term, peak: peak) }
            if more > 0 {
                Text("+\(more)")
                    .font(ThubanFont.mono(12))
                    .foregroundStyle(theme.inkFaintColor)
                    .padding(.bottom, 22)
            }
        }
    }

    private func column(_ term: BoardTerm, peak: Double) -> some View {
        let isSummer = term.season == .summer
        let cap = isSummer ? settings.summerMax : settings.maxCredits
        return VStack(spacing: 5) {
            Text(JS.numberString(term.credits))
                .font(ThubanFont.mono(12, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .monospacedDigit()
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.panel2Color)
                    .frame(height: barHeight * CGFloat(min(1, max(cap, term.credits) / peak)))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSummer ? theme.signalColor : theme.accentColor)
                    .frame(height: max(3, barHeight * CGFloat(min(1, term.credits / peak))))
            }
            .frame(width: 30, height: barHeight, alignment: .bottom)
            VStack(spacing: 0) {
                Text(term.season.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.inkDimColor)
                Text(JS.numberString(term.year))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkFaintColor)
                    .monospacedDigit()
            }
        }
        .frame(width: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(term.label): \(JS.numberString(term.credits)) of \(JS.numberString(cap)) credits")
    }
}
