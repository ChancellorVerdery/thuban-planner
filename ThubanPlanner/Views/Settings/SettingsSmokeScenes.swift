import Foundation
import ThubanPlannerCore

/// Extra Settings smoke screens (every pane is already captured by the standard walk as 80-settings-…). OWNER:
/// Engineer C. Import states can be built without ssh: `app.importPhase = .preview(…)` from
/// `AtlasImporter.convert(AtlasDocument(…), …)`, or `.fetching` / `.failed("…")`.
extension SmokeScenes {
    static var settings: [SmokeScene] {
        []
    }
}
