import Foundation

/// Turns the store's state into DynamicLake surfaces: the live activity, its sneak peek, the side capsule and the lake.
///
/// The live activity only shows up when there is something to say: a task running, one that just
/// finished, a failure or a schedule that runs more than it should. When all is well it goes away,
/// unless "Show next run" is on.
@MainActor
final class Presenter {
    private let connection: Connection
    private let host: LakeHost
    private let store: Store
    let bead: BeadPlayer
    var settings: Settings {
        didSet {
            bead.animates = settings.animateBead
            render()
        }
    }

    private static let activityID = "onit"
    private var activityShown = false
    private var lastActivity: JSON?
    private var lastLake: JSON?
    private var detailJobID: String?
    private var copiedJobID: String?
    private var lakeOpen = false

    /// Jobs seen running on the last render, to notice when one finishes.
    private var wasRunning: Set<String> = []
    private var knownFailures: Set<String> = []
    private var finished: (job: Job, until: Date)?
    private var firstRender = true

    init(connection: Connection, host: LakeHost, store: Store, settings: Settings) {
        self.connection = connection
        self.host = host
        self.store = store
        self.settings = settings
        bead = BeadPlayer(connection: connection, packageURL: host.packageURL)
        bead.animates = settings.animateBead
    }

    func start() {
        bead.start(mood: .nothing)
    }

    /// For `--demo`: renders the list, then every task's detail, so each lake can be checked.
    func renderEverything() {
        render()
        for job in store.visibleJobs {
            detailJobID = job.id
            render()
            copiedJobID = job.id
            render()
            copiedJobID = nil
        }
        detailJobID = nil
    }

    // MARK: - Events

    func handle(_ message: JSON) {
        switch message["type"]?.string {
        case "action":
            Log.write("action \(message["actionID"]?.string ?? "?") from \(message["surface"]?.string ?? "?")")
            if let action = message["actionID"]?.string { perform(action) }
        case "lakeOpened":
            lakeOpen = true
            bead.lakeOpen = true
            render()
        case "lakeClosed":
            lakeOpen = false
            bead.lakeOpen = false
            detailJobID = nil
            render()
        case "error":
            Log.write("DynamicLake error: \(message["error"]?.string ?? "?")")
        case "response" where message["ok"]?.bool == false:
            Log.write("DynamicLake refused \(message["requestID"]?.string ?? "?"): \(message["error"]?.string ?? "?")")
        default:
            break
        }
    }

