import Foundation
import SwiftUI

// MARK: - Connection Detail View

struct ConnectionDetailView: View {
    @Environment(ConnectionState.self) private var conn
    @Environment(AppStore.self) private var store

    @State private var name = ""
    @State private var connectionMode: RedisConnectionMode = .standalone
    @State private var host = ""
    @State private var port: UInt16 = 6379
    @State private var username = ""
    @State private var password = ""
    @State private var testResult: String?
    @State private var isTesting = false

    @State private var ssh = SSHConfig()
    @State private var tls = TLSConfig()
    @State private var environment: ConnectionEnvironment = .unspecified
    @State private var uriInput = ""
    @State private var isCreatingNew = false
    @State private var cachedConfig: RedisConnectionConfig?
    @State private var connectionTimeout: TimeInterval = 10
    @State private var pingTimeout: TimeInterval = 5

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
                                    connectionMode = config.mode
                                    host = config.host
                                    port = config.port
                                    username = config.username
                                    password = config.password
                                    tls = config.tls
                                    uriInput = ""
                                }
                            }
                            .disabled(uriInput.isEmpty)
                        }
                    }

                    Section(isNew ? "New Connection" : "Connection") {
                        TextField("Name", text: $name)
                        Picker("Mode", selection: $connectionMode) {
                            ForEach(RedisConnectionMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
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

                    Section("TLS/SSL") {
                        Toggle("Enable TLS", isOn: $tls.enabled)
                        if tls.enabled {
                            Toggle("Verify Server Certificate", isOn: $tls.verifyServerCertificate)
                            TextField("CA Certificate Path (optional)", text: $tls.caCertificatePath)
                            TextField("Client Certificate Path (optional)", text: $tls.clientCertificatePath)
                            TextField("Client Key Path (optional)", text: $tls.clientKeyPath)
                            Text("For mTLS, provide both client certificate and key")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Environment") {
                        Picker("Environment", selection: $environment) {
                            ForEach(ConnectionEnvironment.allCases, id: \.self) { env in
                                Label(env.rawValue, systemImage: env.icon)
                                    .foregroundStyle(env.color)
                                    .tag(env)
                            }
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

                    testResultView
                } else if let config = editingConfig {
                    Button("Save") {
                        var updated = config
                        updated.name = name
                        updated.mode = connectionMode
                        updated.host = host
                        updated.port = port
                        updated.seedNodes = []
                        updated.username = username
                        updated.password = password
                        updated.ssh = ssh
                        updated.tls = tls
                        updated.environment = environment
                        store.updateConnection(updated)
                        conn.selectedConnection = updated
                    }
                    .disabled(host.isEmpty)

                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(host.isEmpty || isTesting || (ssh.enabled && ssh.host.isEmpty))

                    testResultView
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
            .padding(16)
        }
    }

    private func createConfig() -> RedisConnectionConfig {
        var config = RedisConnectionConfig(
            name: name.isEmpty ? host : name,
            mode: connectionMode,
            host: host,
            port: port,
            seedNodes: [],
            username: username
        )
        config.password = password
        config.ssh = ssh
        config.tls = tls
        config.environment = environment
        config.connectionTimeout = connectionTimeout
        config.pingTimeout = pingTimeout
        return config
    }

    private func loadConfig(from panel: RightPanel) {
        testResult = nil
        switch panel {
        case .editConnection(let config):
            isCreatingNew = false
            cachedConfig = config
            name = config.name
            connectionMode = config.mode
            host = config.host
            port = config.port
            username = config.username
            password = config.password
            ssh = config.ssh
            tls = config.tls
            environment = config.environment
            connectionTimeout = config.connectionTimeout
            pingTimeout = config.pingTimeout
        case .newConnection:
            isCreatingNew = true
            cachedConfig = nil
            name = "localhost"
            connectionMode = .standalone
            host = "127.0.0.1"
            port = 6379
            username = ""
            password = ""
            ssh = SSHConfig()
            tls = TLSConfig()
            environment = .unspecified
        default: break
        }
    }

    @ViewBuilder
    private var testResultView: some View {
        if let result = testResult {
            HStack(spacing: 4) {
                Image(systemName: result.hasPrefix("OK") ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.hasPrefix("OK") ? .green : .red)
                Text(result)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func testConnection() async {
        AppLogger.info(
            "test connection requested mode=\(connectionMode.rawValue) redis=\(host):\(port) "
                + "sshEnabled=\(ssh.enabled) tlsEnabled=\(tls.enabled) "
                + "ssh=\(ssh.host):\(ssh.port) user=\(ssh.user)",
            category: "ConnectionTest"
        )
        isTesting = true
        testResult = nil
        var client: (any RedisSession)?
        var tunnel: SSHTunnel?
        var clusterTunnelManager: SSHClusterTunnelManager?
        defer {
            let manager = clusterTunnelManager
            client?.disconnect()
            tunnel?.stop()
            Task { await manager?.disconnect() }
            isTesting = false
        }

        var connectHost = host
        var connectPort = port
        var clusterEndpointResolver: (any RedisClusterEndpointResolver)?

        if ssh.enabled {
            let trimmedSSHHost = ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSSHUser = ssh.user.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveSSHUser = trimmedSSHUser.isEmpty ? NSUserName() : trimmedSSHUser
            guard !trimmedSSHHost.isEmpty else {
                testResult = "Failed — SSH host is required"
                AppLogger.error("test failed: empty ssh host", category: "ConnectionTest")
                return
            }

            switch connectionMode {
            case .standalone:
                let createdTunnel = SSHTunnel()
                createdTunnel.setupTimeoutSeconds = ssh.setupTimeout
                createdTunnel.connectionAttemptTimeout = .seconds(Int64(ssh.connectionAttemptTimeout))
                createdTunnel.maxConnectionAttempts = ssh.maxConnectionAttempts
                createdTunnel.authTimeoutSeconds = ssh.authTimeout
                tunnel = createdTunnel
                do {
                    try await withTimeout(createdTunnel.setupTimeoutSeconds, context: "SSH tunnel setup") {
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
            case .cluster:
                let manager = SSHClusterTunnelManager(ssh: ssh)
                clusterTunnelManager = manager
                clusterEndpointResolver = manager
                AppLogger.info(
                    "test cluster ssh tunnel manager ready ssh=\(trimmedSSHHost):\(ssh.port) user=\(effectiveSSHUser)",
                    category: "ConnectionTest"
                )
            }
        }

        let createdClient: any RedisSession
        switch connectionMode {
        case .standalone:
            createdClient = RedisClient(
                host: connectHost,
                port: connectPort,
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password,
                tlsEnabled: tls.enabled,
                verifyServerCertificate: tls.verifyServerCertificate,
                caCertificatePath: tls.caCertificatePath,
                clientCertificatePath: tls.clientCertificatePath,
                clientKeyPath: tls.clientKeyPath,
                connectionTimeout: connectionTimeout
            )
        case .cluster:
            createdClient = RedisClusterClient(
                seedNodes: [RedisEndpoint(host: connectHost, port: connectPort)],
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password,
                tlsEnabled: tls.enabled,
                verifyServerCertificate: tls.verifyServerCertificate,
                caCertificatePath: tls.caCertificatePath,
                clientCertificatePath: tls.clientCertificatePath,
                clientKeyPath: tls.clientKeyPath,
                connectionTimeout: connectionTimeout,
                endpointResolver: clusterEndpointResolver
            )
        }
        client = createdClient
        do {
            try await withTimeout(connectionTimeout, context: "Redis connection") {
                try await createdClient.connect()
            }
            let start = Date()
            let pong = try await withTimeout(pingTimeout, context: "Redis PING") {
                try await createdClient.send("PING")
            }
            if case .error(let message) = pong {
                throw RedisError.commandError(message)
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
