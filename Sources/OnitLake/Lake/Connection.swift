import Foundation

/// The socket DynamicLake hands a plugin. Each message is a 4-byte big-endian length and a UTF-8 JSON payload.
final class Connection: @unchecked Sendable {
    private let fd: Int32
    /// Prints messages instead of sending them, for `--demo`.
    private let printing: Bool
    private let writeQueue = DispatchQueue(label: "onit.lake.write")
    private var counter = 0

    init(printing: Bool) {
        fd = -1
        self.printing = printing
    }

    init(socketPath: String) throws {
        printing = false
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            throw POSIXError(.init(rawValue: errno) ?? .ECONNREFUSED)
        }
    }

    /// Sends one command. `schemaVersion` and a `requestID` are added here.
    func send(_ message: JSON) {
        writeQueue.async { [self] in
            counter += 1
            let payload = message.merging(["schemaVersion": 1, "requestID": .string("m\(counter)")]).encoded()
            if printing {
                if message["type"]?.string != "asset" { print(String(decoding: payload, as: UTF8.self)) }
                return
            }
            var length = UInt32(payload.count).bigEndian
            var frame = Data(bytes: &length, count: 4)
            frame.append(payload)
            frame.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                    if written <= 0 { return }
                    offset += written
                }
            }
        }
    }

    /// Reads messages on a background thread and hands each one to `handler` on the main actor.
    /// Exits the process when DynamicLake closes the socket, as it does when the plugin is turned off.
    func startReading(_ handler: @escaping @MainActor @Sendable (JSON) -> Void) {
        let fd = self.fd
        Thread.detachNewThread {
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = read(fd, &chunk, chunk.count)
                if count <= 0 {
                    Log.write("socket closed")
                    exit(0)
                }
                buffer.append(contentsOf: chunk[0..<count])
                while buffer.count >= 4 {
                    let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
                    guard buffer.count >= 4 + length else { break }
                    let body = buffer.subdata(in: buffer.startIndex + 4 ..< buffer.startIndex + 4 + length)
                    buffer.removeFirst(4 + length)
                    if let message = try? JSONDecoder().decode(JSON.self, from: body) {
                        DispatchQueue.main.async { MainActor.assumeIsolated { handler(message) } }
                    }
                }
            }
        }
    }
}

enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/onit-dynamiclake.log")
    private static let queue = DispatchQueue(label: "onit.lake.log")

    /// Starts a fresh log when it has grown past 1 MB.
    static func trim() {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > 1_000_000 { try? FileManager.default.removeItem(at: url) }
    }

    static func write(_ text: String) {
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(text)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
