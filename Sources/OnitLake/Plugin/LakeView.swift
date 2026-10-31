import Foundation

/// onit's panel, built from DynamicLake lake components: the task list, and one task's detail.
@MainActor
enum LakeView {
    /// DynamicLake allows 160 components in a lake; each row uses 7.
    private static let maxRows = 20

    // MARK: - List

    static func list(store: Store, now: Date, copiedJobID: String?) -> JSON {
        let jobs = store.visibleJobs
        var rows = jobs.prefix(maxRows).map { row($0, store: store, now: now) }
        if jobs.count > maxRows {
            rows.append(C.text("\(jobs.count - maxRows) more in onit", style: "compact", tint: "gray"))
        }
        let content: [JSON] = jobs.isEmpty
            ? [C.text("Nothing scheduled yet. launchd agents and crontab entries show up here.", style: "compact", tint: "gray")]
            : [C.scroll(rows, spacing: 6)]

        return [
            "leftSlot": C.asset(BeadPlayer.assetID, size: 36),
            "title": C.text(headline(store: store)),
            "subtitle": C.text(summary(store: store, now: now)),
            "content": .array(content),
        ]
    }

    /// DynaGlance's right side is small: the headline and the first three tasks.
    static func glance(store: Store, now: Date) -> JSON {
        let rows = store.visibleJobs.prefix(3).map { job in
            C.hstack([
                C.symbol(status(job).symbol, tint: status(job).tint, size: 12),
                C.text(job.name, style: "compact"),
                C.spacer(),
                C.text(trailing(job, store: store, now: now).text, style: "compact", tint: "gray"),
            ], spacing: 6)
        }
        return [
            "leftSlot": C.asset(BeadPlayer.assetID),
            "title": C.text(headline(store: store)),
            "subtitle": C.text(summary(store: store, now: now)),
            "content": .array(Array(rows)),
        ]
    }

    private static func row(_ job: Job, store: Store, now: Date) -> JSON {
        let token = Token.of(job)
        let state = status(job)
        let tail = trailing(job, store: store, now: now)
        return C.hstack(
            [
                C.symbol(state.symbol, tint: state.tint, size: 14),
                C.vstack([
                    C.text(job.name, weight: "medium"),
                    C.text(ScheduleText.summary(job.schedule), style: "compact", tint: "gray"),
                ], spacing: 1),
                C.spacer(),
                C.text(tail.text, style: "compact", tint: tail.tint),
                C.button("open:\(token)", symbol: "chevron.right", shape: "plain", tint: "gray", size: 14),
            ],
            spacing: 10,
            id: "row-\(token)",
            padding: ["leading": 4, "trailing": 2],
            contextMenu: menu(for: job),
            drag: drag(for: job)
        )
    }

    // MARK: - Detail

    static func detail(job: Job, store: Store, now: Date, copied: Bool, explanation: FailureExplainer.Explanation?) -> JSON {
        let token = Token.of(job)
        var content: [JSON] = []

        if let explanation {
            let streak = store.failureStreak(for: job)
            var lines: [JSON] = [C.text(streak > 1 ? "Didn't finish \(streak) times in a row" : "Didn't finish last time", weight: "semibold", tint: "red")]
            lines += wrap(explanation.reason, width: 78).map { C.text($0, style: "compact") }
            if let raw = explanation.rawLine { lines.append(C.text(raw, style: "compact", tint: "gray")) }
            content.append(C.vstack(lines, spacing: 2, padding: ["bottom": 4]))
        } else if job.schedule.hasOverlap {
            content.append(C.vstack([
                C.text("Runs on two schedules", weight: "semibold", tint: "orange"),
                C.text("It has an interval and set times, so it runs about \(ScheduleText.runsPerDay(job.schedule)) times a day.", style: "compact"),
            ], spacing: 2, padding: ["bottom": 4]))
        }

        var facts: [(String, String)] = [("Schedule", ScheduleText.summary(job.schedule))]
        if let next = store.nextRun(for: job, now: now) { facts.append(("Next run", TimeText.dayAndTime(next, now: now))) }
        facts.append(("What it runs", JobNaming.whatItRuns(job)))
        content += facts.map { label, value in
            C.hstack([C.text(label, style: "compact", tint: "gray"), C.spacer(), C.text(value, style: "compact")], spacing: 8)
        }

        if !job.isAlwaysOn {
            let runs = store.records(for: job).suffix(3).reversed()
            if !runs.isEmpty {
                content.append(C.spacer(4))
                content += runs.map { run in
                    let result = runResult(run)
                    return C.hstack([
                        C.text(TimeText.runDay(run.end ?? run.start, now: now), style: "compact", tint: "gray"),
                        C.spacer(),
                        C.text(result.text, style: "compact", tint: result.tint),
                    ], spacing: 8)
                }
            }
        }

        content.append(C.spacer(6))
        content.append(actions(job, token: token, copied: copied))

        return [
            "leftSlot": C.button("back", symbol: "chevron.left", tint: "gray"),
            "title": C.text(job.name),
            "subtitle": C.text(statusLine(job, store: store, now: now)),
            "content": .array(content),
        ]
    }

