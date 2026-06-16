import Foundation
import SwiftUI

// MARK: - Connection State (Per-tab state)

enum AppView: String, CaseIterable {
    case browser = "Browser"
    case shell = "Shell"
    case profiler = "Profiler"
    case slowLog = "Slow Log"
    case serverInfo = "Server Info"

    var icon: String {
        switch self {
        case .browser: return "key"
        case .shell: return "terminal"
        case .profiler: return "waveform.path.ecg"
        case .slowLog: return "tortoise"
        case .serverInfo: return "info.circle"
        }
    }
}

enum RightPanel: Equatable {
    case welcome
    case editConnection(RedisConnectionConfig)
    case newConnection

    static func == (lhs: RightPanel, rhs: RightPanel) -> Bool {
        switch (lhs, rhs) {
        case (.welcome, .welcome): return true
        case (.newConnection, .newConnection): return true
        case (.editConnection(let leftConfig), .editConnection(let rightConfig)): return leftConfig.id == rightConfig.id
        default: return false
        }
    }
}

struct RedisServerCapability: Identifiable, Hashable {
    let name: String
    let version: String?
    let details: [RedisServerCapabilityDetail]

    var id: String {
        ([name, version ?? ""] + details.map { "\($0.name)=\($0.value)" }).joined(separator: "|")
    }
}

struct RedisServerCapabilityDetail: Hashable {
    let name: String
    let value: String
}
