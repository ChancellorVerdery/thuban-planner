import Foundation
import ThubanPlannerCore
import WebKit
import os

/// Everything that needs the student's UNC Charlotte sign-in runs INSIDE WebKit, on the persistent default website
/// data store — the store the sign-in sheet's web view uses. The app never signs in by itself, never sees or stores
/// a password (no Keychain) and never reads any browser's cookies: the user signs in on UNC Charlotte's own page in
/// the sheet, and the session lives in this app's WebKit store until "Sign out" removes it.
///
/// Enforcement in WebKit: `BannerNavigationGuard` cancels any navigation to a denied endpoint (and any POST
/// navigation to Banner outside the read-only allowlist); compiled content rules block the denied fragments for every
/// load (`contentRuleListJSON` in the sign-in view; `exportContentRuleListJSON` + the page fence script in the hidden
/// export view); the exporter's own requests pass `BannerRequestGuard.check` (with the user's one-shot
/// `BannerExportAuthorization` for the two plan-creation writes) before they are sent.
@MainActor
enum BannerWebKit {
    static let logger = Logger(subsystem: "org.thuban.planner", category: "banner")

    /// The sign-in start page: Plan Ahead's term selection (UNC Charlotte's sign-in page when signed out).
    static var signInURL: URL { BannerPlanExport.planAheadURL }

    /// The sign-in sheet's configuration: persistent default store, every write blocked.
    static func signInConfiguration() async -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        if let list = await compile(id: "org.thuban.planner.banner-signin", json: BannerRequestGuard.contentRuleListJSON, cache: \.signIn) {
            config.userContentController.add(list)
        }
        return config
    }

    /// The hidden export view's configuration: same store; registration / existing-plan writes blocked by content
    /// rules; Banner's own page scripts fenced off every denied endpoint.
    static func exportConfiguration() async throws -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        guard let list = await compile(id: "org.thuban.planner.banner-export", json: BannerRequestGuard.exportContentRuleListJSON, cache: \.export) else {
            throw BannerError.blocked("The export’s safety rules couldn’t be set up, so nothing was sent.")
        }
        config.userContentController.add(list)
        config.userContentController.addUserScript(WKUserScript(source: BannerRequestGuard.pageFenceScript, injectionTime: .atDocumentStart,
                                                                forMainFrameOnly: false, in: .page))
        return config
    }

    private static func compile(id: String, json: String, cache: ReferenceWritableKeyPath<RuleCache, WKContentRuleList?>) async -> WKContentRuleList? {
        if let existing = RuleCache.shared[keyPath: cache] { return existing }
        do {
            let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: id, encodedContentRuleList: json)
            RuleCache.shared[keyPath: cache] = list
            return list
        } catch {
            logger.error("content rule list failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @MainActor final class RuleCache {
        static let shared = RuleCache()
        var signIn: WKContentRuleList?
        var export: WKContentRuleList?
    }

    private static func isUNCC(_ domain: String) -> Bool {
        let d = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return d == "uncc.edu" || d.hasSuffix(".uncc.edu")
    }

    /// True when the app's WebKit store holds any UNC Charlotte cookie (the user signed in at some point). Local only.
    static func hasUNCCCookies() async -> Bool {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.contains { isUNCC($0.domain) }
    }

    /// Sign out: deletes every UNC Charlotte cookie and website data record (selfservice, webauth …) from the store.
    static func signOut() async {
        let store = WKWebsiteDataStore.default()
        for cookie in await store.httpCookieStore.allCookies() where isUNCC(cookie.domain) {
            await store.httpCookieStore.deleteCookie(cookie)
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let uncc = records.filter { isUNCC($0.displayName) }
        if !uncc.isEmpty { await store.removeData(ofTypes: types, for: uncc) }
    }
}

/// The navigation policy both web views use (see `BannerWebKit`).
@MainActor
final class BannerNavigationGuard {
    /// Last block, for the sheet to show.
    var onBlocked: ((String) -> Void)?

    func decide(_ action: WKNavigationAction) -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .allow }
        if case .deny(let why) = BannerRequestGuard.checkBrowser(url: url) {
            BannerWebKit.logger.notice("blocked navigation: \(url.absoluteString, privacy: .public)")
            onBlocked?(why)
            return .cancel
        }
        // Form posts to Banner itself: only the read-only endpoints.
        if (action.request.httpMethod ?? "GET").uppercased() == "POST", url.host?.lowercased() == BannerRequestGuard.host,
           case .deny(let why) = BannerRequestGuard.check(method: "POST", url: url) {
            onBlocked?(why)
            return .cancel
        }
        return .allow
    }
}

