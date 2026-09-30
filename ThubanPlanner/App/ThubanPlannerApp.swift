import SwiftUI
import ThubanPlannerCore

@main
struct ThubanPlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appModel = AppModel()

    var body: some Scene {
        Window("Thuban Planner", id: "main") {
            ShellView()
                .environment(appModel)
                .frame(minWidth: 1100, minHeight: 700)
                .task { await appModel.load() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Class") {
                    appModel.section = .planner
                    appModel.addCourse()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!appModel.isLoaded || appModel.loadError != nil)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appModel.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Go") {
                ForEach(AppSection.allCases) { section in
                    Button(section.label) { appModel.section = section }
                        .keyboardShortcut(KeyEquivalent(section.shortcut), modifiers: .command)
                }
            }
            CommandMenu("Schedule") {
                Button("Previous Schedule") { appModel.scheduleTab.previousOption() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(appModel.section != .schedule || appModel.scheduleTab.optionCount < 2)
                Button("Next Schedule") { appModel.scheduleTab.nextOption() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(appModel.section != .schedule || appModel.scheduleTab.optionCount < 2)
                Divider()
                Button(appModel.scheduleTab.blockMode ? "Stop Blocking Times" : "Block Times") { appModel.scheduleTab.blockMode.toggle() }
                    .keyboardShortcut("b", modifiers: .command)
                    .disabled(appModel.section != .schedule || appModel.scheduleTab.selectedTermCode == nil)
                Button("Copy CRNs") { appModel.scheduleTab.copyCRNs() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(appModel.section != .schedule || appModel.scheduleTab.currentOption == nil)
                Button("Refresh Sections") { appModel.scheduleTab.refreshAllSections() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(appModel.section != .schedule || appModel.scheduleTab.rows.isEmpty)
                Divider()
                if appModel.scheduleTab.auth.isSignedIn {
                    Button("Sign Out of Banner") { appModel.scheduleTab.signOut() }
                } else {
                    Button("Sign In to Banner…") {
                        appModel.section = .schedule
                        appModel.scheduleTab.showSignIn = true
                    }
                }
            }
            CommandMenu("Route") {
                Button("Calculate Route") { appModel.showRoute() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Fit Route") { appModel.routeFitRequest += 1 }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(appModel.section != .route)
                Button("Zoom In") { appModel.routeZoom(by: 1.25) }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(appModel.section != .route)
                Button("Zoom Out") { appModel.routeZoom(by: 0.8) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(appModel.section != .route)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
