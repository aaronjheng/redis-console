import Foundation
import SwiftUI

// MARK: - Connection Config

struct RedisConnectionConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var port: UInt16 = 6379
    var database: Int = 0

    var password: String = ""

    var sshEnabled: Bool = false
    var sshHost: String = ""
    var sshPort: UInt16 = 22
    var sshUsername: String = ""
    var sshPassword: String = ""
    var sshPrivateKeyPath: String = ""
    var sshPrivateKeyPassphrase: String = ""

    static let `default` = RedisConnectionConfig(name: "localhost", host: "127.0.0.1")

    var address: String { "\(host):\(port)" }
}

// MARK: - Redis Key Entry

@Observable
class RedisKeyEntry: Identifiable, Hashable {
    let id = UUID()
    let key: String
    var type: String
    let ttl: Int?
    let size: Int?

    init(key: String, type: String, ttl: Int?, size: Int?) {
        self.key = key
        self.type = type
        self.ttl = ttl
        self.size = size
    }

    var icon: String {
        switch type {
        case "string": return "doc.text"
        case "list": return "list.bullet"
        case "hash": return "tablecells"
        case "set": return "circle.grid.cross"
        case "zset": return "arrow.up.arrow.down.circle"
        case "stream": return "flowchart"
        default: return "questionmark.circle"
        }
    }

    var ttlText: String {
        guard let ttl = ttl, ttl > 0 else { return "No expiry" }
        if ttl > 86400 { return "\(ttl / 86400)d" }
        if ttl > 3600 { return "\(ttl / 3600)h" }
        if ttl > 60 { return "\(ttl / 60)m" }
        return "\(ttl)s"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }

    static func == (lhs: RedisKeyEntry, rhs: RedisKeyEntry) -> Bool {
        lhs.key == rhs.key
    }
}

// MARK: - Shell History

struct ShellHistoryEntry: Identifiable {
    let id = UUID()
    let command: String
    let result: String
    let timestamp: Date
    let isError: Bool
}

// MARK: - Slow Log Entry

struct SlowLogEntry: Identifiable {
    let id = UUID()
    let index: Int
    let timestamp: Date
    let durationMicroseconds: Int
    let command: [String]
    let clientAddress: String

    var durationText: String {
        if durationMicroseconds > 1_000_000 {
            return String(format: "%.1fs", Double(durationMicroseconds) / 1_000_000)
        } else if durationMicroseconds > 1_000 {
            return String(format: "%.1fms", Double(durationMicroseconds) / 1_000)
        }
        return "\(durationMicroseconds)μs"
    }
}

// MARK: - App Store (Global singleton, shared across all tabs)

@MainActor
class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var connections: [RedisConnectionConfig] = []
    private let storeURL: URL

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            connections = [.default]
            storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("connections.json")
            return
        }
        let dir = appSupport.appendingPathComponent("redis.console", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("connections.json")
        loadConnections()
    }

    func loadConnections() {
        if let data = try? Data(contentsOf: storeURL) {
            let decoded = try? JSONDecoder().decode([RedisConnectionConfig].self, from: data)
            if let decoded {
                connections = decoded
            }
        }
        if connections.isEmpty {
            connections = [.default]
        }
    }

    func saveConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    func addConnection(_ config: RedisConnectionConfig) {
        connections.append(config)
        saveConnections()
    }

    func updateConnection(_ config: RedisConnectionConfig) {
        if let idx = connections.firstIndex(where: { $0.id == config.id }) {
            connections[idx] = config
            saveConnections()
        }
    }

    func deleteConnection(_ config: RedisConnectionConfig) {
        connections.removeAll { $0.id == config.id }
        saveConnections()
    }
}

// MARK: - Connection State (Per-tab state)

enum AppView: String, CaseIterable {
    case browser = "Browser"
    case shell = "Shell"
    case slowlog = "Slow Log"
    case serverInfo = "Server Info"

