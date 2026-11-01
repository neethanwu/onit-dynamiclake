import Foundation

/// onit's panel, built from DynamicLake lake components: the task list, and one task's detail.
@MainActor
enum LakeView {
    /// DynamicLake allows 160 components in a lake, header and stacks included.
    private static let budget = 160

    // MARK: - List

    static func list(store: Store, now: Date, copiedJobID: String?) -> JSON {
        let jobs = store.visibleJobs
        // Header (3) and the scroll (1), then as many rows as fit, keeping room for a "more" line.
        var used = 5
        var rows: [JSON] = []
        for job in jobs {
            let row = row(job, store: store, now: now)
            let cost = componentCount(row)
            guard used + cost <= budget, rows.count < 50 else { break }
            rows.append(row)
            used += cost
        }
        if rows.count < jobs.count {
            rows.removeLast(rows.count == 50 ? 1 : 0)
            rows.append(C.text("\(jobs.count - rows.count) more", style: "compact", tint: "gray"))
        }
        let content: [JSON] = jobs.isEmpty
            ? [C.text("Nothing scheduled yet. launchd agents and crontab entries show up here.", style: "compact", tint: "gray")]
            : [C.scroll(rows, spacing: 4)]
        return [
            "leftSlot": C.asset(BeadPlayer.assetID),
            "title": C.text(headline(store: store)),
            "subtitle": C.text(summary(store: store, now: now)),
            "content": .array(content),
        ]
    }

    /// DynaGlance's right side is small: the headline and the first three tasks.
    static func glance(store: Store, now: Date) -> JSON {
        let rows = store.visibleJobs.prefix(3).map { job in
            C.hstack([
                C.file(dotFile(job), size: 16),
                C.text(job.name, style: "compact"),
                C.spacer(),
                C.text(statusDetail(job, store: store, now: now) ?? statusStyle(job).title, style: "compact", tint: "gray"),
            ], spacing: 6)
        }
        return [
            "leftSlot": C.asset(BeadPlayer.assetID),
            "title": C.text(headline(store: store)),
            "subtitle": C.text(summary(store: store, now: now)),
            "content": .array(Array(rows)),
        ]
    }

    /// onit's row: status dot, name over schedule, status over when. DynamicLake can't make a whole
    /// row clickable, so the dot (a 28 pt target) and the chevron both open the task.
    private static func row(_ job: Job, store: Store, now: Date) -> JSON {
        let token = Token.of(job)
        let status = statusStyle(job)
        var scheduleLine: JSON = C.text(ScheduleText.summary(job.schedule), style: "compact", tint: "gray")
        if job.schedule.hasOverlap {
            scheduleLine = C.hstack([C.file("glyph-headsup.png", size: 12), scheduleLine], spacing: 4)
        }
        var trailing = [C.text(status.title, style: "compact", weight: "medium", tint: status.tint)]
        if let detail = statusDetail(job, store: store, now: now) {
            trailing.append(C.text(detail, style: "compact", tint: "gray"))
        }
        return C.hstack(
            [
                C.file(dotFile(job), size: 28, actionID: "open:\(token)", title: "Details"),
                C.vstack([C.text(job.name, weight: "medium", tint: job.state == .paused ? "gray" : nil), scheduleLine], spacing: 2),
                C.spacer(),
                C.vstack(trailing, spacing: 2, alignment: "trailing"),
                C.button("open:\(token)", symbol: "chevron.right", shape: "plain", tint: "gray", size: 16),
            ],
            spacing: 6,
            id: "row-\(token)",
            contextMenu: menu(for: job),
            drag: drag(for: job)
        )
    }

    private static func componentCount(_ json: JSON) -> Int {
        guard let children = json["children"], case .array(let list) = children else { return 1 }
        return 1 + list.map(componentCount).reduce(0, +)
    }

    // MARK: - Detail

