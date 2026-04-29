import AppKit
import SwiftUI

// MARK: - Tab Manager

@MainActor
class TabManager: ObservableObject {
    @Published var tabStates: [ConnectionState] = []

    func createTab() -> ConnectionState {
        let state = ConnectionState()
        tabStates.append(state)
        return state
    }

    func closeTab(_ state: ConnectionState) {
        state.disconnect()
        tabStates.removeAll { $0.id == state.id }
    }

    func tabIndex(for state: ConnectionState) -> Int? {
        tabStates.firstIndex(where: { $0.id == state.id })
    }
}

// MARK: - Window Delegate Manager

@MainActor
final class WindowDelegateManager {
    private var delegates: [ObjectIdentifier: WindowDelegate] = [:]
    private let lock = NSLock()

    func setDelegate(_ delegate: WindowDelegate, for window: NSWindow) {
        let id = ObjectIdentifier(window)
        lock.lock()
        defer { lock.unlock() }
        delegates[id] = delegate
    }

    func removeDelegate(for window: NSWindow) {
        let id = ObjectIdentifier(window)
        lock.lock()
        defer { lock.unlock() }
        delegates.removeValue(forKey: id)
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let tabManager = TabManager()
    private var stateToWindow: [UUID: NSWindow] = [:]
    private let tabShortcutLimit = 9
    private var tabRefreshScheduled = false
    private let delegateManager = WindowDelegateManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        buildMenuBar()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidUpdate(_:)),
            name: NSApplication.didUpdateNotification,
            object: nil
        )
        openNewTab()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func openNewTab() {
        let state = tabManager.createTab()
        createWindow(for: state)
    }

    @objc func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    @objc func newWindowForTab(_ sender: Any?) {
        openNewTab()
    }

    @objc func selectNextTab() {
        guard let tabGroup = NSApp.keyWindow?.tabGroup,
            let current = NSApp.keyWindow,
            let index = tabGroup.windows.firstIndex(of: current)
        else { return }
        let next = tabGroup.windows[(index + 1) % tabGroup.windows.count]
        next.makeKeyAndOrderFront(nil)
    }

    @objc func selectPreviousTab() {
        guard let tabGroup = NSApp.keyWindow?.tabGroup,
            let current = NSApp.keyWindow,
            let index = tabGroup.windows.firstIndex(of: current)
        else { return }
        let prev = tabGroup.windows[(index - 1 + tabGroup.windows.count) % tabGroup.windows.count]
        prev.makeKeyAndOrderFront(nil)
    }

    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        selectTab(at: sender.tag - 1)
    }

    private func createWindow(for state: ConnectionState) {
        let contentView = TabContentView()
            .environmentObject(state)
            .environmentObject(AppStore.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Redis Console"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView)
        window.collectionBehavior.insert(NSWindow.CollectionBehavior.fullScreenPrimary)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "RedisConsole"

        // Add as tab to existing window, or show as new window
        if let existingWindow = NSApp.keyWindow {
            existingWindow.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }

        stateToWindow[state.id] = window
        requestTabChromeRefresh()

        // Clean up when window closes
        let delegate = WindowDelegate { [weak self] in
            Task { @MainActor in
                self?.tabManager.closeTab(state)
                self?.stateToWindow.removeValue(forKey: state.id)
                self?.requestTabChromeRefresh()
            }
        }
        window.delegate = delegate
        delegateManager.setDelegate(delegate, for: window)
    }

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Redis Console",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Redis Console",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(openNewTab), keyEquivalent: "t")
        newTabItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(newTabItem)
        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeTabItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeTabItem)
        fileMenuItem.submenu = fileMenu

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        let nextTabItem = NSMenuItem(title: "Show Next Tab", action: #selector(selectNextTab), keyEquivalent: "→")
        nextTabItem.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(nextTabItem)
        let prevTabItem = NSMenuItem(title: "Show Previous Tab", action: #selector(selectPreviousTab), keyEquivalent: "←")
        prevTabItem.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(prevTabItem)
        windowMenu.addItem(.separator())
        for index in 1...tabShortcutLimit {
            let item = NSMenuItem(
                title: "Select Tab \(index)",
                action: #selector(selectTabByNumber(_:)),
                keyEquivalent: "\(index)"
            )
            item.tag = index
            item.keyEquivalentModifierMask = [.command]
            windowMenu.addItem(item)
        }
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let fsItem = NSMenuItem(title: "Enter Full Screen", action: #selector(toggleFullScreen), keyEquivalent: "f")
        fsItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fsItem)
        viewMenuItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func handleApplicationDidUpdate(_ notification: Notification) {
        requestTabChromeRefresh()
    }

    private func requestTabChromeRefresh() {
        guard !tabRefreshScheduled else { return }
        tabRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tabRefreshScheduled = false
            self.refreshTabChrome()
        }
    }

    private func refreshTabChrome() {
        var refreshedGroups = Set<ObjectIdentifier>()

        for window in stateToWindow.values {
            if let tabGroup = window.tabGroup {
                let groupID = ObjectIdentifier(tabGroup)
                guard refreshedGroups.insert(groupID).inserted else { continue }
                syncTabAccessories(in: tabGroup.windows)
            } else {
                syncTabAccessories(in: [window])
            }
        }
    }

    private func selectTab(at index: Int) {
        guard index >= 0 else { return }

        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
        if let tabGroup = targetWindow?.tabGroup, index < tabGroup.windows.count {
            tabGroup.windows[index].makeKeyAndOrderFront(nil)
        } else if index == 0 {
            targetWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func syncTabAccessories(in windows: [NSWindow]) {
        for (index, window) in windows.enumerated() {
            if windows.count > 1, index < tabShortcutLimit {
                window.tab.accessoryView = makeTabAccessoryView(text: "⌘\(index + 1)")
            } else {
                window.tab.accessoryView = nil
            }
        }
    }

    private func makeTabAccessoryView(text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.drawsBackground = false
        label.isBezeled = false
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            label.heightAnchor.constraint(equalToConstant: 16),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])

        return container
    }
}

