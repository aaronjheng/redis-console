import AppKit
import Foundation

@MainActor
enum UIInventoryRegistry {
    static var allEntries: [any UIInventoryEntry] {
        [
            // MARK: - Connection Management
            ConnHubListEntry(),
            ConnHubEmptyEntry(),
            ConnHubNewEntry(),
            ConnHubEditEntry(),
            ConnHubClusterEntry(),
            ConnHubSSHEntry(),
            ConnHubTLSEntry(),
            ConnHubConnectingEntry(),
            // MARK: - Key Browser
            BrowserEmptyEntry(),
            BrowserLoadingEntry(),
            BrowserFlatEntry(),
            BrowserNamespaceEntry(),
            BrowserErrorEntry(),
            BrowserAddKeyEntry(),
            BrowserTypeFilterEntry(),
            BrowserPatternFilterEntry(),
            BrowserLoadMoreEntry(),
            BrowserScanningMoreEntry(),
            BrowserThresholdReachedEntry(),
            BrowserNoMatchEntry(),
            // MARK: - Value Editor
            DetailNoneEntry(),
            DetailLoadingEntry(),
            DetailStringEntry(),
            DetailStringRawEntry(),
            DetailStringHexEntry(),
            DetailStringBase64Entry(),
            DetailStringAsciiEntry(),
            DetailStringUnicodeEntry(),
            DetailStringGzipEntry(),
            DetailStringBase64EncodeEntry(),
            DetailHashEntry(),
            DetailHashEmptyEntry(),
            DetailHashSearchEntry(),
            DetailHashLoadMoreEntry(),
            DetailListEntry(),
            DetailListEmptyEntry(),
            DetailListLoadMoreEntry(),
            DetailSetEntry(),
            DetailSetEmptyEntry(),
            DetailSetSearchEntry(),
            DetailSetLoadMoreEntry(),
            DetailZSetEntry(),
            DetailZSetDescendingEntry(),
            DetailZSetSearchEntry(),
            DetailZSetLoadMoreEntry(),
            DetailZSetEmptyEntry(),
            DetailUnknownTypeEntry(),
            DetailRefreshedEntry(),
            DetailTTLEntry(),
            DetailErrorEntry(),
            DetailAddHashEntry(),
            DetailAddListEntry(),
            DetailAddSetEntry(),
            DetailAddZSetEntry(),
            // MARK: - Shell
            ShellEmptyEntry(),
            ShellPopulatedEntry(),
            ShellDangerEntry(),
            // MARK: - Profiler
            ProfilerStoppedEntry(),
            ProfilerRunningEntry(),
            ProfilerWaitingEntry(),
            ProfilerErrorEntry(),
            ProfilerStartingEntry(),
            ProfilerStoppedWithEntriesEntry(),
            // MARK: - Slow Log
            SlowLogEmptyEntry(),
            SlowLogPopulatedEntry(),
            SlowLogLoadingEntry(),
            SlowLogAutoRefreshEntry(),
            // MARK: - Database Analysis
            AnalysisEmptyEntry(),
            AnalysisLoadingEntry(),
            AnalysisPopulatedEntry(),
            AnalysisErrorEntry(),
            AnalysisEstimateEntry(),
            AnalysisNoExpirationEntry(),
            AnalysisEmptyTypeDistributionEntry(),
            AnalysisEmptyTopKeysEntry(),
            // MARK: - Server Info
            ServerInfoEmptyEntry(),
            ServerInfoPopulatedEntry(),
            ServerInfoClusterEntry(),
            ServerInfoClusterNodeSelectedEntry(),
            ServerInfoNoModulesEntry(),
            // MARK: - Production Confirmation
            ProdConfirmEntry(),
        ]
    }

