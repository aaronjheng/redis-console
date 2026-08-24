# Redis Console

macOS native Redis client with SSH tunnel support, written in Swift/SwiftUI.

## Architecture

### Entry Point

`Sources/RedisConsole/App/AppLifecycle.swift` — `@main struct RedisConsoleApp` 使用 `NSApplication` + `AppDelegate` 启动（非 SwiftUI App 生命周期），管理窗口、菜单栏、Tab 创建。

### State Management

- **AppStore** (`State/AppStore.swift`): `@Observable` 全局单例，管理连接配置列表，JSON 持久化到 `~/Library/Application Support/redis.console/connections.json`。
- **ConnectionState** (`State/ConnectionState.swift`): `@Observable` 每 tab 实例，持有全部连接级状态，通过 `@Environment` 注入视图。
- **TabManager** (`App/TabManager.swift`): `@Observable` 管理 `ConnectionState[]` 集合。

### Networking

- **RedisClient** (`Redis/Client/RedisClient.swift`): 基于 `NWConnection` 的自定义客户端，RESP2/RESP3 自动协商，`DispatchQueue` 串行 I/O。
- **RedisClusterClient**: 多节点 Cluster 客户端，与 `RedisClient` 均实现 `RedisSession` 协议。
- **RESPParser / RESPEncoder** (`Redis/RESP/RESPParser.swift`): 自实现 RESP 编解码。
- **SSHTunnel / SSHClusterTunnelManager** (`SSH/`): 基于 NIOSSH 的端口转发隧道，后者以 `actor` 为 Cluster 管理多条隧道。
- Vendor 内嵌 `swift-nio-ssh` 子模块。

### Models

- **RedisConnectionConfig** (`Models/Connection/ConnectionModels.swift`): 连接配置（Standalone/Cluster、SSH、TLS、环境标签）。
- **RedisKeyEntry** (`Models/Browser/RedisKeyModels.swift`): key 条目，附带 `KeyNamespaceTree` 命名空间分组。
- 其余 model 按功能模块拆分在 `Models/` 下。

### UI

- **ContentView** (`UI/Root/ContentView.swift`): `HSplitView` 分侧边栏与工作区；连接前为 ConnectionHub，连接后 Workspace 按 `conn.currentView` 切换工具视图（browser、shell、profiler 等）。
- 工具视图子目录：`Browser/`, `Connection/`, `KeyDetail/`, `Shell/`, `Tools/`。

### Theme

`Sources/RedisConsole/Theme/`: `AppColor` / `AppFont` / `AppMetrics` 语义化 token 与 `UIComponents` 可复用组件。UI 一律使用这些 token，不硬编码颜色、字体和间距。

## Dependencies

Redis 协议与 SSH 隧道均自实现，无第三方网络库。SPM 仅引入 tree-sitter 系列（`swift-tree-sitter`、`tree-sitter-lua/json/bash`），用于 Lua 编辑器与 key 值 JSON 高亮，相关代码在 `UI/Tools/`。

## Code Conventions

- 使用 `@Observable` 宏（macOS 14+），不用 `@Published` / ObservableObject；无 Combine 依赖。
- UI 类型标注 `@MainActor`，网络层类型标记 `@Sendable`。
- 并发原语：`Mutex`、`actor`、`CheckedContinuation`；`DispatchQueue` 仅用于 `RedisClient` I/O。
- 错误类型统一为 `RedisError`（enum, `LocalizedError`）。
- 生产环境危险操作须经 `ProductionConfirmView` 输入关键词确认。

## Git Workflow

提交信息一句话，首字母大写，无 Conventional Commit 前缀，如 `Add delete menu to connection list`。

## Build & Run

遵循 `.swift-format` 与 `.swiftlint.yml` 配置。

```bash
just lint          # swiftlint
just lint-fix      # swiftlint --fix
just format        # swift-format
just format-check  # swift-format lint
just build         # xcodebuild release
just run           # build + open app
just install       # build + copy to ~/Applications
just clean         # rm -rf .build
```
