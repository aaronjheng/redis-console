import Foundation

/// Log level for structured logging
enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

/// AppLogger outputs structured logs in logfmt format
///
/// Example output:
/// ts=2025-01-20T10:30:45.123456Z level=info component=Connection msg="connected successfully" host=localhost port=6379
enum AppLogger {
    private static let queue = DispatchQueue(label: "redis.console.logger")

    static var logFileURL: URL {
        guard let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("redis-console.log")
        }
        let logs = libraryDirectory.appendingPathComponent("Logs", isDirectory: true)
        let dir = logs.appendingPathComponent("redis.console", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("redis-console.log")
    }

    /// Log info level message
    static func info(_ message: String, category: String = "App", fields: [String: String] = [:]) {
        write(level: .info, category: category, message: message, fields: fields)
    }

    /// Log error level message
    static func error(_ message: String, category: String = "App", fields: [String: String] = [:]) {
        write(level: .error, category: category, message: message, fields: fields)
    }

    /// Log debug level message (only in DEBUG builds)
    static func debug(_ message: String, category: String = "App", fields: [String: String] = [:]) {
        #if DEBUG
            write(level: .debug, category: category, message: message, fields: fields)
        #endif
    }

    /// Escape value for logfmt format
    private static func logfmtEscape(_ value: String) -> String {
        // If value contains spaces, quotes, or equals signs, wrap in quotes
        if value.contains(" ") || value.contains("\"") || value.contains("=") || value.contains("\t") {
            // Escape existing quotes and backslashes
            let escaped =
                value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    /// Format timestamp in RFC3339 format
    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Write log entry in logfmt format
    private static func write(level: LogLevel, category: String, message: String, fields: [String: String] = [:]) {
        var parts: [String] = []

        // Timestamp
        parts.append("time=\(formatTimestamp(Date()))")

        // Level
        parts.append("level=\(level.rawValue)")

        // Component (category)
        parts.append("component=\(logfmtEscape(category))")

        // Message
        parts.append("msg=\(logfmtEscape(message))")

        // Additional fields
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            parts.append("\(key)=\(logfmtEscape(value))")
        }

        let line = parts.joined(separator: " ") + "\n"

        queue.async {
            let url = logFileURL
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        defer { try? handle.close() }
                        _ = try? handle.seekToEnd()
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
