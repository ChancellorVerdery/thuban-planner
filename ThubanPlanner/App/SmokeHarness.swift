import AppKit
import Foundation
import ThubanPlannerCore
import os

/// Visual smoke test driven by `THUBAN_PLANNER_SMOKE=<output dir>` (see scripts/smoke.sh). The app is launched on a
/// temporary `THUBAN_PLANNER_HOME`, seeds `SampleData`, walks every section (`10-planner`, `11-route`, `12-settings`),
/// the registered `SmokeScenes` (`30+`), Planner and Route in dark mode (`70-`, `71-`) and every Settings pane
/// (`80-settings-…`), writes PNGs and exits (status 1 on failure). No network, no ssh.
@MainActor
enum SmokeHarness {
    static let variable = "THUBAN_PLANNER_SMOKE"
    private static let logger = Logger(subsystem: "org.thuban.planner", category: "smoke")
    /// The sibling apps' artboard size.
    static let windowSize = NSSize(width: 1440, height: 900)

    static var outputDirectory: URL? {
        guard let raw = ProcessInfo.processInfo.environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var isEnabled: Bool { outputDirectory != nil }

    static func startIfEnabled(app: AppModel) {
        guard let directory = outputDirectory else { return }
        Task { await run(app: app, directory: directory) }
    }

    private static func run(app: AppModel, directory: URL) async {
        var status: Int32 = 0
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let window = try await waitForWindow(timeout: 10) { $0.isVisible && $0.contentView != nil && $0.attachedSheet == nil }
            window.setContentSize(windowSize)
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            await sleep(0.8)

            // 1. Standard walk: every section.
            for (index, section) in AppSection.allCases.enumerated() {
                app.section = section
                await sleep(1.0)
                try capture(window, name: String(format: "%02d-%@", 10 + index, section.rawValue), in: directory)
            }

            // 2. Registered scenes.
            for (index, scene) in SmokeScenes.all.enumerated() {
                await scene.prepare(app)
                await sleep(scene.settle)
                let target: NSWindow
                switch scene.window {
                case .main: target = window
                case .sheet: target = try await waitFor(timeout: 5) { window.attachedSheet }
                case .popover:
                    target = try await waitFor(timeout: 5) {
                        NSApp.windows.first { $0 !== window && $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
                    }
                }
                try capture(target, name: String(format: "%02d-%@", 30 + index, scene.name), in: directory)
                await scene.cleanup(app)
                await sleep(0.5)
            }

            // 3. Dark mode: Planner and Route.
            app.setThemeSelection(ThemeSelection(mode: .dark, schemeId: SchemePresets.defaultId, custom: nil))
            for (index, section) in [AppSection.planner, .route].enumerated() {
                app.section = section
                await sleep(1.0)
                try capture(window, name: String(format: "%03d-%@-dark", 900 + index, section.rawValue), in: directory)
            }
            app.setThemeSelection(ThemeSelection(mode: .light, schemeId: SchemePresets.defaultId, custom: nil))
            await sleep(0.5)

            // 4. Settings, every pane.
            for (index, pane) in SettingsPane.allCases.enumerated() {
                app.openSettings(pane)
                await sleep(0.9)
                let slug = pane.rawValue.lowercased().map { $0.isLetter ? $0 : "-" }
                try capture(window, name: String(format: "%03d-settings-%@", 950 + index, String(slug)), in: directory)
            }
            app.section = .planner
        } catch {
            logger.error("smoke failed: \(error.localizedDescription, privacy: .public)")
            fputs("smoke: FAILED: \(error.localizedDescription)\n", stderr)
            status = 1
        }
        print("smoke: done")
        exit(status)
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func waitForWindow(timeout: Double, _ predicate: (NSWindow) -> Bool) async throws -> NSWindow {
        try await waitFor(timeout: timeout) { NSApp.windows.first(where: predicate) }
    }

    private static func waitFor<T>(timeout: Double, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = probe() { return value }
            await sleep(0.1)
        }
        throw ThubanError.store("smoke: window did not appear within \(Int(timeout)) s")
    }

    /// Renders the window's content view (`cacheDisplay`) to `<name>.png`. No screen-recording permission needed.
    /// `THUBAN_PLANNER_SMOKE_WINDOW_SERVER=1` grabs the window server's own pixels with `screencapture -l` instead
    /// (needs Screen Recording permission for the terminal; falls back to `cacheDisplay` without it).
    private static func capture(_ window: NSWindow, name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent("\(name).png")
        if ProcessInfo.processInfo.environment["THUBAN_PLANNER_SMOKE_WINDOW_SERVER"] == "1", captureWithWindowServer(window, to: url) {
            print("smoke: \(name) (window server)")
            return
        }
        guard let content = window.contentView else { throw ThubanError.store("smoke: window has no content view") }
        let bounds = content.bounds
        let scale = captureScale(window)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int((bounds.width * scale).rounded()), pixelsHigh: Int((bounds.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            throw ThubanError.store("smoke: could not create a bitmap for \(name)")
        }
        rep.size = bounds.size // points; the pixel grid is `scale`× so a 1× main display still yields retina PNGs
        content.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw ThubanError.store("smoke: PNG encoding failed for \(name)") }
        try png.write(to: url)
        print("smoke: \(name)")
    }

    /// Screenshots are always at least 2× (README images stay retina even when the main display is 1×).
    private static func captureScale(_ window: NSWindow) -> CGFloat { max(window.backingScaleFactor, 2) }

    /// `screencapture -l <window> -o -x`: true when it produced a non-trivial PNG (it needs Screen Recording
    /// permission for the launching terminal; without it the file is missing or only shows the desktop).
    private static func captureWithWindowServer(_ window: NSWindow, to url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l", String(window.windowNumber), "-o", "-x", url.path]
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        // Reject captures below `captureScale` (a 1× display) so `cacheDisplay` renders them at retina scale instead.
        guard process.terminationStatus == 0, let rep = NSImageRep(contentsOf: url), rep.pixelsWide > 100,
              CGFloat(rep.pixelsWide) >= window.frame.width * captureScale(window) - 1 else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }
}
