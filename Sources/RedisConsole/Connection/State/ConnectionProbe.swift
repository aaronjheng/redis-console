import Foundation

// MARK: - Connection Probe

/// Outcome of a connection probe. Carries values, not display strings:
/// formatting stays in the view.
enum ConnectionProbeOutcome {
    case success(latencyMs: Double, reply: String?)
    case failure(message: String)
}

/// Standalone use case that verifies a connection config end to end:
/// SSH tunnel (when enabled), Redis connect, and a PING round trip.
///
/// Extracted from `ConnectionDetailView` so the view owns only form state
/// and result rendering. All tunnel/client resources are owned locally and
/// torn down in `run()`, so a probe can never leak into the tab's session.
struct ConnectionProbe {
    let config: RedisConnectionConfig

    func run() async -> ConnectionProbeOutcome {
        AppLogger.info(
            "test connection requested mode=\(config.mode.rawValue) redis=\(config.address) "
                + "sshEnabled=\(config.ssh.enabled) tlsEnabled=\(config.tls.enabled) "
                + "ssh=\(config.ssh.host):\(config.ssh.port) user=\(config.ssh.user)",
            category: "ConnectionTest"
        )
        var client: (any RedisSession)?
        var tunnel: SSHTunnel?
        var clusterTunnelManager: SSHClusterTunnelManager?
        defer {
            let manager = clusterTunnelManager
            client?.disconnect()
            tunnel?.stop()
            Task { await manager?.disconnect() }
        }

        var connectHost = config.host
        var connectPort = config.port
        var clusterEndpointResolver: (any RedisClusterEndpointResolver)?

        if config.ssh.enabled {
            let trimmedSSHHost = config.ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSSHUser = config.ssh.user.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveSSHUser = trimmedSSHUser.isEmpty ? NSUserName() : trimmedSSHUser
            guard !trimmedSSHHost.isEmpty else {
                AppLogger.error("test failed: empty ssh host", category: "ConnectionTest")
                return .failure(message: "SSH host is required")
            }

            switch config.mode {
            case .standalone:
                let createdTunnel = SSHTunnel()
                createdTunnel.setupTimeoutSeconds = config.ssh.setupTimeout
                createdTunnel.connectionAttemptTimeout = .seconds(Int64(config.ssh.connectionAttemptTimeout))
                createdTunnel.maxConnectionAttempts = config.ssh.maxConnectionAttempts
                createdTunnel.authTimeoutSeconds = config.ssh.authTimeout
                tunnel = createdTunnel
                do {
                    try await withTimeout(createdTunnel.setupTimeoutSeconds, context: "SSH tunnel setup") {
                        try await createdTunnel.start(
                            sshHost: trimmedSSHHost,
                            sshPort: config.ssh.port,
                            sshUser: trimmedSSHUser,
                            sshPassword: config.ssh.password.isEmpty ? nil : config.ssh.password,
                            privateKeyPath: config.ssh.privateKeyPath.isEmpty ? nil : config.ssh.privateKeyPath,
                            remoteHost: config.host,
                            remotePort: config.port,
                            mode: config.ssh.mode
                        )
                    }
                    connectHost = "127.0.0.1"
                    connectPort = createdTunnel.localPort
                    AppLogger.info(
                        "test ssh tunnel ready mode=\(createdTunnel.mode.rawValue) local=127.0.0.1:\(connectPort)",
                        category: "ConnectionTest"
                    )
                } catch {
                    AppLogger.error("test ssh tunnel failed error=\(error)", category: "ConnectionTest")
                    return .failure(message: "SSH tunnel: \(error.localizedDescription)")
                }
            case .cluster:
                let manager = SSHClusterTunnelManager(ssh: config.ssh)
                clusterTunnelManager = manager
                clusterEndpointResolver = manager
                AppLogger.info(
                    "test cluster ssh tunnel manager ready ssh=\(trimmedSSHHost):\(config.ssh.port) user=\(effectiveSSHUser)",
                    category: "ConnectionTest"
                )
            }
        }

        let createdClient: any RedisSession
        switch config.mode {
        case .standalone:
            createdClient = RedisClient(
                host: connectHost,
                port: connectPort,
                username: config.username.isEmpty ? nil : config.username,
                password: config.password.isEmpty ? nil : config.password,
                tlsEnabled: config.tls.enabled,
                verifyServerCertificate: config.tls.verifyServerCertificate,
                caCertificatePath: config.tls.caCertificatePath,
                clientCertificatePath: config.tls.clientCertificatePath,
                clientKeyPath: config.tls.clientKeyPath,
                connectionTimeout: config.connectionTimeout
            )
        case .cluster:
            createdClient = RedisClusterClient(
                seedNodes: [RedisEndpoint(host: connectHost, port: connectPort)],
                username: config.username.isEmpty ? nil : config.username,
                password: config.password.isEmpty ? nil : config.password,
                tlsEnabled: config.tls.enabled,
                verifyServerCertificate: config.tls.verifyServerCertificate,
                caCertificatePath: config.tls.caCertificatePath,
                clientCertificatePath: config.tls.clientCertificatePath,
                clientKeyPath: config.tls.clientKeyPath,
                connectionTimeout: config.connectionTimeout,
                endpointResolver: clusterEndpointResolver
            )
        }
        client = createdClient
        do {
            try await withTimeout(config.connectionTimeout, context: "Redis connection") {
                try await createdClient.connect()
            }
            let start = Date()
            let pong = try await withTimeout(config.pingTimeout, context: "Redis PING") {
                try await createdClient.send("PING")
            }
            if case .error(let message) = pong {
                throw RedisError.commandError(message)
            }
            let elapsed = Date().timeIntervalSince(start) * 1000
            AppLogger.info("test succeeded result=\(pong.string ?? "PONG") elapsed=\(elapsed)ms", category: "ConnectionTest")
            return .success(latencyMs: elapsed, reply: pong.string)
        } catch {
            AppLogger.error("test redis failed error=\(error)", category: "ConnectionTest")
            return .failure(message: error.localizedDescription)
        }
    }
}
