import Foundation
import ThubanPlannerCore

/// One extra smoke screenshot: put the app in a state, capture a window, undo the state.
struct SmokeScene {
    enum Window {
        /// The main window's content.
        case main
        /// The sheet attached to the main window (the class detail sheet).
        case sheet
        /// An open popover's own window (e.g. the Schedule sort menu).
        case popover
    }

    var name: String
    var window: Window = .main
    /// Seconds to wait after `prepare` before capturing.
    var settle: Double = 1.2
    var prepare: @MainActor (AppModel) async -> Void
    var cleanup: @MainActor (AppModel) async -> Void = { _ in }

    init(name: String, window: Window = .main, settle: Double = 1.2,
         prepare: @escaping @MainActor (AppModel) async -> Void,
         cleanup: @escaping @MainActor (AppModel) async -> Void = { _ in }) {
        self.name = name
        self.window = window
        self.settle = settle
        self.prepare = prepare
        self.cleanup = cleanup
    }
}

/// The scene registry. Each area owns ONE static list in its own file — `SmokeScenes.planner` in
/// Views/Planner/PlannerSmokeScenes.swift, `.route` in Views/Route/RouteSmokeScenes.swift, `.classDetail` in
/// Views/ClassDetail/ClassDetailSmokeScenes.swift, `.settings` in Views/Settings/SettingsSmokeScenes.swift, `.schedule` in Views/Schedule/ScheduleSmokeScenes.swift — so
/// parallel branches never edit the same line. This line is pre-wired and frozen; the harness runs the scenes in
/// this order after the standard walk.
enum SmokeScenes {
    static var all: [SmokeScene] { planner + route + classDetail + settings + schedule }
}
