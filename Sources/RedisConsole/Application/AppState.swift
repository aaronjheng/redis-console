import Foundation
import SwiftUI

// MARK: - Connection State (Per-tab state)

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

    var connectTask: Task<Void, Never>?
    var sshTunnel: SSHTunnel?
    var sshClusterTunnelManager: SSHClusterTunnelManager?
    var isScanningKeysRequest = false
    var pendingResetScan = false
    var profilerTask: Task<Void, Never>?
    var profilerMonitorClients: [RedisMonitorClient] = []
    var profilerMonitorTasks: RedisProfilerTaskBag?
    var profilerSSHTunnel: SSHTunnel?
    var profilerClusterTunnelManager: SSHClusterTunnelManager?
    var profilerGeneration = 0
    let profilerMaxEntries = 2_000
    let keyMetadataPipelineBatchSize = 50
    let keyDetailPageSize = 100
    let keyPatternScanIterationLimit = 1_000
    let bulkDeleteScanLimit = 20_000
    let bulkDeleteBatchSize = 100
    let shellHistoryLimit = 200
    static let browserPreferencesKey = "com.redisconsole.browserPreferences"
    static let shellHistoryKeyPrefix = "com.redisconsole.shellHistory."

    init() {
        loadBrowserPreferences()
    }

    var windowTitle: String {
        if let conn = selectedConnection {
            return conn.name
        }
        return "Redis Console"
    }

}
