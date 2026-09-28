import Foundation
import ThubanPlannerCore

/// Extra Settings smoke screens (every pane is already captured light by the standard walk as 80-settings-…).
/// OWNER: Engineer C. Import states are built without ssh: the current plan is written out as the Atlas rows the
/// import SQL returns (`SettingsSmokeFixtures.document`) and converted exactly like a real import.
extension SmokeScenes {
    @MainActor private static var settingsSaved: PlannerData?

    static var settings: [SmokeScene] {
        [
            // Planning
            SmokeScene(name: "settings-planning-dark") { app in
                app.setAppearanceMode(.dark)
                app.openSettings(.planning)
            } cleanup: { app in
                app.setAppearanceMode(.light)
            },
            SmokeScene(name: "settings-planning-even") { app in
                app.setStrategy(.even)
                app.openSettings(.planning)
            } cleanup: { app in
                app.setStrategy(.soonestSummer)
            },
            SmokeScene(name: "settings-planning-empty") { app in
                settingsSaved = app.data
                app.replaceData(.empty)
                app.openSettings(.planning)
            } cleanup: { app in
                if let saved = settingsSaved { app.replaceData(saved) }
                settingsSaved = nil
            },
            // Import
            SmokeScene(name: "settings-import-idle-dark") { app in
                app.setAppearanceMode(.dark)
                app.importPhase = .idle
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.setAppearanceMode(.light)
            },
            SmokeScene(name: "settings-import-first-run", settle: 1.5) { app in
                let sample = app.data
                settingsSaved = sample
                app.replaceData(.empty)
                app.smokeSetFirstRun(true)
                app.importPhase = SettingsSmokeFixtures.preview(of: sample, app: app, duplicateIds: false)
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
                if let saved = settingsSaved { app.replaceData(saved) }
                settingsSaved = nil
            },
            SmokeScene(name: "settings-import-preview") { app in
                app.importPhase = SettingsSmokeFixtures.preview(of: app.data, app: app, duplicateIds: true)
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
            },
            SmokeScene(name: "settings-import-preview-dark") { app in
                app.setAppearanceMode(.dark)
                app.importPhase = SettingsSmokeFixtures.preview(of: app.data, app: app, duplicateIds: true)
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
                app.setAppearanceMode(.light)
            },
            SmokeScene(name: "settings-import-fetching") { app in
                app.importPhase = .fetching
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
            },
            SmokeScene(name: "settings-import-done") { app in
                if case .preview(let preview) = SettingsSmokeFixtures.preview(of: app.data, app: app, duplicateIds: false) {
                    app.importPhase = .done(preview.summary, backup: app.dataFolder.appendingPathComponent("backups/planner-before-import-20260928-181200.json"))
                }
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
            },
            SmokeScene(name: "settings-import-failed") { app in
                app.importPhase = .failed("ssh: Could not resolve hostname beelink: nodename nor servname provided, or not known")
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
            },
            SmokeScene(name: "settings-import-bad-connection") { app in
                app.preferences.atlasEmail = "not an email"
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.preferences.atlasEmail = Preferences.defaultAtlasEmail
            },
            // Data
            SmokeScene(name: "settings-data-backups", settle: 1.5) { app in
                // The smoke home is fresh; make a few labelled copies there (never the user's data).
                _ = try? app.store.snapshot(label: "before import", now: Date().addingTimeInterval(-86_400 * 3))
                _ = try? app.store.snapshot(label: "before restore", now: Date().addingTimeInterval(-3_600))
                app.mutate { $0.importSource = "atlas:beelink"; $0.importedAt = Date().addingTimeInterval(-86_400 * 3) }
                app.openSettings(.data)
            } cleanup: { app in
                app.mutate { $0.importSource = nil; $0.importedAt = nil }
            },
            SmokeScene(name: "settings-data-dark") { app in
                app.setAppearanceMode(.dark)
                app.openSettings(.data)
            } cleanup: { app in
                app.setAppearanceMode(.light)
            },
            // Appearance / About in dark
            SmokeScene(name: "settings-appearance-dark") { app in
                app.setAppearanceMode(.dark)
                app.openSettings(.appearance)
            } cleanup: { app in
                app.setAppearanceMode(.light)
            },
            SmokeScene(name: "settings-about-dark") { app in
                app.setAppearanceMode(.dark)
                app.openSettings(.about)
            } cleanup: { app in
                app.setAppearanceMode(.light)
            },
        ]
    }
}

/// Builds import states from a plan without ssh. SMOKE ONLY.
enum SettingsSmokeFixtures {
    /// The plan as the Atlas rows the import SQL returns. `duplicateIds` gives two classes one id (as Atlas can), so
    /// the preview shows the re-minted-id warning.
    static func document(from data: PlannerData, duplicateIds: Bool) -> AtlasDocument {
        var courses = data.courses
        if duplicateIds, courses.count > 31 {
            courses[31].id = courses[30].id
        }
        let courseRows: [JSONValue] = courses.map { c in
            .object([
                "id": .string(c.id), "code": .string(c.code), "title": .string(c.title), "credits": .number(c.credits),
                "prereqs": .array(c.prereqs.map(JSONValue.string)), "coreqs": .array(c.coreqs.map(JSONValue.string)),
                "summer_ok": .bool(c.summerOk), "term_key": c.term.map(JSONValue.string) ?? .null,
            ])
        }
        let termRows: [JSONValue] = data.terms.map { t in
            .object(["key": .string(t.key), "season": .string(t.season.rawValue), "year": .number(t.year), "current": .bool(t.current)])
        }
        let settings: JSONValue = .object([
            "max_credits": .number(data.settings.maxCredits), "summer_max": .number(data.settings.summerMax),
            "strategy": .string(data.settings.strategy.rawValue),
            "disabled_terms": .array(data.disabledTerms.map(JSONValue.string)),
        ])
        return AtlasDocument(email: Preferences.defaultAtlasEmail, settings: settings, terms: termRows, courses: courseRows)
    }

    @MainActor
    static func preview(of data: PlannerData, app: AppModel, duplicateIds: Bool) -> ImportPhase {
        let source = "atlas:\(app.preferences.atlasHost)"
        do {
            let converted = try AtlasImporter.convert(document(from: data, duplicateIds: duplicateIds), source: source,
                                                      now: app.now, calendar: app.calendar)
            return .preview(ImportPreview(summary: converted.summary, data: converted.data, source: source,
                                          replacesExisting: !app.data.isEmpty,
                                          localCourses: app.data.courses.count, localTerms: app.data.terms.count))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
