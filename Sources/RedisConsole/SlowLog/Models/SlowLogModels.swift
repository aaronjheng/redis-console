import Foundation

// MARK: - Slow Log Models

struct SlowLogEntry: Identifiable, Sendable {
    let id: Int
    let timestamp: Date
    let duration: Int  // microseconds
    let command: [String]
    let clientIP: String
    let clientName: String

    var durationMs: Double {
        Double(duration) / 1000.0
    }

    var durationText: String {
        if duration >= 1_000_000 {
            return String(format: "%.2f s", Double(duration) / 1_000_000)
        } else if duration >= 1_000 {
            return String(format: "%.2f ms", Double(duration) / 1_000)
        } else {
            return "\(duration) \u{00B5}s"
        }
    }

    var commandText: String {
        command.joined(separator: " ")
    }
}

/// In-memory viewing parameters for the slow-log panel. Nothing here is
/// persisted: `threshold` only feeds the empty-state hint and
/// `autoRefreshInterval` is transient "am I watching" state.
struct SlowLogConfig: Equatable {
    var threshold: Int = 10_000  // microseconds
    /// Transient UI state ("am I watching right now"): every launch starts
    /// with polling off.
    var autoRefreshInterval: TimeInterval = 0  // 0 = disabled

    static let autoRefreshOptions: [(title: String, value: TimeInterval)] = [
        ("Off", 0),
        ("5s", 5),
        ("10s", 10),
        ("30s", 30),
        ("60s", 60),
    ]
}