    static var sortedByPriority: [any UIInventoryEntry] {
        allEntries.enumerated().sorted { lhs, rhs in
            if lhs.element.priority.sortOrder != rhs.element.priority.sortOrder {
                lhs.element.priority.sortOrder < rhs.element.priority.sortOrder
            } else {
                lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    // MARK: - Shared Helpers

    fileprivate static var defaultConnection: RedisConnectionConfig {
        RedisConnectionConfig(name: "Local Redis", host: "127.0.0.1", port: 6379, environment: .development)
    }

    fileprivate static func connect(
        _ state: ConnectionState,
        view: AppView = .browser,
        connection: RedisConnectionConfig? = nil
    ) {
        state.activeClient = FakeRedisSession()
        state.selectedConnection = connection ?? defaultConnection
        state.currentView = view
    }

    fileprivate static var sampleConnections: [RedisConnectionConfig] {
        [
            RedisConnectionConfig(name: "Local Redis", host: "127.0.0.1", port: 6379, environment: .development),
            RedisConnectionConfig(name: "Staging", host: "staging-redis.internal", port: 6379, environment: .development),
            RedisConnectionConfig(name: "Production Cache", host: "prod-cache-01.internal", port: 6379, environment: .production),
            RedisConnectionConfig(
                name: "Analytics Cluster",
                mode: .cluster,
                host: "10.0.0.1",
                port: 7000,
                seedNodes: [
                    RedisEndpoint(host: "10.0.0.1", port: 7000),
                    RedisEndpoint(host: "10.0.0.2", port: 7000),
                    RedisEndpoint(host: "10.0.0.3", port: 7000),
                ],
                environment: .production
            ),
        ]
    }

    fileprivate static var clusterSeedNodes: [RedisEndpoint] {
        [
            RedisEndpoint(host: "10.0.0.1", port: 7000),
            RedisEndpoint(host: "10.0.0.2", port: 7000),
            RedisEndpoint(host: "10.0.0.3", port: 7000),
        ]
    }

    fileprivate static var sampleKeys: [RedisKeyEntry] {
        [
            RedisKeyEntry(key: "user:1001", type: "hash", ttl: 3600, size: 256, length: 12),
            RedisKeyEntry(key: "session:abc", type: "string", ttl: 1800, size: 64, length: nil),
            RedisKeyEntry(key: "metrics:cpu", type: "list", ttl: nil, size: 1024, length: 50),
            RedisKeyEntry(key: "tags:recent", type: "set", ttl: nil, size: 512, length: 23),
            RedisKeyEntry(key: "leaderboard:daily", type: "zset", ttl: 86400, size: 2048, length: 100),
            RedisKeyEntry(key: "config:app", type: "string", ttl: nil, size: 128, length: nil),
            RedisKeyEntry(key: "cache:home:hero", type: "string", ttl: 300, size: 4096, length: nil),
        ]
    }

    fileprivate static var sampleNamespacedKeys: [RedisKeyEntry] {
        [
            RedisKeyEntry(key: "app:users:1001:profile", type: "hash", ttl: nil, size: 256, length: 8),
            RedisKeyEntry(key: "app:users:1001:settings", type: "hash", ttl: nil, size: 128, length: 5),
            RedisKeyEntry(key: "app:users:1002:profile", type: "hash", ttl: nil, size: 280, length: 9),
            RedisKeyEntry(key: "app:sessions:abc", type: "string", ttl: 1800, size: 64, length: nil),
            RedisKeyEntry(key: "app:metrics:cpu:1m", type: "list", ttl: nil, size: 1024, length: 60),
            RedisKeyEntry(key: "app:metrics:cpu:5m", type: "list", ttl: nil, size: 5120, length: 300),
            RedisKeyEntry(key: "app:cache:home:hero", type: "string", ttl: 300, size: 4096, length: nil),
            RedisKeyEntry(key: "billing:invoices:2024:01", type: "list", ttl: nil, size: 8192, length: 120),
        ]
    }

    fileprivate static var sampleServerInfo: [String: [String: String]] {
        [
            "Server": [
                "redis_version": "7.2.0",
                "redis_mode": "standalone",
                "os": "Darwin 24.0.0",
                "arch_bits": "64",
                "uptime_in_seconds": "864000",
                "tcp_port": "6379",
            ],
            "Clients": [
                "connected_clients": "12",
                "blocked_clients": "2",
                "tracking_clients": "0",
            ],
            "Memory": [
                "used_memory": "1048576",
                "used_memory_human": "1.00M",
                "used_memory_rss": "2097152",
                "mem_fragmentation_ratio": "2.00",
                "maxmemory": "0",
            ],
            "Stats": [
                "total_connections_received": "1500",
                "total_commands_processed": "98234",
                "instantaneous_ops_per_sec": "240",
                "keyspace_hits": "8000",
                "keyspace_misses": "200",
                "evicted_keys": "0",
                "expired_keys": "45",
            ],
            "Keyspace": [
                "db0": "keys=1500,expires=300,avg_ttl=3600000"
            ],
        ]
    }

    fileprivate static var sampleCapabilities: [RedisServerCapability] {
        [
            RedisServerCapability(name: "JSON", version: "2.6.0", details: []),
            RedisServerCapability(
                name: "BloomFilter",
                version: "2.4.0",
                details: [RedisServerCapabilityDetail(name: "BF", value: "enabled")]
            ),
            RedisServerCapability(name: "TimeSeries", version: "1.10.0", details: []),
        ]
    }

    fileprivate static var sampleClusterInfo: [String: String] {
        [
            "cluster_state": "ok",
            "cluster_slots_assigned": "16384",
            "cluster_slots_ok": "16384",
            "cluster_known_nodes": "4",
            "cluster_size": "3",
            "cluster_current_epoch": "3",
            "cluster_my_epoch": "1",
        ]
    }

    fileprivate static var sampleClusterNodes: [RedisClusterNodeSummary] {
        [
            RedisClusterNodeSummary(
                endpoint: RedisEndpoint(host: "10.0.0.1", port: 7000),
                role: .primary,
                slotRanges: [RedisClusterSlotRangeSummary(start: 0, end: 5460)],
                replicaOf: nil
            ),
            RedisClusterNodeSummary(
                endpoint: RedisEndpoint(host: "10.0.0.2", port: 7000),
                role: .primary,
                slotRanges: [RedisClusterSlotRangeSummary(start: 5461, end: 10922)],
                replicaOf: nil
            ),
            RedisClusterNodeSummary(
                endpoint: RedisEndpoint(host: "10.0.0.3", port: 7000),
                role: .primary,
                slotRanges: [RedisClusterSlotRangeSummary(start: 10923, end: 16383)],
                replicaOf: nil
            ),
            RedisClusterNodeSummary(
                endpoint: RedisEndpoint(host: "10.0.0.4", port: 7000),
                role: .replica,
                slotRanges: [],
                replicaOf: RedisEndpoint(host: "10.0.0.1", port: 7000)
            ),
        ]
    }

    fileprivate static var sampleSlowLogEntries: [SlowLogEntry] {
        [
            SlowLogEntry(
                id: 14,
                timestamp: Date(timeIntervalSinceNow: -60),
                duration: 25_000,
                command: ["KEYS", "*"],
                clientIP: "127.0.0.1:54321",
                clientName: "redis-cli"
            ),
            SlowLogEntry(
                id: 13,
                timestamp: Date(timeIntervalSinceNow: -120),
                duration: 8_500,
                command: ["SORT", "leaderboard:daily"],
                clientIP: "127.0.0.1:54322",
                clientName: "app"
            ),
            SlowLogEntry(
                id: 12,
                timestamp: Date(timeIntervalSinceNow: -300),
                duration: 1_200_000,
                command: ["LRANGE", "metrics:cpu", "0", "-1"],
                clientIP: "10.0.0.5:51000",
                clientName: "worker"
            ),
        ]
    }

    fileprivate static var sampleProfilerEntries: [RedisProfilerEntry] {
        let node = RedisEndpoint(host: "127.0.0.1", port: 6379)
        return [
            RedisProfilerEntry(
                rawLine: #"1719421200.123 [0 127.0.0.1:54321] "SET" "session:42" "value""#,
                node: node
            ),
            RedisProfilerEntry(
                rawLine: #"1719421200.250 [0 127.0.0.1:54321] "GET" "user:1001""#,
                node: node
            ),
            RedisProfilerEntry(
                rawLine: #"1719421200.500 [0 127.0.0.1:54322] "ZADD" "leaderboard:daily" "100" "player:7""#,
                node: node
            ),
            RedisProfilerEntry(
                rawLine: #"1719421200.750 [0 127.0.0.1:54321] "HGETALL" "config:app""#,
                node: node
            ),
        ]
    }

    fileprivate static var sampleShellHistory: [ShellHistoryEntry] {
        [
            ShellHistoryEntry(
                command: "SET session:abc hello",
                result: "OK",
                timestamp: Date(timeIntervalSinceNow: -120),
                isError: false
            ),
            ShellHistoryEntry(
                command: "GET session:abc",
                result: "hello",
                timestamp: Date(timeIntervalSinceNow: -90),
                isError: false
            ),
            ShellHistoryEntry(
                command: "KEYS *",
                result: "(error) ERR dangerous command refused",
                timestamp: Date(timeIntervalSinceNow: -30),
                isError: true
            ),
        ]
    }

    fileprivate static var sampleAnalysis: DatabaseAnalysis {
        var analysis = DatabaseAnalysis()
        analysis.totalKeys = 1500
        analysis.totalMemory = 12_582_912
        analysis.typeDistribution = [
            "hash": TypeStats(count: 800, memory: 8_388_608),
            "string": TypeStats(count: 500, memory: 2_097_152),
            "list": TypeStats(count: 120, memory: 1_572_864),
            "set": TypeStats(count: 50, memory: 262_144),
            "zset": TypeStats(count: 30, memory: 262_144),
        ]
        analysis.topKeysByMemory = [
            KeyMemoryEntry(key: "billing:invoices:2024:01", type: "list", memory: 524_288, length: 120, ttl: nil),
            KeyMemoryEntry(key: "leaderboard:daily", type: "zset", memory: 262_144, length: 100, ttl: 86400),
            KeyMemoryEntry(key: "metrics:cpu", type: "list", memory: 131_072, length: 50, ttl: nil),
        ]
        analysis.topNamespaces = [
            NamespaceStats(namespace: "app:users", keyCount: 600, totalMemory: 6_291_456, types: ["hash": 600]),
            NamespaceStats(namespace: "app:metrics", keyCount: 120, totalMemory: 1_572_864, types: ["list": 120]),
            NamespaceStats(namespace: "billing", keyCount: 200, totalMemory: 1_048_576, types: ["list": 200]),
        ]
        analysis.expirationSummary = [
            ExpirationBucket(label: "Expired (< 1m)", keyCount: 5, estimatedMemory: 20_480),
            ExpirationBucket(label: "Short (1m–1h)", keyCount: 80, estimatedMemory: 327_680),
            ExpirationBucket(label: "Medium (1h–1d)", keyCount: 150, estimatedMemory: 1_048_576),
            ExpirationBucket(label: "Long (> 1d)", keyCount: 65, estimatedMemory: 524_288),
            ExpirationBucket(label: "No expiry", keyCount: 1200, estimatedMemory: 10_485_760),
        ]
        var metrics = ServerMetrics()
        metrics.usedMemory = 12_582_912
        metrics.usedMemoryHuman = "12.00M"
        metrics.usedMemoryRSS = 25_165_824
        metrics.memoryFragmentationRatio = 2.0
        metrics.connectedClients = 12
        metrics.blockedClients = 2
        metrics.keyspaceHits = 8000
        metrics.keyspaceMisses = 200
        metrics.hitRate = 0.9756
        metrics.uptimeInSeconds = 864_000
        metrics.opsPerSecond = 240
        metrics.evictedKeys = 0
        metrics.expiredKeys = 45
        analysis.serverMetrics = metrics
        analysis.keysSampled = 1500
        analysis.isEstimate = false
        return analysis
    }

    fileprivate static var sampleAnalysisEmptyTypeDistribution: DatabaseAnalysis {
        var analysis = sampleAnalysis
        analysis.typeDistribution = [:]
        return analysis
    }

    fileprivate static var sampleAnalysisEmptyTopKeys: DatabaseAnalysis {
        var analysis = sampleAnalysis
        analysis.topKeysByMemory = []
        return analysis
    }
}

// MARK: - Connection Management

private struct ConnHubListEntry: UIInventoryEntry {
    let id = "conn-hub-list"
    let feature = "Connection Management"
    let module = "ConnectionHubSidebarView"
    let state = "Populated connection list sidebar"
    let priority: ScreenshotPriority = .high
    let notes = "Disconnected; sidebar shows saved connections with context menu"
    let viewHierarchy = "TabContentView > ConnectionHubView > ConnectionHubSidebarView"

    func configure(state: ConnectionState, store: AppStore) {
        state.rightPanel = .welcome
        store.connections = UIInventoryRegistry.sampleConnections
    }
}

private struct ConnHubNewEntry: UIInventoryEntry {
    let id = "conn-hub-new"
    let feature = "Connection Management"
    let module = "ConnectionDetailView"
    let state = "New connection form, empty"
    let priority: ScreenshotPriority = .critical
    let notes = "Disconnected; rightPanel set to .newConnection"
    let viewHierarchy = "TabContentView > ConnectionHubView > ConnectionDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        state.rightPanel = .newConnection
        store.connections = UIInventoryRegistry.sampleConnections
    }
}

private struct ConnHubEditEntry: UIInventoryEntry {
    let id = "conn-hub-edit"
    let feature = "Connection Management"
    let module = "ConnectionDetailView"
    let state = "Edit connection form, filled"
    let priority: ScreenshotPriority = .high
    let notes = "Disconnected; rightPanel set to .editConnection with filled config"
    let viewHierarchy = "TabContentView > ConnectionHubView > ConnectionDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        let config = RedisConnectionConfig(name: "Local Redis", host: "127.0.0.1", port: 6379, environment: .development)
        state.rightPanel = .editConnection(config)
        store.connections = UIInventoryRegistry.sampleConnections
    }
}

private struct ConnHubClusterEntry: UIInventoryEntry {
    let id = "conn-hub-cluster"
    let feature = "Connection Management"
    let module = "ConnectionDetailView"
    let state = "Cluster connection form with seed nodes"
    let priority: ScreenshotPriority = .medium
    let notes = "Disconnected; editConnection with mode .cluster and seed nodes"
    let viewHierarchy = "TabContentView > ConnectionHubView > ConnectionDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        let config = RedisConnectionConfig(
            name: "Analytics Cluster",
            mode: .cluster,
            host: "10.0.0.1",
            port: 7000,
            seedNodes: UIInventoryRegistry.clusterSeedNodes,
            environment: .production
        )
        state.rightPanel = .editConnection(config)
        store.connections = UIInventoryRegistry.sampleConnections
    }
}