    private static func actions(_ job: Job, token: String, copied: Bool) -> JSON {
        var buttons: [JSON] = [
            C.button("run:\(token)", title: job.isFailed ? "Try Again" : "Run Now", id: "act-run", shape: "roundedRect", tint: "blue"),
        ]
        if job.source == .launchd {
            buttons.append(job.state == .paused
                ? C.button("resume:\(token)", title: "Resume", id: "act-pause", shape: "roundedRect", tint: "gray")
                : C.button("pause:\(token)", title: "Pause", id: "act-pause", shape: "roundedRect", tint: "gray"))
        }
        if job.isFailed || job.schedule.hasOverlap {
            buttons.append(C.button("copy:\(token)", title: copied ? "Copied" : "Copy for Your Agent", id: "act-copy",
                                    shape: "roundedRect", tint: copied ? "green" : "gray"))
        }
        if job.logPath != nil {
            buttons.append(C.button("log:\(token)", title: "Open Log", id: "act-log", shape: "roundedRect", tint: "gray"))
        }
        buttons.append(C.spacer())
        return C.hstack(buttons, spacing: 8, drag: drag(for: job))
    }

    // MARK: - Pieces

    /// Same order as the live activity: failures, then running tasks, then schedules that overlap.
    private static func headline(store: Store) -> String {
        let failed = store.failedJobs.count
        let running = store.runningJobs
        if failed > 0 { return failed == 1 ? "1 task didn't finish" : "\(failed) tasks didn't finish" }
        if !running.isEmpty { return running.count == 1 ? "\(running[0].name) is running" : "\(running.count) tasks running" }
        if store.overlapCount > 0 {
            return store.overlapCount == 1 ? "1 task runs more than you think" : "\(store.overlapCount) tasks run more than you think"
        }
        return store.activeJobs.isEmpty ? "Nothing scheduled" : "All good"
    }

    private static func summary(store: Store, now: Date) -> String {
        let count = store.activeJobs.count
        var parts = [count == 1 ? "1 task" : "\(count) tasks"]
        if let next = store.nextUp(now: now) {
            parts.append("next: \(next.job.name) \(TimeText.until(next.date, now: now))")
        }
        return parts.joined(separator: " · ")
    }

    private static func status(_ job: Job) -> (symbol: String, tint: String) {
        switch job.state {
        case .failed: return ("xmark.circle.fill", "red")
        case .running: return job.isAlwaysOn ? ("infinity.circle", "gray") : ("circle.dotted.circle", "blue")
        case .paused: return ("pause.circle.fill", "gray")
        case .succeeded where !job.schedule.hasOverlap: return ("checkmark.circle.fill", "green")
        default: return job.schedule.hasOverlap ? ("exclamationmark.circle.fill", "orange") : ("circle", "gray")
        }
    }

