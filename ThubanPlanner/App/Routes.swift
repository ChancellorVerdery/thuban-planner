import Foundation
import ThubanPlannerCore

/// SwiftUI's `ColorScheme` shadows the core type inside the app target.
typealias ThubanScheme = ThubanPlannerCore.ColorScheme

/// The sections in the section bar, in order (⌘1 … ⌘4). Settings is a section of the main window (⌘, too).
enum AppSection: String, CaseIterable, Hashable, Codable, Identifiable {
    case planner, route, schedule, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .planner: return "Planner"
        case .route: return "Route"
        case .schedule: return "Schedule"
        case .settings: return "Settings"
        }
    }

    var icon: IconName {
        switch self {
        case .planner: return .planner
        case .route: return .route
        case .schedule: return .schedule
        case .settings: return .settings
        }
    }

    /// ⌘1 … ⌘4
    var shortcut: Character { Character(String((AppSection.allCases.firstIndex(of: self) ?? 0) + 1)) }
}

/// Settings panes, in nav order.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case planning = "Planning"
    case appearance = "Appearance"
    case importAtlas = "Import"
    case data = "Data"
    case about = "About"

    var id: String { rawValue }

    var icon: IconName {
        switch self {
        case .planning: return .sliders
        case .appearance: return .settings
        case .importAtlas: return .download
        case .data: return .archive
        case .about: return .info
        }
    }
}
