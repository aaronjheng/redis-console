import AppKit
import Foundation
import Observation

// MARK: - Connection State (Per-tab state)

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
@Observable
class ConnectionState {
    let id = UUID()
    @ObservationIgnored
    weak var window: NSWindow?

    var activeClient: (any RedisSession)?
    var isConnecting = false
    var connectionError: String?
    var selectedConnection: RedisConnectionConfig?
    var pendingConnection: RedisConnectionConfig?

    var keys: [RedisKeyEntry] = []
    var selectedKey: RedisKeyEntry?
    var keyDetail: String = ""
    var keyDetailRows: [(String, String)] = []
    var keyType: String = ""
    var valueSize: Int?
    var keyDetailLength: Int?
    var keyDetailError: String?
    var keyDetailOffset = 0
    var keyDetailCursor: String = "0"
    var keyDetailHasMoreRows = false
    var keyDetailSearchText = ""
    var keyDetailZSetOrder: KeyDetailZSetOrder = .ascending
    var isLoadingKeys = false
    var isLoadingDetail = false
    var scanCursor: String = "0"
    var hasMoreKeys = true
    var keyFilter: String = "*"
    var keyTypeFilter: String = "" {
        didSet { saveBrowserPreferences() }
    }
    var keyScanCount = 500
    var keyTotalCount: Int?
    var keyScannedCount = 0
    var keyScanIterationCount = 0
    var keyScanLimitReached = false
    var isNamespaceGroupingEnabled = false {
        didSet { saveBrowserPreferences() }
    }
    var namespaceSeparator = ":"
    var stringValueFormat: StringValueFormat = .json {
        didSet { saveBrowserPreferences() }
    }
    var keyDetailLastRefreshedAt: Date?

    var shellHistory: [ShellHistoryEntry] = []
    var shellInput: String = ""
    var shellClient: (any RedisSession)?

    var slowLogEntries: [SlowLogEntry] = []
    var slowLogConfig = SlowLogConfig()
    var isLoadingSlowLog = false
    var slowLogError: String?
    var slowLogFetchCount = 128

    var analysis: DatabaseAnalysis?
    var isLoadingAnalysis = false
    var analysisError: String?
    var analysisTaskHandle: Task<Void, Never>?
    /// The off-main-actor worker that performs the actual analysis work. Held
    /// separately so cancellation (via `cancelAnalysis()`) reaches the worker's
    /// `try Task.checkCancellation()` checkpoints.
    var analysisTask: Task<DatabaseAnalysis, Error>?

    var profilerEntries: [RedisProfilerEntry] = []
    var profilerCapturedCount = 0
    var profilerError: String?
    var isProfilerRunning = false
    var isProfilerStarting = false

    var serverInfo: [String: [String: String]] = [:]
    var serverCapabilities: [RedisServerCapability] = []
    var clusterInfo: [String: String] = [:]
    var clusterNodes: [RedisClusterNodeSummary] = []
    var selectedServerInfoNode: RedisEndpoint?
    var isLoadingServerInfo = false

    var functionLibraries: [RedisFunctionLibrary] = []
    var isLoadingFunctions = false
    var functionsError: String?
    var selectedFunctionLibrary: RedisFunctionLibrary?

    var functionCallHistory: [RedisFunctionCallResult] = []
    var isCallingFunction = false

    var currentView: AppView = .browser
    var rightPanel: RightPanel = .welcome

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
    let shellHistoryLimit = 200
    static let browserPreferencesKey = "com.redisconsole.browserPreferences"

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