    /// onit's task detail: a header with the way back, a card for what needs attention, the facts,
    /// recent runs and actions. The header is built in `content` so the back button stays small.
    static func detail(job: Job, store: Store, now: Date, copied: Bool, explanation: FailureExplainer.Explanation?) -> JSON {
        let token = Token.of(job)
        let status = statusStyle(job)
        var content: [JSON] = [
            C.hstack([
                C.button("back", symbol: "chevron.left", shape: "plain", tint: "gray", size: 18),
                C.vstack([
                    C.text(job.name, style: "large", weight: "bold"),
                    C.hstack([
                        C.text(status.headline(job, store: store, now: now), style: "compact", weight: "medium", tint: status.tint),
                        C.text(statusTail(job, store: store, now: now), style: "compact", tint: "gray"),
                    ], spacing: 4),
                ], spacing: 1),
                C.spacer(),
            ], spacing: 10, padding: ["bottom": 6]),
        ]

        if let explanation {
            let streak = store.failureStreak(for: job)
            var lines: [JSON] = [C.text(streak > 1 ? "Didn't finish \(streak) times in a row" : "Didn't finish last time", weight: "semibold")]
            lines += wrap(explanation.reason, width: 74).map { C.text($0, style: "compact") }
            if let raw = explanation.rawLine { lines.append(C.text(raw, style: "compact", tint: "gray")) }
            content.append(card(glyph: "glyph-failed.png", lines: lines))
        } else if job.schedule.hasOverlap {
            content.append(card(glyph: "glyph-headsup.png", lines: [
                C.text("Runs more often than you might think", weight: "semibold"),
                C.text("\(ScheduleText.summary(job.schedule)). That's about \(ScheduleText.runsPerDay(job.schedule)) runs a day.", style: "compact"),
            ]))
        }

        var facts: [(String, String)] = [("Schedule", ScheduleText.summary(job.schedule))]
        if let next = store.nextRun(for: job, now: now) { facts.append(("Next run", TimeText.dayAndTime(next, now: now))) }
        facts.append(("What it runs", JobNaming.whatItRuns(job)))
        content.append(C.vstack(facts.map { label, value in
            C.hstack([C.text(label, style: "compact", tint: "gray"), C.spacer(), C.text(value, style: "compact")], spacing: 8)
        }, spacing: 5, padding: ["top": 4, "bottom": 4]))

        if !job.isAlwaysOn {
            let runs = Array(store.records(for: job).suffix(3).reversed())
            var section: [JSON] = [C.text("Recent runs", style: "compact", weight: "semibold")]
            if runs.isEmpty {
                section.append(C.text("No runs recorded yet", style: "compact", tint: "gray"))
            }
            section += runs.map { run in
                let result = runResult(run)
                return C.hstack([
                    C.text(TimeText.runDay(run.end ?? run.start, now: now), style: "compact"),
                    C.spacer(),
                    C.text(result.text, style: "compact", tint: result.tint),
                ], spacing: 8)
            }
            content.append(C.vstack(section, spacing: 5, padding: ["top": 4, "bottom": 4]))
        }

        content.append(actions(job, token: token, copied: copied))
        return ["hideHeader": true, "content": .array(content)]
    }

    /// A banner like onit's ProblemCard and OverlapCard: a small still Bead, then the words.
    private static func card(glyph: String, lines: [JSON]) -> JSON {
        C.hstack([C.file(glyph, size: 18), C.vstack(lines, spacing: 2), C.spacer()],
                 spacing: 10, alignment: "top", padding: ["top": 2, "bottom": 6])
    }