private struct ConnHubSSHEntry: UIInventoryEntry {
    let id = "conn-hub-ssh"
    let feature = "Connection Management"
    let module = "ConnectionDetailView"
    let state = "Connection form with SSH tunnel enabled"
    let priority: ScreenshotPriority = .medium
    let notes = "Disconnected; editConnection with ssh.enabled and bastion host"
    let viewHierarchy = "TabContentView > ConnectionHubView > ConnectionDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        var config = RedisConnectionConfig(name: "Staging", host: "staging-redis.internal", port: 6379, environment: .development)
        config.ssh = SSHConfig(
            enabled: true,
            host: "bastion.internal",
            port: 22,
            user: "deploy",
            password: "",
            privateKeyPath: "~/.ssh/id_ed25519",
            privateKeyPassphrase: ""
        )
        state.rightPanel = .editConnection(config)
        store.connections = UIInventoryRegistry.sampleConnections
    }
}

private struct ConnHubTLSEntry: UIInventoryEntry {
    let id = "conn-hub-tls"
    let feature = "Connection Management"
    let module = "ConnectionDetailView"
    let state = "Connection form with TLS enabled, development environment"
    let priority: ScreenshotPriority = .low
    let notes = "Disconnected; editConnection with tls.enabled, CA path, environment .development"
    let viewHierarchy = "TabContentView > ConnectionHubView > ConnectionDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        var config = RedisConnectionConfig(
            name: "Staging Cache",
            host: "staging-cache-01.internal",
            port: 6379,
            environment: .development
        )
        config.tls = TLSConfig(
            enabled: true,
            verifyServerCertificate: true,
            caCertificatePath: "/etc/ssl/certs/ca.pem",
            clientCertificatePath: "",
            clientKeyPath: ""
        )
        state.rightPanel = .editConnection(config)
        store.connections = UIInventoryRegistry.sampleConnections
    }
}

private struct ConnHubConnectingEntry: UIInventoryEntry {
    let id = "conn-hub-connecting"
    let feature = "Connection Management"
    let module = "ConnectingView"
    let state = "Connecting spinner during connect"
    let priority: ScreenshotPriority = .high
    let notes = "Disconnected; isConnecting true with pendingConnection, no activeClient"
    let viewHierarchy = "TabContentView > ConnectionHubView > ConnectingView"

    func configure(state: ConnectionState, store: AppStore) {
        state.isConnecting = true
        state.connectionError = nil
        state.pendingConnection = RedisConnectionConfig(
            name: "Local Redis",
            host: "127.0.0.1",
            port: 6379,
            environment: .development
        )
    }
}

// MARK: - Key Browser

private struct BrowserEmptyEntry: UIInventoryEntry {
    let id = "browser-empty"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Empty key list, no keys in database"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; empty keys array, flat mode"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = []
        state.keyTotalCount = 0
        state.keyScannedCount = 0
        state.isNamespaceGroupingEnabled = false
    }
}

private struct BrowserLoadingEntry: UIInventoryEntry {
    let id = "browser-loading"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Scanning keys, loading spinner"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; isLoadingKeys true with scan cursor"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = []
        state.isLoadingKeys = true
        state.scanCursor = "42"
        state.keyScannedCount = 0
        state.hasMoreKeys = true
    }
}

private struct BrowserFlatEntry: UIInventoryEntry {
    let id = "browser-flat"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Flat key list with mixed key types"
    let priority: ScreenshotPriority = .critical
    let notes = "Connected; mixed-type keys, flat mode, no type filter"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        state.keyTotalCount = UIInventoryRegistry.sampleKeys.count
        state.keyScannedCount = UIInventoryRegistry.sampleKeys.count
        state.keyTypeFilter = ""
        state.isNamespaceGroupingEnabled = false
    }
}

private struct BrowserNamespaceEntry: UIInventoryEntry {
    let id = "browser-namespace"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Namespace tree grouped by colon separator"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; namespaced keys, namespace grouping enabled"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleNamespacedKeys
        state.keyTotalCount = UIInventoryRegistry.sampleNamespacedKeys.count
        state.keyScannedCount = UIInventoryRegistry.sampleNamespacedKeys.count
        state.isNamespaceGroupingEnabled = true
        state.namespaceSeparator = ":"
    }
}

private struct BrowserErrorEntry: UIInventoryEntry {
    let id = "browser-error"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Browser with connection error banner"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; connectionError set, empty keys"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = []
        state.connectionError = "Failed to execute SCAN: Connection reset by peer"
    }
}

private struct BrowserAddKeyEntry: UIInventoryEntry {
    let id = "browser-add-key"
    let feature = "Key Browser"
    let module = "AddKeySheet"
    let state = "Browser with add-key sheet (string variant)"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; populated browser. Sheet presentation is UI-driven, not ConnectionState-backed"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > AddKeySheet"
    let isCapturable = false

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        state.keyTotalCount = UIInventoryRegistry.sampleKeys.count
        state.keyScannedCount = UIInventoryRegistry.sampleKeys.count
        state.isNamespaceGroupingEnabled = false
    }
}