    var icon: String {
        switch self {
        case .browser: return "key"
        case .shell: return "terminal"
        case .slowlog: return "clock.badge.exclamationmark"
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

@MainActor
class ConnectionState: ObservableObject {
    let id = UUID()
    weak var window: NSWindow?

    @Published var activeClient: RedisClient?
    @Published var isConnecting = false
    @Published var connectionError: String?
    @Published var selectedConnection: RedisConnectionConfig?
    @Published var pendingConnection: RedisConnectionConfig?

    @Published var keys: [RedisKeyEntry] = []
    @Published var selectedKey: RedisKeyEntry?
    @Published var keyDetail: String = ""
    @Published var keyDetailRows: [(String, String)] = []
    @Published var keyType: String = ""
    @Published var isLoadingKeys = false
    @Published var isLoadingDetail = false
    @Published var scanCursor: String = "0"
    @Published var hasMoreKeys = true
    @Published var keyFilter: String = "*"

    @Published var shellHistory: [ShellHistoryEntry] = []
    @Published var shellInput: String = ""

    @Published var serverInfo: [String: [String: String]] = [:]

    @Published var slowLogEntries: [SlowLogEntry] = []

    @Published var currentView: AppView = .browser
    @Published var rightPanel: RightPanel = .welcome

    private var connectTask: Task<Void, Never>?
    private var sshTunnel: SSHTunnel?
    private var isScanningKeysRequest = false
    private var pendingResetScan = false

    var windowTitle: String {
        if let conn = selectedConnection {
            return conn.name
        }
        return "Redis Console"
    }

    // MARK: - Connect / Disconnect

    func connect(to config: RedisConnectionConfig) async {
        let resolvedConfig = config
        AppLogger.info(
            "connect requested name=\(resolvedConfig.name) "
                + "redis=\(resolvedConfig.host):\(resolvedConfig.port) sshEnabled=\(resolvedConfig.sshEnabled)",
            category: "Connection"
        )
        connectTask?.cancel()
        activeClient?.disconnect()
        sshTunnel?.stop()
        sshTunnel = nil

        isConnecting = true
        connectionError = nil
        pendingConnection = resolvedConfig

        let task = Task { @MainActor in
            var connectHost = resolvedConfig.host
            var connectPort = resolvedConfig.port
            var client: RedisClient?

            do {
                if resolvedConfig.sshEnabled {
                    let sshHost = resolvedConfig.sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sshUsername = resolvedConfig.sshUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let effectiveSSHUsername = sshUsername.isEmpty ? NSUserName() : sshUsername
                    guard !sshHost.isEmpty else {
                        throw SSHTunnelError.connectionFailed("SSH host is required")
                    }

                    let tunnel = SSHTunnel()
                    sshTunnel = tunnel
                    AppLogger.info(
                        "starting ssh tunnel ssh=\(sshHost):\(resolvedConfig.sshPort) "
                            + "user=\(effectiveSSHUsername) remote=\(resolvedConfig.host):\(resolvedConfig.port)",
                        category: "Connection"
                    )
                    try await withTimeout(12, context: "SSH tunnel setup") {
                        try await tunnel.start(
                            sshHost: sshHost,
                            sshPort: resolvedConfig.sshPort,
                            sshUsername: effectiveSSHUsername,
                            sshPassword: resolvedConfig.sshPassword.isEmpty ? nil : resolvedConfig.sshPassword,
                            privateKeyPath: resolvedConfig.sshPrivateKeyPath.isEmpty ? nil : resolvedConfig.sshPrivateKeyPath,
                            remoteHost: resolvedConfig.host,
                            remotePort: resolvedConfig.port
                        )
                    }
                    connectHost = "127.0.0.1"
                    connectPort = tunnel.localPort
                    AppLogger.info(
                        "ssh tunnel ready mode=\(tunnel.mode.rawValue) local=127.0.0.1:\(connectPort)",
                        category: "Connection"
                    )
                }

                try Task.checkCancellation()

                let redis = RedisClient(
                    host: connectHost,
                    port: connectPort,
                    password: resolvedConfig.password.isEmpty ? nil : resolvedConfig.password
                )
                client = redis

                try await withTimeout(10, context: "Redis connection") {
                    try await redis.connect()
                }
                AppLogger.info("redis connected \(connectHost):\(connectPort)", category: "Connection")

                try Task.checkCancellation()

                if resolvedConfig.database != 0 {
                    _ = try? await withTimeout(5, context: "Redis SELECT") {
                        try await redis.send("SELECT", "\(resolvedConfig.database)")
                    }
                }

                activeClient = redis
                selectedConnection = resolvedConfig
                isConnecting = false
                pendingConnection = nil
                await loadServerInfo()
                await scanKeys(reset: true)
                AppLogger.info("connect completed name=\(resolvedConfig.name)", category: "Connection")
            } catch is CancellationError {
                client?.disconnect()
                AppLogger.info("connect cancelled name=\(resolvedConfig.name)", category: "Connection")
            } catch {
                client?.disconnect()
                connectionError = error.localizedDescription
                isConnecting = false
                pendingConnection = nil
                sshTunnel?.stop()
                sshTunnel = nil
                AppLogger.error("connect failed name=\(resolvedConfig.name) error=\(error)", category: "Connection")
            }
        }

        connectTask = task
        await task.value
    }

    func cancelConnection() {
        AppLogger.info("cancel connection", category: "Connection")
        connectTask?.cancel()
        connectTask = nil
        activeClient?.disconnect()
        sshTunnel?.stop()
        sshTunnel = nil
        isConnecting = false
        pendingConnection = nil
        connectionError = nil
    }

    func disconnect() {
        AppLogger.info("disconnect current connection", category: "Connection")
        activeClient?.disconnect()
        activeClient = nil
        sshTunnel?.stop()
        sshTunnel = nil
        selectedConnection = nil
        keys = []
        selectedKey = nil
        keyDetail = ""
        serverInfo = [:]
        shellHistory = []
    }

    // MARK: - Key Browser

    func scanKeys(reset: Bool = false) async {
        if isScanningKeysRequest {
            pendingResetScan = pendingResetScan || reset
            return
        }

        guard let client = activeClient, client.isConnected else {
            isLoadingKeys = false
            return
        }

        isScanningKeysRequest = true
        if reset {
            scanCursor = "0"
            keys = []
            hasMoreKeys = true
        }
        isLoadingKeys = true

        do {
            let result = try await client.send("SCAN", scanCursor, "MATCH", keyFilter, "COUNT", "1000")
            let arr = result.arrayValues
            guard arr.count >= 2 else {
                isScanningKeysRequest = false
                isLoadingKeys = false
                return
            }
            scanCursor = arr[0]?.string ?? "0"
            hasMoreKeys = scanCursor != "0"
            let newKeyNames = arr[1]?.arrayValues.compactMap { $0?.string } ?? []
            let existingKeys = Set(keys.map { $0.key })
            let newEntries = newKeyNames.filter { !existingKeys.contains($0) }.map {
                RedisKeyEntry(key: $0, type: "", ttl: nil, size: nil)
            }
            keys.append(contentsOf: newEntries)
        } catch {
            connectionError = error.localizedDescription
        }

        let shouldRestart = pendingResetScan
        pendingResetScan = false
        isScanningKeysRequest = false
        isLoadingKeys = false
        loadTypes()

        if shouldRestart {
            await scanKeys(reset: true)
        }
    }

    private func loadTypes() {
        guard let client = activeClient, client.isConnected else { return }
        let toLoad = keys.filter { $0.type.isEmpty }
        Task {
            await withTaskGroup(of: Void.self) { group in
                for entry in toLoad {
                    group.addTask {
                        let typeResult = try? await client.send("TYPE", entry.key)
                        guard let typeName = typeResult?.string else { return }
                        await MainActor.run {
                            entry.type = typeName
                        }
                    }
                }
            }
        }
    }

    func selectKey(_ entry: RedisKeyEntry) async {
        selectedKey = entry
        isLoadingDetail = true
        keyDetail = ""
        keyDetailRows = []
        guard let client = activeClient else { return }
        do {
            let typeResult = try await client.send("TYPE", entry.key)
            keyType = typeResult.string ?? "string"
            entry.type = keyType
            switch keyType {
            case "string":
                let value = try await client.send("GET", entry.key)
                keyDetail = value.string ?? "(nil)"
            case "list":
                let value = try await client.send("LRANGE", entry.key, "0", "99")
                let items = value.arrayValues.enumerated().compactMap { index, value -> (String, String)? in
                    guard let stringValue = value?.string else { return nil }
                    return ("[\(index)]", stringValue)
                }
                keyDetailRows = items
            case "hash":
                let value = try await client.send("HGETALL", entry.key)
                let items = value.arrayValues
                var rows: [(String, String)] = []
                var itemIndex = 0
                while itemIndex + 1 < items.count {
                    let field = items[itemIndex]?.string ?? ""
                    let fieldValue = items[itemIndex + 1]?.string ?? ""
                    rows.append((field, fieldValue))
                    itemIndex += 2
                }
                keyDetailRows = rows
            case "set":
                let value = try await client.send("SMEMBERS", entry.key)
                keyDetailRows = value.arrayValues.enumerated().compactMap { index, value in
                    guard let stringValue = value?.string else { return nil }
                    return ("[\(index)]", stringValue)
                }
            case "zset":
                let value = try await client.send("ZRANGE", entry.key, "0", "99", "WITHSCORES")
                let items = value.arrayValues
                var rows: [(String, String)] = []
                var itemIndex = 0
                while itemIndex + 1 < items.count {
                    let member = items[itemIndex]?.string ?? ""
                    let score = items[itemIndex + 1]?.string ?? ""
                    rows.append((score, member))
                    itemIndex += 2
                }
                keyDetailRows = rows
            case "stream":
                let value = try await client.send("XRANGE", entry.key, "-", "+", "COUNT", "100")
                keyDetail = value.displayString
            default:
                let value = try await client.send("GET", entry.key)
                keyDetail = value.string ?? "(nil)"
            }
        } catch {
            keyDetail = "Error: \(error.localizedDescription)"
        }
        isLoadingDetail = false
    }

    func deleteKey(_ entry: RedisKeyEntry) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("DEL", entry.key)
        keys.removeAll { $0.key == entry.key }
        if selectedKey?.key == entry.key {
            selectedKey = nil
            keyDetail = ""
        }
    }

    func renameKey(old: String, new: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("RENAME", old, new)
        await scanKeys(reset: true)
    }

    // MARK: - Shell

    func executeCommand(_ input: String) async {
        guard let client = activeClient, client.isConnected else { return }
        let parts = parseCommand(input)
        guard !parts.isEmpty else { return }
        do {
            let result = try await client.send(parts)
            let entry = ShellHistoryEntry(
                command: input,
                result: result.displayString,
                timestamp: Date(),
                isError: {
                    if case .error = result { return true }
                    return false
                }()
            )
            shellHistory.append(entry)
        } catch {
            let entry = ShellHistoryEntry(
                command: input,
                result: error.localizedDescription,
                timestamp: Date(),
                isError: true
            )
            shellHistory.append(entry)
        }
        shellInput = ""
    }

    private func parseCommand(_ input: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var quoteChar: Character = "\""

        for char in input {
            if char == "\"" || char == "'" {
                if inQuotes && char == quoteChar {
                    inQuotes = false
                } else if !inQuotes {
                    inQuotes = true
                    quoteChar = char
                }
            } else if char == " " && !inQuotes {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            parts.append(current)
        }
        return parts
    }

    // MARK: - Server Info

    func loadServerInfo() async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("INFO")
            guard let infoStr = result.string else { return }
            var sections: [String: [String: String]] = [:]
            var currentSection = ""
            for line in infoStr.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("#") {
                    currentSection = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                    sections[currentSection] = [:]
                } else if trimmed.contains(":") {
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count >= 2 {
                        sections[currentSection]?[parts[0]] = parts.dropFirst().joined(separator: ":")
                    }
                }
            }
            serverInfo = sections
        } catch {}
    }

