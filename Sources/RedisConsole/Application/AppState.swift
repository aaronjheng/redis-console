import Foundation
import SwiftUI

// MARK: - Connection Config

struct SSHConfig: Codable, Hashable {
    var enabled: Bool = false
    var host: String = ""
    var port: UInt16 = 22
    var user: String = ""
    var password: String = ""
    var privateKeyPath: String = ""
    var privateKeyPassphrase: String = ""
}

struct TLSConfig: Codable, Hashable {
    var enabled: Bool = false
    var verifyServerCertificate: Bool = true
    var caCertificatePath: String = ""
    var clientCertificatePath: String = ""
    var clientKeyPath: String = ""
}

struct RedisConnectionConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var mode: RedisConnectionMode = .standalone
    var host: String
    var port: UInt16 = 6379
    var seedNodes: [RedisEndpoint] = []

    var username: String = ""
    var password: String = ""

    var ssh: SSHConfig = SSHConfig()
    var tls: TLSConfig = TLSConfig()

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case host
        case port
        case seedNodes
        case username
        case ssh
        case password
        case tls
    }

    static let `default` = RedisConnectionConfig(name: "localhost", host: "127.0.0.1")

    var effectiveSeedNodes: [RedisEndpoint] {
        [RedisEndpoint(host: host, port: port)]
    }

    var address: String {
        switch mode {
        case .standalone:
            return "\(host):\(port)"
        case .cluster:
            return effectiveSeedNodes.map(\.address).joined(separator: ", ")
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        mode: RedisConnectionMode = .standalone,
        host: String,
        port: UInt16 = 6379,
        seedNodes: [RedisEndpoint] = [],
        username: String = "",
        password: String = "",
        ssh: SSHConfig = SSHConfig(),
        tls: TLSConfig = TLSConfig()
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.host = host
        self.port = port
        self.seedNodes = seedNodes
        self.username = username
        self.password = password
        self.ssh = ssh
        self.tls = tls
    }

    static func parseURI(_ uri: String) -> RedisConnectionConfig? {
        guard let components = URLComponents(string: uri),
            let scheme = components.scheme,
            scheme == "redis" || scheme == "rediss"
        else { return nil }

        let host = components.host ?? "127.0.0.1"
        let port = UInt16(components.port ?? 6379)
        let useTLS = scheme == "rediss"

        var username = ""
        var password = ""

        if let pwd = components.password {
            username = components.user ?? ""
            password = pwd
        } else if let user = components.user {
            password = user
        }

        return RedisConnectionConfig(
            name: host,
            mode: .standalone,
            host: host,
            port: port,
            seedNodes: [],
            username: username,
            password: password,
            tls: TLSConfig(enabled: useTLS)
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        mode = try container.decodeIfPresent(RedisConnectionMode.self, forKey: .mode) ?? .standalone
        host = try container.decode(String.self, forKey: .host)
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 6379
        seedNodes = try container.decodeIfPresent([RedisEndpoint].self, forKey: .seedNodes) ?? []
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        ssh = try container.decodeIfPresent(SSHConfig.self, forKey: .ssh) ?? SSHConfig()
        tls = try container.decodeIfPresent(TLSConfig.self, forKey: .tls) ?? TLSConfig()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(mode, forKey: .mode)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(seedNodes, forKey: .seedNodes)
        try container.encode(username, forKey: .username)
        try container.encode(ssh, forKey: .ssh)
        try container.encode(tls, forKey: .tls)
    }
}

// MARK: - Redis Key Entry

@Observable
class RedisKeyEntry: Identifiable, Hashable {
    let id = UUID()
    let key: String
    var type: String
    var ttl: Int?
    var size: Int?

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
        default: return "questionmark.circle"
        }
    }

    var ttlText: String {
        guard let ttl = ttl, ttl > 0 else { return "No limit" }
        if ttl > 86400 { return "\(ttl / 86400)d" }
        if ttl > 3600 { return "\(ttl / 3600)h" }
        if ttl > 60 { return "\(ttl / 60)m" }
        return "\(ttl)s"
    }

    var hasExpiry: Bool {
        guard let ttl else { return false }
        return ttl > 0
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

// MARK: - Profiler

private final class RedisProfilerTaskBag: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []

    func add(_ task: Task<Void, Never>) {
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        let tasks = tasks
        self.tasks.removeAll()
        lock.unlock()

        for task in tasks {
            task.cancel()
        }
    }
}

private struct RedisProfilerCapture: Sendable {
    let node: RedisEndpoint?
    let line: String
}

private struct RedisProfilerStream {
    let stream: AsyncThrowingStream<RedisProfilerCapture, Error>
    let monitorClients: [RedisMonitorClient]
    let monitorTasks: RedisProfilerTaskBag?
    let tunnel: SSHTunnel?
    let tunnelManager: SSHClusterTunnelManager?
}

struct RedisProfilerEntry: Identifiable, Hashable {
    private struct ParsedLine {
        let timestamp: Date
        let database: Int?
        let source: String
        let commandName: String
        let commandText: String
        let arguments: [String]
    }

    let id = UUID()
    let timestamp: Date
    let database: Int?
    let source: String
    let commandName: String
    let commandText: String
    let arguments: [String]
    let rawLine: String
    let node: RedisEndpoint?

    init(rawLine: String, node: RedisEndpoint? = nil, capturedAt: Date = Date()) {
        self.rawLine = rawLine
        self.node = node

        let parsed = Self.parse(rawLine: rawLine, capturedAt: capturedAt)
        timestamp = parsed.timestamp
        database = parsed.database
        source = parsed.source
        commandName = parsed.commandName
        commandText = parsed.commandText
        arguments = parsed.arguments
    }

    var databaseText: String {
        database.map(String.init) ?? "-"
    }