// MARK: - Value Editor

private struct DetailNoneEntry: UIInventoryEntry {
    let id = "detail-none"
    let feature = "Value Editor"
    let module = "KeyDetailView"
    let state = "No key selected, placeholder"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; populated keys, selectedKey nil"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > KeyDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        state.selectedKey = nil
    }
}

private struct DetailLoadingEntry: UIInventoryEntry {
    let id = "detail-loading"
    let feature = "Value Editor"
    let module = "KeyDetailView"
    let state = "Loading key detail"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; selectedKey set, isLoadingDetail true"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > KeyDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "metrics:cpu", type: "list", ttl: nil, size: 1024, length: 50)
        state.selectedKey = key
        state.keyType = "list"
        state.isLoadingDetail = true
    }
}

private struct DetailStringEntry: UIInventoryEntry {
    let id = "detail-string"
    let feature = "Value Editor"
    let module = "StringDetailView"
    let state = "String value viewer, JSON formatted"
    let priority: ScreenshotPriority = .critical
    let notes = "Connected; string key, keyDetail JSON, format .json"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > StringDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "config:app", type: "string", ttl: nil, size: 128, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = #"{"theme":"dark","pageSize":50,"featureFlags":{"beta":true}}"#
        state.valueSize = 128
        state.keyDetailLength = 1
        state.stringValueFormat = .json
    }
}

private struct DetailHashEntry: UIInventoryEntry {
    let id = "detail-hash"
    let feature = "Value Editor"
    let module = "HashDetailView"
    let state = "Hash value viewer with populated fields"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; hash key, keyDetailRows field/value pairs"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > HashDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "user:1001", type: "hash", ttl: 3600, size: 256, length: 12)
        state.selectedKey = key
        state.keyType = "hash"
        state.keyDetailRows = [
            ("username", "alice"),
            ("email", "alice@example.com"),
            ("created_at", "2024-01-15"),
            ("last_login", "2024-06-26"),
            ("role", "admin"),
        ]
        state.valueSize = 256
        state.keyDetailLength = 12
    }
}

private struct DetailListEntry: UIInventoryEntry {
    let id = "detail-list"
    let feature = "Value Editor"
    let module = "ListDetailView"
    let state = "List value viewer with elements"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; list key, keyDetailRows index/value pairs"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ListDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "metrics:cpu", type: "list", ttl: nil, size: 1024, length: 50)
        state.selectedKey = key
        state.keyType = "list"
        state.keyDetailRows = [
            ("0", "alpha"),
            ("1", "beta"),
            ("2", "gamma"),
            ("3", "delta"),
            ("4", "epsilon"),
        ]
        state.valueSize = 1024
        state.keyDetailLength = 50
    }
}

private struct DetailSetEntry: UIInventoryEntry {
    let id = "detail-set"
    let feature = "Value Editor"
    let module = "SetDetailView"
    let state = "Set value viewer with members"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; set key, keyDetailRows member entries"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > SetDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "tags:recent", type: "set", ttl: nil, size: 512, length: 23)
        state.selectedKey = key
        state.keyType = "set"
        state.keyDetailRows = [
            ("alpha", ""),
            ("beta", ""),
            ("gamma", ""),
            ("delta", ""),
            ("epsilon", ""),
        ]
        state.valueSize = 512
        state.keyDetailLength = 23
    }
}

private struct DetailZSetEntry: UIInventoryEntry {
    let id = "detail-zset"
    let feature = "Value Editor"
    let module = "ZSetDetailView"
    let state = "Sorted set viewer, ascending order"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; zset key, keyDetailRows member/score, ascending"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ZSetDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "leaderboard:daily", type: "zset", ttl: 86400, size: 2048, length: 100)
        state.selectedKey = key
        state.keyType = "zset"
        state.keyDetailZSetOrder = .ascending
        state.keyDetailRows = [
            ("player:1", "100"),
            ("player:2", "250"),
            ("player:3", "500"),
            ("player:4", "750"),
            ("player:5", "1000"),
        ]
        state.valueSize = 2048
        state.keyDetailLength = 100
    }
}

private struct DetailTTLEntry: UIInventoryEntry {
    let id = "detail-ttl"
    let feature = "Value Editor"
    let module = "KeyTTLEditorPopover"
    let state = "Key with TTL, TTL editor popover"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; string key with TTL 1800. Popover presentation is UI-driven"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > KeyTTLEditorPopover"
    let isCapturable = false

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "session:abc", type: "string", ttl: 1800, size: 64, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = "hello-world"
        state.valueSize = 64
        state.keyDetailLength = 1
    }
}

private struct DetailErrorEntry: UIInventoryEntry {
    let id = "detail-error"
    let feature = "Value Editor"
    let module = "KeyDetailView"
    let state = "Detail error banner"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; selectedKey set, keyDetailError set"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > KeyDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "user:1001", type: "hash", ttl: 3600, size: 256, length: 12)
        state.selectedKey = key
        state.keyType = "hash"
        state.keyDetailError = "LOADING failed: Connection reset by peer"
    }
}

private struct DetailAddHashEntry: UIInventoryEntry {
    let id = "detail-add-hash"
    let feature = "Value Editor"
    let module = "AddHashFieldSheet"
    let state = "Hash detail with add-field sheet"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; hash detail populated. Sheet presentation is UI-driven"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > HashDetailView > AddHashFieldSheet"
    let isCapturable = false

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "user:1001", type: "hash", ttl: 3600, size: 256, length: 12)
        state.selectedKey = key
        state.keyType = "hash"
        state.keyDetailRows = [
            ("username", "alice"),
            ("email", "alice@example.com"),
        ]
        state.valueSize = 256
        state.keyDetailLength = 12
    }
}

private struct DetailAddListEntry: UIInventoryEntry {
    let id = "detail-add-list"
    let feature = "Value Editor"
    let module = "AddListElementSheet"
    let state = "List detail with add-element sheet (tail)"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; list detail populated. Sheet presentation is UI-driven"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ListDetailView > AddListElementSheet"
    let isCapturable = false

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "metrics:cpu", type: "list", ttl: nil, size: 1024, length: 50)
        state.selectedKey = key
        state.keyType = "list"
        state.keyDetailRows = [("0", "alpha"), ("1", "beta")]
        state.valueSize = 1024
        state.keyDetailLength = 50
    }
}

private struct DetailAddSetEntry: UIInventoryEntry {
    let id = "detail-add-set"
    let feature = "Value Editor"
    let module = "AddSetMemberSheet"
    let state = "Set detail with add-member sheet"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; set detail populated. Sheet presentation is UI-driven"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > SetDetailView > AddSetMemberSheet"
    let isCapturable = false

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "tags:recent", type: "set", ttl: nil, size: 512, length: 23)
        state.selectedKey = key
        state.keyType = "set"
        state.keyDetailRows = [("alpha", ""), ("beta", "")]
        state.valueSize = 512
        state.keyDetailLength = 23
    }
}

private struct DetailAddZSetEntry: UIInventoryEntry {
    let id = "detail-add-zset"
    let feature = "Value Editor"
    let module = "AddZSetMemberSheet"
    let state = "Sorted set detail with add-member sheet"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; zset detail populated. Sheet presentation is UI-driven"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ZSetDetailView > AddZSetMemberSheet"
    let isCapturable = false

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "leaderboard:daily", type: "zset", ttl: 86400, size: 2048, length: 100)
        state.selectedKey = key
        state.keyType = "zset"
        state.keyDetailZSetOrder = .ascending
        state.keyDetailRows = [("player:1", "100"), ("player:2", "250")]
        state.valueSize = 2048
        state.keyDetailLength = 100
    }
}

