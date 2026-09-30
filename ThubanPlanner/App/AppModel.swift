import AppKit
import Foundation
import Observation
import ThubanPlannerCore
import os

/// Root model. Owns the plan (`data`, persisted by `store` after every change), the route computed from it
/// (`schedule`, recomputed on every change), the preferences, the resolved theme, navigation, and the import state.
/// Views read it with `@Environment(AppModel.self)` and change things ONLY through its methods
/// (AppModel+Mutations.swift) — never by editing `data` themselves.
///
/// Files: queries in AppModel+Queries.swift, writes in AppModel+Mutations.swift, the Atlas import and backups in
/// AppModel+Import.swift. Rules live in the core package (PlannerData mutations, Scheduler).
@MainActor
@Observable
final class AppModel {
    static let logger = Logger(subsystem: "org.thuban.planner", category: "app")

    // MARK: Domain

    /// The whole local plan, always `loadCourse()`-normalized. Read freely; write only through `mutate` (or the
    /// named APIs built on it).
    private(set) var data: PlannerData = .empty
    /// Atlas's `scheduleDegree(data, now)` — the route. Recomputed whenever `data` or `now` changes.
    private(set) var schedule: Schedule = .empty
    /// The clock the scheduler reads (it only matters when no term is recorded). Refreshed on day change / activation.
    private(set) var now = Date()
    private(set) var isLoaded = false
    /// True when this launch found no planner.json (the Planner offers the Atlas import).
    private(set) var isFirstRun = false
    /// Set when planner.json exists but cannot be read; the app then runs on empty data WITHOUT saving over it.
    private(set) var loadError: String?
    /// Last failed save (shown as a banner by the shell).
    var saveError: String?

    @ObservationIgnored let store: PlannerStore
    /// Swappable for tests / previews; the import runs ssh through it.
    @ObservationIgnored var commandRunner: CommandRunner = ProcessRunner()
    /// The calendar the scheduler and term helpers use (the user's, like Atlas's browser-local time).
    @ObservationIgnored var calendar: Calendar = .current

