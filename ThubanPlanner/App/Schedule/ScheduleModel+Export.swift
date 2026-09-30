import AppKit
import Foundation
import ThubanPlannerCore

/// Where the Schedule tab is with the (optional) UNC Charlotte sign-in.
enum ScheduleAuth: Equatable {
    /// Cookies exist from an earlier sign-in; not checked against Banner yet.
    case unknown
    case signedOut
    /// Was signed in; the session ended.
    case expired
    case signedIn(name: String?)

    var isSignedIn: Bool { if case .signedIn = self { return true }; return false }
}

/// The export sheet's stage.
enum ScheduleExportPhase: Equatable {
    /// Reading Plan Ahead (signed in? how many plans?) — nothing is written.
    case checking
    /// Waiting for the user's "Create plan".
    case ready
    /// Banner's plan limit is reached: export impossible.
    case full(count: Int, max: Int)
    case working(String)
    case done(BannerExportOutcome)
    case failed(String, wroteNothing: Bool)

    var isBusy: Bool {
        switch self {
        case .checking, .working: return true
        default: return false
        }
    }
}

/// Everything the export sheet shows: the term, the exact sections, the plan name, the stage.
struct ScheduleExportDraft: Identifiable, Equatable {
    let id = UUID()
    var termCode: String
    var termLabel: String
    var scheduleNumber: Int
    var items: [BannerPlanExportItem]
    var credits: Double
    var name: String
    var phase: ScheduleExportPhase
    var preflight: BannerExportPreflight?
    /// THUBAN_PLANNER_EXPORT_DRY_RUN=1: requests are built and logged, never sent.
    var dryRun: Bool
    /// Banner's name limit (the live page's maxlength when known).
    var nameLimit: Int = BannerPlanExport.fallbackNameLimit

    var nameProblem: String? { BannerPlanExport.nameProblem(name, limit: nameLimit) }
}

extension ScheduleModel {
    // MARK: Sign-in

    /// At activation: a stored UNC Charlotte cookie means "signed in earlier" (checked only when exporting). Local only.
    func checkStoredSignIn() {
        Task { [weak self] in
            let has = await BannerWebKit.hasUNCCCookies()
            guard let self, !self.auth.isSignedIn else { return }
            self.auth = has ? .unknown : .signedOut
        }
    }

    /// Opens UNC Charlotte's sign-in page in the sheet (only when the user asks, or an export needs it).
    func signIn() {
        guard !offline else { showSignIn = true; return }
        showSignIn = true
    }

    /// Called by the sign-in sheet when a signed-in Banner page loaded.
    func didSignIn(name: String?) {
        if case .signedIn(let old) = auth, name == nil { auth = .signedIn(name: old); return }
        auth = .signedIn(name: name)
    }

    /// Called by the sign-in sheet when Banner says this session is NOT signed in (e.g. the public landing page).
    func markNotSignedIn() {
        if auth.isSignedIn || auth == .unknown { auth = .signedOut }
    }