// MARK: - Shell

private struct ShellEmptyEntry: UIInventoryEntry {
    let id = "shell-empty"
    let feature = "Shell"
    let module = "ShellView"
    let state = "Empty shell, no commands"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; currentView .shell, empty shellHistory"
    let viewHierarchy = "TabContentView > WorkspaceView > ShellView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .shell)
        state.shellHistory = []
    }
}

private struct ShellPopulatedEntry: UIInventoryEntry {
    let id = "shell-populated"
    let feature = "Shell"
    let module = "ShellView"
    let state = "Shell with command history and error result"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; shellHistory with OK and error entries"
    let viewHierarchy = "TabContentView > WorkspaceView > ShellView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .shell)
        state.shellHistory = UIInventoryRegistry.sampleShellHistory
    }
}

private struct ShellDangerEntry: UIInventoryEntry {
    let id = "shell-danger"
    let feature = "Shell"
    let module = "ShellView"
    let state = "Dangerous command confirmation alert"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; shellInput FLUSHALL. Alert presentation is UI-driven"
    let viewHierarchy = "TabContentView > WorkspaceView > ShellView > alert"
    let isCapturable = false

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .shell)
        state.shellHistory = UIInventoryRegistry.sampleShellHistory
        state.shellInput = "FLUSHALL"
    }
}

// MARK: - Profiler

private struct ProfilerStoppedEntry: UIInventoryEntry {
    let id = "profiler-stopped"
    let feature = "Profiler"
    let module = "ProfilerView"
    let state = "Profiler idle, stopped"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; currentView .profiler, isProfilerRunning false"
    let viewHierarchy = "TabContentView > WorkspaceView > ProfilerView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .profiler)
        state.isProfilerRunning = false
        state.profilerEntries = []
        state.profilerCapturedCount = 0
    }
}

private struct ProfilerRunningEntry: UIInventoryEntry {
    let id = "profiler-running"
    let feature = "Profiler"
    let module = "ProfilerView"
    let state = "Profiler running with captured commands"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; isProfilerRunning true, profilerEntries populated"
    let viewHierarchy = "TabContentView > WorkspaceView > ProfilerView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .profiler)
        let entries = UIInventoryRegistry.sampleProfilerEntries
        state.isProfilerRunning = true
        state.profilerEntries = entries
        state.profilerCapturedCount = entries.count
    }
}

private struct ProfilerWaitingEntry: UIInventoryEntry {
    let id = "profiler-waiting"
    let feature = "Profiler"
    let module = "ProfilerView"
    let state = "Profiler running, waiting for commands"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; isProfilerRunning true, profilerEntries empty"
    let viewHierarchy = "TabContentView > WorkspaceView > ProfilerView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .profiler)
        state.isProfilerRunning = true
        state.isProfilerStarting = false
        state.profilerEntries = []
        state.profilerCapturedCount = 0
    }
}

private struct ProfilerErrorEntry: UIInventoryEntry {
    let id = "profiler-error"
    let feature = "Profiler"
    let module = "ProfilerView"
    let state = "Profiler error banner"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; profilerError set, isProfilerRunning false"
    let viewHierarchy = "TabContentView > WorkspaceView > ProfilerView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .profiler)
        state.isProfilerRunning = false
        state.profilerError = "Failed to start MONITOR: NOAUTH Authentication required"
    }
}

// MARK: - Slow Log

private struct SlowLogEmptyEntry: UIInventoryEntry {
    let id = "slowlog-empty"
    let feature = "Slow Log"
    let module = "SlowLogView"
    let state = "Empty slow log"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; currentView .slowLog, empty slowLogEntries"
    let viewHierarchy = "TabContentView > WorkspaceView > SlowLogView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .slowLog)
        state.slowLogEntries = []
        state.slowLogError = nil
    }
}

private struct SlowLogPopulatedEntry: UIInventoryEntry {
    let id = "slowlog-populated"
    let feature = "Slow Log"
    let module = "SlowLogView"
    let state = "Slow log with entries"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; slowLogEntries populated with varied durations"
    let viewHierarchy = "TabContentView > WorkspaceView > SlowLogView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .slowLog)
        state.slowLogEntries = UIInventoryRegistry.sampleSlowLogEntries
        state.slowLogFetchCount = 128
    }
}

// MARK: - Database Analysis

private struct AnalysisEmptyEntry: UIInventoryEntry {
    let id = "analysis-empty"
    let feature = "Database Analysis"
    let module = "DatabaseAnalysisView"
    let state = "No analysis data"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; currentView .databaseAnalysis, analysis nil"
    let viewHierarchy = "TabContentView > WorkspaceView > DatabaseAnalysisView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .databaseAnalysis)
        state.analysis = nil
        state.isLoadingAnalysis = false
        state.analysisError = nil
    }
}

private struct AnalysisLoadingEntry: UIInventoryEntry {
    let id = "analysis-loading"
    let feature = "Database Analysis"
    let module = "DatabaseAnalysisView"
    let state = "Analysis running, loading"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; isLoadingAnalysis true, analysis nil"
    let viewHierarchy = "TabContentView > WorkspaceView > DatabaseAnalysisView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .databaseAnalysis)
        state.analysis = nil
        state.isLoadingAnalysis = true
    }
}

private struct AnalysisPopulatedEntry: UIInventoryEntry {
    let id = "analysis-populated"
    let feature = "Database Analysis"
    let module = "DatabaseAnalysisView"
    let state = "Analysis results with type distribution and top keys"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; analysis populated with distribution, top keys, expiration"
    let viewHierarchy = "TabContentView > WorkspaceView > DatabaseAnalysisView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .databaseAnalysis)
        state.analysis = UIInventoryRegistry.sampleAnalysis
        state.isLoadingAnalysis = false
    }
}

// MARK: - Server Info

private struct ServerInfoEmptyEntry: UIInventoryEntry {
    let id = "serverinfo-empty"
    let feature = "Server Info"
    let module = "ServerInfoView"
    let state = "No server info loaded"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; currentView .serverInfo, empty serverInfo"
    let viewHierarchy = "TabContentView > WorkspaceView > ServerInfoView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .serverInfo)
        state.serverInfo = [:]
        state.serverCapabilities = []
    }
}

private struct ServerInfoPopulatedEntry: UIInventoryEntry {
    let id = "serverinfo-populated"
    let feature = "Server Info"
    let module = "ServerInfoView"
    let state = "Server info loaded with capabilities"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; serverInfo sections and serverCapabilities populated"
    let viewHierarchy = "TabContentView > WorkspaceView > ServerInfoView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .serverInfo)
        state.serverInfo = UIInventoryRegistry.sampleServerInfo
        state.serverCapabilities = UIInventoryRegistry.sampleCapabilities
    }
}

private struct ServerInfoClusterEntry: UIInventoryEntry {
    let id = "serverinfo-cluster"
    let feature = "Server Info"
    let module = "ServerInfoView"
    let state = "Cluster server info with topology toggle enabled"
    let priority: ScreenshotPriority = .high
    let notes =
        "Connected; cluster mode, clusterInfo and clusterNodes populated. "
        + "Topology toggle is @State-driven and not capturable via ConnectionState"
    let viewHierarchy = "TabContentView > WorkspaceView > ServerInfoView"

    func configure(state: ConnectionState, store: AppStore) {
        let connection = RedisConnectionConfig(
            name: "Analytics Cluster",
            mode: .cluster,
            host: "10.0.0.1",
            port: 7000,
            seedNodes: UIInventoryRegistry.clusterSeedNodes,
            environment: .production
        )
        UIInventoryRegistry.connect(state, view: .serverInfo, connection: connection)
        state.serverInfo = UIInventoryRegistry.sampleServerInfo
        state.clusterInfo = UIInventoryRegistry.sampleClusterInfo
        state.clusterNodes = UIInventoryRegistry.sampleClusterNodes
    }
}

