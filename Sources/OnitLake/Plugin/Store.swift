import Foundation

enum OverallState: Equatable {
    case empty
    case ok
    case running
    case headsUp
    case failed
}

/// onit's JobStore without the UI: polls launchd and cron, keeps run history, and runs actions.
/// Adapted from onit (Onit/Models/JobStore.swift); hidden tasks are kept in this plugin's own file.
@MainActor
final class Store {
    private(set) var jobs: [Job] = []
    let history = RunHistory()
    private var prefs: Prefs
    private var pollTask: Task<Void, Never>?
    var onChange: (() -> Void)?

    private static let pollInterval: Duration = .seconds(10)

    init() {
        prefs = Prefs.load()
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.refresh()
            await self?.backfillFromSystemLog()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        let scanned = await Task.detached(priority: .utility) {
            LaunchdScanner.scan() + CronScanner.scan()
        }.value

        var updated = scanned.map { job in
            var job = job
            job.isHidden = prefs.hidden.contains(job.id) || (job.looksSystemOwned && !prefs.shown.contains(job.id))
            return job
        }
        history.observe(updated.filter { !$0.isHidden })
        updated = updated.map(applyHistory)
        jobs = updated
        onChange?()
    }

    private func backfillFromSystemLog() async {
        let candidates = jobs.filter { $0.source == .launchd && !$0.isHidden && !$0.isAlwaysOn && history.records(for: $0.id).isEmpty }
        let labels = Set(candidates.map(\.label))
        guard !labels.isEmpty else { return }
        let ends = await Task.detached(priority: .background) { LaunchdLog.recentRunEnds(for: labels) }.value
        for job in candidates {
            history.backfill(jobID: job.id, ends: ends[job.label] ?? [], lastExitCode: job.lastExitCode)
        }
        jobs = jobs.map(applyHistory)
        onChange?()
    }

    private func applyHistory(_ job: Job) -> Job {
        var job = job
        let records = history.records(for: job.id)
        job.lastRun = records.last.map { $0.end ?? $0.start } ?? RunHistory.lastLogWrite(for: job)
        return job
    }

    // MARK: - Derived state

    var activeJobs: [Job] { jobs.filter { !$0.isHidden } }

    var visibleJobs: [Job] {
        let now = Date.now
        return activeJobs.sorted { lhs, rhs in
            let left = sortRank(lhs), right = sortRank(rhs)
            if left != right { return left < right }
            let leftNext = nextRun(for: lhs, now: now) ?? .distantFuture
            let rightNext = nextRun(for: rhs, now: now) ?? .distantFuture
            if leftNext != rightNext { return leftNext < rightNext }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var hiddenCount: Int { jobs.filter(\.isHidden).count }
    var overlapCount: Int { activeJobs.filter(\.schedule.hasOverlap).count }
    var failedJobs: [Job] { activeJobs.filter(\.isFailed) }
    /// Running jobs that will finish, as opposed to always-on ones.
    var runningJobs: [Job] { activeJobs.filter { $0.state == .running && !$0.isAlwaysOn } }

    var overallState: OverallState {
        let active = activeJobs
        if active.isEmpty { return .empty }
        if !failedJobs.isEmpty { return .failed }
        if active.contains(where: \.schedule.hasOverlap) { return .headsUp }
        if !runningJobs.isEmpty { return .running }
        return .ok
    }

    func job(id: String) -> Job? {
        jobs.first { $0.id == id }
    }

    func nextRun(for job: Job, now: Date) -> Date? {
        guard job.state != .paused else { return nil }
        return ScheduleText.nextRun(for: job.schedule, lastRun: job.lastRun, after: now)
    }

    func nextUp(now: Date) -> (job: Job, date: Date)? {
        activeJobs
            .compactMap { job in nextRun(for: job, now: now).map { (job, $0) } }
            .min { $0.1 < $1.1 }
    }

    func runningSince(_ job: Job) -> Date? {
        guard job.state == .running else { return nil }
        return history.records(for: job.id).last { $0.end == nil }?.start
    }

    func records(for job: Job) -> [RunRecord] {
        history.records(for: job.id)
    }

    func failureStreak(for job: Job) -> Int {
        var streak = 0
        for record in history.records(for: job.id).reversed() {
            guard let code = record.exitCode, code != 0 else { break }
            streak += 1
        }
        return job.isFailed ? max(streak, 1) : streak
    }

    private func sortRank(_ job: Job) -> Int {
        switch job.state {
        case .failed: 0
        case .running where !job.isAlwaysOn: 1
        case .paused: 4
        default: job.schedule.hasOverlap ? 2 : 3
        }
    }

    // MARK: - Actions

    func runNow(_ job: Job) async {
        switch job.source {
        case .launchd:
            let target = "\(Shell.guiDomain)/\(job.label)"
            let plistPath = job.plistURL?.path
            await Task.detached {
                if Shell.launchctl("kickstart", target).status != 0, let plistPath {
                    Shell.launchctl("bootstrap", Shell.guiDomain, plistPath)
                    Shell.launchctl("kickstart", target)
                }
            }.value
        case .cron:
            let command = job.commandLine
            await Task.detached { Shell.spawn(command) }.value
        }
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    func setPaused(_ job: Job, paused: Bool) async {
        guard job.source == .launchd, let plistPath = job.plistURL?.path else { return }
        let target = "\(Shell.guiDomain)/\(job.label)"
        await Task.detached {
            if paused {
                Shell.launchctl("disable", target)
                Shell.launchctl("bootout", target)
            } else {
                Shell.launchctl("enable", target)
                Shell.launchctl("bootstrap", Shell.guiDomain, plistPath)
            }
        }.value
        await refresh()
    }

    func setHidden(_ job: Job, hidden: Bool) {
        if hidden {
            prefs.hidden.insert(job.id)
            prefs.shown.remove(job.id)
        } else {
            prefs.hidden.remove(job.id)
            if job.looksSystemOwned { prefs.shown.insert(job.id) }
        }
        prefs.save()
        if let index = jobs.firstIndex(where: { $0.id == job.id }) { jobs[index].isHidden = hidden }
        onChange?()
    }

    func unhideAll() {
        prefs.hidden.removeAll()
        prefs.save()
        Task { await refresh() }
    }

    func copy(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        process.standardInput = pipe
        try? process.run()
        pipe.fileHandleForWriting.write(Data(text.utf8))
        try? pipe.fileHandleForWriting.close()
    }

    func openLog(_ job: Job) {
        guard let path = job.logPath else { return }
        Shell.run("/usr/bin/open", ["-a", "Console", (path as NSString).expandingTildeInPath])
    }

    func revealDefinition(_ job: Job) {
        guard let url = job.plistURL else { return }
        Shell.run("/usr/bin/open", ["-R", url.path])
    }
}

extension Job {
    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}

/// Tasks the person hid or chose to show, kept next to the run history.
private struct Prefs: Codable {
    var hidden: Set<String> = []
    var shown: Set<String> = []

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("onit-dynamiclake/prefs.json")
    }

    static func load() -> Prefs {
        guard let data = try? Data(contentsOf: url), let prefs = try? JSONDecoder().decode(Prefs.self, from: data) else { return Prefs() }
        return prefs
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}
