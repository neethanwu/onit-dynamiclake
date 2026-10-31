import Foundation

/// What DynamicLake tells the plugin through its environment.
struct LakeHost: Sendable {
    var socketPath: String?
    var packageURL: URL
    var features: Set<String>
    var settingsPath: String?

    static var current: LakeHost {
        let env = ProcessInfo.processInfo.environment
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return LakeHost(
            socketPath: env["DYNAMICLAKE_JSON_SOCKET"],
            packageURL: env["DYNAMICLAKE_PLUGIN_PACKAGE"].map { URL(fileURLWithPath: $0) } ?? executable.deletingLastPathComponent(),
            features: Set((env["DYNAMICLAKE_PLUGIN_FEATURES"] ?? "").split(separator: ",").map(String.init)),
            settingsPath: env["DYNAMICLAKE_PLUGIN_SETTINGS_PATH"]
        )
    }

    func supports(_ feature: String) -> Bool { features.contains(feature) }
}

/// The plugin's settings, declared in plugin.json and edited in DynamicLake's settings window.
struct Settings: Equatable, Sendable {
    /// Keep a quiet live activity with the next run when nothing needs attention.
    var showNextUp = false
    /// Open the sneak peek for a moment when a task fails.
    var announceFailures = true
    /// Let Bead blink, hop and shiver, and run while the lake is open.
    var animateBead = true

    init() {}

    init(values: [String: JSON]) {
        showNextUp = values["showNextUp"]?.bool ?? showNextUp
        announceFailures = values["announceFailures"]?.bool ?? announceFailures
        animateBead = values["animateBead"]?.bool ?? animateBead
    }

    static func load(from path: String?) -> Settings {
        guard let path, let data = FileManager.default.contents(atPath: path),
              let json = try? JSONDecoder().decode(JSON.self, from: data),
              case .object(let values)? = json["values"]
        else { return Settings() }
        return Settings(values: values)
    }
}

/// Watches the settings file's folder: DynamicLake replaces the file atomically, which would end a watch on the file itself.
final class SettingsWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?

    init?(path: String?, onChange: @escaping @Sendable () -> Void) {
        guard let path else { return nil }
        let folder = (path as NSString).deletingLastPathComponent
        let fd = open(folder, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }
}