// MARK: - Production Confirmation

private struct ProdConfirmEntry: UIInventoryEntry {
    let id = "prod-confirm"
    let feature = "Production Confirmation"
    let module = "ProductionConfirmView"
    let state = "Production delete confirmation, type DELETE"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; production connection, key selected. Confirm dialog is UI-driven"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ProductionConfirmView"
    let isCapturable = false

    func configure(state: ConnectionState, store: AppStore) {
        let connection = RedisConnectionConfig(
            name: "Production Cache",
            host: "prod-cache-01.internal",
            port: 6379,
            environment: .production
        )
        UIInventoryRegistry.connect(state, view: .browser, connection: connection)
        state.keys = UIInventoryRegistry.sampleKeys
        state.selectedKey = state.keys.first
    }
}

// MARK: - Connection Management (supplementary)

private struct ConnHubEmptyEntry: UIInventoryEntry {
    let id = "conn-hub-empty"
    let feature = "Connection Management"
    let module = "ConnectionHubSidebarView"
    let state = "Empty connection list, zero saved connections"
    let priority: ScreenshotPriority = .medium
    let notes = "Disconnected; store.connections empty, rightPanel .welcome"
    let viewHierarchy = "TabContentView > ConnectionHubView > ConnectionHubSidebarView"

    func configure(state: ConnectionState, store: AppStore) {
        store.connections = []
        state.rightPanel = .welcome
    }
}

// MARK: - Key Browser (supplementary)

private struct BrowserTypeFilterEntry: UIInventoryEntry {
    let id = "browser-type-filter"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Browser with type filter active (string only)"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; keyTypeFilter set to string, only string keys visible"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys.filter { $0.type == "string" }
        state.keyTotalCount = UIInventoryRegistry.sampleKeys.count
        state.keyScannedCount = state.keys.count
        state.keyTypeFilter = "string"
        state.isNamespaceGroupingEnabled = false
    }
}

private struct BrowserPatternFilterEntry: UIInventoryEntry {
    let id = "browser-pattern-filter"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Browser with pattern filter active (user:*)"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; keyFilter set to user:*, filtered results shown"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys.filter { $0.key.hasPrefix("user:") }
        state.keyTotalCount = UIInventoryRegistry.sampleKeys.count
        state.keyScannedCount = state.keys.count
        state.keyFilter = "user:*"
        state.isNamespaceGroupingEnabled = false
    }
}

private struct BrowserLoadMoreEntry: UIInventoryEntry {
    let id = "browser-load-more"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Browser with Load more button visible"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; populated keys, hasMoreKeys true"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        state.keyTotalCount = 100
        state.keyScannedCount = UIInventoryRegistry.sampleKeys.count
        state.hasMoreKeys = true
        state.isNamespaceGroupingEnabled = false
    }
}

private struct BrowserScanningMoreEntry: UIInventoryEntry {
    let id = "browser-scanning-more"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Browser with inline scanning spinner loading more keys"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; populated keys, hasMoreKeys true, isLoadingKeys true"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        state.keyTotalCount = 100
        state.keyScannedCount = UIInventoryRegistry.sampleKeys.count
        state.hasMoreKeys = true
        state.isLoadingKeys = true
        state.scanCursor = "42"
        state.isNamespaceGroupingEnabled = false
    }
}

private struct BrowserThresholdReachedEntry: UIInventoryEntry {
    let id = "browser-threshold-reached"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Browser footer showing Threshold Reached indicator"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; keyScanLimitReached true, hasMoreKeys true"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        state.keyTotalCount = 5000
        state.keyScannedCount = UIInventoryRegistry.sampleKeys.count
        state.hasMoreKeys = true
        state.keyScanLimitReached = true
        state.keyFilter = "cache:*"
        state.isNamespaceGroupingEnabled = false
    }
}

private struct BrowserNoMatchEntry: UIInventoryEntry {
    let id = "browser-no-match"
    let feature = "Key Browser"
    let module = "BrowserView"
    let state = "Browser with no matching keys for active pattern filter"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; keyFilter set to zzz:*, empty keys, filter pattern visible in search field"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = []
        state.keyTotalCount = UIInventoryRegistry.sampleKeys.count
        state.keyScannedCount = 0
        state.keyFilter = "zzz:*"
        state.keyTypeFilter = ""
        state.isNamespaceGroupingEnabled = false
    }
}

// MARK: - Value Editor (supplementary — string formats)

private struct DetailStringRawEntry: UIInventoryEntry {
    let id = "detail-string-raw"
    let feature = "Value Editor"
    let module = "StringDetailView"
    let state = "String value in raw format"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; string key, stringValueFormat .raw"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > StringDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "config:app", type: "string", ttl: nil, size: 128, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = #"{"theme":"dark","pageSize":50}"#
        state.valueSize = 128
        state.keyDetailLength = 1
        state.stringValueFormat = .raw
    }
}

private struct DetailStringHexEntry: UIInventoryEntry {
    let id = "detail-string-hex"
    let feature = "Value Editor"
    let module = "StringDetailView"
    let state = "String value as hex dump"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; string key, stringValueFormat .hex"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > StringDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "config:app", type: "string", ttl: nil, size: 128, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = #"{"theme":"dark","pageSize":50}"#
        state.valueSize = 128
        state.keyDetailLength = 1
        state.stringValueFormat = .hex
    }
}

private struct DetailStringBase64Entry: UIInventoryEntry {
    let id = "detail-string-base64"
    let feature = "Value Editor"
    let module = "StringDetailView"
    let state = "String value decoded from Base64"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; base64-encoded value, stringValueFormat .base64"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > StringDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "config:app", type: "string", ttl: nil, size: 64, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = "eyJ0aGVtZSI6ImRhcmsifQ=="
        state.valueSize = 64
        state.keyDetailLength = 1
        state.stringValueFormat = .base64
    }
}

private struct DetailStringAsciiEntry: UIInventoryEntry {
    let id = "detail-string-ascii"
    let feature = "Value Editor"
    let module = "StringDetailView"
    let state = "String value in ASCII mode"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; string key, stringValueFormat .ascii"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > StringDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "config:app", type: "string", ttl: nil, size: 128, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = #"{"theme":"dark","pageSize":50}"#
        state.valueSize = 128
        state.keyDetailLength = 1
        state.stringValueFormat = .ascii
    }
}

private struct DetailStringUnicodeEntry: UIInventoryEntry {
    let id = "detail-string-unicode"
    let feature = "Value Editor"
    let module = "StringDetailView"
    let state = "String value in Unicode-escaped mode"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; string with unicode content, stringValueFormat .unicode"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > StringDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "cache:home:hero", type: "string", ttl: 300, size: 256, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = "Hello World \u{4e16}\u{754c} — café"
        state.valueSize = 256
        state.keyDetailLength = 1
        state.stringValueFormat = .unicode
    }
}

private struct DetailStringGzipEntry: UIInventoryEntry {
    let id = "detail-string-gzip"
    let feature = "Value Editor"
    let module = "StringDetailView"
    let state = "String value GZip decompression failed"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; non-gzip data with stringValueFormat .gzip, shows error"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > StringDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "config:app", type: "string", ttl: nil, size: 128, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = #"{"theme":"dark"}"#
        state.valueSize = 128
        state.keyDetailLength = 1
        state.stringValueFormat = .gzip
    }
}

private struct DetailStringBase64EncodeEntry: UIInventoryEntry {
    let id = "detail-string-base64-encode"
    let feature = "Value Editor"
    let module = "StringDetailView"
    let state = "String value encoded to Base64"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; string key, stringValueFormat .base64Encode"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > StringDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "config:app", type: "string", ttl: nil, size: 128, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = #"{"theme":"dark","pageSize":50}"#
        state.valueSize = 128
        state.keyDetailLength = 1
        state.stringValueFormat = .base64Encode
    }
}

