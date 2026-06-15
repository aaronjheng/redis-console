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
    var length: Int?

    init(key: String, type: String, ttl: Int?, size: Int?, length: Int? = nil) {
        self.key = key
        self.type = type
        self.ttl = ttl
        self.size = size
        self.length = length
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

enum KeyDetailZSetOrder: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: return "Ascending"
        case .descending: return "Descending"
        }
    }
}

enum StringValueFormat: String, CaseIterable, Identifiable, Codable {
    case raw
    case unicode
    case json
    case ascii
    case hex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .raw: return "Raw"
        case .unicode: return "Unicode"
        case .json: return "JSON"
        case .ascii: return "ASCII"
        case .hex: return "Hex"
        }
    }
}

struct BulkDeletePreview: Identifiable {
    let id = UUID()
    let pattern: String
    let typeFilter: String
    let keys: [String]
    let scannedCount: Int
    let didReachLimit: Bool
    let duration: TimeInterval

    var typeText: String {
        typeFilter.isEmpty ? "all types" : typeFilter
    }
}

struct BulkDeleteResult {
    let processed: Int
    let deleted: Int
    let usedFallback: Bool
    let duration: TimeInterval
}

// MARK: - Shell History

struct ShellHistoryEntry: Identifiable, Codable {
    let id: UUID
    let command: String
    let result: String
    let timestamp: Date
    let isError: Bool

    init(
        id: UUID = UUID(),
        command: String,
        result: String,
        timestamp: Date,
        isError: Bool
    ) {
        self.id = id
        self.command = command
        self.result = result
        self.timestamp = timestamp
        self.isError = isError
    }
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
    @Published var keyDetailLength: Int?
    @Published var keyDetailError: String?
    @Published var keyDetailOffset = 0
    @Published var keyDetailCursor: String = "0"
    @Published var keyDetailHasMoreRows = false
    @Published var keyDetailSearchText = ""
    @Published var keyDetailZSetOrder: KeyDetailZSetOrder = .ascending
    @Published var isLoadingKeys = false
    @Published var isLoadingDetail = false
    @Published var scanCursor: String = "0"
    @Published var hasMoreKeys = true
    @Published var keyFilter: String = "*"
    @Published var keyTypeFilter: String = "" {
        didSet { saveBrowserPreferences() }
    }
    @Published var keyScanCount = 500
    @Published var keyScanReturnedCount = 0
    @Published var keyScanIterationCount = 0
    @Published var keyScanLimitReached = false
    @Published var isNamespaceGroupingEnabled = false {
        didSet { saveBrowserPreferences() }
    }
    @Published var namespaceSeparator = ":" {
        didSet { saveBrowserPreferences() }
    }
    @Published var stringValueFormat: StringValueFormat = .json {
        didSet { saveBrowserPreferences() }
    }
    @Published var keyDetailLastRefreshedAt: Date?

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
    private let keyMetadataPipelineBatchSize = 50
    private let keyDetailPageSize = 100
    private let keyPatternScanIterationLimit = 1_000
    private let bulkDeleteScanLimit = 20_000
    private let bulkDeleteBatchSize = 100
    private let shellHistoryLimit = 200
    private static let browserPreferencesKey = "com.redisconsole.browserPreferences"
    private static let shellHistoryKeyPrefix = "com.redisconsole.shellHistory."

    private struct BrowserPreferences: Codable {
        var keyTypeFilter: String
        var isNamespaceGroupingEnabled: Bool
        var namespaceSeparator: String
        var stringValueFormat: StringValueFormat
    }

    init() {
        loadBrowserPreferences()
    }

    var windowTitle: String {
        if let conn = selectedConnection {
            return conn.name
        }
        return "Redis Console"
    }

