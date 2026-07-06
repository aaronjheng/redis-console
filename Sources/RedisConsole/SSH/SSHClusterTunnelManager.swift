import Foundation

actor SSHClusterTunnelManager: RedisClusterEndpointResolver {
    private let sshHost: String
    private let sshPort: UInt16
    private let sshUser: String
    private let sshPassword: String?
    private let privateKeyPath: String?
    private let setupTimeout: TimeInterval
    private var tunnels: [RedisEndpoint: SSHTunnel] = [:]
    private var generation = 0

    init(ssh: SSHConfig) {
        sshHost = ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
        sshPort = ssh.port

        let trimmedUser = ssh.user.trimmingCharacters(in: .whitespacesAndNewlines)
        sshUser = trimmedUser.isEmpty ? NSUserName() : trimmedUser
        sshPassword = ssh.password.isEmpty ? nil : ssh.password
        privateKeyPath = ssh.privateKeyPath.isEmpty ? nil : ssh.privateKeyPath
        setupTimeout = ssh.setupTimeout
    }

    func clientEndpoint(for endpoint: RedisEndpoint) async throws -> RedisEndpoint {
        guard !sshHost.isEmpty else {
            throw SSHTunnelError.connectionFailed("SSH host is required")
        }

        if let tunnel = tunnels[endpoint], tunnel.isRunning {
            return localEndpoint(for: tunnel)
        }

        let startGeneration = generation
        let tunnel = SSHTunnel()
        tunnel.setupTimeoutSeconds = setupTimeout
        let configuredSSHHost = sshHost
        let configuredSSHPort = sshPort
        let configuredSSHUser = sshUser
        let configuredSSHPassword = sshPassword
        let configuredPrivateKeyPath = privateKeyPath
        AppLogger.info(
            "starting cluster ssh tunnel ssh=\(configuredSSHHost):\(configuredSSHPort) "
                + "user=\(configuredSSHUser) remote=\(endpoint.address)",
            category: "SSHTunnel"
        )

        do {
            try await withTimeout(setupTimeout, context: "SSH tunnel setup") {
                try await tunnel.start(
                    sshHost: configuredSSHHost,
                    sshPort: configuredSSHPort,
                    sshUser: configuredSSHUser,
                    sshPassword: configuredSSHPassword,
                    privateKeyPath: configuredPrivateKeyPath,
                    remoteHost: endpoint.host,
                    remotePort: endpoint.port
                )
            }
            try Task.checkCancellation()
        } catch {
            tunnel.stop()
            throw error
        }

        guard startGeneration == generation else {
            tunnel.stop()
            throw RedisError.notConnected
        }

        if let existingTunnel = tunnels[endpoint], existingTunnel.isRunning {
            tunnel.stop()
            return localEndpoint(for: existingTunnel)
        }

        tunnels[endpoint] = tunnel
        let localEndpoint = localEndpoint(for: tunnel)
        AppLogger.info(
            "cluster ssh tunnel ready remote=\(endpoint.address) local=\(localEndpoint.address)",
            category: "SSHTunnel"
        )
        return localEndpoint
    }

    func disconnect() async {
        generation += 1
        let activeTunnels = Array(tunnels.values)
        tunnels.removeAll()

        for tunnel in activeTunnels {
            tunnel.stop()
        }
    }

    private func localEndpoint(for tunnel: SSHTunnel) -> RedisEndpoint {
        RedisEndpoint(host: "127.0.0.1", port: tunnel.localPort)
    }
}