private struct DetailRefreshedEntry: UIInventoryEntry {
    let id = "detail-refreshed"
    let feature = "Value Editor"
    let module = "KeyDetailView"
    let state = "Key detail after refresh"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; string key, keyDetailLastRefreshedAt set"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > KeyDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "config:app", type: "string", ttl: nil, size: 128, length: nil)
        state.selectedKey = key
        state.keyType = "string"
        state.keyDetail = #"{"theme":"dark","pageSize":50}"#
        state.valueSize = 128
        state.keyDetailLength = 1
        state.stringValueFormat = .json
        state.keyDetailLastRefreshedAt = Date()
    }
}

// MARK: - Value Editor (supplementary — collection variants)

private struct DetailHashEmptyEntry: UIInventoryEntry {
    let id = "detail-hash-empty"
    let feature = "Value Editor"
    let module = "HashDetailView"
    let state = "Hash detail with zero fields"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; hash key, keyDetailRows empty"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > HashDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "user:1001", type: "hash", ttl: 3600, size: 0, length: 0)
        state.selectedKey = key
        state.keyType = "hash"
        state.keyDetailRows = []
        state.valueSize = 0
        state.keyDetailLength = 0
    }
}

private struct DetailHashSearchEntry: UIInventoryEntry {
    let id = "detail-hash-search"
    let feature = "Value Editor"
    let module = "HashDetailView"
    let state = "Hash detail with search filter active"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; hash key, keyDetailSearchText set"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > HashDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "user:1001", type: "hash", ttl: 3600, size: 256, length: 12)
        state.selectedKey = key
        state.keyType = "hash"
        state.keyDetailRows = [("email", "alice@example.com")]
        state.valueSize = 256
        state.keyDetailLength = 12
        state.keyDetailSearchText = "email"
    }
}

private struct DetailHashLoadMoreEntry: UIInventoryEntry {
    let id = "detail-hash-load-more"
    let feature = "Value Editor"
    let module = "HashDetailView"
    let state = "Hash detail with Load more button"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; hash key, keyDetailHasMoreRows true"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > HashDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "user:1001", type: "hash", ttl: 3600, size: 256, length: 50)
        state.selectedKey = key
        state.keyType = "hash"
        state.keyDetailRows = [("username", "alice"), ("email", "alice@example.com")]
        state.valueSize = 256
        state.keyDetailLength = 50
        state.keyDetailHasMoreRows = true
    }
}

private struct DetailListEmptyEntry: UIInventoryEntry {
    let id = "detail-list-empty"
    let feature = "Value Editor"
    let module = "ListDetailView"
    let state = "List detail with zero elements"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; list key, keyDetailRows empty"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ListDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "metrics:cpu", type: "list", ttl: nil, size: 0, length: 0)
        state.selectedKey = key
        state.keyType = "list"
        state.keyDetailRows = []
        state.valueSize = 0
        state.keyDetailLength = 0
    }
}

private struct DetailListLoadMoreEntry: UIInventoryEntry {
    let id = "detail-list-load-more"
    let feature = "Value Editor"
    let module = "ListDetailView"
    let state = "List detail with Load more button"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; list key, keyDetailHasMoreRows true"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ListDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "metrics:cpu", type: "list", ttl: nil, size: 1024, length: 50)
        state.selectedKey = key
        state.keyType = "list"
        state.keyDetailRows = [("0", "alpha"), ("1", "beta")]
        state.valueSize = 1024
        state.keyDetailLength = 50
        state.keyDetailHasMoreRows = true
    }
}

private struct DetailSetEmptyEntry: UIInventoryEntry {
    let id = "detail-set-empty"
    let feature = "Value Editor"
    let module = "SetDetailView"
    let state = "Set detail with zero members"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; set key, keyDetailRows empty"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > SetDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "tags:recent", type: "set", ttl: nil, size: 0, length: 0)
        state.selectedKey = key
        state.keyType = "set"
        state.keyDetailRows = []
        state.valueSize = 0
        state.keyDetailLength = 0
    }
}

private struct DetailSetSearchEntry: UIInventoryEntry {
    let id = "detail-set-search"
    let feature = "Value Editor"
    let module = "SetDetailView"
    let state = "Set detail with search filter active"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; set key, keyDetailSearchText set"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > SetDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "tags:recent", type: "set", ttl: nil, size: 512, length: 23)
        state.selectedKey = key
        state.keyType = "set"
        state.keyDetailRows = [("alpha", "")]
        state.valueSize = 512
        state.keyDetailLength = 23
        state.keyDetailSearchText = "alpha"
    }
}

private struct DetailSetLoadMoreEntry: UIInventoryEntry {
    let id = "detail-set-load-more"
    let feature = "Value Editor"
    let module = "SetDetailView"
    let state = "Set detail with Load more button"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; set key, keyDetailHasMoreRows true"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > SetDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "tags:recent", type: "set", ttl: nil, size: 512, length: 23)
        state.selectedKey = key
        state.keyType = "set"
        state.keyDetailRows = [("alpha", ""), ("beta", "")]
        state.valueSize = 512
        state.keyDetailLength = 23
        state.keyDetailHasMoreRows = true
    }
}

private struct DetailZSetDescendingEntry: UIInventoryEntry {
    let id = "detail-zset-descending"
    let feature = "Value Editor"
    let module = "ZSetDetailView"
    let state = "Sorted set viewer, descending order"
    let priority: ScreenshotPriority = .high
    let notes = "Connected; zset key, keyDetailZSetOrder .descending"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ZSetDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "leaderboard:daily", type: "zset", ttl: 86400, size: 2048, length: 100)
        state.selectedKey = key
        state.keyType = "zset"
        state.keyDetailZSetOrder = .descending
        state.keyDetailRows = [
            ("player:5", "1000"),
            ("player:4", "750"),
            ("player:3", "500"),
            ("player:2", "250"),
            ("player:1", "100"),
        ]
        state.valueSize = 2048
        state.keyDetailLength = 100
    }
}

private struct DetailZSetSearchEntry: UIInventoryEntry {
    let id = "detail-zset-search"
    let feature = "Value Editor"
    let module = "ZSetDetailView"
    let state = "Sorted set with search active, order picker disabled"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; zset key, keyDetailSearchText set, order picker disabled"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ZSetDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "leaderboard:daily", type: "zset", ttl: 86400, size: 2048, length: 100)
        state.selectedKey = key
        state.keyType = "zset"
        state.keyDetailZSetOrder = .ascending
        state.keyDetailRows = [("player:1", "100")]
        state.valueSize = 2048
        state.keyDetailLength = 100
        state.keyDetailSearchText = "player:1"
    }
}

private struct DetailZSetLoadMoreEntry: UIInventoryEntry {
    let id = "detail-zset-load-more"
    let feature = "Value Editor"
    let module = "ZSetDetailView"
    let state = "Sorted set with Load more button"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; zset key, keyDetailHasMoreRows true"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ZSetDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "leaderboard:daily", type: "zset", ttl: 86400, size: 2048, length: 100)
        state.selectedKey = key
        state.keyType = "zset"
        state.keyDetailZSetOrder = .ascending
        state.keyDetailRows = [("player:1", "100"), ("player:2", "250")]
        state.valueSize = 2048
        state.keyDetailLength = 100
        state.keyDetailHasMoreRows = true
    }
}

private struct DetailZSetEmptyEntry: UIInventoryEntry {
    let id = "detail-zset-empty"
    let feature = "Value Editor"
    let module = "ZSetDetailView"
    let state = "Sorted set with zero members"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; zset key, keyDetailRows empty"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > ZSetDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "leaderboard:daily", type: "zset", ttl: 86400, size: 0, length: 0)
        state.selectedKey = key
        state.keyType = "zset"
        state.keyDetailZSetOrder = .ascending
        state.keyDetailRows = []
        state.valueSize = 0
        state.keyDetailLength = 0
    }
}