    // MARK: Preferences & theme

    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            persistPreferences()
            if preferences.theme != oldValue.theme {
                recomputeTheme()
                SharedTheme.publish(preferences.theme)
            }
        }
    }
    private(set) var systemIsDark = false
    private(set) var theme: ResolvedTheme = ThemeResolver.resolve(.default, systemIsDark: false)
    var themeSelection: ThemeSelection { preferences.theme }

    // MARK: Navigation

    var section: AppSection = .planner {
        didSet { if section != oldValue { preferences.lastSection = section.rawValue } }
    }
    /// The Settings section's pane (Settings ▸ Planning / Appearance / Import / Data / About).
    var settingsPane: SettingsPane = .planning
    /// Class detail sheet (hosted by the shell). Set to a course id to present it; nil dismisses.
    var presentedCourseId: String?

    // MARK: Per-section UI state shared between a section's view and its toolbar (views own everything else as @State)

    /// Planner: the selected class row (the Route highlights it too). Set after "Add class" so the row takes focus.
    var selectedCourseId: String?
    /// Planner: a row asks to start editing this class's code field (consumed and cleared by the row).
    var editRequestCourseId: String?
    /// Route: the board's zoom (1 = fitted). The toolbar's zoom buttons and the board's pinch / scroll write it.
    var routeZoom: Double = 1
    /// Route: the board's real scale (1 = actual size), written by the board; the toolbar shows it.
    var routeScale: Double = 1
    /// Route: bump to re-fit the board (toolbar "Fit", "Calculate route", ⌘0).
    var routeFitRequest = 0

    // MARK: Schedule tab (App/Schedule/ScheduleModel.swift)

    /// The Schedule section's own observable model (Banner terms, sections, timetables, schedule.json).
    @ObservationIgnored let scheduleTab: ScheduleModel

    // MARK: Import (AppModel+Import.swift)

    var importPhase: ImportPhase = .idle
    @ObservationIgnored var importTask: Task<Void, Never>?
    /// Bumped by every import start / cancel; a task only writes `importPhase` while its run is still current.
    @ObservationIgnored var importRun = 0
    /// Where the current / last import reads from ("atlas:<host>" or "file:<name>"), for the failed card's wording.
    var lastImportSource: String?
    /// The file of the last file import (Try again reloads it).
    @ObservationIgnored var lastImportFile: URL?

    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var preferencesSaveTask: Task<Void, Never>?

    init(store: PlannerStore = PlannerStore()) {
        self.store = store
        scheduleTab = ScheduleModel(store: TimetableStore(directory: store.directory), offline: SmokeHarness.isEnabled)
        preferences = Preferences.load()
        if let shared = SharedTheme.load() { preferences.theme = shared }
        systemIsDark = Self.currentSystemIsDark()
        theme = ThemeResolver.resolve(preferences.theme, systemIsDark: systemIsDark)
        if let raw = preferences.lastSection, let saved = AppSection(rawValue: raw) { section = saved }
        scheduleTab.app = self
    }

    // MARK: Lifecycle

    /// Called once from the main window's `.task`: loads (or seeds) the plan, computes the route, starts observing
    /// appearance / day changes, then hands over to the smoke harness when it is enabled.
    func load() async {
        guard !isLoaded else { return }
        if appearanceObservation == nil { observeAppearance() }
        observeSharedTheme()
        // First Thuban app to run with sharing seeds the file with its own scheme.
        if SharedTheme.load() == nil { SharedTheme.publish(preferences.theme) }
        recomputeTheme()
        now = Date()
        isFirstRun = !store.exists
        do {
            data = try store.load().normalized()
        } catch {
            loadError = error.localizedDescription
            Self.logger.error("load failed: \(error.localizedDescription, privacy: .public)")
        }
        if loadError == nil, !store.exists, Self.shouldSeedSample {
            data = SampleData.make(now: now, calendar: calendar)
            isFirstRun = false
            save()
        }
        recomputeSchedule()
        observeDayChanges()
        isLoaded = true
        SmokeHarness.startIfEnabled(app: self)
    }

    /// `THUBAN_PLANNER_SEED=sample` (or a smoke run) seeds an EMPTY home with `SampleData`. Never replaces a file.
    static var shouldSeedSample: Bool {
        SmokeHarness.isEnabled || ProcessInfo.processInfo.environment["THUBAN_PLANNER_SEED"] == "sample"
    }

    /// Re-reads the clock; the route is recomputed when the calendar term changed.
    func refreshNow() {
        let fresh = Date()
        let changed = TermKey.current(now: fresh, calendar: calendar) != TermKey.current(now: now, calendar: calendar)
        now = fresh
        if changed { recomputeSchedule() }
    }

    private func observeDayChanges() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNow() }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPreferences() }
        })
    }

    // MARK: Writing

    /// THE write path. Applies `change` to a copy of the plan, re-normalizes it (Atlas reloads after every save),
    /// publishes it, recomputes the route and saves atomically. Every named mutation is a thin wrapper around this.
    /// Returns what `change` returns.
    @discardableResult
    func mutate<T>(_ change: (inout PlannerData) throws -> T) rethrows -> T {
        var copy = data
        let result = try change(&copy)
        copy.normalize()
        if copy != data {
            data = copy
            recomputeSchedule()
            save()
        }
        return result
    }

    /// Replaces the whole plan (import, restore). Callers snapshot first.
    func replaceData(_ newData: PlannerData) {
        data = newData.normalized()
        loadError = nil
        isFirstRun = false
        recomputeSchedule()
        save()
    }

    /// SMOKE ONLY: lets a smoke scene put the first-run state on screen (`isFirstRun` is otherwise set only by `load()`,
    /// and a smoke run always seeds `SampleData`). No-op outside a smoke run. Recipe (the Planner's empty / first-run
    /// state with the Atlas import offer):
    /// `app.replaceData(.empty); app.smokeSetFirstRun(true); app.preferences.importOffered = false` — cleanup:
    /// `app.replaceData(SampleData.make(now: app.now, calendar: app.calendar))` (which also clears `isFirstRun`).
    func smokeSetFirstRun(_ value: Bool) {
        guard SmokeHarness.isEnabled else { return }
        isFirstRun = value
    }

    private func recomputeSchedule() {
        let fresh = Scheduler.scheduleDegree(data, now: now, calendar: calendar)
        if fresh != schedule {
            schedule = fresh
            // The Schedule tab's "Thuban route" source reads the route.
            if scheduleTab.isActivated { scheduleTab.refreshRows() }
        }
        if let id = selectedCourseId, data.course(id) == nil { selectedCourseId = nil }
        if let id = presentedCourseId, data.course(id) == nil { presentedCourseId = nil }
    }

    private func save() {
        // A document that failed to load is never overwritten by the empty fallback.
        guard loadError == nil else { return }
        do {
            try store.save(data, now: Date())
            if saveError != nil { saveError = nil }
        } catch {
            saveError = error.localizedDescription
            Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Preferences

    private func persistPreferences() {
        preferencesSaveTask?.cancel()
        let snapshot = preferences
        preferencesSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do { try Preferences.save(snapshot) } catch { Self.logger.error("preferences save failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func flushPreferences() {
        guard let pending = preferencesSaveTask else { return }
        pending.cancel()
        preferencesSaveTask = nil
        try? Preferences.save(preferences)
    }

    // MARK: Navigation helpers

    /// Shows the Settings section on a pane (⌘, opens it on the last pane).
    func openSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsPane = pane }
        section = .settings
    }

    /// Planner's "Calculate route": the route is always current; this shows it, fitted.
    func showRoute() {
        routeFitRequest += 1
        routeZoom = 1
        section = .route
    }

    /// Opens the class detail sheet.
    func presentCourse(_ id: String) { presentedCourseId = id }

    // MARK: Theme

    func setThemeSelection(_ selection: ThemeSelection) { preferences.theme = selection }

    func setAppearanceMode(_ mode: AppearanceMode) {
        var selection = themeSelection
        selection.mode = mode
        setThemeSelection(selection)
    }

    func selectScheme(id: String) {
        var selection = themeSelection
        selection.schemeId = id
        if id == ThubanScheme.customId, selection.custom == nil { selection.custom = SchemePresets.default.asCustom() }
        setThemeSelection(selection)
    }

    @ObservationIgnored private var sharedThemeObserver: NSObjectProtocol?

    /// Another Thuban app changed the scheme: adopt it (publishing again is a no-op once the file matches).
    private func observeSharedTheme() {
        guard sharedThemeObserver == nil else { return }
        sharedThemeObserver = SharedTheme.observe { [weak self] selection in
            guard let self, self.preferences.theme != selection else { return }
            self.preferences.theme = selection
        }
    }

    private func observeAppearance() {
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let dark = Self.currentSystemIsDark()
                if dark != self.systemIsDark {
                    self.systemIsDark = dark
                    self.recomputeTheme()
                }
            }
        }
    }

    /// True when macOS itself is dark (independent of any override applied to `NSApp.appearance`).
    static func currentSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    private func recomputeTheme() {
        let resolved = ThemeResolver.resolve(themeSelection, systemIsDark: systemIsDark)
        if resolved != theme { theme = resolved }
        switch themeSelection.mode {
        case .auto: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        AppIconRenderer.apply(theme: resolved)
    }
}