    private func perform(_ action: String) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        let verb = parts[0]
        let job = parts.count > 1 ? store.jobs.first { Token.of($0) == parts[1] } : nil
        switch (verb, job) {
        case ("back", _):
            detailJobID = nil
            render()
        case ("open", let job?):
            detailJobID = job.id
            render()
        case ("run", let job?):
            Task { await store.runNow(job) }
        case ("pause", let job?):
            Task { await store.setPaused(job, paused: true) }
        case ("resume", let job?):
            Task { await store.setPaused(job, paused: false) }
        case ("copy", let job?):
            store.copy(fixPrompt(for: job) ?? job.commandLine)
            copiedJobID = job.id
            render()
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copiedJobID == job.id { copiedJobID = nil; render() }
            }
        case ("log", let job?):
            store.openLog(job)
        case ("reveal", let job?):
            store.revealDefinition(job)
        case ("hide", let job?):
            if detailJobID == job.id { detailJobID = nil }
            store.setHidden(job, hidden: true)
        case ("unhide", _):
            store.unhideAll()
        default:
            Log.write("unknown action \(action)")
        }
    }

    // MARK: - Rendering

    func render() {
        let now = Date.now
        let running = Set(store.runningJobs.map(\.id))
        let failures = Set(store.failedJobs.map(\.id))
        defer {
            wasRunning = running
            knownFailures = failures
            firstRender = false
        }

        // A task that was running and is now done shows a short "finished" moment.
        if !firstRender {
            for id in wasRunning.subtracting(running) {
                if let job = store.job(id: id), !job.isHidden, !job.isFailed {
                    finished = (job, now.addingTimeInterval(4))
                    Task {
                        try? await Task.sleep(for: .seconds(4.2))
                        render()
                    }
                }
            }
        }
        if let current = finished, current.until <= now { finished = nil }
        let newFailure = !firstRender && !failures.subtracting(knownFailures).isEmpty

        bead.set(mood: mood)
        renderActivity(now: now, announce: newFailure)
        renderLake(now: now)
    }

    /// Bead's mood follows what the live activity is saying, in the same order.
    private var mood: BeadMood {
        if !store.failedJobs.isEmpty { return .failed }
        if !store.runningJobs.isEmpty, finished == nil { return .onIt }
        if store.overlapCount > 0 { return .headsUp }
        return BeadMood(store.overallState)
    }

    // MARK: Live activity

    private func renderActivity(now: Date, announce: Bool) {
        guard var activity = activity(now: now) else {
            if activityShown {
                connection.send(["type": "dismiss", "activityID": .string(Self.activityID)])
                activityShown = false
                lastActivity = nil
            }
            return
        }
        guard activity != lastActivity || announce else { return }
        let justFinished = activity["finished"] != nil && lastActivity?["finished"] == nil
        let type: JSON = activityShown ? "update" : "create"
        lastActivity = activity
        if case .object(var object) = activity {
            object.removeValue(forKey: "finished")
            activity = .object(object)
        }
        // Open the sneak peek on its own only for moments worth noticing, never for routine updates.
        if host.supports("presentSneakPeek") {
            if announce, settings.announceFailures {
                activity = activity.merging(["presentSneakPeek": 3])
            } else if justFinished {
                activity = activity.merging(["presentSneakPeek": 2])
            }
        }
        connection.send(activity.merging(["type": type, "activityID": .string(Self.activityID), "title": "onit", "size": "small"]))
        activityShown = true
    }

    /// The activity for the current state, or nil when onit has nothing to say.
    private func activity(now: Date) -> JSON? {
        let beadImage = C.asset(BeadPlayer.assetID)
        let failed = store.failedJobs
        let running = store.runningJobs

        if let first = failed.first {
            let count = failed.count
            let reason = explanation(for: first).reason
            let headline = count > 1 ? "\(count) tasks didn't finish" : "\(first.name) didn't finish"
            return surfaces(
                priority: "normal",
                right: count > 1 ? C.text("\(count)", style: numericStyle, tint: "red") : C.status("failed", tint: "red"),
                peekCenter: "\(headline) · \(reason)",
                peekRight: C.button("run:\(Token.of(first))", symbol: "arrow.clockwise", id: "retry", tint: "red"),
                capsule: beadImage
            )
        }
        if let done = finished?.job {
            let duration = store.records(for: done).last?.duration.map { " in \(TimeText.duration($0))" } ?? ""
            return surfaces(
                priority: "normal",
                right: C.status("success", tint: "green"),
                peekCenter: "\(done.name) finished\(duration)",
                peekRight: nil,
                capsule: beadImage
            ).merging(["finished": true])
        }
        if let first = running.first {
            let since = store.runningSince(first).map { " · \(TimeText.elapsed(since: $0, now: now))" } ?? ""
            let center = running.count > 1 ? "\(running.count) tasks running: \(running.map(\.name).joined(separator: ", "))" : "\(first.name) is running\(since)"
            return surfaces(
                priority: "normal",
                right: C.status("inProgress", tint: "blue"),
                peekCenter: center,
                peekRight: nil,
                capsule: beadImage
            )
        }
        if store.overlapCount > 0, let job = store.activeJobs.first(where: \.schedule.hasOverlap) {
            let count = store.overlapCount
            return surfaces(
                priority: "low",
                right: C.text("\(count)", style: numericStyle, tint: "orange"),
                peekCenter: "\(job.name) runs on two schedules, about \(ScheduleText.runsPerDay(job.schedule)) times a day",
                peekRight: nil,
                capsule: beadImage
            )
        }
        if settings.showNextUp, let next = store.nextUp(now: now) {
            let right: JSON = next.date.timeIntervalSince(now) < 3600
                ? C.timer(from: now, to: next.date)
                : C.text(TimeText.short(until: next.date, now: now), style: numericStyle, tint: "gray")
            return surfaces(
                priority: "low",
                right: right,
                peekCenter: "Next: \(next.job.name) · \(TimeText.dayAndTime(next.date, now: now))",
                peekRight: nil,
                capsule: nil
            )
        }
        return nil
    }

    private func surfaces(priority: String, right: JSON, peekCenter: String, peekRight: JSON?, capsule: JSON?) -> JSON {
        var peek: [String: JSON] = [
            "leftSlot": C.asset(BeadPlayer.assetID),
            "center": C.text(peekCenter, style: "marquee"),
        ]
        peek["rightSlot"] = peekRight
        var surfaces: [String: JSON] = [
            "compactLiveActivity": ["leftSlot": C.asset(BeadPlayer.assetID), "rightSlot": right],
            "sneakPeek": .object(peek),
        ]
        if let capsule { surfaces["extraLiveActivity"] = ["leftSlot": capsule] }
        return ["priority": .string(priority), "surfaces": .object(surfaces)]
    }

    private var numericStyle: String { host.supports("numericText") ? "numeric" : "compact" }

    // MARK: Lake

    private func renderLake(now: Date) {
        guard host.supports("lake"), host.supports("lakeLayout") else { return }
        let lake: JSON
        if let id = detailJobID, let job = store.job(id: id) {
            lake = LakeView.detail(job: job, store: store, now: now, copied: copiedJobID == job.id,
                                   explanation: job.isFailed ? explanation(for: job) : nil)
        } else {
            lake = LakeView.list(store: store, now: now, copiedJobID: copiedJobID)
        }
        let full = lake.merging(["glance": LakeView.glance(store: store, now: now)])
        guard full != lastLake else { return }
        lastLake = full
        connection.send(["type": "lake", "lake": full])
    }

    // MARK: Helpers

    private func explanation(for job: Job) -> FailureExplainer.Explanation {
        let tail = job.logPath.map { FailureExplainer.readTail(ofFile: $0) } ?? ""
        return FailureExplainer.explain(exitCode: job.lastExitCode, logTail: tail)
    }

    private func fixPrompt(for job: Job) -> String? {
        if job.isFailed {
            let tail = job.logPath.map { FailureExplainer.readTail(ofFile: $0) } ?? ""
            return FixPrompt.forFailure(job, explanation: explanation(for: job), logTail: tail)
        }
        if job.schedule.hasOverlap { return FixPrompt.forOverlap(job) }
        return nil
    }
}

/// Short, stable ids for jobs in action and component ids, which DynamicLake limits to letters, digits, `.`, `_`, `:` and `-`.
enum Token {
    static func of(_ job: Job) -> String {
        "j" + CronScanner.stableHash(job.id)
    }
}