    // MARK: - Slow Log

    func loadSlowLog() async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("SLOWLOG", "GET", "50")
            var entries: [SlowLogEntry] = []
            for item in result.arrayValues {
                guard let arr = item?.arrayValues, arr.count >= 6 else { continue }
                let index = arr[0]?.intValue ?? 0
                let ts = arr[1]?.intValue ?? 0
                let duration = arr[2]?.intValue ?? 0
                let cmd = arr[3]?.arrayValues.compactMap { $0?.string } ?? []
                let clientAddr = arr[5]?.string ?? ""
                entries.append(
                    SlowLogEntry(
                        index: index,
                        timestamp: Date(timeIntervalSince1970: Double(ts)),
                        durationMicroseconds: duration,
                        command: cmd,
                        clientAddress: clientAddr
                    ))
            }
            slowLogEntries = entries
        } catch {}
    }

    // MARK: - Auto-complete

    func completions(for prefix: String) -> [String] {
        let commands = [
            "APPEND", "AUTH", "BGREWRITEAOF", "BGSAVE", "BITCOUNT", "BITOP", "BITPOS",
            "BLPOP", "BRPOP", "BRPOPLPUSH", "CLIENT", "CLUSTER", "CONFIG", "DBSIZE",
            "DEBUG", "DECR", "DECRBY", "DEL", "DISCARD", "DUMP", "ECHO", "EVAL", "EVALSHA",
            "EXEC", "EXISTS", "EXPIRE", "EXPIREAT", "FLUSHALL", "FLUSHDB", "GEOADD",
            "GEODIST", "GEOHASH", "GEOPOS", "GET", "GETBIT", "GETRANGE", "GETSET",
            "HDEL", "HEXISTS", "HGET", "HGETALL", "HINCRBY", "HINCRBYFLOAT", "HKEYS",
            "HLEN", "HMGET", "HMSET", "HSCAN", "HSET", "HSETNX", "HVALS", "INCR",
            "INCRBY", "INCRBYFLOAT", "INFO", "KEYS", "LASTSAVE", "LINDEX", "LINSERT",
            "LLEN", "LPOP", "LPUSH", "LPUSHX", "LRANGE", "LREM", "LSET", "LTRIM",
            "MEMORY", "MGET", "MIGRATE", "MONITOR", "MOVE", "MSET", "MSETNX", "MULTI",
            "OBJECT", "PERSIST", "PEXPIRE", "PEXPIREAT", "PFADD", "PFCOUNT", "PFMERGE",
            "PING", "PSETEX", "PSUBSCRIBE", "PTTL", "PUBLISH", "PUBSUB", "PUNSUBSCRIBE",
            "QUIT", "RANDOMKEY", "READONLY", "READWRITE", "RENAME", "RENAMENX", "RESTORE",
            "ROLE", "RPOP", "RPOPLPUSH", "RPUSH", "RPUSHX", "SADD", "SAVE", "SCAN",
            "SCARD", "SCRIPT", "SDIFF", "SDIFFSTORE", "SELECT", "SET", "SETBIT",
            "SETEX", "SETNX", "SETRANGE", "SHUTDOWN", "SINTER", "SINTERSTORE", "SISMEMBER",
            "SLAVEOF", "SLOWLOG", "SMEMBERS", "SMOVE", "SORT", "SPOP", "SRANDMEMBER",
            "SREM", "SSCAN", "STRLEN", "SUBSCRIBE", "SUNION", "SUNIONSTORE", "SYNC",
            "TIME", "TOUCH", "TTL", "TYPE", "UNLINK", "UNSUBSCRIBE", "UNWATCH", "WAIT",
            "WATCH", "XADD", "XCLAIM", "XDEL", "XGROUP", "XINFO", "XLEN", "XPENDING",
            "XRANGE", "XREAD", "XREADGROUP", "XREVRANGE", "XTRIM", "ZADD", "ZCARD",
            "ZCOUNT", "ZINCRBY", "ZINTERSTORE", "ZLEXCOUNT", "ZPOPMAX", "ZPOPMIN",
            "ZRANGE", "ZRANGEBYLEX", "ZRANGEBYSCORE", "ZRANK", "ZREM", "ZREMRANGEBYLEX",
            "ZREMRANGEBYRANK", "ZREMRANGEBYSCORE", "ZREVRANGE", "ZREVRANGEBYLEX",
            "ZREVRANGEBYSCORE", "ZREVRANK", "ZSCAN", "ZSCORE", "ZUNIONSTORE",
        ]
        let upper = prefix.uppercased()
        return commands.filter { $0.hasPrefix(upper) }
    }
}