    private func loadBrowserPreferences() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.browserPreferencesKey),
            let preferences = try? JSONDecoder().decode(BrowserPreferences.self, from: data)
        else {
            return
        }

        keyTypeFilter = preferences.keyTypeFilter
        isNamespaceGroupingEnabled = preferences.isNamespaceGroupingEnabled
        namespaceSeparator = normalizedNamespaceSeparator(preferences.namespaceSeparator)
        stringValueFormat = preferences.stringValueFormat
    }

    private func saveBrowserPreferences() {
        let preferences = BrowserPreferences(
            keyTypeFilter: keyTypeFilter,
            isNamespaceGroupingEnabled: isNamespaceGroupingEnabled,
            namespaceSeparator: normalizedNamespaceSeparator(namespaceSeparator),
            stringValueFormat: stringValueFormat
        )
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.browserPreferencesKey)
    }

    private func normalizedNamespaceSeparator(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return ":" }
        return String(first)
    }

    func updateNamespaceSeparator(_ value: String) {
        namespaceSeparator = normalizedNamespaceSeparator(value)
    }

    private func shellHistoryKey(for connection: RedisConnectionConfig) -> String {
        Self.shellHistoryKeyPrefix + connection.id.uuidString
    }

    private func loadShellHistory(for connection: RedisConnectionConfig) {
        guard
            let data = UserDefaults.standard.data(forKey: shellHistoryKey(for: connection)),
            let decoded = try? JSONDecoder().decode([ShellHistoryEntry].self, from: data)
        else {
            shellHistory = []
            return
        }
        shellHistory = Array(decoded.suffix(shellHistoryLimit))
    }

    private func saveShellHistory(for connection: RedisConnectionConfig) {
        let limitedHistory = Array(shellHistory.suffix(shellHistoryLimit))
        shellHistory = limitedHistory
        guard let data = try? JSONEncoder().encode(limitedHistory) else { return }
        UserDefaults.standard.set(data, forKey: shellHistoryKey(for: connection))
    }

    private func appendShellHistory(_ entry: ShellHistoryEntry) {
        shellHistory.append(entry)
        if shellHistory.count > shellHistoryLimit {
            shellHistory.removeFirst(shellHistory.count - shellHistoryLimit)
        }
        guard let selectedConnection else { return }
        saveShellHistory(for: selectedConnection)
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
                loadShellHistory(for: resolvedConfig)
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
            keyScanReturnedCount = 0
            keyScanIterationCount = 0
            keyScanLimitReached = false
        }
        isLoadingKeys = true

        let isPattern = keyFilter.contains("*") || keyFilter.contains("?") || keyFilter.contains("[")

        do {
            if !isPattern {
                let typeResult = try? await client.send("TYPE", keyFilter)
                if let typeName = typeResult?.string, typeName != "none" {
                    let entry = RedisKeyEntry(key: keyFilter, type: typeName, ttl: nil, size: nil)
                    keys = [entry]
                    keyScanReturnedCount = 1
                    loadKeyMetadata(for: [entry])
                } else {
                    keys = []
                    keyScanReturnedCount = 0
                    clearSelectedKeyDetail()
                }
                hasMoreKeys = false
            } else {
                let scanAll = keyFilter != "*"
                var iterations = 0
                let maxIterations = scanAll ? keyPatternScanIterationLimit : 1
                repeat {
                    let result = try await client.scan(cursor: scanCursor, match: keyFilter, count: keyScanCount)
                    scanCursor = result.nextCursor
                    hasMoreKeys = scanCursor != "0"
                    let newKeyNames = result.keys
                    keyScanReturnedCount += newKeyNames.count
                    let existingKeys = Set(keys.map { $0.key })
                    let newEntries = newKeyNames.filter { !existingKeys.contains($0) }.map {
                        RedisKeyEntry(key: $0, type: "", ttl: nil, size: nil)
                    }
                    keys.append(contentsOf: newEntries)
                    iterations += 1
                    keyScanIterationCount += 1
                } while hasMoreKeys && iterations < maxIterations && (scanAll || keys.isEmpty)
                keyScanLimitReached = hasMoreKeys && iterations >= maxIterations
            }
        } catch {
            connectionError = error.localizedDescription
        }

        let shouldRestart = pendingResetScan
        pendingResetScan = false
        isScanningKeysRequest = false
        isLoadingKeys = false

        if isPattern {
            let entriesNeedingMetadata = keys.filter { entry in
                entry.type.isEmpty || entry.ttl == nil || entry.size == nil || entry.length == nil
            }
            loadKeyMetadata(for: entriesNeedingMetadata)
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
        keyDetailLength = nil
        keyDetailError = nil
        keyDetailOffset = 0
        keyDetailCursor = "0"
        keyDetailHasMoreRows = false
        keyDetailSearchText = ""
        keyDetailLastRefreshedAt = nil
        isLoadingDetail = false
    }

    private func loadKeyMetadata(for entries: [RedisKeyEntry]) {
        guard let client = activeClient, client.isConnected else { return }
        guard !entries.isEmpty else { return }

        Task { @MainActor in
            for batchStart in stride(from: 0, to: entries.count, by: keyMetadataPipelineBatchSize) {
                let batchEnd = min(batchStart + keyMetadataPipelineBatchSize, entries.count)
                let batchEntries = Array(entries[batchStart..<batchEnd])
                let commands = batchEntries.flatMap { entry in
                    [
                        ["TYPE", entry.key],
                        ["TTL", entry.key],
                        ["MEMORY", "USAGE", entry.key, "SAMPLES", "0"],
                    ]
                }

                do {
                    let metadataResults = try await client.sendPipeline(commands)
                    applyMetadataResults(metadataResults, to: batchEntries)
                    await loadKeyLengths(for: batchEntries, using: client)
                } catch {
                    connectionError = error.localizedDescription
                }
            }
        }
    }

    private func applyMetadataResults(_ results: [RESPValue], to entries: [RedisKeyEntry]) {
        for (entryIndex, entry) in entries.enumerated() {
            let resultIndex = entryIndex * 3
            guard resultIndex + 2 < results.count else { continue }

            if let typeName = results[resultIndex].string {
                if typeName == "none" {
                    keys.removeAll { $0.key == entry.key }
                    if selectedKey?.key == entry.key {
                        clearSelectedKeyDetail()
                    }
                    continue
                }
                entry.type = typeName
            }
            entry.ttl = results[resultIndex + 1].intValue
            entry.size = results[resultIndex + 2].intValue

            if selectedKey?.key == entry.key {
                keyType = entry.type
                valueSize = entry.size
            }
        }
    }

    private func loadKeyLengths(for entries: [RedisKeyEntry], using client: any RedisSession) async {
        var commands: [[String]] = []
        var targets: [RedisKeyEntry] = []
        for entry in entries {
            guard let command = keyLengthCommand(type: entry.type, key: entry.key) else { continue }
            commands.append(command)
            targets.append(entry)
        }
        guard !commands.isEmpty else { return }

        do {
            let lengthResults = try await client.sendPipeline(commands)
            for (entry, result) in zip(targets, lengthResults) {
                guard let length = result.intValue else { continue }
                entry.length = length
                if selectedKey?.key == entry.key {
                    keyDetailLength = length
                }
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private func keyLengthCommand(type: String, key: String) -> [String]? {
        switch type {
        case "string": return ["STRLEN", key]
        case "list": return ["LLEN", key]
        case "hash": return ["HLEN", key]
        case "set": return ["SCARD", key]
        case "zset": return ["ZCARD", key]
        default: return nil
        }
    }

    func selectKey(_ entry: RedisKeyEntry) async {
        selectedKey = entry
        keyDetailSearchText = ""
        keyDetailZSetOrder = .ascending
        resetKeyDetailPaging(clearRows: true)
        await loadSelectedKeyDetail(append: false)
    }

    func loadMoreSelectedKeyDetailRows() async {
        guard keyDetailHasMoreRows, !isLoadingDetail else { return }
        await loadSelectedKeyDetail(append: true)
    }

    func searchSelectedKeyDetail(_ searchText: String) async {
        keyDetailSearchText = searchText
        resetKeyDetailPaging(clearRows: true)
        await loadSelectedKeyDetail(append: false)
    }

    func updateSelectedZSetOrder(_ order: KeyDetailZSetOrder) async {
        guard keyDetailZSetOrder != order else { return }
        keyDetailZSetOrder = order
        resetKeyDetailPaging(clearRows: true)
        await loadSelectedKeyDetail(append: false)
    }

    private func loadSelectedKeyDetail(append: Bool) async {
        guard let entry = selectedKey else { return }
        guard let client = activeClient else { return }

        isLoadingDetail = true
        keyDetailError = nil
        if !append {
            keyDetail = ""
            keyDetailRows = []
            valueSize = nil
            keyDetailLength = nil
        }

        do {
            let typeResult = try await client.send("TYPE", entry.key)
            try throwIfRedisError(typeResult)
            keyType = typeResult.string ?? "string"
            guard keyType != "none" else {
                keys.removeAll { $0.key == entry.key }
                clearSelectedKeyDetail()
                return
            }
            entry.type = keyType
            keyDetailLength = await loadLength(for: entry.key, type: keyType, using: client)
            entry.length = keyDetailLength

            switch keyType {
            case "string":
                let value = try await client.send("GET", entry.key)
                try throwIfRedisError(value)
                keyDetail = value.string ?? "(nil)"
                keyDetailHasMoreRows = false
            case "list":
                try await loadListDetail(key: entry.key, append: append, using: client)
            case "hash":
                try await loadHashDetail(key: entry.key, append: append, using: client)
            case "set":
                try await loadSetDetail(key: entry.key, append: append, using: client)
            case "zset":
                try await loadZSetDetail(key: entry.key, append: append, using: client)
            default:
                let value = try await client.send("GET", entry.key)
                try throwIfRedisError(value)
                keyDetail = value.string ?? "(nil)"
                keyDetailHasMoreRows = false
            }

            await refreshMetadata(for: entry, using: client)
            keyDetailLastRefreshedAt = Date()
        } catch {
            reportKeyOperationError(error)
        }
        isLoadingDetail = false
    }

    private func resetKeyDetailPaging(clearRows: Bool) {
        keyDetailOffset = 0
        keyDetailCursor = "0"
        keyDetailHasMoreRows = false
        keyDetailError = nil
        if clearRows {
            keyDetailRows = []
            keyDetail = ""
        }
    }

    private func refreshMetadata(for entry: RedisKeyEntry, using client: any RedisSession) async {
        do {
            let results = try await client.sendPipeline([
                ["TTL", entry.key],
                ["MEMORY", "USAGE", entry.key, "SAMPLES", "0"],
            ])
            entry.ttl = results.first?.intValue
            entry.size = results.dropFirst().first?.intValue
            valueSize = entry.size
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private func loadLength(for key: String, type: String, using client: any RedisSession) async -> Int? {
        guard let command = keyLengthCommand(type: type, key: key) else { return nil }
        guard let result = try? await client.send(command) else { return nil }
        return result.intValue
    }

    private func loadListDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        let start = append ? keyDetailOffset : 0
        let stop = start + keyDetailPageSize - 1
        let value = try await client.send("LRANGE", key, "\(start)", "\(stop)")
        try throwIfRedisError(value)
        let rows = value.arrayValues.enumerated().compactMap { index, value -> (String, String)? in
            guard let value else { return nil }
            return ("\(start + index)", value.string ?? value.displayString)
        }
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailOffset = start + rows.count
        if let keyDetailLength {
            keyDetailHasMoreRows = keyDetailOffset < keyDetailLength
        } else {
            keyDetailHasMoreRows = rows.count == keyDetailPageSize
        }
    }

    private func loadHashDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        var args = ["HSCAN", key, append ? keyDetailCursor : "0"]
        if let pattern = keyDetailMatchPattern {
            args.append(contentsOf: ["MATCH", pattern])
        }
        args.append(contentsOf: ["COUNT", "\(keyDetailPageSize)"])

        let response = try await client.send(args)
        let result = try parseScanValues(response, context: "HSCAN")
        let rows = keyValueRows(from: result.values)
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailCursor = result.nextCursor
        keyDetailHasMoreRows = result.nextCursor != "0"
    }

    private func loadSetDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        var args = ["SSCAN", key, append ? keyDetailCursor : "0"]
        if let pattern = keyDetailMatchPattern {
            args.append(contentsOf: ["MATCH", pattern])
        }
        args.append(contentsOf: ["COUNT", "\(keyDetailPageSize)"])

        let response = try await client.send(args)
        let result = try parseScanValues(response, context: "SSCAN")
        let baseIndex = append ? keyDetailRows.count : 0
        let rows = result.values.enumerated().compactMap { index, value -> (String, String)? in
            guard let value else { return nil }
            return ("[\(baseIndex + index)]", value.string ?? value.displayString)
        }
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailCursor = result.nextCursor
        keyDetailHasMoreRows = result.nextCursor != "0"
    }

    private func loadZSetDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        if keyDetailMatchPattern != nil {
            try await loadScannedZSetDetail(key: key, append: append, using: client)
            return
        }

        let start = append ? keyDetailOffset : 0
        let stop = start + keyDetailPageSize - 1
        let command = keyDetailZSetOrder == .descending ? "ZREVRANGE" : "ZRANGE"
        let value = try await client.send(command, key, "\(start)", "\(stop)", "WITHSCORES")
        try throwIfRedisError(value)
        let rows = scoredRows(from: value.arrayValues)
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailOffset = start + rows.count
        if let keyDetailLength {
            keyDetailHasMoreRows = keyDetailOffset < keyDetailLength
        } else {
            keyDetailHasMoreRows = rows.count == keyDetailPageSize
        }
    }

    private func loadScannedZSetDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        var args = ["ZSCAN", key, append ? keyDetailCursor : "0"]
        if let pattern = keyDetailMatchPattern {
            args.append(contentsOf: ["MATCH", pattern])
        }
        args.append(contentsOf: ["COUNT", "\(keyDetailPageSize)"])

        let response = try await client.send(args)
        let result = try parseScanValues(response, context: "ZSCAN")
        let rows = scoredRows(from: result.values)
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailCursor = result.nextCursor
        keyDetailHasMoreRows = result.nextCursor != "0"
    }

    private var keyDetailMatchPattern: String? {
        let trimmed = keyDetailSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("*") || trimmed.contains("?") || trimmed.contains("[") {
            return trimmed
        }
        return "*\(trimmed)*"
    }

    private func parseScanValues(
        _ response: RESPValue,
        context: String
    ) throws -> (nextCursor: String, values: [RESPValue?]) {
        try throwIfRedisError(response)
        let values = response.arrayValues
        guard values.count >= 2, let cursor = values[0]?.string else {
            throw RedisError.parseError("Unexpected \(context) response")
        }
        return (nextCursor: cursor, values: values[1]?.arrayValues ?? [])
    }

    private func keyValueRows(from values: [RESPValue?]) -> [(String, String)] {
        var rows: [(String, String)] = []
        var itemIndex = 0
        while itemIndex + 1 < values.count {
            guard let key = values[itemIndex] else {
                itemIndex += 2
                continue
            }
            let value = values[itemIndex + 1]
            rows.append((key.string ?? key.displayString, value?.string ?? value?.displayString ?? ""))
            itemIndex += 2
        }
        return rows
    }

    private func scoredRows(from values: [RESPValue?]) -> [(String, String)] {
        var rows: [(String, String)] = []
        var itemIndex = 0
        while itemIndex + 1 < values.count {
            let member = values[itemIndex]?.string ?? values[itemIndex]?.displayString ?? ""
            let score = values[itemIndex + 1]?.string ?? values[itemIndex + 1]?.displayString ?? ""
            rows.append((score, member))
            itemIndex += 2
        }
        return rows
    }

    private func throwIfRedisError(_ value: RESPValue) throws {
        if case .error(let message) = value {
            throw RedisError.commandError(message)
        }
    }

    private func reportKeyOperationError(_ error: Error) {
        let message = error.localizedDescription
        connectionError = message
        keyDetailError = message
        keyDetail = "Error: \(message)"
    }

    func previewBulkDelete(pattern: String, typeFilter: String) async throws -> BulkDeletePreview {
        guard let client = activeClient, client.isConnected else {
            throw RedisError.notConnected
        }

        let startedAt = Date()
        let matchPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "*" : pattern
        let result = try await scanKeysForBulkAction(
            pattern: matchPattern,
            typeFilter: typeFilter,
            using: client
        )
        return BulkDeletePreview(
            pattern: matchPattern,
            typeFilter: typeFilter,
            keys: result.keys,
            scannedCount: result.scannedCount,
            didReachLimit: result.didReachLimit,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    func executeBulkDelete(_ preview: BulkDeletePreview) async throws -> BulkDeleteResult {
        guard let client = activeClient, client.isConnected else {
            throw RedisError.notConnected
        }

        let startedAt = Date()
        let unlinkResult: BulkDeleteCommandResult
        do {
            unlinkResult = try await deleteKeys(preview.keys, command: "UNLINK", using: client)
        } catch let error as RedisError where error.isUnknownCommand {
            let fallbackResult = try await deleteKeys(preview.keys, command: "DEL", using: client)
            await scanKeys(reset: true)
            return BulkDeleteResult(
                processed: fallbackResult.processed,
                deleted: fallbackResult.deleted,
                usedFallback: true,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        await scanKeys(reset: true)
        return BulkDeleteResult(
            processed: unlinkResult.processed,
            deleted: unlinkResult.deleted,
            usedFallback: false,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private func scanKeysForBulkAction(
        pattern: String,
        typeFilter: String,
        using client: any RedisSession
    ) async throws -> BulkDeleteScanResult {
        var cursor = "0"
        var matchedKeys: [String] = []
        var seenKeys: Set<String> = []
        var scannedCount = 0
        var iterations = 0

        repeat {
            let result = try await client.scan(cursor: cursor, match: pattern, count: keyScanCount)
            cursor = result.nextCursor
            iterations += 1
            scannedCount += result.keys.count

            let uniqueKeys = result.keys.filter { seenKeys.insert($0).inserted }
            let filteredKeys =
                typeFilter.isEmpty
                ? uniqueKeys
                : try await keys(uniqueKeys, matchingType: typeFilter, using: client)
            let remainingLimit = max(0, bulkDeleteScanLimit - matchedKeys.count)
            matchedKeys.append(contentsOf: filteredKeys.prefix(remainingLimit))
        } while cursor != "0"
            && iterations < keyPatternScanIterationLimit
            && matchedKeys.count < bulkDeleteScanLimit

        let didReachLimit = cursor != "0" || iterations >= keyPatternScanIterationLimit
        return BulkDeleteScanResult(
            keys: matchedKeys,
            scannedCount: scannedCount,
            didReachLimit: didReachLimit
        )
    }

    private func keys(
        _ keyNames: [String],
        matchingType typeFilter: String,
        using client: any RedisSession
    ) async throws -> [String] {
        guard !keyNames.isEmpty else { return [] }
        var matchedKeys: [String] = []
        for batchStart in stride(from: 0, to: keyNames.count, by: keyMetadataPipelineBatchSize) {
            let batchEnd = min(batchStart + keyMetadataPipelineBatchSize, keyNames.count)
            let batchKeys = Array(keyNames[batchStart..<batchEnd])
            let responses = try await client.sendPipeline(batchKeys.map { ["TYPE", $0] })
            for (key, response) in zip(batchKeys, responses) {
                try throwIfRedisError(response)
                if response.string == typeFilter {
                    matchedKeys.append(key)
                }
            }
        }
        return matchedKeys
    }

    private struct BulkDeleteCommandResult {
        let processed: Int
        let deleted: Int
    }

    private struct BulkDeleteScanResult {
        let keys: [String]
        let scannedCount: Int
        let didReachLimit: Bool
    }

    private func deleteKeys(
        _ keyNames: [String],
        command: String,
        using client: any RedisSession
    ) async throws -> BulkDeleteCommandResult {
        var processed = 0
        var deleted = 0
        for batchStart in stride(from: 0, to: keyNames.count, by: bulkDeleteBatchSize) {
            let batchEnd = min(batchStart + bulkDeleteBatchSize, keyNames.count)
            let batchKeys = Array(keyNames[batchStart..<batchEnd])
            let responses = try await client.sendPipeline(batchKeys.map { [command, $0] })
            for response in responses {
                try throwIfRedisError(response)
                processed += 1
                deleted += response.intValue ?? 0
            }
        }
        return BulkDeleteCommandResult(processed: processed, deleted: deleted)
    }

    func deleteKey(_ entry: RedisKeyEntry) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("DEL", entry.key)
            try throwIfRedisError(result)
            keys.removeAll { $0.key == entry.key }
            if selectedKey?.key == entry.key {
                clearSelectedKeyDetail()
            }
        } catch {
            reportKeyOperationError(error)
        }
    }

    func renameKey(old: String, new: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("RENAMENX", old, new)
            try throwIfRedisError(result)
            guard result.intValue != 0 else {
                throw RedisError.commandError("Key \"\(new)\" already exists")
            }
            await scanKeys(reset: true)
        } catch {
            reportKeyOperationError(error)
        }
    }

    // MARK: - Key Editing

    func updateKeyTTL(_ entry: RedisKeyEntry, ttl: Int) async {
        guard let client = activeClient else { return }

        do {
            if ttl == -1 {
                let currentTTL = try? await client.send("TTL", entry.key)
                if (currentTTL?.intValue ?? -1) > 0 {
                    let result = try await client.send("PERSIST", entry.key)
                    try throwIfRedisError(result)
                }
                entry.ttl = -1
            } else {
                let result = try await client.send("EXPIRE", entry.key, "\(ttl)")
                try throwIfRedisError(result)
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
            reportKeyOperationError(error)
        }
    }

    func updateStringValue(key: String, value: String) async {
        guard let client = activeClient else { return }
        do {
            let ttlResult = try await client.send("TTL", key)
            try throwIfRedisError(ttlResult)
            let ttl = ttlResult.intValue ?? -1

            let setResult = try await client.send("SET", key, value, "XX")
            try throwIfRedisError(setResult)
            guard setResult.string != nil else {
                throw RedisError.commandError("Key \"\(key)\" no longer exists")
            }

            if ttl > 0 {
                let expireResult = try await client.send("EXPIRE", key, "\(ttl)")
                try throwIfRedisError(expireResult)
            }
        } catch {
            reportKeyOperationError(error)
        }
    }

    func addHashField(key: String, field: String, value: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("HSET", key, field, value)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func updateHashField(key: String, field: String, value: String) async {
        await addHashField(key: key, field: field, value: value)
    }

    func deleteHashField(key: String, field: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("HDEL", key, field)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func addListElement(key: String, value: String, tail: Bool = false) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send(tail ? "RPUSHX" : "LPUSHX", key, value)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func updateListElement(key: String, index: Int, value: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("LSET", key, "\(index)", value)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func deleteListElement(key: String, index: Int) async {
        guard let client = activeClient else { return }
        let marker = "__redis_console_delete_\(UUID().uuidString)__"
        do {
            let setResult = try await client.send("LSET", key, "\(index)", marker)
            try throwIfRedisError(setResult)
            let removeResult = try await client.send("LREM", key, "1", marker)
            try throwIfRedisError(removeResult)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func addSetMember(key: String, member: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("SADD", key, member)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func deleteSetMember(key: String, member: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("SREM", key, member)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func addZSetMember(key: String, member: String, score: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("ZADD", key, "NX", score, member)
            try throwIfRedisError(result)
            guard result.intValue != 0 else {
                throw RedisError.commandError("Sorted set member already exists")
            }
        } catch {
            reportKeyOperationError(error)
        }
    }

    func updateZSetScore(key: String, member: String, score: String) async {
        guard let client = activeClient else { return }
        do {
            let currentScore = try await client.send("ZSCORE", key, member)
            try throwIfRedisError(currentScore)
            guard currentScore.string != nil else {
                throw RedisError.commandError("Sorted set member no longer exists")
            }

            let result = try await client.send("ZADD", key, "XX", "CH", score, member)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func deleteZSetMember(key: String, member: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("ZREM", key, member)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func refreshSelectedKey() async {
        guard let selectedKey else { return }
        resetKeyDetailPaging(clearRows: true)
        await loadSelectedKeyDetail(append: false)
    }

    // MARK: - Shell

    func executeCommand(_ input: String) async {
        guard let client = activeClient, client.isConnected else { return }
        do {
            let parts = try parseCommand(input)
            guard !parts.isEmpty else { return }
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
            appendShellHistory(entry)
        } catch {
            let entry = ShellHistoryEntry(
                command: input,
                result: error.localizedDescription,
                timestamp: Date(),
                isError: true
            )
            appendShellHistory(entry)
        }
        shellInput = ""
    }

    private func parseCommand(_ input: String) throws -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var isEscaping = false
        var hasToken = false
        var quoteChar: Character = "\""

        for char in input {
            if isEscaping {
                current.append(unescapedShellCharacter(char))
                hasToken = true
                isEscaping = false
            } else if char == "\\" {
                isEscaping = true
                hasToken = true
            } else if char == "\"" || char == "'" {
                if inQuotes && char == quoteChar {
                    inQuotes = false
                } else if !inQuotes {
                    inQuotes = true
                    quoteChar = char
                    hasToken = true
                } else {
                    current.append(char)
                }
            } else if char.isWhitespace && !inQuotes {
                if hasToken {
                    parts.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(char)
                hasToken = true
            }
        }

        if isEscaping {
            current.append("\\")
        }
        if inQuotes {
            throw RedisError.commandError("Unclosed quote in command")
        }
        if hasToken {
            parts.append(current)
        }
        return parts
    }

    private func unescapedShellCharacter(_ character: Character) -> Character {
        switch character {
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        default: return character
        }
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
            guard let moduleValue else { return nil }
            let fields = moduleValue.keyValuePairs.compactMap { pair -> (String, String)? in
                guard let key = pair.key.string?.lowercased() else { return nil }
                return (key, moduleValueDisplayString(pair.value))
            }
            guard !fields.isEmpty else { return nil }

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
