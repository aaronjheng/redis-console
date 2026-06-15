import Foundation

extension ConnectionState {
    // MARK: - Profiler

    func startProfiler() {
        guard !isProfilerRunning && !isProfilerStarting else { return }
        guard let config = selectedConnection else {
            profilerError = "Connect to a Redis server before starting the profiler."
            return
        }

        profilerGeneration += 1
        let generation = profilerGeneration
        cancelProfilerResources()
        profilerError = nil
        isProfilerStarting = true

        profilerTask = Task { @MainActor in
            await runProfiler(config: config, generation: generation)
        }
    }

    func stopProfiler(clearEntries: Bool = false) {
        profilerGeneration += 1
        cancelProfilerResources()
        isProfilerRunning = false
        isProfilerStarting = false

        if clearEntries {
            clearProfiler()
        }
    }

    func clearProfiler() {
        profilerEntries = []
        profilerCapturedCount = 0
        profilerError = nil
    }

    private func cancelProfilerResources() {
        profilerTask?.cancel()
        profilerTask = nil

        profilerMonitorTasks?.cancelAll()
        profilerMonitorTasks = nil

        for client in profilerMonitorClients {
            client.disconnect()
        }
        profilerMonitorClients = []

        profilerSSHTunnel?.stop()
        profilerSSHTunnel = nil

        let clusterTunnelManager = profilerClusterTunnelManager
        profilerClusterTunnelManager = nil
        Task {
            await clusterTunnelManager?.disconnect()
        }
    }

    private func runProfiler(config: RedisConnectionConfig, generation: Int) async {
        var monitorClients: [RedisMonitorClient] = []
        var monitorTasks: RedisProfilerTaskBag?
        var tunnel: SSHTunnel?
        var clusterTunnelManager: SSHClusterTunnelManager?

        defer {
            let shouldClearStoredResources = profilerGeneration == generation
            let storedMonitorClients = shouldClearStoredResources ? profilerMonitorClients : []
            let storedMonitorTasks = shouldClearStoredResources ? profilerMonitorTasks : nil
            let storedTunnel = shouldClearStoredResources ? profilerSSHTunnel : nil
            let storedClusterTunnelManager = shouldClearStoredResources ? profilerClusterTunnelManager : nil

            monitorTasks?.cancelAll()
            storedMonitorTasks?.cancelAll()
            for client in monitorClients {
                client.disconnect()
            }
            for client in storedMonitorClients {
                client.disconnect()
            }
            tunnel?.stop()
            storedTunnel?.stop()
            let clusterTunnelManager = clusterTunnelManager
            let clusterTunnelManagerFromStoredState = storedClusterTunnelManager
            Task {
                await clusterTunnelManager?.disconnect()
                await clusterTunnelManagerFromStoredState?.disconnect()
            }

            if shouldClearStoredResources {
                profilerMonitorClients = []
                profilerMonitorTasks = nil
                profilerSSHTunnel = nil
                profilerClusterTunnelManager = nil
                profilerTask = nil
                isProfilerRunning = false
                isProfilerStarting = false
            }
        }

        do {
            let profilerStream: RedisProfilerStream

            switch config.mode {
            case .standalone:
                profilerStream = try await startStandaloneProfilerStream(config: config)
            case .cluster:
                profilerStream = try await startClusterProfilerStream(config: config)
            }

            monitorClients = profilerStream.monitorClients
            monitorTasks = profilerStream.monitorTasks
            tunnel = profilerStream.tunnel
            clusterTunnelManager = profilerStream.tunnelManager

            try Task.checkCancellation()

            isProfilerStarting = false
            isProfilerRunning = true
            AppLogger.info("profiler started redis=\(config.address)", category: "Profiler")

            for try await capture in profilerStream.stream {
                try Task.checkCancellation()
                appendProfilerCapture(capture)
            }
        } catch is CancellationError {
            AppLogger.info("profiler stopped redis=\(config.address)", category: "Profiler")
        } catch {
            if profilerGeneration == generation {
                profilerError = error.localizedDescription
            }
            AppLogger.error("profiler failed redis=\(config.address) error=\(error)", category: "Profiler")
        }
    }

    private func startStandaloneProfilerStream(
        config: RedisConnectionConfig
    ) async throws -> RedisProfilerStream {
        var connectHost = config.host
        var connectPort = config.port
        var tunnel: SSHTunnel?

        if config.ssh.enabled {
            let createdTunnel = try await startProfilerSSHTunnel(config: config, remoteHost: config.host, remotePort: config.port)
            tunnel = createdTunnel
            profilerSSHTunnel = createdTunnel
            connectHost = "127.0.0.1"
            connectPort = createdTunnel.localPort
        }

        try Task.checkCancellation()

        let monitorClient = makeProfilerMonitorClient(config: config, host: connectHost, port: connectPort)
        profilerMonitorClients = [monitorClient]

        let rawStream = try await withTimeout(10, context: "Redis profiler connection") {
            try await monitorClient.startMonitoring()
        }

        let (stream, continuation) = AsyncThrowingStream<RedisProfilerCapture, Error>.makeStream(
            of: RedisProfilerCapture.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(profilerMaxEntries)
        )
        let taskBag = RedisProfilerTaskBag()
        profilerMonitorTasks = taskBag
        taskBag.add(
            monitorStreamTask(
                rawStream: rawStream,
                node: nil,
                continuation: continuation
            )
        )

        return RedisProfilerStream(
            stream: stream,
            monitorClients: [monitorClient],
            monitorTasks: taskBag,
            tunnel: tunnel,
            tunnelManager: nil
        )
    }