    private static func actions(_ job: Job, token: String, copied: Bool) -> JSON {
        var buttons: [JSON] = [
            C.button("run:\(token)", symbol: "play.fill", title: job.isFailed ? "Try Again" : "Run Now", id: "act-run", shape: "roundedRect", tint: "blue"),
        ]
        if job.source == .launchd {
            buttons.append(job.state == .paused
                ? C.button("resume:\(token)", symbol: "play", title: "Resume", id: "act-pause", shape: "roundedRect", tint: "gray")
                : C.button("pause:\(token)", symbol: "pause.fill", title: "Pause", id: "act-pause", shape: "roundedRect", tint: "gray"))
        }
        if job.isFailed || job.schedule.hasOverlap {
            buttons.append(C.button("copy:\(token)", symbol: copied ? "checkmark" : "doc.on.doc", title: copied ? "Copied" : "Copy for Your Agent",
                                    id: "act-copy", shape: "roundedRect", tint: copied ? "green" : (job.isFailed ? "red" : "orange")))
        }
        if job.logPath != nil {
            buttons.append(C.button("log:\(token)", symbol: "doc.text", title: "Open Log", id: "act-log", shape: "roundedRect", tint: "gray"))
        }
        buttons.append(C.spacer())
        return C.hstack(buttons, spacing: 8, padding: ["top": 6], drag: drag(for: job))
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

    /// onit's StatusStyle.
    @MainActor
    struct StatusStyle {
        var title: String
        var tint: String

        func headline(_ job: Job, store: Store, now: Date) -> String {
            switch job.state {
            case .failed: return "Failed" + (job.lastRun.map { " \(TimeText.ago($0, now: now))" } ?? "")
            case .succeeded: return "Last run OK"
            case .running: return "Running" + (store.runningSince(job).map { " \(TimeText.elapsed(since: $0, now: now))" } ?? "")
            case .paused: return "Paused"
            case .waiting: return job.source == .cron ? (job.lastRun.map { "Ran \(TimeText.ago($0, now: now))" } ?? "Scheduled") : "Hasn't run yet"
            }
        }
    }

    static func statusStyle(_ job: Job) -> StatusStyle {
        switch job.state {
        case .failed: return StatusStyle(title: "Failed", tint: "red")
        case .running: return StatusStyle(title: job.isAlwaysOn ? "Always on" : "Running", tint: job.isAlwaysOn ? "gray" : "blue")
        case .succeeded: return StatusStyle(title: "OK", tint: "green")
        case .paused: return StatusStyle(title: "Paused", tint: "gray")
        case .waiting: return StatusStyle(title: job.source == .cron ? "Scheduled" : "Not run yet", tint: "gray")
        }
    }

    private static func dotFile(_ job: Job) -> String {
        switch job.state {
        case .failed: return "dot-failed.png"
        case .running: return job.isAlwaysOn ? "dot-ok.png" : "dot-running.png"
        case .succeeded: return "dot-ok.png"
        case .paused, .waiting: return "dot-idle.png"
        }
    }

    /// The second line under a row's status, as in onit's list.
    private static func statusDetail(_ job: Job, store: Store, now: Date) -> String? {
        switch job.state {
        case .running:
            return job.isAlwaysOn ? nil : store.runningSince(job).map { TimeText.elapsed(since: $0, now: now) }
        case .paused:
            return nil
        case .waiting:
            return store.nextRun(for: job, now: now).map { TimeText.until($0, now: now) }
        case .succeeded, .failed:
            if let next = store.nextRun(for: job, now: now), job.lastRun == nil { return TimeText.until(next, now: now) }
            return job.lastRun.map { TimeText.ago($0, now: now) }
        }
    }

    /// What follows the status in the detail header: when it runs next, and launchd or cron.
    private static func statusTail(_ job: Job, store: Store, now: Date) -> String {
        let tag = job.source == .launchd ? "launchd" : "cron"
        let next: String?
        switch job.state {
        case .paused: next = "won't run until you resume it"
        case .running: next = nil
        case .waiting where job.source == .launchd: next = store.nextRun(for: job, now: now).map { "first run \(TimeText.until($0, now: now))" }
        default: next = store.nextRun(for: job, now: now).map { "next \(TimeText.until($0, now: now))" }
        }
        return ([next, tag].compactMap { $0 }).map { "· \($0)" }.joined(separator: " ")
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
        var items = [
            C.menuItem("Show Details", symbol: "info.circle", actionID: "open:\(token)"),
            C.menuItem(job.isFailed ? "Try Again" : "Run Now", symbol: "play", actionID: "run:\(token)"),
        ]
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

    /// Lake text is one line, so longer sentences are split by word into lines of even length,
    /// none longer than `width`, so a last line isn't left with one word.
    nonisolated static func wrap(_ text: String, width: Int) -> [String] {
        let lineCount = max(1, Int((Double(text.count) / Double(width)).rounded(.up)))
        let target = min(width, Int((Double(text.count) / Double(lineCount)).rounded(.up)) + 4)
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if !line.isEmpty, line.count + 1 + word.count > target {
                lines.append(line)
                line = ""
            }
            line += line.isEmpty ? String(word) : " " + word
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
}