    private static func trailing(_ job: Job, store: Store, now: Date) -> (text: String, tint: String) {
        switch job.state {
        case .failed:
            return (job.lastRun.map { "Failed \(TimeText.ago($0, now: now))" } ?? "Failed", "red")
        case .running:
            if job.isAlwaysOn { return ("Always on", "gray") }
            return (store.runningSince(job).map { "Running \(TimeText.elapsed(since: $0, now: now))" } ?? "Running", "blue")
        case .paused:
            return ("Paused", "gray")
        default:
            if let next = store.nextRun(for: job, now: now) { return (TimeText.until(next, now: now), "gray") }
            if let last = job.lastRun { return ("Ran \(TimeText.ago(last, now: now))", "gray") }
            return ("Not run yet", "gray")
        }
    }

    /// The same words as onit's detail header.
    private static func statusLine(_ job: Job, store: Store, now: Date) -> String {
        let next = store.nextRun(for: job, now: now).map { "next \(TimeText.until($0, now: now))" }
        let tag = job.source == .launchd ? "launchd" : "cron"
        func joined(_ lead: String, _ tail: String?) -> String { [lead, tail, tag].compactMap { $0 }.joined(separator: " · ") }
        switch job.state {
        case .failed:
            return joined("Failed" + (job.lastRun.map { " \(TimeText.ago($0, now: now))" } ?? ""), next)
        case .succeeded:
            return joined("Last run OK", next)
        case .running:
            return joined("Running" + (store.runningSince(job).map { " \(TimeText.elapsed(since: $0, now: now))" } ?? ""), nil)
        case .paused:
            return joined("Paused, won't run until you resume it", nil)
        case .waiting:
            if job.source == .cron {
                return joined(job.lastRun.map { "Ran \(TimeText.ago($0, now: now))" } ?? "Scheduled", next)
            }
            return joined("Hasn't run yet", store.nextRun(for: job, now: now).map { "first run \(TimeText.until($0, now: now))" })
        }
    }

    private static func runResult(_ run: RunRecord) -> (text: String, tint: String) {
        let duration = run.duration.map { " · \(TimeText.duration($0))" } ?? ""
        switch run.exitCode {
        case nil where run.end == nil: return ("Running", "blue")
        case nil: return ("Ran\(duration)", "gray")
        case 0?: return ("OK\(duration)", "green")
        case let code?: return ("Failed (code \(code))\(duration)", "red")
        }
    }

    private static func menu(for job: Job) -> [JSON] {
        let token = Token.of(job)
        var items = [C.menuItem(job.isFailed ? "Try Again" : "Run Now", symbol: "play", actionID: "run:\(token)")]
        if job.source == .launchd {
            items.append(job.state == .paused
                ? C.menuItem("Resume", symbol: "play.circle", actionID: "resume:\(token)")
                : C.menuItem("Pause", symbol: "pause.circle", actionID: "pause:\(token)"))
        }
        if job.isFailed || job.schedule.hasOverlap {
            items.append(C.menuItem("Copy for Your Agent", symbol: "doc.on.doc", actionID: "copy:\(token)"))
        }
        if job.logPath != nil { items.append(C.menuItem("Open Log", symbol: "doc.text", actionID: "log:\(token)")) }
        if job.plistURL != nil { items.append(C.menuItem("Show in Finder", symbol: "folder", actionID: "reveal:\(token)")) }
        items.append(C.menuItem("Hide", symbol: "eye.slash", actionID: "hide:\(token)", destructive: true))
        return items
    }

    /// Dragging a task that needs fixing gives the prompt for your agent; otherwise its plist.
    private static func drag(for job: Job) -> JSON? {
        if job.isFailed {
            let tail = job.logPath.map { FailureExplainer.readTail(ofFile: $0) } ?? ""
            let prompt = FixPrompt.forFailure(job, explanation: FailureExplainer.explain(exitCode: job.lastExitCode, logTail: tail), logTail: tail)
            return ["text": .string(String(prompt.prefix(20_000)))]
        }
        if job.schedule.hasOverlap { return ["text": .string(FixPrompt.forOverlap(job))] }
        if let url = job.plistURL { return ["filePath": .string(url.path)] }
        return nil
    }

    /// Lake text is one line, so longer sentences are split by word.
    nonisolated static func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if !line.isEmpty, line.count + 1 + word.count > width {
                lines.append(line)
                line = ""
            }
            line += line.isEmpty ? String(word) : " " + word
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
}
