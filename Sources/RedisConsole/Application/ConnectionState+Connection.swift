import Foundation

extension ConnectionState {
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
                        try await withTimeout(SSHTunnel.setupTimeoutSeconds, context: "SSH tunnel setup") {
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
        scanCursor = "0"
        hasMoreKeys = true
        keyTotalCount = nil
        keyScannedCount = 0
        keyScanIterationCount = 0
        keyScanLimitReached = false
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
        scanCursor = "0"
        hasMoreKeys = true
        keyTotalCount = nil
        keyScannedCount = 0
        keyScanIterationCount = 0
        keyScanLimitReached = false
        keyDetail = ""
        serverInfo = [:]
        serverCapabilities = []
        clusterInfo = [:]
        clusterNodes = []
        selectedServerInfoNode = nil
        shellHistory = []
    }
}
