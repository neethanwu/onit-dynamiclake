import Foundation

// onit for DynamicLake.
//
// DynamicLake launches this executable from the plugin package and passes a socket in
// DYNAMICLAKE_JSON_SOCKET. Run it yourself with --demo to print what it would send for the
// tasks on this Mac, without DynamicLake.

let host = LakeHost.current
let demo = CommandLine.arguments.contains("--demo")

let connection: Connection
if demo {
    connection = Connection(printing: true)
} else if let path = host.socketPath {
    do {
        connection = try Connection(socketPath: path)
    } catch {
        Log.write("could not connect to DynamicLake: \(error)")
        exit(1)
    }
} else {
    FileHandle.standardError.write(Data("Launch onit from DynamicLake, or run with --demo.\n".utf8))
    exit(1)
}

Log.trim()
Log.write("start; features: \(host.features.sorted().joined(separator: ","))")

MainActor.assumeIsolated {
    let store = Store()
    let presenter = Presenter(connection: connection, host: host, store: store, settings: Settings.load(from: host.settingsPath))
    store.onChange = { [weak presenter] in presenter?.render() }

    let watcher = SettingsWatcher(path: host.settingsPath) {
        MainActor.assumeIsolated {
            let settings = Settings.load(from: host.settingsPath)
            if settings != presenter.settings { presenter.settings = settings }
        }
    }

    if demo {
        Task {
            presenter.start()
            await store.refresh()
            presenter.renderEverything()
            try? await Task.sleep(for: .milliseconds(300))
            exit(0)
        }
    } else {
        connection.startReading { message in presenter.handle(message) }
        presenter.start()
        store.start()
        // Keep the presenter, store and watcher alive for the life of the process.
        Retained.objects = [presenter, store, watcher as Any]
    }
}

// A run loop rather than dispatchMain(), which retires the main thread and breaks main-actor checks.
RunLoop.main.run()

@MainActor
enum Retained {
    static var objects: [Any] = []
}