    var nodeText: String {
        node?.address ?? "-"
    }

    var timeText: String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: timestamp)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        let millisecond = (components.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d", hour, minute, second, millisecond)
    }

    var argumentsText: String {
        guard arguments.count > 1 else { return "" }
        return arguments.dropFirst().map(Self.displayArgument).joined(separator: " ")
    }

    var searchText: String {
        ([databaseText, nodeText, source, commandName, commandText, rawLine] + arguments)
            .joined(separator: " ")
            .lowercased()
    }

    var isNoiseCommand: Bool {
        switch commandName {
        case "PING":
            return true
        case "CLUSTER":
            guard arguments.count > 1 else { return false }
            return Self.noiseClusterSubcommands.contains(arguments[1].uppercased())
        default:
            return false
        }
    }

    private static let noiseClusterSubcommands: Set<String> = [
        "INFO",
        "NODES",
        "SHARDS",
        "SLOTS",
    ]

    private static func parse(
        rawLine: String,
        capturedAt: Date
    ) -> ParsedLine {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestampEnd = trimmed.firstIndex(of: " ") ?? trimmed.endIndex
        let timestampText = String(trimmed[..<timestampEnd])
        let timestamp = Double(timestampText).map { Date(timeIntervalSince1970: $0) } ?? capturedAt

        var remainder =
            timestampEnd < trimmed.endIndex
            ? String(trimmed[trimmed.index(after: timestampEnd)...]).trimmingCharacters(in: .whitespaces)
            : ""

        var database: Int?
        var source = "-"

        if remainder.first == "[", let closeBracketIndex = remainder.firstIndex(of: "]") {
            let metadataStart = remainder.index(after: remainder.startIndex)
            let metadata = String(remainder[metadataStart..<closeBracketIndex])
            let parts = metadata.split(separator: " ", maxSplits: 1).map(String.init)
            database = parts.first.flatMap(Int.init)
            if parts.count > 1 {
                source = parts[1]
            } else if !metadata.isEmpty {
                source = metadata
            }

            let commandStart = remainder.index(after: closeBracketIndex)
            remainder = String(remainder[commandStart...]).trimmingCharacters(in: .whitespaces)
        }

        let arguments = parseArguments(remainder)
        let commandName = arguments.first?.uppercased() ?? "-"
        let commandText = arguments.isEmpty ? remainder : arguments.map(displayArgument).joined(separator: " ")
        return ParsedLine(
            timestamp: timestamp,
            database: database,
            source: source,
            commandName: commandName,
            commandText: commandText,
            arguments: arguments
        )
    }

    private static func parseArguments(_ value: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in value {
            if isQuoted {
                if isEscaped {
                    current.append(unescaped(character))
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    arguments.append(current)
                    current = ""
                    isQuoted = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                isQuoted = true
            }
        }

        if isQuoted || !current.isEmpty {
            arguments.append(current)
        }

        return arguments
    }

    private static func unescaped(_ character: Character) -> Character {
        switch character {
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        default: return character
        }
    }

    private static func displayArgument(_ value: String) -> String {
        if value.isEmpty {
            return "\"\""
        }

        let needsQuoting = value.contains { character in
            character.isWhitespace || character == "\""
        }
        guard needsQuoting else { return value }

        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

// MARK: - App Store (Global singleton, shared across all tabs)

@MainActor
class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var connections: [RedisConnectionConfig] = []
    private let storeURL: URL
    private let secretsAccountSuffix = "secrets"

    private struct ConnectionSecrets: Codable {
        let redisPassword: String
        let sshPassword: String
        let sshPrivateKeyPassphrase: String

        var isEmpty: Bool {
            redisPassword.isEmpty && sshPassword.isEmpty && sshPrivateKeyPassphrase.isEmpty
        }
    }

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
                connections = decoded.map { config in
                    var resolved = config
                    loadSecretsFromKeychain(into: &resolved)
                    return resolved
                }
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
        saveSecretsToKeychain(for: config)
        saveConnections()
    }

    func updateConnection(_ config: RedisConnectionConfig) {
        if let idx = connections.firstIndex(where: { $0.id == config.id }) {
            connections[idx] = config
            saveSecretsToKeychain(for: config)
            saveConnections()
        }
    }

    func deleteConnection(_ config: RedisConnectionConfig) {
        connections.removeAll { $0.id == config.id }
        deleteSecretsFromKeychain(for: config)
        saveConnections()
    }

    func exportConnections(_ configs: [RedisConnectionConfig]) -> Data? {
        try? JSONEncoder().encode(configs)
    }

    func importConnections(from data: Data) -> [RedisConnectionConfig]? {
        try? JSONDecoder().decode([RedisConnectionConfig].self, from: data)
    }

    func addImportedConnections(_ configs: [RedisConnectionConfig]) {
        for config in configs {
            var newConfig = config
            newConfig.id = UUID()
            connections.append(newConfig)
            saveSecretsToKeychain(for: newConfig)
        }
        saveConnections()
    }

    private func keychainAccount(for id: UUID) -> String {
        "connection.\(id.uuidString).\(secretsAccountSuffix)"
    }

    private func saveSecretsToKeychain(for config: RedisConnectionConfig) {
        let secrets = ConnectionSecrets(
            redisPassword: config.password,
            sshPassword: config.ssh.password,
            sshPrivateKeyPassphrase: config.ssh.privateKeyPassphrase
        )
        if secrets.isEmpty {
            KeychainStore.deletePassword(account: keychainAccount(for: config.id))
            return
        }

        guard let encoded = try? JSONEncoder().encode(secrets) else {
            AppLogger.error("saveSecretsToKeychain JSON encode failed connectionId=\(config.id.uuidString)", category: "AppStore")
            return
        }
        guard let payload = String(data: encoded, encoding: .utf8) else {
            AppLogger.error("saveSecretsToKeychain UTF-8 conversion failed connectionId=\(config.id.uuidString)", category: "AppStore")
            return
        }

        let saved = KeychainStore.setPassword(payload, account: keychainAccount(for: config.id))
        if !saved {
            AppLogger.error("failed to save secrets to keychain connectionId=\(config.id.uuidString)", category: "AppStore")
        }
    }

    private func loadSecretsFromKeychain(into config: inout RedisConnectionConfig) {
        let connectionId = config.id.uuidString
        guard let payload = KeychainStore.getPassword(account: keychainAccount(for: config.id)) else {
            config.password = ""
            config.ssh.password = ""
            config.ssh.privateKeyPassphrase = ""
            return
        }
        guard let data = payload.data(using: .utf8) else {
            AppLogger.error("loadSecretsFromKeychain payload not UTF-8 connectionId=\(connectionId)", category: "AppStore")
            config.password = ""
            config.ssh.password = ""
            config.ssh.privateKeyPassphrase = ""
            return
        }
        guard let decoded = try? JSONDecoder().decode(ConnectionSecrets.self, from: data) else {
            AppLogger.error("loadSecretsFromKeychain JSON decode failed connectionId=\(connectionId)", category: "AppStore")
            config.password = ""
            config.ssh.password = ""
            config.ssh.privateKeyPassphrase = ""
            return
        }
        config.password = decoded.redisPassword
        config.ssh.password = decoded.sshPassword
        config.ssh.privateKeyPassphrase = decoded.sshPrivateKeyPassphrase
    }

    private func deleteSecretsFromKeychain(for config: RedisConnectionConfig) {
        KeychainStore.deletePassword(account: keychainAccount(for: config.id))
    }
}

