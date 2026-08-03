# Redis Console

## Project Overview

macOS native Redis client with SSH tunnel support, written in Swift/SwiftUI.

## Architecture

### Entry Point

`Sources/RedisConsole/App/AppLifecycle.swift` — `@main struct RedisConsoleApp` 使用 `NSApplication` + `AppDelegate` 启动（非 SwiftUI App 生命周期）。`AppDelegate` 管理窗口、菜单栏、Tab 创建。

### State Management

- **AppStore** (`State/AppStore.swift`): `@Observable` 全局单例，管理 `RedisConnectionConfig` 列表。JSON 持久化到 `~/Library/Application Support/redis.console/connections.json`。
- **ConnectionState** (`State/ConnectionState.swift`): `@Observable` 每 tab 实例，持有所有连接级状态（连接、key 浏览、shell、profiler、slow log、analysis、server info、functions）。通过 `@Environment` 注入视图。
- **TabManager** (`App/TabManager.swift`): `@Observable` 管理 `ConnectionState[]` 集合。

### Networking — Redis Protocol

- **RedisClient** (`Redis/Client/RedisClient.swift`): 基于 `NWConnection` (Network.framework) 的自定义 Redis 客户端。支持 RESP2/RESP3 自动协商。使用 `Mutex` 保护状态，`DispatchQueue` 串行处理 I/O。`@Sendable` 设计。
- **RedisClusterClient** (`Redis/Client/RedisClusterClient.swift`): 多节点 Cluster 客户端，实现 `RedisSession` 协议。
- **RedisSession** (`Redis/Client/RedisSession.swift`): 协议抽象，`RedisClient` 和 `RedisClusterClient` 均遵循。
- **RESPParser** (`Redis/RESP/RESPParser.swift`): 自定义 RESP2/RESP3 解析器（无第三方依赖）。
- **RESPEncoder** (同文件): 命令编码。

### Networking — SSH Tunnel

- **SSHTunnel** (`SSH/SSHTunnel.swift`): 基于 `NIOSSH` + `NIOTransportServices` 的 SSH 隧道。端口转发到本地。
- **SSHClusterTunnelManager** (`SSH/SSHClusterTunnelManager.swift`): 为 Cluster 模式管理多个 SSH 隧道。`actor` 实现 `RedisClusterEndpointResolver`。
- **SSHKeyParsing** (`SSH/SSHKeyParsing.swift`): SSH 密钥解析。
- Vendor 目录包含 `swift-nio-ssh` 子模块。

### Models

- **RedisConnectionConfig** (`Models/Connection/ConnectionModels.swift`): 连接配置，支持 Standalone/Cluster 模式、SSH、TLS、环境标签（Development/Production）。
- **RedisKeyEntry** (`Models/Browser/RedisKeyModels.swift`): `@Observable` class，key 条目。附带 `KeyNamespaceTree` 命名空间分组逻辑。
- 其他 Models 文件按功能模块拆分：`ProfilerModels`, `FunctionModels`, `SlowLogModels`, `ShellHistoryEntry`, `DatabaseAnalysisModels`, `Navigation`。

### UI Architecture

- **ContentView** (`UI/Root/ContentView.swift`): `TabContentView` 使用 `HSplitView` 分为侧边栏和工作区。连接前显示 `ConnectionHubSidebarView` + `ConnectionHubView`，连接后显示 `WorkspaceSidebarView` + `WorkspaceView`。
- **WorkspaceView** (`UI/Root/ContentView.swift`): 根据 `conn.currentView` 切换各工具视图（browser, functions, shell, profiler, slowLog, databaseAnalysis, serverInfo）。
- 每个工具视图在 `UI/` 下有自己的子目录：`Browser/`, `Connection/`, `KeyDetail/`, `Shell/`, `Tools/`。

### Theme / Design System

`Sources/RedisConsole/Theme/` 目录下：

- **AppColor**: 语义化颜色 token（`success`, `error`, `badgeBackground()`, `chartString` 等）。
- **AppFont**: 字体 token。
- **AppMetrics**: 间距（`AppSpacing`）、圆角（`AppRadius`）、尺寸（`AppSize`）token。
- **UIComponents**: 可复用组件（`Badge`, `ErrorBanner`, `Card`, `FilterField`, `RefreshControl`, `PrimaryButtonStyle`, `SecondaryButtonStyle`, `ProductionConfirmView` 等）。

### Key Dependencies

- **无 Swift Package Manager 依赖** — 所有 Redis 协议解析、SSH 隧道均为自实现。
- Vendor 内嵌 `swift-nio-ssh`（NIOSSH + NIOTransportServices）。
- 系统框架：`Network.framework`, `AppKit`, `SwiftUI`, `Observation`, `CryptoKit`, `Security`, `OSLog`。

### Code Conventions

- 使用 `@Observable` 宏（iOS 17+ / macOS 14+），**不使用** `@Published` 或 `ObservableObject`。
- 使用 `@MainActor` 注解 UI 相关类型。
- 并发原语：`Mutex`（来自 `Synchronization` 框架）、`actor`、`CheckedContinuation`。`DispatchQueue` 仅用于 `RedisClient` 的 I/O 串行化。
- 没有 Combine 依赖。
- 网络层类型标记 `@Sendable`。
- 错误类型：`RedisError` (enum, `LocalizedError`)。
- 生产环境确认：`ProductionConfirmView` 组件，要求输入关键词确认。

### Code Quality

- 遵循 `.swift-format` 和 `.swiftlint.yml` 配置。
- Lint: `just lint` / `just lint-fix`
- Format: `just format` / `just format-check`

### Git Workflow

- 提交信息：一句话，首字母大写，无 Conventional Commit 前缀。
- 示例：`Add delete menu to connection list`

### Build & Run

```bash
just lint          # swiftlint
just lint-fix      # swiftlint --fix
just format        # swift-format
just format-check  # swift-format lint
just build-release # xcodebuild release
just run           # build + open app
just install       # build + copy to ~/Applications
just clean         # rm -rf .build
```