    private func startClusterProfilerStream(
        config: RedisConnectionConfig
    ) async throws -> RedisProfilerStream {
        guard let clusterClient = activeClient as? RedisClusterClient else {
            throw RedisError.commandError("Profiler requires an active Redis Cluster connection")
        }

        let nodes = try await clusterClient.clusterNodes()
        let endpoints = RedisEndpoint.unique(nodes.map(\.endpoint))
        guard !endpoints.isEmpty else {
            throw RedisError.commandError("Redis Cluster topology has no nodes")
        }

        let tunnelManager = config.ssh.enabled ? SSHClusterTunnelManager(ssh: config.ssh) : nil
        profilerClusterTunnelManager = tunnelManager

        let (stream, continuation) = AsyncThrowingStream<RedisProfilerCapture, Error>.makeStream(
            of: RedisProfilerCapture.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(profilerMaxEntries)
        )
        let taskBag = RedisProfilerTaskBag()
        profilerMonitorTasks = taskBag

        var monitorClients: [RedisMonitorClient] = []

        for endpoint in endpoints {
            try Task.checkCancellation()

            let clientEndpoint: RedisEndpoint
            if let tunnelManager {
                clientEndpoint = try await tunnelManager.clientEndpoint(for: endpoint)
            } else {
                clientEndpoint = endpoint
            }

            let monitorClient = makeProfilerMonitorClient(config: config, host: clientEndpoint.host, port: clientEndpoint.port)
            monitorClients.append(monitorClient)
            profilerMonitorClients = monitorClients

            let rawStream = try await withTimeout(10, context: "Redis profiler connection to \(endpoint.address)") {
                try await monitorClient.startMonitoring()
            }

            taskBag.add(
                monitorStreamTask(
                    rawStream: rawStream,
                    node: endpoint,
                    continuation: continuation
                )
            )
        }

        return RedisProfilerStream(
            stream: stream,
            monitorClients: monitorClients,
            monitorTasks: taskBag,
            tunnel: nil,
            tunnelManager: tunnelManager
        )
    }

    private func makeProfilerMonitorClient(
        config: RedisConnectionConfig,
        host: String,
        port: UInt16
    ) -> RedisMonitorClient {
        RedisMonitorClient(
            host: host,
            port: port,
            username: config.username.isEmpty ? nil : config.username,
            password: config.password.isEmpty ? nil : config.password,
            tlsEnabled: config.tls.enabled,
            verifyServerCertificate: config.tls.verifyServerCertificate,
            caCertificatePath: config.tls.caCertificatePath,
            clientCertificatePath: config.tls.clientCertificatePath,
            clientKeyPath: config.tls.clientKeyPath
        )
    }

    private func startProfilerSSHTunnel(
        config: RedisConnectionConfig,
        remoteHost: String,
        remotePort: UInt16
    ) async throws -> SSHTunnel {
        let sshHost = config.ssh.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let sshUser = config.ssh.user.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSSHUser = sshUser.isEmpty ? NSUserName() : sshUser
        guard !sshHost.isEmpty else {
            throw SSHTunnelError.connectionFailed("SSH host is required")
        }

        let tunnel = SSHTunnel()
        do {
            try await withTimeout(12, context: "SSH tunnel setup") {
                try await tunnel.start(
                    sshHost: sshHost,
                    sshPort: config.ssh.port,
                    sshUser: effectiveSSHUser,
                    sshPassword: config.ssh.password.isEmpty ? nil : config.ssh.password,
                    privateKeyPath: config.ssh.privateKeyPath.isEmpty ? nil : config.ssh.privateKeyPath,
                    remoteHost: remoteHost,
                    remotePort: remotePort
                )
            }
            return tunnel
        } catch {
            tunnel.stop()
            throw error
        }
    }

    private nonisolated func monitorStreamTask(
        rawStream: AsyncThrowingStream<String, Error>,
        node: RedisEndpoint?,
        continuation: AsyncThrowingStream<RedisProfilerCapture, Error>.Continuation
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await line in rawStream {
                    try Task.checkCancellation()
                    continuation.yield(RedisProfilerCapture(node: node, line: line))
                }

                if !Task.isCancelled {
                    continuation.finish(throwing: RedisError.notConnected)
                }
            } catch is CancellationError {
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private func appendProfilerCapture(_ capture: RedisProfilerCapture) {
        profilerCapturedCount += 1
        profilerEntries.append(RedisProfilerEntry(rawLine: capture.line, node: capture.node))

        if profilerEntries.count > profilerMaxEntries {
            profilerEntries.removeFirst(profilerEntries.count - profilerMaxEntries)
        }
    }
}
