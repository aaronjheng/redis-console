import Foundation

enum AppLogger {
    private static let queue = DispatchQueue(label: "redis.console.logger")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var logFileURL: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
        let dir = logs.appendingPathComponent("redis.console", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app.log")
    }

    static func info(_ message: String, category: String = "App") {
        write(level: "INFO", category: category, message: message)
    }

    static func error(_ message: String, category: String = "App") {
        write(level: "ERROR", category: category, message: message)
    }

    private static func write(level: String, category: String, message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] [\(category)] \(message)\n"
        queue.async {
            let url = logFileURL
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        defer { try? handle.close() }
                        try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                    }
                } else {
                    try? data.write(to: url, options: .atomic)
                }
            }
            print(line, terminator: "")
        }
    }
}