private struct DetailUnknownTypeEntry: UIInventoryEntry {
    let id = "detail-unknown-type"
    let feature = "Value Editor"
    let module = "KeyDetailView"
    let state = "Key detail for unknown type (stream)"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; keyType set to stream, falls into generic default branch"
    let viewHierarchy = "TabContentView > WorkspaceView > BrowserView > KeyDetailView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .browser)
        state.keys = UIInventoryRegistry.sampleKeys
        let key = RedisKeyEntry(key: "events:stream", type: "stream", ttl: nil, size: 512, length: 10)
        state.selectedKey = key
        state.keyType = "stream"
        state.keyDetail = "1-0 1625097600 1 field1 value1\n2-0 1625097601 1 field2 value2"
        state.valueSize = 512
        state.keyDetailLength = 10
    }
}

// MARK: - Profiler (supplementary)

private struct ProfilerStartingEntry: UIInventoryEntry {
    let id = "profiler-starting"
    let feature = "Profiler"
    let module = "ProfilerView"
    let state = "Profiler starting, transitional state"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; isProfilerStarting true, isProfilerRunning false"
    let viewHierarchy = "TabContentView > WorkspaceView > ProfilerView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .profiler)
        state.isProfilerStarting = true
        state.isProfilerRunning = false
        state.profilerEntries = []
        state.profilerCapturedCount = 0
    }
}

private struct ProfilerStoppedWithEntriesEntry: UIInventoryEntry {
    let id = "profiler-stopped-with-entries"
    let feature = "Profiler"
    let module = "ProfilerView"
    let state = "Profiler stopped with previously captured entries visible"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; isProfilerRunning false, profilerEntries populated"
    let viewHierarchy = "TabContentView > WorkspaceView > ProfilerView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .profiler)
        let entries = UIInventoryRegistry.sampleProfilerEntries
        state.isProfilerRunning = false
        state.isProfilerStarting = false
        state.profilerEntries = entries
        state.profilerCapturedCount = entries.count
    }
}

// MARK: - Slow Log (supplementary)

private struct SlowLogLoadingEntry: UIInventoryEntry {
    let id = "slowlog-loading"
    let feature = "Slow Log"
    let module = "SlowLogView"
    let state = "Slow log loading, refresh control dimmed"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; isLoadingSlowLog true"
    let viewHierarchy = "TabContentView > WorkspaceView > SlowLogView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .slowLog)
        state.slowLogEntries = []
        state.isLoadingSlowLog = true
    }
}

private struct SlowLogAutoRefreshEntry: UIInventoryEntry {
    let id = "slowlog-auto-refresh"
    let feature = "Slow Log"
    let module = "SlowLogView"
    let state = "Slow log with auto-refresh enabled (5s interval)"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; slowLogConfig.autoRefreshInterval set to 5"
    let viewHierarchy = "TabContentView > WorkspaceView > SlowLogView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .slowLog)
        state.slowLogEntries = UIInventoryRegistry.sampleSlowLogEntries
        state.slowLogConfig.autoRefreshInterval = 5
    }
}

// MARK: - Database Analysis (supplementary)

private struct AnalysisErrorEntry: UIInventoryEntry {
    let id = "analysis-error"
    let feature = "Database Analysis"
    let module = "DatabaseAnalysisView"
    let state = "Analysis error banner"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; analysisError set, analysis nil"
    let viewHierarchy = "TabContentView > WorkspaceView > DatabaseAnalysisView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .databaseAnalysis)
        state.analysis = nil
        state.isLoadingAnalysis = false
        state.analysisError = "Failed to run analysis: MEMORY USAGE command not supported"
    }
}

private struct AnalysisEstimateEntry: UIInventoryEntry {
    let id = "analysis-estimate"
    let feature = "Database Analysis"
    let module = "DatabaseAnalysisView"
    let state = "Analysis results with Estimate badge"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; analysis populated with isEstimate true"
    let viewHierarchy = "TabContentView > WorkspaceView > DatabaseAnalysisView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .databaseAnalysis)
        var analysis = UIInventoryRegistry.sampleAnalysis
        analysis.isEstimate = true
        state.analysis = analysis
    }
}

private struct AnalysisNoExpirationEntry: UIInventoryEntry {
    let id = "analysis-no-expiration"
    let feature = "Database Analysis"
    let module = "DatabaseAnalysisView"
    let state = "Analysis with no expiration data"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; analysis populated with empty expirationSummary"
    let viewHierarchy = "TabContentView > WorkspaceView > DatabaseAnalysisView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .databaseAnalysis)
        var analysis = UIInventoryRegistry.sampleAnalysis
        analysis.expirationSummary = []
        state.analysis = analysis
    }
}

private struct AnalysisEmptyTypeDistributionEntry: UIInventoryEntry {
    let id = "analysis-empty-type-distribution"
    let feature = "Database Analysis"
    let module = "DatabaseAnalysisView"
    let state = "Analysis with empty type distribution"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; analysis populated, typeDistribution empty, topKeysByMemory populated"
    let viewHierarchy = "TabContentView > WorkspaceView > DatabaseAnalysisView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .databaseAnalysis)
        state.analysis = UIInventoryRegistry.sampleAnalysisEmptyTypeDistribution
        state.isLoadingAnalysis = false
    }
}

private struct AnalysisEmptyTopKeysEntry: UIInventoryEntry {
    let id = "analysis-empty-top-keys"
    let feature = "Database Analysis"
    let module = "DatabaseAnalysisView"
    let state = "Analysis with empty top keys"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; analysis populated, topKeysByMemory empty, typeDistribution populated"
    let viewHierarchy = "TabContentView > WorkspaceView > DatabaseAnalysisView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .databaseAnalysis)
        state.analysis = UIInventoryRegistry.sampleAnalysisEmptyTopKeys
        state.isLoadingAnalysis = false
    }
}

// MARK: - Server Info (supplementary)

private struct ServerInfoClusterNodeSelectedEntry: UIInventoryEntry {
    let id = "serverinfo-cluster-node-selected"
    let feature = "Server Info"
    let module = "ServerInfoView"
    let state = "Cluster server info with a specific node selected"
    let priority: ScreenshotPriority = .medium
    let notes = "Connected; cluster mode, selectedServerInfoNode set to first primary"
    let viewHierarchy = "TabContentView > WorkspaceView > ServerInfoView"

    func configure(state: ConnectionState, store: AppStore) {
        let connection = RedisConnectionConfig(
            name: "Analytics Cluster",
            mode: .cluster,
            host: "10.0.0.1",
            port: 7000,
            seedNodes: UIInventoryRegistry.clusterSeedNodes,
            environment: .production
        )
        UIInventoryRegistry.connect(state, view: .serverInfo, connection: connection)
        state.serverInfo = UIInventoryRegistry.sampleServerInfo
        state.clusterInfo = UIInventoryRegistry.sampleClusterInfo
        state.clusterNodes = UIInventoryRegistry.sampleClusterNodes
        state.selectedServerInfoNode = UIInventoryRegistry.sampleClusterNodes.first?.endpoint
    }
}

private struct ServerInfoNoModulesEntry: UIInventoryEntry {
    let id = "serverinfo-no-modules"
    let feature = "Server Info"
    let module = "ServerInfoView"
    let state = "Server info with no Redis modules loaded"
    let priority: ScreenshotPriority = .low
    let notes = "Connected; serverInfo populated, serverCapabilities empty"
    let viewHierarchy = "TabContentView > WorkspaceView > ServerInfoView"

    func configure(state: ConnectionState, store: AppStore) {
        UIInventoryRegistry.connect(state, view: .serverInfo)
        state.serverInfo = UIInventoryRegistry.sampleServerInfo
        state.serverCapabilities = []
    }
}