// MARK: - Window Delegate

class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - App Entry Point

@main
struct RedisConsoleApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - Tab Content View (per-tab)

struct TabContentView: View {
    @EnvironmentObject var conn: ConnectionState
    @EnvironmentObject var store: AppStore
    @State private var cachedRightPanel: RightPanel = .welcome

    var body: some View {
        HSplitView {
            TabSidebarView()
                .frame(minWidth: 220, maxWidth: 280)

            if conn.activeClient?.isConnected == true {
                switch conn.currentView {
                case .browser: BrowserView()
                case .shell: ShellView()
                case .slowlog: SlowLogView()
                case .serverInfo: ServerInfoView()
                }
            } else if conn.isConnecting {
                ConnectingView()
            } else {
                switch cachedRightPanel {
                case .editConnection, .newConnection:
                    ConnectionDetailView()
                        .frame(minWidth: 400)
                case .welcome:
                    WelcomeView()
                }
            }
        }
        .background(WindowTitleUpdater().environmentObject(conn))
        .onChange(of: conn.rightPanel) { _, newValue in
            cachedRightPanel = newValue
        }
        .onAppear {
            cachedRightPanel = conn.rightPanel
        }
    }
}

// MARK: - Window Title Updater

struct WindowTitleUpdater: NSViewRepresentable {
    @EnvironmentObject var conn: ConnectionState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        conn.window = window
        if let client = conn.activeClient, client.isConnected, let selectedConnection = conn.selectedConnection {
            window.title = "\(selectedConnection.name) — \(selectedConnection.address)"
        } else {
            window.title = "Redis Console"
        }
    }
}

// MARK: - Tab Sidebar

