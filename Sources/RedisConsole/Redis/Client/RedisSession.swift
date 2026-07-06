import Foundation
import SwiftUI

struct RedisEndpoint: Codable, Hashable, Sendable {
    var host: String
    var port: UInt16

    var address: String {
        "\(host):\(port)"
    }

    static func parse(_ value: String, defaultPort: UInt16 = 6379) -> RedisEndpoint? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("://"), let components = URLComponents(string: trimmed), let host = components.host {
            return RedisEndpoint(host: host, port: UInt16(components.port ?? Int(defaultPort)))
        }

        if trimmed.hasPrefix("["), let closeIndex = trimmed.firstIndex(of: "]") {
            let hostStart = trimmed.index(after: trimmed.startIndex)
            let host = String(trimmed[hostStart..<closeIndex])
            let afterClose = trimmed.index(after: closeIndex)
            if afterClose < trimmed.endIndex, trimmed[afterClose] == ":" {
                let portStart = trimmed.index(after: afterClose)
                if let port = UInt16(trimmed[portStart...]) {
                    return RedisEndpoint(host: host, port: port)
                }
            }
            return RedisEndpoint(host: host, port: defaultPort)
        }

        if let colonIndex = trimmed.lastIndex(of: ":"), colonIndex > trimmed.startIndex {
            let portStart = trimmed.index(after: colonIndex)
            if let port = UInt16(trimmed[portStart...]) {
                let host = String(trimmed[..<colonIndex])
                return RedisEndpoint(host: host, port: port)
            }
        }

        return RedisEndpoint(host: trimmed, port: defaultPort)
    }

    static func parseList(_ value: String, defaultPort: UInt16 = 6379) -> [RedisEndpoint] {
        let separators = CharacterSet(charactersIn: ",;\n\t ")
        let parts = value.components(separatedBy: separators)
        return unique(parts.compactMap { RedisEndpoint.parse($0, defaultPort: defaultPort) })
    }

    static func unique(_ endpoints: [RedisEndpoint]) -> [RedisEndpoint] {
        var seen: Set<RedisEndpoint> = []
        var result: [RedisEndpoint] = []
        for endpoint in endpoints where !endpoint.host.isEmpty {
            if seen.insert(endpoint).inserted {
                result.append(endpoint)
            }
        }
        return result
    }
}

enum RedisConnectionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case standalone
    case cluster

    var title: String {
        switch self {
        case .standalone: return "Standalone"
        case .cluster: return "Cluster"
        }
    }

    var badgeForegroundColor: Color {
        switch self {
        case .standalone: return .secondary
        case .cluster: return .accentColor
        }
    }

    var badgeBackgroundColor: Color {
        switch self {
        case .standalone: return Color.secondary.opacity(0.12)
        case .cluster: return Color.accentColor.opacity(0.14)
        }
    }
}

struct RedisScanResult: Sendable {
    let nextCursor: String
    let keys: [String]
    let scannedCount: Int

    init(nextCursor: String, keys: [String], scannedCount: Int = 0) {
        self.nextCursor = nextCursor
        self.keys = keys
        self.scannedCount = scannedCount
    }

    init(response: RESPValue, scannedCount: Int = 0) throws {
        let values = response.arrayValues
        guard values.count >= 2, let cursor = values[0]?.string else {
            throw RedisError.parseError("Unexpected SCAN response")
        }
        nextCursor = cursor
        keys = values[1]?.arrayValues.compactMap { $0?.string } ?? []
        self.scannedCount = scannedCount
    }
}

enum RedisClusterNodeRole: String, Hashable, Sendable {
    case primary
    case replica

    var title: String {
        switch self {
        case .primary: return "Primary"
        case .replica: return "Replica"
        }
    }
}

struct RedisClusterSlotRangeSummary: Hashable, Sendable {
    let start: Int
    let end: Int

    var label: String {
        start == end ? "\(start)" : "\(start)-\(end)"
    }

    var count: Int {
        max(0, end - start + 1)
    }
}

struct RedisClusterNodeSummary: Identifiable, Hashable, Sendable {
    let endpoint: RedisEndpoint
    let role: RedisClusterNodeRole
    let slotRanges: [RedisClusterSlotRangeSummary]
    let replicaOf: RedisEndpoint?

    var id: String {
        endpoint.address
    }

    var slotSummary: String {
        guard !slotRanges.isEmpty else { return "-" }
        return slotRanges.map(\.label).joined(separator: ", ")
    }

    var coveredSlotCount: Int {
        slotRanges.reduce(0) { $0 + $1.count }
    }
}

protocol RedisSession: AnyObject, Sendable {
    var mode: RedisConnectionMode { get }
    var isConnected: Bool { get }
    var lastError: String? { get }

    func connect() async throws
    func disconnect()
    func send(_ args: String...) async throws -> RESPValue
    func send(_ args: [String]) async throws -> RESPValue
    func sendPipeline(_ commands: [[String]]) async throws -> [RESPValue]
    func scan(cursor: String, match: String, count: Int) async throws -> RedisScanResult
    func totalKeyCount() async throws -> Int?
}

protocol RedisClusterEndpointResolver: Sendable {
    func clientEndpoint(for endpoint: RedisEndpoint) async throws -> RedisEndpoint
    func disconnect() async
}

extension RedisClient: RedisSession {
    var mode: RedisConnectionMode { .standalone }

    func scan(cursor: String, match: String, count: Int) async throws -> RedisScanResult {
        let response = try await send("SCAN", cursor, "MATCH", match, "COUNT", "\(count)")
        return try RedisScanResult(response: response, scannedCount: count)
    }

    func totalKeyCount() async throws -> Int? {
        try await fetchRedisTotalKeyCount { command in
            try await self.send(command)
        }
    }
}

func fetchRedisTotalKeyCount(
    _ sendCommand: ([String]) async throws -> RESPValue
) async throws -> Int? {
    do {
        let dbSizeResponse = try await sendCommand(["DBSIZE"])
        try throwIfRedisError(dbSizeResponse)
        if let count = dbSizeResponse.intValue {
            return count
        }
    } catch {
        AppLogger.debug("DBSIZE failed while counting keys: \(error)", category: "Redis")
    }

    let infoResponse = try await sendCommand(["INFO", "keyspace"])
    try throwIfRedisError(infoResponse)
    guard let info = infoResponse.string else { return nil }
    return keyCountFromKeyspaceInfo(info, database: 0)
}

func keyCountFromKeyspaceInfo(_ info: String, database: Int) -> Int? {
    let databasePrefix = "db\(database):"

    for rawLine in info.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix(databasePrefix) else { continue }

        let fields = line.dropFirst(databasePrefix.count).split(separator: ",")
        for field in fields {
            let parts = field.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0] == "keys" else { continue }
            return Int(parts[1])
        }
        return nil
    }

    return nil
}

func throwIfRedisError(_ value: RESPValue) throws {
    if case .error(let message) = value {
        throw RedisError.commandError(message)
    }
}