// MARK: - Connection State (Per-tab state)

enum AppView: String, CaseIterable {
    case browser = "Browser"
    case shell = "Shell"
    case profiler = "Profiler"
    case serverInfo = "Server Info"

    var icon: String {
        switch self {
        case .browser: return "key"
        case .shell: return "terminal"
        case .profiler: return "waveform.path.ecg"
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

@MainActor
class ConnectionState: ObservableObject {
    let id = UUID()
    weak var window: NSWindow?

    @Published var activeClient: (any RedisSession)?
    @Published var isConnecting = false
    @Published var connectionError: String?
    @Published var selectedConnection: RedisConnectionConfig?
    @Published var pendingConnection: RedisConnectionConfig?

    @Published var keys: [RedisKeyEntry] = []
    @Published var selectedKey: RedisKeyEntry?
    @Published var keyDetail: String = ""
    @Published var keyDetailRows: [(String, String)] = []
    @Published var keyType: String = ""
    @Published var valueSize: Int?
    @Published var isLoadingKeys = false
    @Published var isLoadingDetail = false
    @Published var scanCursor: String = "0"
    @Published var hasMoreKeys = true
    @Published var keyFilter: String = "*"
    @Published var keyTypeFilter: String = ""
    @Published var keyScanCount = 500

    @Published var shellHistory: [ShellHistoryEntry] = []
    @Published var shellInput: String = ""

    @Published var profilerEntries: [RedisProfilerEntry] = []
    @Published var profilerCapturedCount = 0
    @Published var profilerError: String?
    @Published var isProfilerRunning = false
    @Published var isProfilerStarting = false

    @Published var serverInfo: [String: [String: String]] = [:]
    @Published var serverCapabilities: [RedisServerCapability] = []
    @Published var clusterInfo: [String: String] = [:]
    @Published var clusterNodes: [RedisClusterNodeSummary] = []
    @Published var selectedServerInfoNode: RedisEndpoint?

    @Published var currentView: AppView = .browser
    @Published var rightPanel: RightPanel = .welcome

    private var connectTask: Task<Void, Never>?
    private var sshTunnel: SSHTunnel?
    private var sshClusterTunnelManager: SSHClusterTunnelManager?
    private var isScanningKeysRequest = false
    private var pendingResetScan = false
    private var profilerTask: Task<Void, Never>?
    private var profilerMonitorClients: [RedisMonitorClient] = []
    private var profilerMonitorTasks: RedisProfilerTaskBag?
    private var profilerSSHTunnel: SSHTunnel?
    private var profilerClusterTunnelManager: SSHClusterTunnelManager?
    private var profilerGeneration = 0
    private let profilerMaxEntries = 2_000
    private let keyTypePipelineBatchSize = 100

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
                + "mode=\(resolvedConfig.mode.rawValue) redis=\(resolvedConfig.address) "
                + "sshEnabled=\(resolvedConfig.ssh.enabled) tlsEnabled=\(resolvedConfig.tls.enabled)",
            category: "Connection"
        )
        stopProfiler(clearEntries: true)
        connectTask?.cancel()
        activeClient?.disconnect()
        sshTunnel?.stop()
        sshTunnel = nil
        let previousClusterTunnelManager = sshClusterTunnelManager
        sshClusterTunnelManager = nil
        await previousClusterTunnelManager?.disconnect()

        isConnecting = true
        connectionError = nil
        pendingConnection = resolvedConfig
        serverInfo = [:]
        serverCapabilities = []
        clusterInfo = [:]
        clusterNodes = []
        selectedServerInfoNode = nil

        let task = Task { @MainActor in
            var connectHost = resolvedConfig.host
            var connectPort = resolvedConfig.port
            var client: (any RedisSession)?
            var clusterTunnelManager: SSHClusterTunnelManager?

            do {
                var clusterEndpointResolver: (any RedisClusterEndpointResolver)?

                if resolvedConfig.ssh.enabled {
                    let sshHost = resolvedConfig.ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sshUser = resolvedConfig.ssh.user.trimmingCharacters(in: .whitespacesAndNewlines)
                    let effectiveSSHUser = sshUser.isEmpty ? NSUserName() : sshUser
                    guard !sshHost.isEmpty else {
                        throw SSHTunnelError.connectionFailed("SSH host is required")
                    }

                    switch resolvedConfig.mode {
                    case .standalone:
                        let tunnel = SSHTunnel()
                        sshTunnel = tunnel
                        AppLogger.info(
                            "starting ssh tunnel ssh=\(sshHost):\(resolvedConfig.ssh.port) "
                                + "user=\(effectiveSSHUser) remote=\(resolvedConfig.host):\(resolvedConfig.port)",
                            category: "Connection"
                        )
                        try await withTimeout(12, context: "SSH tunnel setup") {
                            try await tunnel.start(
                                sshHost: sshHost,
                                sshPort: resolvedConfig.ssh.port,
                                sshUser: effectiveSSHUser,
                                sshPassword: resolvedConfig.ssh.password.isEmpty ? nil : resolvedConfig.ssh.password,
                                privateKeyPath: resolvedConfig.ssh.privateKeyPath.isEmpty ? nil : resolvedConfig.ssh.privateKeyPath,
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
                    case .cluster:
                        let manager = SSHClusterTunnelManager(ssh: resolvedConfig.ssh)
                        clusterTunnelManager = manager
                        sshClusterTunnelManager = manager
                        clusterEndpointResolver = manager
                        AppLogger.info(
                            "cluster ssh tunnel manager ready ssh=\(sshHost):\(resolvedConfig.ssh.port) "
                                + "user=\(effectiveSSHUser)",
                            category: "Connection"
                        )
                    }
                }

                try Task.checkCancellation()

                let redis: any RedisSession
                switch resolvedConfig.mode {
                case .standalone:
                    redis = RedisClient(
                        host: connectHost,
                        port: connectPort,
                        username: resolvedConfig.username.isEmpty ? nil : resolvedConfig.username,
                        password: resolvedConfig.password.isEmpty ? nil : resolvedConfig.password,
                        tlsEnabled: resolvedConfig.tls.enabled,
                        verifyServerCertificate: resolvedConfig.tls.verifyServerCertificate,
                        caCertificatePath: resolvedConfig.tls.caCertificatePath,
                        clientCertificatePath: resolvedConfig.tls.clientCertificatePath,
                        clientKeyPath: resolvedConfig.tls.clientKeyPath
                    )
                case .cluster:
                    redis = RedisClusterClient(
                        seedNodes: resolvedConfig.effectiveSeedNodes,
                        username: resolvedConfig.username.isEmpty ? nil : resolvedConfig.username,
                        password: resolvedConfig.password.isEmpty ? nil : resolvedConfig.password,
                        tlsEnabled: resolvedConfig.tls.enabled,
                        verifyServerCertificate: resolvedConfig.tls.verifyServerCertificate,
                        caCertificatePath: resolvedConfig.tls.caCertificatePath,
                        clientCertificatePath: resolvedConfig.tls.clientCertificatePath,
                        clientKeyPath: resolvedConfig.tls.clientKeyPath,
                        endpointResolver: clusterEndpointResolver
                    )
                }
                client = redis

                try await withTimeout(10, context: "Redis connection") {
                    try await redis.connect()
                }
                AppLogger.info("redis connected mode=\(resolvedConfig.mode.rawValue) \(resolvedConfig.address)", category: "Connection")

                try Task.checkCancellation()

                activeClient = redis
                selectedConnection = resolvedConfig
                isConnecting = false
                pendingConnection = nil
                await loadServerInfo()
                await scanKeys(reset: true)
                AppLogger.info("connect completed name=\(resolvedConfig.name)", category: "Connection")
            } catch is CancellationError {
                client?.disconnect()
                clearClusterTunnelManagerIfCurrent(clusterTunnelManager)
                if let clusterTunnelManager {
                    await clusterTunnelManager.disconnect()
                }
                AppLogger.info("connect cancelled name=\(resolvedConfig.name)", category: "Connection")
            } catch {
                client?.disconnect()
                connectionError = error.localizedDescription
                isConnecting = false
                pendingConnection = nil
                sshTunnel?.stop()
                sshTunnel = nil
                clearClusterTunnelManagerIfCurrent(clusterTunnelManager)
                if let clusterTunnelManager {
                    await clusterTunnelManager.disconnect()
                }
                AppLogger.error("connect failed name=\(resolvedConfig.name) error=\(error)", category: "Connection")
            }
        }

        connectTask = task
        await task.value
    }

    private func clearClusterTunnelManagerIfCurrent(_ manager: SSHClusterTunnelManager?) {
        guard let current = sshClusterTunnelManager, let manager else { return }
        guard ObjectIdentifier(current) == ObjectIdentifier(manager) else { return }
        sshClusterTunnelManager = nil
    }

    func cancelConnection() {
        AppLogger.info("cancel connection", category: "Connection")
        stopProfiler(clearEntries: true)
        connectTask?.cancel()
        connectTask = nil
        activeClient?.disconnect()
        sshTunnel?.stop()
        sshTunnel = nil
        let clusterTunnelManager = sshClusterTunnelManager
        sshClusterTunnelManager = nil
        Task { await clusterTunnelManager?.disconnect() }
        isConnecting = false
        pendingConnection = nil
        connectionError = nil
    }

    func disconnect() {
        AppLogger.info("disconnect current connection", category: "Connection")
        stopProfiler(clearEntries: true)
        activeClient?.disconnect()
        activeClient = nil
        sshTunnel?.stop()
        sshTunnel = nil
        let clusterTunnelManager = sshClusterTunnelManager
        sshClusterTunnelManager = nil
        Task { await clusterTunnelManager?.disconnect() }
        selectedConnection = nil
        keys = []
        selectedKey = nil
        keyDetail = ""
        serverInfo = [:]
        serverCapabilities = []
        clusterInfo = [:]
        clusterNodes = []
        selectedServerInfoNode = nil
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
            clearSelectedKeyDetail()
            hasMoreKeys = true
        }
        isLoadingKeys = true

        let isPattern = keyFilter.contains("*") || keyFilter.contains("?") || keyFilter.contains("[")

        do {
            if !isPattern {
                let typeResult = try? await client.send("TYPE", keyFilter)
                if let typeName = typeResult?.string, typeName != "none" {
                    let entry = RedisKeyEntry(key: keyFilter, type: typeName, ttl: nil, size: nil)
                    keys = [entry]
                } else {
                    keys = []
                    clearSelectedKeyDetail()
                }
                hasMoreKeys = false
            } else {
                let scanAll = keyFilter != "*"
                var iterations = 0
                let maxIterations = scanAll ? 1000 : 1
                repeat {
                    let result = try await client.scan(cursor: scanCursor, match: keyFilter, count: keyScanCount)
                    scanCursor = result.nextCursor
                    hasMoreKeys = scanCursor != "0"
                    let newKeyNames = result.keys
                    let existingKeys = Set(keys.map { $0.key })
                    let newEntries = newKeyNames.filter { !existingKeys.contains($0) }.map {
                        RedisKeyEntry(key: $0, type: "", ttl: nil, size: nil)
                    }
                    keys.append(contentsOf: newEntries)
                    iterations += 1
                } while hasMoreKeys && iterations < maxIterations && (scanAll || keys.isEmpty)
            }
        } catch {
            connectionError = error.localizedDescription
        }

        let shouldRestart = pendingResetScan
        pendingResetScan = false
        isScanningKeysRequest = false
        isLoadingKeys = false

        if isPattern {
            loadTypes()
        }

        if shouldRestart {
            await scanKeys(reset: true)
        }
    }

    private func clearSelectedKeyDetail() {
        selectedKey = nil
        keyDetail = ""
        keyDetailRows = []
        keyType = ""
        valueSize = nil
        isLoadingDetail = false
    }

    private func loadTypes() {
        guard let client = activeClient, client.isConnected else { return }
        let keyNames = keys.filter { $0.type.isEmpty }.map(\.key)
        Task {
            for batchStart in stride(from: 0, to: keyNames.count, by: keyTypePipelineBatchSize) {
                let batchEnd = min(batchStart + keyTypePipelineBatchSize, keyNames.count)
                let batchKeys = Array(keyNames[batchStart..<batchEnd])
                let commands = batchKeys.map { ["TYPE", $0] }
                guard let typeResults = try? await client.sendPipeline(commands) else {
                    continue
                }

                for (keyName, typeResult) in zip(batchKeys, typeResults) {
                    guard let typeName = typeResult.string else {
                        continue
                    }
                    if let entry = keys.first(where: { $0.key == keyName }) {
                        entry.type = typeName
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
        valueSize = nil
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
                    return ("\(index)", stringValue)
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
            default:
                let value = try await client.send("GET", entry.key)
                keyDetail = value.string ?? "(nil)"
            }

            let ttlResult = try? await client.send("TTL", entry.key)
            entry.ttl = ttlResult?.intValue
            let memResult = try? await client.send("MEMORY", "USAGE", entry.key)
            entry.size = memResult?.intValue
            valueSize = memResult?.intValue
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

    // MARK: - Key Editing

    func updateKeyTTL(_ entry: RedisKeyEntry, ttl: Int) async {
        guard let client = activeClient else { return }

        do {
            if ttl == -1 {
                let currentTTL = try? await client.send("TTL", entry.key)
                if (currentTTL?.intValue ?? -1) > 0 {
                    _ = try await client.send("PERSIST", entry.key)
                }
                entry.ttl = -1
            } else {
                let result = try await client.send("EXPIRE", entry.key, "\(ttl)")
                if result.intValue == 0 || ttl == 0 {
                    keys.removeAll { $0.key == entry.key }
                    if selectedKey?.key == entry.key {
                        clearSelectedKeyDetail()
                    }
                    return
                }
                entry.ttl = ttl
            }
        } catch {
            keyDetail = "Error: \(error.localizedDescription)"
        }
    }

    func updateStringValue(key: String, value: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("SET", key, value)
    }

    func addHashField(key: String, field: String, value: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("HSET", key, field, value)
    }

    func updateHashField(key: String, field: String, value: String) async {
        await addHashField(key: key, field: field, value: value)
    }

    func deleteHashField(key: String, field: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("HDEL", key, field)
    }

    func addListElement(key: String, value: String, tail: Bool = false) async {
        guard let client = activeClient else { return }
        _ = try? await client.send(tail ? "RPUSH" : "LPUSH", key, value)
    }

    func updateListElement(key: String, index: Int, value: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("LSET", key, "\(index)", value)
    }

    func deleteListElement(key: String, value: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("LREM", key, "1", value)
    }

    func addSetMember(key: String, member: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("SADD", key, member)
    }

    func deleteSetMember(key: String, member: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("SREM", key, member)
    }

    func addZSetMember(key: String, member: String, score: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("ZADD", key, score, member)
    }

    func updateZSetScore(key: String, member: String, score: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("ZADD", key, score, member)
    }

    func deleteZSetMember(key: String, member: String) async {
        guard let client = activeClient else { return }
        _ = try? await client.send("ZREM", key, member)
    }

    func refreshSelectedKey() async {
        guard let selectedKey else { return }
        await selectKey(selectedKey)
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

    // MARK: - Profiler

    func startProfiler() {
        guard !isProfilerRunning && !isProfilerStarting else { return }
        guard let config = selectedConnection else {
            profilerError = "Connect to a Redis server before starting the profiler."
            return
        }

        profilerGeneration += 1
        let generation = profilerGeneration
        cancelProfilerResources()
        profilerError = nil
        isProfilerStarting = true

        profilerTask = Task { @MainActor in
            await runProfiler(config: config, generation: generation)
        }
    }

    func stopProfiler(clearEntries: Bool = false) {
        profilerGeneration += 1
        cancelProfilerResources()
        isProfilerRunning = false
        isProfilerStarting = false

        if clearEntries {
            clearProfiler()
        }
    }

    func clearProfiler() {
        profilerEntries = []
        profilerCapturedCount = 0
        profilerError = nil
    }

    private func cancelProfilerResources() {
        profilerTask?.cancel()
        profilerTask = nil

        profilerMonitorTasks?.cancelAll()
        profilerMonitorTasks = nil

        for client in profilerMonitorClients {
            client.disconnect()
        }
        profilerMonitorClients = []

        profilerSSHTunnel?.stop()
        profilerSSHTunnel = nil

        let clusterTunnelManager = profilerClusterTunnelManager
        profilerClusterTunnelManager = nil
        Task {
            await clusterTunnelManager?.disconnect()
        }
    }

    private func runProfiler(config: RedisConnectionConfig, generation: Int) async {
        var monitorClients: [RedisMonitorClient] = []
        var monitorTasks: RedisProfilerTaskBag?
        var tunnel: SSHTunnel?
        var clusterTunnelManager: SSHClusterTunnelManager?

        defer {
            let shouldClearStoredResources = profilerGeneration == generation
            let storedMonitorClients = shouldClearStoredResources ? profilerMonitorClients : []
            let storedMonitorTasks = shouldClearStoredResources ? profilerMonitorTasks : nil
            let storedTunnel = shouldClearStoredResources ? profilerSSHTunnel : nil
            let storedClusterTunnelManager = shouldClearStoredResources ? profilerClusterTunnelManager : nil

            monitorTasks?.cancelAll()
            storedMonitorTasks?.cancelAll()
            for client in monitorClients {
                client.disconnect()
            }
            for client in storedMonitorClients {
                client.disconnect()
            }
            tunnel?.stop()
            storedTunnel?.stop()
            let clusterTunnelManager = clusterTunnelManager
            let clusterTunnelManagerFromStoredState = storedClusterTunnelManager
            Task {
                await clusterTunnelManager?.disconnect()
                await clusterTunnelManagerFromStoredState?.disconnect()
            }

            if shouldClearStoredResources {
                profilerMonitorClients = []
                profilerMonitorTasks = nil
                profilerSSHTunnel = nil
                profilerClusterTunnelManager = nil
                profilerTask = nil
                isProfilerRunning = false
                isProfilerStarting = false
            }
        }

        do {
            let profilerStream: RedisProfilerStream

            switch config.mode {
            case .standalone:
                profilerStream = try await startStandaloneProfilerStream(config: config)
            case .cluster:
                profilerStream = try await startClusterProfilerStream(config: config)
            }

            monitorClients = profilerStream.monitorClients
            monitorTasks = profilerStream.monitorTasks
            tunnel = profilerStream.tunnel
            clusterTunnelManager = profilerStream.tunnelManager

            try Task.checkCancellation()

            isProfilerStarting = false
            isProfilerRunning = true
            AppLogger.info("profiler started redis=\(config.address)", category: "Profiler")

            for try await capture in profilerStream.stream {
                try Task.checkCancellation()
                appendProfilerCapture(capture)
            }
        } catch is CancellationError {
            AppLogger.info("profiler stopped redis=\(config.address)", category: "Profiler")
        } catch {
            if profilerGeneration == generation {
                profilerError = error.localizedDescription
            }
            AppLogger.error("profiler failed redis=\(config.address) error=\(error)", category: "Profiler")
        }
    }

    private func startStandaloneProfilerStream(
        config: RedisConnectionConfig
    ) async throws -> RedisProfilerStream {
        var connectHost = config.host
        var connectPort = config.port
        var tunnel: SSHTunnel?

        if config.ssh.enabled {
            let createdTunnel = try await startProfilerSSHTunnel(config: config, remoteHost: config.host, remotePort: config.port)
            tunnel = createdTunnel
            profilerSSHTunnel = createdTunnel
            connectHost = "127.0.0.1"
            connectPort = createdTunnel.localPort
        }

        try Task.checkCancellation()

        let monitorClient = makeProfilerMonitorClient(config: config, host: connectHost, port: connectPort)
        profilerMonitorClients = [monitorClient]

        let rawStream = try await withTimeout(10, context: "Redis profiler connection") {
            try await monitorClient.startMonitoring()
        }

        let (stream, continuation) = AsyncThrowingStream<RedisProfilerCapture, Error>.makeStream(
            of: RedisProfilerCapture.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(profilerMaxEntries)
        )
        let taskBag = RedisProfilerTaskBag()
        profilerMonitorTasks = taskBag
        taskBag.add(
            monitorStreamTask(
                rawStream: rawStream,
                node: nil,
                continuation: continuation
            )
        )

        return RedisProfilerStream(
            stream: stream,
            monitorClients: [monitorClient],
            monitorTasks: taskBag,
            tunnel: tunnel,
            tunnelManager: nil
        )
    }

    private func startClusterProfilerStream(
        config: RedisConnectionConfig
    ) async throws -> RedisProfilerStream {
        guard let clusterClient = activeClient as? RedisClusterClient else {
            throw RedisError.commandError("Profiler requires an active Redis Cluster connection")
        }

        let nodes = try await clusterClient.clusterNodes()
        let endpoints = RedisEndpoint.unique(nodes.map(\.endpoint))
        guard !endpoints.isEmpty else {
            throw RedisError.commandError("Redis Cluster topology has no nodes")
        }

        let tunnelManager = config.ssh.enabled ? SSHClusterTunnelManager(ssh: config.ssh) : nil
        profilerClusterTunnelManager = tunnelManager

        let (stream, continuation) = AsyncThrowingStream<RedisProfilerCapture, Error>.makeStream(
            of: RedisProfilerCapture.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(profilerMaxEntries)
        )
        let taskBag = RedisProfilerTaskBag()
        profilerMonitorTasks = taskBag

        var monitorClients: [RedisMonitorClient] = []

        for endpoint in endpoints {
            try Task.checkCancellation()

            let clientEndpoint: RedisEndpoint
            if let tunnelManager {
                clientEndpoint = try await tunnelManager.clientEndpoint(for: endpoint)
            } else {
                clientEndpoint = endpoint
            }

            let monitorClient = makeProfilerMonitorClient(config: config, host: clientEndpoint.host, port: clientEndpoint.port)
            monitorClients.append(monitorClient)
            profilerMonitorClients = monitorClients

            let rawStream = try await withTimeout(10, context: "Redis profiler connection to \(endpoint.address)") {
                try await monitorClient.startMonitoring()
            }

            taskBag.add(
                monitorStreamTask(
                    rawStream: rawStream,
                    node: endpoint,
                    continuation: continuation
                )
            )
        }

        return RedisProfilerStream(
            stream: stream,
            monitorClients: monitorClients,
            monitorTasks: taskBag,
            tunnel: nil,
            tunnelManager: tunnelManager
        )
    }

    private func makeProfilerMonitorClient(
        config: RedisConnectionConfig,
        host: String,
        port: UInt16
    ) -> RedisMonitorClient {
        RedisMonitorClient(
            host: host,
            port: port,
            username: config.username.isEmpty ? nil : config.username,
            password: config.password.isEmpty ? nil : config.password,
            tlsEnabled: config.tls.enabled,
            verifyServerCertificate: config.tls.verifyServerCertificate,
            caCertificatePath: config.tls.caCertificatePath,
            clientCertificatePath: config.tls.clientCertificatePath,
            clientKeyPath: config.tls.clientKeyPath
        )
    }

    private func startProfilerSSHTunnel(
        config: RedisConnectionConfig,
        remoteHost: String,
        remotePort: UInt16
    ) async throws -> SSHTunnel {
        let sshHost = config.ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let sshUser = config.ssh.user.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSSHUser = sshUser.isEmpty ? NSUserName() : sshUser
        guard !sshHost.isEmpty else {
            throw SSHTunnelError.connectionFailed("SSH host is required")
        }

        let tunnel = SSHTunnel()
        do {
            try await withTimeout(12, context: "SSH tunnel setup") {
                try await tunnel.start(
                    sshHost: sshHost,
                    sshPort: config.ssh.port,
                    sshUser: effectiveSSHUser,
                    sshPassword: config.ssh.password.isEmpty ? nil : config.ssh.password,
                    privateKeyPath: config.ssh.privateKeyPath.isEmpty ? nil : config.ssh.privateKeyPath,
                    remoteHost: remoteHost,
                    remotePort: remotePort
                )
            }
            return tunnel
        } catch {
            tunnel.stop()
            throw error
        }
    }

    private nonisolated func monitorStreamTask(
        rawStream: AsyncThrowingStream<String, Error>,
        node: RedisEndpoint?,
        continuation: AsyncThrowingStream<RedisProfilerCapture, Error>.Continuation
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await line in rawStream {
                    try Task.checkCancellation()
                    continuation.yield(RedisProfilerCapture(node: node, line: line))
                }

                if !Task.isCancelled {
                    continuation.finish(throwing: RedisError.notConnected)
                }
            } catch is CancellationError {
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func appendProfilerCapture(_ capture: RedisProfilerCapture) {
        profilerCapturedCount += 1
        profilerEntries.append(RedisProfilerEntry(rawLine: capture.line, node: capture.node))

        if profilerEntries.count > profilerMaxEntries {
            profilerEntries.removeFirst(profilerEntries.count - profilerMaxEntries)
        }
    }

    // MARK: - Server Info

    func loadServerInfo() async {
        guard let client = activeClient else { return }
        do {
            let result: RESPValue
            var capabilityEndpoint: RedisEndpoint?

            if let clusterClient = client as? RedisClusterClient {
                let nodes = try await clusterClient.clusterNodes()
                clusterNodes = nodes

                let selectedEndpoint =
                    selectedServerInfoNode.flatMap { endpoint in
                        nodes.contains { $0.endpoint == endpoint } ? endpoint : nil
                    }
                    ?? nodes.first(where: { $0.role == .primary })?.endpoint
                    ?? nodes.first?.endpoint
                selectedServerInfoNode = selectedEndpoint

                let clusterInfoResult = try await clusterClient.send(["CLUSTER", "INFO"])
                if case .error(let message) = clusterInfoResult {
                    throw RedisError.commandError(message)
                }
                if let clusterInfoString = clusterInfoResult.string {
                    clusterInfo = parseFlatInfo(clusterInfoString)
                }

                guard let selectedEndpoint else {
                    serverInfo = [:]
                    serverCapabilities = []
                    return
                }
                capabilityEndpoint = selectedEndpoint
                result = try await clusterClient.send(["INFO"], to: selectedEndpoint)
            } else {
                clusterInfo = [:]
                clusterNodes = []
                selectedServerInfoNode = nil
                result = try await client.send("INFO")
            }

            if case .error(let message) = result {
                throw RedisError.commandError(message)
            }
            guard let infoStr = result.string else { return }
            serverInfo = parseServerInfo(infoStr)
            let infoCapabilities = parseInfoModuleCapabilities(infoStr)
            serverCapabilities =
                await loadModuleCapabilities(using: client, endpoint: capabilityEndpoint)
                ?? infoCapabilities
        } catch {}
    }

    func selectServerInfoNode(_ endpoint: RedisEndpoint) async {
        selectedServerInfoNode = endpoint
        await loadServerInfo()
    }

    private func parseServerInfo(_ infoStr: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var currentSection = ""
        for line in infoStr.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                currentSection = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                sections[currentSection] = [:]
            } else if let separatorIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<separatorIndex])
                let valueStart = trimmed.index(after: separatorIndex)
                sections[currentSection]?[key] = String(trimmed[valueStart...])
            }
        }
        return sections
    }

    private func parseFlatInfo(_ infoStr: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in infoStr.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separatorIndex = trimmed.firstIndex(of: ":") else {
                continue
            }
            let key = String(trimmed[..<separatorIndex])
            let valueStart = trimmed.index(after: separatorIndex)
            values[key] = String(trimmed[valueStart...])
        }
        return values
    }

    private func loadModuleCapabilities(
        using client: any RedisSession,
        endpoint: RedisEndpoint?
    ) async -> [RedisServerCapability]? {
        do {
            let result: RESPValue
            if let clusterClient = client as? RedisClusterClient, let endpoint {
                result = try await clusterClient.send(["MODULE", "LIST"], to: endpoint)
            } else {
                result = try await client.send("MODULE", "LIST")
            }

            if case .error = result {
                return nil
            }
            return parseModuleListCapabilities(result)
        } catch {
            return nil
        }
    }

    private func parseModuleListCapabilities(_ value: RESPValue) -> [RedisServerCapability] {
        value.arrayValues.enumerated().compactMap { index, moduleValue in
            guard let values = moduleValue?.arrayValues, !values.isEmpty else { return nil }

            var fields: [(String, String)] = []
            var fieldIndex = 0
            while fieldIndex + 1 < values.count {
                guard let key = values[fieldIndex]?.string?.lowercased() else {
                    fieldIndex += 2
                    continue
                }
                fields.append((key, moduleValueDisplayString(values[fieldIndex + 1])))
                fieldIndex += 2
            }

            return moduleCapability(from: fields, fallbackName: "Module \(index + 1)")
        }
    }

    private func parseInfoModuleCapabilities(_ infoStr: String) -> [RedisServerCapability] {
        var capabilities: [RedisServerCapability] = []
        var isModulesSection = false

        for line in infoStr.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                isModulesSection = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) == "Modules"
                continue
            }

            guard isModulesSection, trimmed.hasPrefix("module:") else { continue }
            let payload = String(trimmed.dropFirst("module:".count))
            let fields = splitModuleInfoFields(payload).compactMap { field -> (String, String)? in
                guard let separatorIndex = field.firstIndex(of: "=") else { return nil }
                let key = String(field[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let valueStart = field.index(after: separatorIndex)
                let value = String(field[valueStart...]).trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : (key.lowercased(), value)
            }
            guard !fields.isEmpty else { continue }
            capabilities.append(moduleCapability(from: fields, fallbackName: "Module \(capabilities.count + 1)"))
        }

        return capabilities
    }

    private func moduleCapability(
        from fields: [(String, String)],
        fallbackName: String
    ) -> RedisServerCapability {
        let name = fields.first { $0.0 == "name" }?.1 ?? fallbackName
        let rawVersion = fields.first { $0.0 == "ver" }?.1
        let details = fields.compactMap { key, value -> RedisServerCapabilityDetail? in
            guard key != "name", key != "ver" else { return nil }
            return RedisServerCapabilityDetail(name: key, value: value)
        }

        return RedisServerCapability(
            name: name,
            version: rawVersion.map(moduleVersionDisplayString),
            details: details
        )
    }

    private func splitModuleInfoFields(_ payload: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var bracketDepth = 0

        for character in payload {
            switch character {
            case "[":
                bracketDepth += 1
                current.append(character)
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
            case "," where bracketDepth == 0:
                fields.append(current)
                current = ""
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            fields.append(current)
        }
        return fields
    }

    private func moduleValueDisplayString(_ value: RESPValue?) -> String {
        guard let value else { return "-" }
        switch value {
        case .array(let values):
            return "[" + values.map(moduleValueDisplayString).joined(separator: ", ") + "]"
        case .bulkString(let string):
            return string ?? "(nil)"
        case .simpleString(let string):
            return string
        case .integer(let integer):
            return "\(integer)"
        default:
            return value.displayString
        }
    }

    private func moduleVersionDisplayString(_ rawValue: String) -> String {
        guard let versionNumber = Int(rawValue), versionNumber >= 10_000 else {
            return rawValue
        }

        let major = versionNumber / 10_000
        let minor = (versionNumber / 100) % 100
        let patch = versionNumber % 100
        return "\(major).\(minor).\(patch) (\(rawValue))"
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
            "WATCH", "ZADD", "ZCARD",
            "ZCOUNT", "ZINCRBY", "ZINTERSTORE", "ZLEXCOUNT", "ZPOPMAX", "ZPOPMIN",
            "ZRANGE", "ZRANGEBYLEX", "ZRANGEBYSCORE", "ZRANK", "ZREM", "ZREMRANGEBYLEX",
            "ZREMRANGEBYRANK", "ZREMRANGEBYSCORE", "ZREVRANGE", "ZREVRANGEBYLEX",
            "ZREVRANGEBYSCORE", "ZREVRANK", "ZSCAN", "ZSCORE", "ZUNIONSTORE",
        ]
        let upper = prefix.uppercased()
        return commands.filter { $0.hasPrefix(upper) }
    }
}