struct TabSidebarView: View {
    @EnvironmentObject var conn: ConnectionState
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if conn.activeClient?.isConnected == true {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        if let selectedConnection = conn.selectedConnection {
                            Text(selectedConnection.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(selectedConnection.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        conn.disconnect()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Disconnect")
                }
                .padding()

                Divider()

                List(selection: $conn.currentView) {
                    Section("Tools") {
                        ForEach(AppView.allCases, id: \.self) { view in
                            Label(view.rawValue, systemImage: view.icon)
                                .tag(view)
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                HStack {
                    Text("Connections")
                        .font(.headline)
                    Spacer()
                    Button {
                        exportConnections(store.connections)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help("Export All Connections")
                    Button {
                        importConnections()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .help("Import Connections")
                    Button {
                        conn.selectedConnection = nil
                        conn.rightPanel = .newConnection
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .padding()

                Divider()

                List(
                    selection: Binding(
                        get: { conn.selectedConnection },
                        set: {
                            conn.selectedConnection = $0
                            if let selectedConnection = $0 {
                                conn.rightPanel = .editConnection(selectedConnection)
                            }
                        }
                    )
                ) {
                    ForEach(store.connections) { config in
                        ConnectionRow(config: config, isConnected: false)
                            .tag(config)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .overlay(
                                DoubleClickHandler {
                                    Task { await conn.connect(to: config) }
                                }
                            )
                            .contextMenu {
                                Button("Duplicate") {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(config.address, forType: .string)
                                }
                                Button("Delete") {
                                    store.deleteConnection(config)
                                    if conn.selectedConnection?.id == config.id {
                                        conn.selectedConnection = nil
                                        conn.rightPanel = .welcome
                                    }
                                }
                                Divider()
                                Button("Copy URI") {
                                    var uri = "redis://"
                                    if !config.username.isEmpty || !config.password.isEmpty {
                                        if !config.username.isEmpty {
                                            uri += config.username
                                        }
                                        if !config.password.isEmpty {
                                            uri += ":\(config.password)"
                                        }
                                        uri += "@"
                                    }
                                    uri += "\(config.host):\(config.port)"
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(uri, forType: .string)
                                }
                                Divider()
                                Button("Export...") {
                                    exportConnections([config])
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func exportConnections(_ configs: [RedisConnectionConfig]) {
        guard let data = store.exportConnections(configs) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue =
            configs.count == 1
            ? "\(configs[0].name).json"
            : "redis-connections.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    private func importConnections() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url),
                let configs = store.importConnections(from: data)
            else { return }
            store.addImportedConnections(configs)
        }
    }
}

// MARK: - Connecting View

struct ConnectingView: View {
    @EnvironmentObject var conn: ConnectionState
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isPulsing ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isPulsing)
            }
            .onAppear { isPulsing = true }

            if let pending = conn.pendingConnection {
                Text("Connecting to \(pending.name)")
                    .font(.title3)
                    .bold()
                Text(pending.host + ":" + String(pending.port))
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
            Button("Cancel") { conn.cancelConnection() }
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Redis Console")
                .font(.title)
            Text("Select a connection or click + to add one")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Connection Detail View

struct ConnectionDetailView: View {
    @EnvironmentObject var conn: ConnectionState
    @EnvironmentObject var store: AppStore

    @State private var name = ""
    @State private var host = ""
    @State private var port: UInt16 = 6379
    @State private var username = ""
    @State private var password = ""
    @State private var testResult: String?
    @State private var isTesting = false

    @State private var ssh = SSHConfig()
    @State private var uriInput = ""
    @State private var isCreatingNew = false
    @State private var cachedConfig: RedisConnectionConfig?

    private var editingConfig: RedisConnectionConfig? {
        cachedConfig
    }
    private var isNew: Bool {
        isCreatingNew
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Form {
                    Section("Import from URI") {
                        HStack {
                            TextField("URI", text: $uriInput)
                            Button("Import") {
                                if let config = RedisConnectionConfig.parseURI(uriInput) {
                                    name = config.name
                                    host = config.host
                                    port = config.port
                                    username = config.username
                                    password = config.password
                                    uriInput = ""
                                }
                            }
                            .disabled(uriInput.isEmpty)
                        }
                    }

                    Section(isNew ? "New Connection" : "Connection") {
                        TextField("Name", text: $name)
                        TextField("Host", text: $host)
                        HStack {
                            Text("Port")
                            Spacer()
                            TextField(
                                "",
                                text: Binding(
                                    get: { "\(port)" },
                                    set: {
                                        if let parsedPort = UInt16($0) {
                                            port = parsedPort
                                        }
                                    }
                                )
                            )
                            .frame(width: 80)
                        }
                        TextField("Username", text: $username)
                        SecureField("Password", text: $password)
                    }

                    Section("SSH Tunnel") {
                        Toggle("Enable SSH Tunnel", isOn: $ssh.enabled)
                        if ssh.enabled {
                            TextField("Host", text: $ssh.host)
                            HStack {
                                Text("Port")
                                Spacer()
                                TextField(
                                    "",
                                    text: Binding(
                                        get: { "\(ssh.port)" },
                                        set: {
                                            if let parsedPort = UInt16($0) {
                                                ssh.port = parsedPort
                                            }
                                        }
                                    )
                                )
                                .frame(width: 80)
                            }
                            TextField("User (optional)", text: $ssh.user)
                            SecureField("Password (optional)", text: $ssh.password)
                            TextField("Private Key Path (optional)", text: $ssh.privateKeyPath)
                            Text("Provide a password or a private key file path")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .onChange(of: conn.rightPanel) { _, newValue in
                loadConfig(from: newValue)
            }
            .onAppear {
                loadConfig(from: conn.rightPanel)
            }

            Divider()

            if let result = testResult {
                HStack {
                    Image(systemName: result.hasPrefix("OK") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.hasPrefix("OK") ? .green : .red)
                    Text(result)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            HStack {
                if isNew {
                    Button("Save") {
                        let config = createConfig()
                        store.addConnection(config)
                        conn.selectedConnection = config
                        conn.rightPanel = .editConnection(config)
                    }
                    .disabled(host.isEmpty)

                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(host.isEmpty || isTesting || (ssh.enabled && ssh.host.isEmpty))
                } else if let config = editingConfig {
                    Button("Save") {
                        var updated = config
                        updated.name = name
                        updated.host = host
                        updated.port = port
                        updated.username = username
                        updated.password = password
                        updated.ssh = ssh
                        store.updateConnection(updated)
                        conn.selectedConnection = updated
                    }
                    .disabled(host.isEmpty)

                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(host.isEmpty || isTesting || (ssh.enabled && ssh.host.isEmpty))
                }

                Spacer()

                Button("Connect") {
                    let config = createConfig()
                    if let existing = editingConfig {
                        var temp = config
                        temp.id = existing.id
                        Task { await conn.connect(to: temp) }
                    } else {
                        store.addConnection(config)
                        Task { await conn.connect(to: config) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty || (ssh.enabled && ssh.host.isEmpty))
            }
            .padding()
        }
    }

    private func createConfig() -> RedisConnectionConfig {
        var config = RedisConnectionConfig(
            name: name.isEmpty ? host : name,
            host: host,
            port: port,
            username: username
        )
        config.password = password
        config.ssh = ssh
        return config
    }

    private func loadConfig(from panel: RightPanel) {
        testResult = nil
        switch panel {
        case .editConnection(let config):
            isCreatingNew = false
            cachedConfig = config
            name = config.name
            host = config.host
            port = config.port
            username = config.username
            password = config.password
            ssh = config.ssh
        case .newConnection:
            isCreatingNew = true
            cachedConfig = nil
            name = "localhost"
            host = "127.0.0.1"
            port = 6379
            username = ""
            password = ""
            ssh = SSHConfig()
        default: break
        }
    }

    func testConnection() async {
        AppLogger.info(
            "test connection requested redis=\(host):\(port) sshEnabled=\(ssh.enabled) ssh=\(ssh.host):\(ssh.port) user=\(ssh.user)",
            category: "ConnectionTest"
        )
        isTesting = true
        testResult = nil
        var client: RedisClient?
        var tunnel: SSHTunnel?
        defer {
            client?.disconnect()
            tunnel?.stop()
            isTesting = false
        }

        var connectHost = host
        var connectPort = port

        if ssh.enabled {
            let trimmedSSHHost = ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSSHUser = ssh.user.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveSSHUser = trimmedSSHUser.isEmpty ? NSUserName() : trimmedSSHUser
            guard !trimmedSSHHost.isEmpty else {
                testResult = "Failed — SSH host is required"
                AppLogger.error("test failed: empty ssh host", category: "ConnectionTest")
                return
            }

            let createdTunnel = SSHTunnel()
            tunnel = createdTunnel
            do {
                try await withTimeout(12, context: "SSH tunnel setup") {
                    try await createdTunnel.start(
                        sshHost: trimmedSSHHost,
                        sshPort: ssh.port,
                        sshUser: effectiveSSHUser,
                        sshPassword: ssh.password.isEmpty ? nil : ssh.password,
                        privateKeyPath: ssh.privateKeyPath.isEmpty ? nil : ssh.privateKeyPath,
                        remoteHost: host,
                        remotePort: port
                    )
                }
                connectHost = "127.0.0.1"
                connectPort = createdTunnel.localPort
                AppLogger.info(
                    "test ssh tunnel ready mode=\(createdTunnel.mode.rawValue) local=127.0.0.1:\(connectPort)",
                    category: "ConnectionTest"
                )
            } catch {
                testResult = "Failed — SSH tunnel: \(error.localizedDescription)"
                AppLogger.error("test ssh tunnel failed error=\(error)", category: "ConnectionTest")
                return
            }
        }

        let createdClient = RedisClient(host: connectHost, port: connectPort, password: password.isEmpty ? nil : password)
        client = createdClient
        do {
            try await withTimeout(10, context: "Redis connection") {
                try await createdClient.connect()
            }
            let start = Date()
            let pong = try await withTimeout(5, context: "Redis PING") {
                try await createdClient.send("PING")
            }
            let elapsed = Date().timeIntervalSince(start) * 1000
            testResult = "OK — \(pong.string ?? "PONG") (\(String(format: "%.2f", elapsed)) ms)"
            AppLogger.info("test succeeded result=\(pong.string ?? "PONG") elapsed=\(elapsed)ms", category: "ConnectionTest")
        } catch {
            testResult = "Failed — \(error.localizedDescription)"
            AppLogger.error("test redis failed error=\(error)", category: "ConnectionTest")
        }
    }
}

// MARK: - Connection Row

struct ConnectionRow: View {
    let config: RedisConnectionConfig
    let isConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(config.name)
                .font(.body)
            Text(config.address)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Double Click Handler

struct DoubleClickHandler: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DoubleClickView {
        let view = DoubleClickView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DoubleClickView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

class DoubleClickView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }
}
