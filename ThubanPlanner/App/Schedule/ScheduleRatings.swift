import Foundation
import Observation
import ThubanPlannerCore
import os

/// Rate My Professors lookups for the Schedule tab: UNC Charlotte pages only, read-only (`RMPClient` +
/// `RMPRequestGuard`), cached in `rmp-cache.json` (7 days found / 2 days not found). One name at a time, paced by the
/// client. Lookups happen only when a class detail opens (that class's instructors) or when the "Highest professor
/// rating" sort is on / the user asks (every instructor of the term) — never otherwise.
@MainActor
@Observable
final class ScheduleRatings {
    /// What the UI knows about one instructor name.
    enum Lookup: Equatable {
        case loading
        /// UNC Charlotte profiles that could be this person (possibly from a stale cache entry).
        case loaded([RMPTeacher])
        case failed(String)
    }

    struct Progress: Equatable {
        var done: Int
        var total: Int
    }

    static let logger = Logger(subsystem: "org.thuban.planner", category: "rmp")

    @ObservationIgnored let store: RMPCacheStore
    @ObservationIgnored var client = RMPClient()
    @ObservationIgnored private var queue: [RMPPersonName] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var loaded = false
    /// Called after the cache changes (the Schedule model re-sorts).
    @ObservationIgnored var onChange: (() -> Void)?

    /// No network (smoke run): answers come from `RMPSampleData`.
    let offline: Bool
    /// SMOKE ONLY: offline lookups of these name keys fail (the error state).
    @ObservationIgnored var smokeFailingKeys: Set<String> = []

    private(set) var cache = RMPCache()
    private(set) var inFlight: Set<String> = []
    private(set) var errors: [String: String] = [:]
    /// The bulk lookup's progress (names), nil when none is running.
    private(set) var progress: Progress?
    @ObservationIgnored private var bulkKeys: Set<String> = []

    init(store: RMPCacheStore, offline: Bool) {
        self.store = store
        self.offline = offline
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if !offline { cache = store.load() }
    }

    // MARK: Reads (cache only)

    func lookup(_ name: RMPPersonName) -> Lookup? {
        loadIfNeeded()
        if let entry = cache.entry(for: name) { return .loaded(entry.candidates) }
        if inFlight.contains(name.key) || queue.contains(where: { $0.key == name.key }) { return .loading }
        if let error = errors[name.key] { return .failed(error) }
        return nil
    }

    /// The match for a Banner instructor teaching `subject`, from the cache only (nil = never looked up).
    func match(_ raw: String, subject: String) -> RMPMatch? {
        guard let name = RMPPersonName.parse(raw) else { return nil }
        loadIfNeeded()
        guard let entry = cache.entry(for: name) else { return nil }
        return RMPMatcher.match(name: name, candidates: entry.candidates, subject: subject)
    }

    /// True while a looked-up entry is being refreshed.
    func isRefreshing(_ name: RMPPersonName) -> Bool { inFlight.contains(name.key) }

    // MARK: Lookups

    /// Looks up one name now (ahead of any bulk lookup) unless a fresh cache entry exists.
    func request(_ name: RMPPersonName, force: Bool = false) {
        loadIfNeeded()
        if !force, cache.freshEntry(for: name, now: Date()) != nil { return }
        errors[name.key] = nil
        queue.removeAll { $0.key == name.key }
        guard !inFlight.contains(name.key) else { return }
        queue.insert(name, at: 0)
        startWorker()
    }

    /// Looks up every name without a fresh entry (deduplicated), in order, reporting progress.
    func requestAll(_ raw: [String]) {
        loadIfNeeded()
        var seen = Set<String>()
        let names = raw.compactMap(RMPPersonName.parse).filter { seen.insert($0.key).inserted }
        let now = Date()
        let missing = names.filter { cache.freshEntry(for: $0, now: now) == nil && errors[$0.key] == nil }
        let newKeys = missing.map(\.key).filter { !bulkKeys.contains($0) }
        guard !newKeys.isEmpty else { return }
        if progress == nil { progress = Progress(done: 0, total: 0); bulkKeys = [] }
        for name in missing where !bulkKeys.contains(name.key) {
            bulkKeys.insert(name.key)
            progress?.total += 1
            if !inFlight.contains(name.key), !queue.contains(where: { $0.key == name.key }) { queue.append(name) }
        }
        startWorker()
    }

    private func startWorker() {
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task { [weak self] in
            await self?.drain()
            self?.worker = nil
            if let self, !self.queue.isEmpty { self.startWorker() }
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            let name = queue.removeFirst()
            inFlight.insert(name.key)
            do {
                let candidates: [RMPTeacher]
                if offline {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    if smokeFailingKeys.contains(name.key) { throw RMPError.network("The Internet connection appears to be offline.") }
                    candidates = RMPSampleData.candidates(for: name)
                } else {
                    candidates = try await client.candidates(for: name)
                }
                cache.store(candidates, for: name, at: Date())
                errors[name.key] = nil
                save()
            } catch {
                Self.logger.error("RMP lookup failed: \(error.localizedDescription, privacy: .public)")
                errors[name.key] = error.localizedDescription
            }
            inFlight.remove(name.key)
            if bulkKeys.contains(name.key) {
                progress?.done += 1
                if let p = progress, p.done >= p.total { progress = nil; bulkKeys = [] }
            }
            onChange?()
        }
        if progress != nil, queue.isEmpty { progress = nil; bulkKeys = [] }
    }

    private func save() {
        guard !offline else { return }
        do { try store.save(cache) } catch {
            Self.logger.error("rmp-cache.json save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// SMOKE ONLY: fills the cache from the sample data for these names, synchronously.
    func smokeFill(_ raw: [String]) {
        guard offline else { return }
        loadIfNeeded()
        for name in raw.compactMap(RMPPersonName.parse) { cache.store(RMPSampleData.candidates(for: name), for: name, at: Date()) }
        onChange?()
    }

    /// SMOKE ONLY: forgets every answer; lookups of `failing` names then fail.
    func smokeReset(failing: [String] = []) {
        guard offline else { return }
        cache = RMPCache()
        errors = [:]
        smokeFailingKeys = Set(failing.compactMap(RMPPersonName.parse).map(\.key))
        onChange?()
    }
}