/// What the confirmation sheet needs to know before anything is written.
struct BannerExportPreflight: Equatable {
    var studentName: String?
    var planCount: Int?
    var maxPlans: Int?

    var isFull: Bool {
        guard let maxPlans, maxPlans > 0, let planCount else { return false }
        return planCount >= maxPlans
    }
}

/// The result of a finished export.
struct BannerExportOutcome: Equatable {
    var planName: String
    var sequenceNumber: Int?
    var classCount: Int
    /// The read-back found the plan with exactly the exported CRNs.
    var verified: Bool
    /// A note when the read-back couldn't confirm everything.
    var note: String?
    var dryRun: Bool
}

enum BannerExportFailure: Error, Equatable, LocalizedError {
    case signedOut
    /// The student already has Banner's maximum number of plans for the term.
    case full(count: Int, max: Int)
    /// Something stopped the export; `wroteNothing` = no plan was saved.
    case failed(String, wroteNothing: Bool)

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Your UNC Charlotte sign-in has ended. Sign in again to export."
        case .full(let count, let max): return "You already have \(count) of \(max) plans for this term."
        case .failed(let message, _): return message
        }
    }
}

/// A hidden web view (same WebKit store as the sign-in sheet) that reads Plan Ahead and — only with the user's
/// `BannerExportAuthorization` — creates ONE new plan. It never clicks anything on Banner's pages; Banner's own
/// scripts are fenced off every write. Request sequence:
///
/// 1. GET  term/termSelection?mode=plan            (a sign-in page instead = signed out)
/// 2. POST term/search?mode=plan  term=<code>…      (read-only: selects the term for the session)
/// 3. GET  plan/selectPlan                          (bootstraps: planCount, maxPlans, existing plans)
/// 4. GET  plan/plan                                (the new-plan page: must be a new, empty plan; its save / add
///                                                   endpoints and name maxlength are read)
/// 5. POST plan/addPlanItem  term, courseReferenceNumber, section=section   (once per confirmed CRN)
/// 6. POST plan/submitPlan/batch  {create:[models + headerDescription], update:[], destroy:[]}
/// 7. GET  plan/selectPlan                          (read back: the new plan with exactly those CRNs)
@MainActor
final class BannerPlanExporter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private let guardPolicy = BannerNavigationGuard()
    private var pending: CheckedContinuation<URL, Error>?
    private var timeoutTask: Task<Void, Never>?
    /// The exporter's own requests run here, with the unfenced `fetch`.
    private let world = WKContentWorld.world(name: "thuban-export")
    /// Progress text for the sheet.
    var onStep: ((String) -> Void)?

    private func view() async throws -> WKWebView {
        if let webView { return webView }
        let config = try await BannerWebKit.exportConfiguration()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        view.navigationDelegate = self
        guardPolicy.onBlocked = { [weak self] why in self?.resume(.failure(BannerError.blocked(why))) }
        webView = view
        return view
    }

    // MARK: Public steps

    /// Steps 1–3: signed in? how many plans? Read-only.
    func preflight(termCode: String) async throws -> BannerExportPreflight {
        onStep?("Checking your Plan Ahead plans…")
        let name = try await openPlanAhead()
        try await selectTerm(termCode)
        _ = try await open(BannerPlanExport.selectPlanURL)
        let info = try await pageInfo()
        return BannerExportPreflight(studentName: name, planCount: info?.planCount ?? info.map { $0.plans.count },
                                     maxPlans: info?.maxPlans)
    }

    /// The whole export (steps 1–7). `authorization` is the user's one-shot permission; it is revoked on return.
    func export(items: [BannerPlanExportItem], name rawName: String, termCode: String,
                authorization: BannerExportAuthorization) async throws -> BannerExportOutcome {
        defer { authorization.revoke() }
        let name = BannerPlanExport.cleanName(rawName)
        let crns = items.map(\.crn)
        guard authorization.termCode == termCode, authorization.crns == crns else {
            throw BannerExportFailure.failed("The classes changed after you confirmed. Nothing was sent.", wroteNothing: true)
        }

        onStep?("Opening Plan Ahead…")
        _ = try await openPlanAhead()
        try await selectTerm(termCode)
        _ = try await open(BannerPlanExport.selectPlanURL)
        let before = try await pageInfo()
        let previous = Set(before?.plans.map(\.sequenceNumber) ?? [])
        if let before, before.isFull {
            throw BannerExportFailure.full(count: before.planCount ?? before.plans.count, max: before.maxPlans ?? BannerPlanExport.documentedMaxPlans)
        }

        onStep?("Starting a new plan…")
        _ = try await open(BannerPlanExport.newPlanURL)
        let page = try await newPlanPage()
        guard page.hasPlanData, let info = page.info else {
            throw BannerExportFailure.failed("Banner didn’t open a plan page, so nothing was sent.", wroteNothing: true)
        }
        guard info.isNewEmptyPlan else {
            throw BannerExportFailure.failed("Banner opened an existing plan instead of a new one, so nothing was sent — your plans weren’t touched.",
                                             wroteNothing: true)
        }
        if let save = page.saveEndpoint, !Self.sameEndpoint(save + "/batch", BannerPlanExport.submitPlanBatchURL) {
            throw BannerExportFailure.failed("Banner’s plan page saves somewhere unexpected (\(save)), so nothing was sent.", wroteNothing: true)
        }
        if let add = page.addEndpoint, !Self.sameEndpoint(add, BannerPlanExport.addPlanItemURL) {
            throw BannerExportFailure.failed("Banner’s plan page adds classes somewhere unexpected (\(add)), so nothing was sent.", wroteNothing: true)
        }
        if let limit = page.nameLimit, limit > 0, let problem = BannerPlanExport.nameProblem(name, limit: limit) {
            throw BannerExportFailure.failed("\(problem) Nothing was sent.", wroteNothing: true)
        }

        // Step 5: add each section (nothing is saved until step 6).
        var models: [JSONValue] = []
        for (index, item) in items.enumerated() {
            onStep?("Adding \(item.courseCode) (\(index + 1) of \(items.count))…")
            let request = BannerPlanExport.addPlanItemRequest(term: termCode, crn: item.crn)
            let response = try await send(request, authorization: authorization)
            switch BannerPlanExport.parseAddPlanItem(response, crn: item.crn) {
            case .added(let model): models.append(model)
            case .rejected(let message):
                throw BannerExportFailure.failed("Banner didn’t accept \(item.courseCode) \(item.section). \(message) No plan was saved.", wroteNothing: true)
            }
        }

        // Step 6: save the new plan.
        onStep?("Saving “\(name)”…")
        let submit = BannerPlanExport.submitPlanRequest(models: models, name: name)
        let answer = try await send(submit, authorization: authorization)
        let sequence: Int?
        switch BannerPlanExport.parseSubmitPlan(answer) {
        case .saved(let seq, _): sequence = seq
        case .rejected(let message):
            throw BannerExportFailure.failed("Banner didn’t save the plan: \(message)", wroteNothing: false)
        }
        authorization.revoke()

        // Step 7: read it back.
        onStep?("Checking the new plan…")
        _ = try? await open(BannerPlanExport.selectPlanURL)
        let after = (try? await pageInfo()) ?? nil
        switch BannerPlanExport.verify(plans: after?.plans ?? [], name: name, sequenceNumber: sequence, term: termCode,
                                       crns: crns, previousSequences: previous) {
        case .verified(let plan):
            return BannerExportOutcome(planName: plan.displayName, sequenceNumber: plan.sequenceNumber, classCount: items.count,
                                       verified: true, note: nil, dryRun: false)
        case .mismatch(let plan, let missing, let extra):
            var parts: [String] = []
            if !missing.isEmpty { parts.append("missing CRN \(missing.joined(separator: ", "))") }
            if !extra.isEmpty { parts.append("also has CRN \(extra.joined(separator: ", "))") }
            return BannerExportOutcome(planName: plan.displayName, sequenceNumber: plan.sequenceNumber, classCount: items.count - missing.count,
                                       verified: false, note: "Banner saved the plan, but it \(parts.joined(separator: " and ")). Check it in Plan Ahead.",
                                       dryRun: false)
        case .notFound:
            return BannerExportOutcome(planName: name, sequenceNumber: sequence, classCount: items.count, verified: false,
                                       note: "Banner said the plan was saved, but it didn’t show up when read back. Check Plan Ahead.", dryRun: false)
        }
    }

    // MARK: Pieces

    /// Step 1: the Plan Ahead term page; throws `.signedOut` on a sign-in page. Returns the student's name.
    private func openPlanAhead() async throws -> String? {
        do {
            _ = try await open(BannerPlanExport.planAheadURL)
        } catch BannerError.signedOut {
            throw BannerExportFailure.signedOut
        }
        let name = try? await webView?.evaluateJavaScript("document.querySelector('meta[name=\"fullName\"]')?.content || ''") as? String
        return name.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Step 2: POST term/search?mode=plan (read-only) from inside the page.
    private func selectTerm(_ code: String) async throws {
        let form = "term=\(code)&studyPath=&studyPathText=&startDatepicker=&endDatepicker="
        let request = BannerExportRequest(method: "POST", url: BannerPlanExport.termSearchURL,
                                          contentType: "application/x-www-form-urlencoded; charset=UTF-8", body: Data(form.utf8))
        let data = try await send(request, authorization: nil)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        if BannerPage.looksLikeHTML(data), text.contains("webauth") { throw BannerExportFailure.signedOut }
    }

    private func pageInfo() async throws -> BannerPlanPageInfo? {
        guard let view = webView,
              let json = try await view.evaluateJavaScript("JSON.stringify(window.bootstraps || null)") as? String,
              json != "null" else { return nil }
        return try? BannerPlanPageInfo.parse(bootstrapsJSON: Data(json.utf8))
    }

    private struct NewPlanPage {
        var info: BannerPlanPageInfo?
        var hasPlanData: Bool
        var saveEndpoint: String?
        var addEndpoint: String?
        var nameLimit: Int?
    }

    private func newPlanPage() async throws -> NewPlanPage {
        guard let view = webView else { return NewPlanPage(info: nil, hasPlanData: false) }
        let script = """
        JSON.stringify({
          hasPlan: !!(window.bootstraps && window.bootstraps.selectedPlan),
          save: document.querySelector('#saveButton')?.getAttribute('data-plan-save-endpoint') || null,
          add: document.querySelector('#addPlanItem')?.getAttribute('data-endpoint') || null,
          max: parseInt(document.querySelector('#txt_planDesc')?.getAttribute('maxlength') || '0', 10) || null
        })
        """
        let raw = try await view.evaluateJavaScript(script) as? String ?? "{}"
        let value = try? JSONValue.parse(Data(raw.utf8))
        return NewPlanPage(info: try await pageInfo(),
                           hasPlanData: value?["hasPlan"] == .bool(true) || value?["save"]?.stringValue != nil,
                           saveEndpoint: value?["save"]?.stringValue, addEndpoint: value?["add"]?.stringValue,
                           nameLimit: value?["max"].flatMap { if case .number(let n) = $0 { return Int(n) } else { return nil } })
    }

    static func sameEndpoint(_ raw: String, _ expected: URL) -> Bool {
        guard let url = URL(string: raw, relativeTo: URL(string: "https://selfservice.uncc.edu")!)?.absoluteURL else { return false }
        func norm(_ u: URL) -> String { (u.host ?? "").lowercased() + u.path.lowercased().replacingOccurrences(of: "//", with: "/") }
        return norm(url) == norm(expected)
    }

    /// Sends one request with `fetch` (credentials, the page's synchronizer token) from the exporter's own content
    /// world — after `BannerRequestGuard` allowed it.
    private func send(_ request: BannerExportRequest, authorization: BannerExportAuthorization?) async throws -> Data {
        if case .deny(let why) = BannerRequestGuard.check(method: request.method, url: request.url, body: request.body, export: authorization) {
            throw BannerExportFailure.failed(why, wroteNothing: true)
        }
        guard let view = webView else { throw BannerExportFailure.failed("Plan Ahead isn’t open.", wroteNothing: true) }
        BannerWebKit.logger.notice("export request: \(request.method, privacy: .public) \(request.url.absoluteString, privacy: .public)")
        let script = """
        const token = document.querySelector('meta[name="synchronizerToken"]')?.content || '';
        const r = await fetch(url, { method: method, credentials: 'include', redirect: 'follow',
          headers: { 'Content-Type': contentType, 'X-Synchronizer-Token': token, 'X-Requested-With': 'XMLHttpRequest',
                     'Accept': 'application/json, text/javascript, */*; q=0.01' }, body: body });
        return JSON.stringify({ status: r.status, url: r.url, text: await r.text() });
        """
        let raw: Any?
        do {
            raw = try await view.callAsyncJavaScript(script, arguments: ["url": request.url.absoluteString, "method": request.method,
                                                                          "contentType": request.contentType, "body": request.bodyText],
                                                     in: nil, contentWorld: world)
        } catch {
            throw BannerExportFailure.failed("Couldn’t reach Banner: \(error.localizedDescription)", wroteNothing: request.url != BannerPlanExport.submitPlanBatchURL)
        }
        guard let text = raw as? String, let value = try? JSONValue.parse(Data(text.utf8)) else {
            throw BannerExportFailure.failed("Banner’s answer couldn’t be read.", wroteNothing: request.url != BannerPlanExport.submitPlanBatchURL)
        }
        if let final = value["url"]?.stringValue.flatMap(URL.init(string:)), BannerPage.isSignInURL(final) { throw BannerExportFailure.signedOut }
        let status: Int = { if case .number(let n)? = value["status"] { return Int(n) } else { return 0 } }()
        let body = Data((value["text"]?.stringValue ?? "").utf8)
        if status == 401 || status == 403 { throw BannerExportFailure.signedOut }
        if status >= 400, request.url != BannerPlanExport.submitPlanBatchURL {
            throw BannerExportFailure.failed("Banner answered with an error (HTTP \(status)).", wroteNothing: true)
        }
        return body
    }

    /// Loads `url` and returns the final URL after redirects. Throws `.signedOut` when it lands on a sign-in page.
    private func open(_ url: URL, timeout: Double = 30) async throws -> URL {
        if case .deny(let why) = BannerRequestGuard.checkBrowser(url: url) { throw BannerError.blocked(why) }
        let view = try await view()
        pending?.resume(throwing: CancellationError())
        pending = nil
        var final: URL = try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            view.load(URLRequest(url: url))
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled, let self, let pending = self.pending else { return }
                self.pending = nil
                view.stopLoading()
                pending.resume(throwing: BannerError.network("Banner took too long to answer."))
            }
        }
        // Single sign-on may hop through a page that forwards itself by script: give it a moment before deciding.
        var hops = 0
        while BannerPage.isSignInURL(final), hops < 3 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard view.isLoading || view.url != final else { break }
            if view.isLoading {
                final = try await withCheckedThrowingContinuation { continuation in pending = continuation }
            } else if let url = view.url {
                final = url
            }
            hops += 1
        }
        if BannerPage.isSignInURL(final) { throw BannerExportFailure.signedOut }
        return final
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(guardPolicy.decide(navigationAction))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(webView.url ?? BannerPlanExport.planAheadURL))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<URL, Error>) {
        guard pending != nil else { return }
        // A navigation cancelled by a redirect / our own policy reports NSURLErrorCancelled; wait for the real one.
        if case .failure(let error) = result, (error as NSError).code == NSURLErrorCancelled, (error as NSError).domain == NSURLErrorDomain { return }
        if case .failure(let error) = result, (error as NSError).domain == "WebKitErrorDomain", (error as NSError).code == 102 { return }
        resume(result.mapError { $0 is BannerError || $0 is BannerExportFailure ? $0 : BannerError.network($0.localizedDescription) })
    }

    private func resume(_ result: Result<URL, Error>) {
        guard let pending else { return }
        self.pending = nil
        timeoutTask?.cancel()
        switch result {
        case .success(let url): pending.resume(returning: url)
        case .failure(let error): pending.resume(throwing: error)
        }
    }
}