    /// The sign-in sheet closed: continue the export that asked for it.
    func signInSheetClosed() {
        guard exportAfterSignIn else { return }
        exportAfterSignIn = false
        guard auth.isSignedIn else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000) // let the sheet finish closing
            self?.beginExport()
        }
    }

    /// Removes every uncc.edu cookie / website record from the app's WebKit store.
    func signOut() {
        exporter = nil
        Task { [weak self] in
            await BannerWebKit.signOut()
            self?.auth = .signedOut
        }
    }

    var studentName: String? { if case .signedIn(let name?) = auth { return name }; return nil }

    // MARK: Export

    /// True when "Export to Banner…" can start (a timetable is on screen).
    var canExport: Bool { currentOption != nil && selectedTermCode != nil && !blockMode && exportDraft == nil }

    /// "Export to Banner…": sign in first when needed, then the confirmation sheet (which reads Plan Ahead's plan
    /// count). Nothing is written until the user clicks "Create plan".
    func beginExport() {
        guard let option = currentOption, let code = selectedTermCode else { return }
        let dryRun = BannerPlanExport.isDryRun()
        let draft = ScheduleExportDraft(termCode: code, termLabel: selectedTermLabel, scheduleNumber: selectedIndex + 1,
                                        items: BannerPlanExport.items(for: option), credits: BannerPlanExport.totalCredits(option),
                                        name: BannerPlanExport.defaultName(termLabel: selectedTermLabel, scheduleNumber: selectedIndex + 1),
                                        phase: dryRun || offline ? .ready : .checking, preflight: nil, dryRun: dryRun)
        if dryRun || offline {
            exportDraft = draft
            return
        }
        guard auth.isSignedIn || auth == .unknown else {
            exportAfterSignIn = true
            showSignIn = true
            return
        }
        exportDraft = draft
        runPreflight()
    }

    /// Reads Plan Ahead for the confirmation (signed in? plan count / limit). Read-only.
    func runPreflight() {
        guard let draft = exportDraft, !draft.dryRun, !offline else { return }
        updateDraft { $0.phase = .checking }
        let exporter = exporter ?? BannerPlanExporter()
        self.exporter = exporter
        exporter.onStep = nil
        exportTask = Task { [weak self] in
            do {
                let result = try await exporter.preflight(termCode: draft.termCode)
                guard let self else { return }
                self.auth = .signedIn(name: result.studentName ?? self.studentName)
                self.updateDraft { d in
                    d.preflight = result
                    d.phase = result.isFull ? .full(count: result.planCount ?? 0, max: result.maxPlans ?? BannerPlanExport.documentedMaxPlans) : .ready
                }
            } catch BannerExportFailure.signedOut {
                self?.needsSignInAgain()
            } catch {
                self?.updateDraft { $0.phase = .failed(error.localizedDescription, wroteNothing: true) }
            }
        }
    }

    /// The session ended: close the export, open sign-in, and come back after.
    private func needsSignInAgain() {
        auth = .expired
        exportDraft = nil
        exportAfterSignIn = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.showSignIn = true
        }
    }

    func updateDraft(_ change: (inout ScheduleExportDraft) -> Void) {
        guard var draft = exportDraft else { return }
        change(&draft)
        exportDraft = draft
    }

    /// The user clicked "Create plan": mint the one-shot authorization for exactly these sections and run the export.
    func confirmExport() {
        guard let draft = exportDraft, draft.phase == .ready, draft.nameProblem == nil, !draft.items.isEmpty else { return }
        let name = BannerPlanExport.cleanName(draft.name)
        let crns = draft.items.map(\.crn)
        if draft.dryRun || offline {
            let requests = BannerPlanExport.plannedRequests(items: draft.items, name: name)
            for (i, r) in requests.enumerated() {
                Self.logger.notice("export dry run \(i + 1)/\(requests.count): \(r.logLine, privacy: .public)")
                print("export dry run \(i + 1)/\(requests.count): \(r.logLine)")
            }
            updateDraft { $0.phase = .done(BannerExportOutcome(planName: name, sequenceNumber: nil, classCount: draft.items.count,
                                                                verified: false, note: "Dry run — \(requests.count) requests logged, nothing sent to Banner.",
                                                                dryRun: true)) }
            return
        }
        let authorization = BannerExportAuthorization(termCode: draft.termCode, crns: crns)
        let exporter = exporter ?? BannerPlanExporter()
        self.exporter = exporter
        exporter.onStep = { [weak self] text in self?.updateDraft { $0.phase = .working(text) } }
        updateDraft { $0.phase = .working("Opening Plan Ahead…") }
        exportTask = Task { [weak self] in
            do {
                let outcome = try await exporter.export(items: draft.items, name: name, termCode: draft.termCode, authorization: authorization)
                self?.updateDraft { $0.phase = .done(outcome) }
            } catch BannerExportFailure.signedOut {
                self?.auth = .expired
                self?.updateDraft { $0.phase = .failed("Your UNC Charlotte sign-in ended before the plan was saved, so nothing was created. Sign in again and export.",
                                                        wroteNothing: true) }
            } catch BannerExportFailure.full(let count, let max) {
                self?.updateDraft { $0.phase = .full(count: count, max: max) }
            } catch BannerExportFailure.failed(let message, let wroteNothing) {
                self?.updateDraft { $0.phase = .failed(message, wroteNothing: wroteNothing) }
            } catch {
                self?.updateDraft { $0.phase = .failed(error.localizedDescription, wroteNothing: true) }
            }
            authorization.revoke()
            exporter.onStep = nil
        }
    }

    /// "Try again" after a failure that wrote nothing.
    func retryExport() {
        guard let draft = exportDraft, case .failed(_, true) = draft.phase else { return }
        if auth == .expired || auth == .signedOut {
            needsSignInAgain()
        } else if draft.dryRun || offline {
            updateDraft { $0.phase = .ready }
        } else {
            runPreflight()
        }
    }

    func closeExport() {
        if case .working? = exportDraft?.phase { return } // never abandon a running write
        exportTask?.cancel()
        exportTask = nil
        exportDraft = nil
    }

    /// Opens Banner's Plan Ahead in the default browser.
    func openPlanAhead() { NSWorkspace.shared.open(BannerPlanExport.planAheadURL) }

    // MARK: Smoke

    /// SMOKE ONLY: shows the export sheet in a given stage (offline, sample timetable).
    func smokeShowExport(_ phase: ScheduleExportPhase, auth: ScheduleAuth = .signedIn(name: "Sample Student"),
                         preflight: BannerExportPreflight? = BannerExportPreflight(studentName: "Sample Student", planCount: 2, maxPlans: 5)) {
        guard offline, let option = currentOption, let code = selectedTermCode else { return }
        self.auth = auth
        exportDraft = ScheduleExportDraft(termCode: code, termLabel: selectedTermLabel, scheduleNumber: selectedIndex + 1,
                                          items: BannerPlanExport.items(for: option), credits: BannerPlanExport.totalCredits(option),
                                          name: BannerPlanExport.defaultName(termLabel: selectedTermLabel, scheduleNumber: selectedIndex + 1),
                                          phase: phase, preflight: preflight, dryRun: false)
    }

    /// SMOKE ONLY.
    func smokeSetAuth(_ auth: ScheduleAuth) {
        guard offline else { return }
        self.auth = auth
    }
}
