import Foundation

enum BeadMood: String {
    case dozing, onIt = "onit", headsUp = "headsup", failed, nothing

    init(_ state: OverallState) {
        switch state {
        case .empty: self = .nothing
        case .ok: self = .dozing
        case .running: self = .onIt
        case .headsUp: self = .headsUp
        case .failed: self = .failed
        }
    }
}

/// Plays Bead in DynamicLake by replacing one image asset with the next frame.
///
/// What a spike showed about DynamicLake (Oct 2026): animated PNG and GIF don't play, swapping an
/// asset is instant and doesn't flicker, and about 20 or more messages a second gets rate limited.
/// So Bead moves the way onit's motion spec says, within that budget:
/// - In the notch it is mostly still. Blinks, a peek, a hop or a shiver play once in a while,
///   a handful of frames each.
/// - It only runs (8 fps) while the lake is open and something is running.
@MainActor
final class BeadPlayer {
    static let assetID = "bead"

    private let connection: Connection
    private let frames: [String: String]
    private var mood: BeadMood = .nothing
    private var running = false
    private var idleTask: Task<Void, Never>?
    private var currentFrame: String?
    var animates = true
    var lakeOpen = false {
        didSet { if lakeOpen != oldValue { restart(entering: false) } }
    }

    init(connection: Connection, packageURL: URL) {
        self.connection = connection
        var frames: [String: String] = [:]
        let folder = packageURL.appendingPathComponent("bead")
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "png" {
            if let data = try? Data(contentsOf: url) {
                frames[url.deletingPathExtension().lastPathComponent] = data.base64EncodedString()
            }
        }
        self.frames = frames
        if frames.isEmpty { Log.write("no Bead frames found in \(folder.path)") }
    }

    /// Registers the asset so surfaces can point at it. DynamicLake drops assets when the plugin disconnects.
    func start(mood: BeadMood) {
        self.mood = mood
        show("still-\(mood.rawValue)", force: true)
        restart(entering: false)
    }

    func set(mood: BeadMood) {
        guard mood != self.mood else { return }
        self.mood = mood
        restart(entering: true)
    }

    // MARK: - Playing

    private func restart(entering: Bool) {
        idleTask?.cancel()
        show("still-\(mood.rawValue)")
        guard animates, !Self.reduceMotion else { return }
        let mood = self.mood
        idleTask = Task { [weak self] in
            if entering { await self?.arrive(mood) }
            await self?.live(mood)
        }
    }

    /// The one-shot move when Bead enters a mood: heads-up hops, failed shivers.
    private func arrive(_ mood: BeadMood) async {
        switch mood {
        case .headsUp: await hop()
        case .failed: await shiver()
        default: break
        }
    }

    private func live(_ mood: BeadMood) async {
        if mood == .onIt, lakeOpen {
            await run()
            return
        }
        var nextBlink = Date.now + .random(in: 2.4...5.2)
        var nextNudge = Date.now + .random(in: 6...10)
        var nextDrip = Date.now + .random(in: 3.5...5)
        while !Task.isCancelled {
            let now = Date.now
            if now >= nextBlink {
                switch mood {
                case .dozing:
                    await peek()
                    nextBlink = now + .random(in: 7...11)
                case .onIt, .headsUp, .failed:
                    await blink(mood)
                    nextBlink = now + .random(in: 2.4...5.2)
                case .nothing:
                    nextBlink = .distantFuture
                }
            }
            if mood == .failed, now >= nextDrip {
                await drip()
                nextDrip = now + .random(in: 3.5...5)
            }
            if now >= nextNudge {
                if mood == .headsUp { await hop() }
                if mood == .failed { await shiver() }
                nextNudge = now + .random(in: 7...11)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func blink(_ mood: BeadMood) async {
        if Double.random(in: 0...1) < 0.2 {
            await play(["blink-\(mood.rawValue)-1", "blink-\(mood.rawValue)-2", "blink-\(mood.rawValue)-1", "still-\(mood.rawValue)"], step: 0.06)
            try? await Task.sleep(for: .milliseconds(120))
        }
        await play(["blink-\(mood.rawValue)-1", "blink-\(mood.rawValue)-2", "blink-\(mood.rawValue)-1", "still-\(mood.rawValue)"], step: 0.06)
    }

    private func peek() async {
        await play(["peek-dozing"], step: 0.8)
        show("still-dozing")
    }

    private func hop() async {
        await play((0..<5).map { "hop-\($0)" } + ["still-headsup"], step: 0.06)
    }

    private func shiver() async {
        await play((0..<5).map { "shiver-\($0)" } + ["still-failed"], step: 0.05)
    }

    private func drip() async {
        await play((1...5).map { "drip-\($0)" } + ["still-failed"], step: 0.15)
    }

    private func run() async {
        var index = 0
        while !Task.isCancelled {
            show("run-\(index)")
            index = (index + 1) % 8
            try? await Task.sleep(for: .milliseconds(125))
        }
    }

    private func play(_ names: [String], step: Double) async {
        for name in names {
            guard !Task.isCancelled else { return }
            show(name)
            try? await Task.sleep(for: .seconds(step))
        }
    }

    private func show(_ name: String, force: Bool = false) {
        guard force || name != currentFrame, let data = frames[name] else { return }
        currentFrame = name
        connection.send(["type": "asset", "asset": ["id": .string(Self.assetID), "mimeType": "image/png", "base64Data": .string(data)]])
    }

    private static var reduceMotion: Bool {
        UserDefaults(suiteName: "com.apple.universalaccess")?.bool(forKey: "reduceMotion") ?? false
    }
}
