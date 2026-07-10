import Crypto
import Foundation
import NIO
import NIOCore
@preconcurrency import NIOSSH
import NIOTransportServices
import Network

class SSHTunnel: @unchecked Sendable {
    enum TunnelMode: String {
        case nioSSH
    }

    // Configurable timeout settings
    var setupTimeoutSeconds: TimeInterval = 30
    var connectionAttemptTimeout: TimeAmount = .seconds(5)
    var maxConnectionAttempts = 4
    var authTimeoutSeconds: TimeInterval = 10
    private var connectionRetryDelaysNanoseconds: [UInt64] = [
        300_000_000,
        800_000_000,
        1_600_000_000,
    ]

    private var group: NIOTSEventLoopGroup?
    private var channel: Channel?
    private var localServer: Channel?
    private(set) var localPort: UInt16 = 0
    private(set) var isRunning = false
    private(set) var mode: TunnelMode = .nioSSH
    private let lock = NSLock()

    // SSH configuration
    private var sshHost: String = ""
    private var sshPort: UInt16 = 22
    private var sshUser: String = ""
    private var sshPassword: String?
    private var privateKeyPath: String?
    private var remoteHost: String = ""
    private var remotePort: UInt16 = 6379

    private var effectiveSSHUser: String {
        let trimmedUser = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUser.isEmpty {
            return trimmedUser
        }
        return NSUserName()
    }

    // swiftlint:disable:next function_parameter_count
    func start(
        sshHost: String,
        sshPort: UInt16,
        sshUser: String,
        sshPassword: String?,
        privateKeyPath: String?,
        remoteHost: String,
        remotePort: UInt16
    ) async throws {
        let effectiveUser = sshUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSUserName() : sshUser
        AppLogger.info(
            "start requested ssh=\(sshHost):\(sshPort) user=\(effectiveUser) "
                + "remote=\(remoteHost):\(remotePort) hasPassword=\(!(sshPassword ?? "").isEmpty) " + "keyPath=\(privateKeyPath ?? "")",
            category: "SSHTunnel"
        )
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.sshPassword = sshPassword
        self.privateKeyPath = privateKeyPath
        self.remoteHost = remoteHost
        self.remotePort = remotePort

        // Find available local port
        self.localPort = findAvailablePort()

        // Create Network.framework-backed event loop group.
        let group = NIOTSEventLoopGroup(loopCount: 1)
        self.group = group

        do {
            AppLogger.info("starting tunnel mode=nioSSH", category: "SSHTunnel")
            // Connect SSH channel
            let sshChannel = try await connectSSHWithRetry(group: group)
            self.channel = sshChannel

            // Start local TCP server
            let localServer = try await startLocalServer(group: group, sshChannel: sshChannel)
            self.localServer = localServer

            self.mode = .nioSSH
            self.isRunning = true
            AppLogger.info("tunnel mode=nioSSH ready local=127.0.0.1:\(localPort)", category: "SSHTunnel")
        } catch {
            AppLogger.error("start failed error=\(error)", category: "SSHTunnel")
            try? await group.shutdownGracefully()
            self.group = nil
            throw error
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        isRunning = false
        AppLogger.info("stop tunnel mode=\(mode.rawValue)", category: "SSHTunnel")

        // Close local server
        localServer?.close(promise: nil)
        localServer = nil

        // Close SSH channel
        channel?.close(promise: nil)
        channel = nil

        // Shutdown event loop group
        if let group = group {
            try? group.syncShutdownGracefully()
            self.group = nil
        }
    }

    // MARK: - SSH Connection

    private func connectSSHWithRetry(group: NIOTSEventLoopGroup) async throws -> Channel {
        var lastError: Error?

        for attempt in 1...maxConnectionAttempts {
            try Task.checkCancellation()

            do {
                return try await connectSSH(group: group)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let mappedError = mappedSSHError(error)
                lastError = mappedError

                guard attempt < maxConnectionAttempts, isRetriableConnectionError(error) else {
                    throw mappedError
                }

                let retryDelay = connectionRetryDelayNanoseconds(after: attempt)
                AppLogger.warn(
                    "ssh connect attempt failed ssh=\(sshHost):\(sshPort) "
                        + "attempt=\(attempt)/\(maxConnectionAttempts) "
                        + "retryInMs=\(retryDelay / 1_000_000) error=\(mappedError)",
                    category: "SSHTunnel"
                )
                try await Task.sleep(for: .nanoseconds(Int64(retryDelay)))
            }
        }

        throw lastError ?? SSHTunnelError.connectionFailed("SSH connection failed")
    }

    private func connectSSH(group: NIOTSEventLoopGroup) async throws -> Channel {
        let authDelegate = SSHAuthDelegateBox(value: createAuthDelegate())
        let serverHostKeyDelegate = SSHServerAuthDelegateBox(value: AcceptAllServerHostKeysDelegate())
        let handshakePromise = group.next().makePromise(of: Void.self)

        let bootstrap = NIOTSConnectionBootstrap(group: group)
            .connectTimeout(connectionAttemptTimeout)
            .channelOption(NIOTSChannelOptions.waitForActivity, value: false)
            .channelInitializer { channel in
                let sshHandler = NIOSSHHandler(
                    role: .client(
                        .init(
                            userAuthDelegate: authDelegate.value,
                            serverAuthDelegate: serverHostKeyDelegate.value
                        )),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )

                do {
                    try channel.pipeline.syncOperations.addHandler(sshHandler)
                    try channel.pipeline.syncOperations.addHandlers([
                        HandshakeHandler(promise: handshakePromise),
                        ErrorHandler(),
                    ])
                    return channel.eventLoop.makeSucceededFuture(())
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }

        do {
            let channel = try await bootstrap.connect(host: sshHost, port: Int(sshPort)).get()

            // Wait for SSH authentication to complete.
            do {
                try await withTimeout(authTimeoutSeconds, context: "SSH authentication") {
                    try await handshakePromise.futureResult.get()
                }
            } catch {
                channel.close(promise: nil)
                AppLogger.error("ssh auth failed error=\(error)", category: "SSHTunnel")
                throw mappedSSHError(error)
            }

            return channel
        } catch {
            throw mappedSSHError(error)
        }
    }

    private func connectionRetryDelayNanoseconds(after attempt: Int) -> UInt64 {
        let index = max(0, min(attempt - 1, connectionRetryDelaysNanoseconds.count - 1))
        return connectionRetryDelaysNanoseconds[index]
    }

    private func isRetriableConnectionError(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let connectionError = error as? NIOConnectionError {
            if !connectionError.connectionErrors.isEmpty {
                return connectionError.connectionErrors.allSatisfy {
                    isRetriableConnectionError($0.error)
                }
            }

            return isLocalHostname(sshHost)
                && (connectionError.dnsAError != nil || connectionError.dnsAAAAError != nil)
        }

        if let channelError = error as? ChannelError, case .connectTimeout = channelError {
            return true
        }

        if let nwError = error as? NWError {
            return isRetriableNWError(nwError)
        }

        if let posixError = error as? POSIXError {
            return isRetriableErrno(posixError.code.rawValue)
        }

        guard let ioError = error as? IOError else { return false }
        return isRetriableErrno(ioError.errnoCode)
    }

    private func isLocalHostname(_ host: String) -> Bool {
        host.lowercased().hasSuffix(".local")
    }

    private func isRetriableNWError(_ error: NWError) -> Bool {
        switch error {
        case .posix(let code):
            return isRetriableErrno(code.rawValue)
        case .dns:
            return isLocalHostname(sshHost)
        case .tls:
            return false
        @unknown default:
            return false
        }
    }

    private func isRetriableErrno(_ errnoCode: CInt) -> Bool {
        switch errnoCode {
        case ECONNREFUSED, EHOSTDOWN, EHOSTUNREACH, ENETDOWN, ENETUNREACH, ETIMEDOUT, EADDRNOTAVAIL:
            return true
        default:
            return false
        }
    }

    private func mappedSSHError(_ error: Error) -> Error {
        guard let sshError = error as? NIOSSHError else {
            return error
        }

        if sshError.type == .keyExchangeNegotiationFailure {
            return SSHTunnelError.connectionFailed(
                "SSH algorithm negotiation failed. Server needs modern algorithms: "
                    + "KEX curve25519/ecdh, host key ssh-ed25519 or ecdsa-sha2-*, "
                    + "cipher aes128-gcm@openssh.com or aes256-gcm@openssh.com."
            )
        }

        return error
    }

    private func createAuthDelegate() -> NIOSSHClientUserAuthenticationDelegate {
        if let password = sshPassword, !password.isEmpty {
            return PasswordAuthDelegate(username: effectiveSSHUser, password: password)
        } else if let keyPath = privateKeyPath, !keyPath.isEmpty {
            let expandedPath = (keyPath as NSString).expandingTildeInPath
            return KeyAuthDelegate(username: effectiveSSHUser, keyPath: expandedPath)
        } else {
            // Try default key locations
            return KeyAuthDelegate(username: effectiveSSHUser, keyPath: nil)
        }
    }

    // MARK: - Local TCP Server

    private func startLocalServer(group: NIOTSEventLoopGroup, sshChannel: Channel) async throws -> Channel {
        let sshHandler = try await sshChannel.pipeline.handler(type: NIOSSHHandler.self)
            .map { SSHHandlerBox(value: $0) }
            .get()

        let bootstrap = NIOTSListenerBootstrap(group: group)
            .serverChannelOption(NIOTSChannelOptions.allowLocalEndpointReuse, value: true)
            .childChannelInitializer { channel in
                self.forwardToSSHChannel(
                    localChannel: channel,
                    sshHandler: sshHandler.value,
                    sshChannel: sshChannel
                )
            }

        let server = try await bootstrap.bind(host: "127.0.0.1", port: Int(localPort)).get()

        // Update localPort in case it was 0 (system-assigned)
        if let localAddress = server.localAddress {
            self.localPort = UInt16(localAddress.port ?? Int(self.localPort))
        }

        return server
    }

    private func forwardToSSHChannel(
        localChannel: Channel,
        sshHandler: NIOSSHHandler,
        sshChannel: Channel
    ) -> EventLoopFuture<Void> {
        // Create a direct-tcpip channel through SSH
        let promise = localChannel.eventLoop.makePromise(of: Channel.self)

        do {
            let originator = try localChannel.localAddress ?? SocketAddress(ipAddress: "127.0.0.1", port: 0)

            let channelType: SSHChannelType = .directTCPIP(
                .init(
                    targetHost: remoteHost,
                    targetPort: Int(remotePort),
                    originatorAddress: originator
                )
            )

            sshHandler.createChannel(promise, channelType: channelType) { childChannel, _ in
                childChannel.pipeline.addHandlers([
                    SSHWrapperHandler(),
                    ErrorHandler(),
                ])
            }
        } catch {
            return localChannel.eventLoop.makeFailedFuture(error)
        }

        return promise.futureResult.flatMap { sshChildChannel in
            // Set up bidirectional forwarding
            let localToSSH = localChannel.pipeline.addHandler(
                DataForwarder(target: sshChildChannel)
            )
            let sshToLocal = sshChildChannel.pipeline.addHandler(
                DataForwarder(target: localChannel)
            )

            return localToSSH.and(sshToLocal).flatMap { _ in
                // Start reading
                _ = localChannel.setOption(ChannelOptions.autoRead, value: true)
                _ = sshChildChannel.setOption(ChannelOptions.autoRead, value: true)

                localChannel.closeFuture.whenComplete { _ in
                    sshChildChannel.close(promise: nil)
                }

                sshChildChannel.closeFuture.whenComplete { _ in
                    localChannel.close(promise: nil)
                }

                return localChannel.eventLoop.makeSucceededFuture(())
            }
        }
    }

    // MARK: - Helper Methods

    private func findAvailablePort() -> UInt16 {
        for _ in 0..<100 {
            let port = UInt16.random(in: 10000..<60000)
            if isPortAvailable(port) { return port }
        }
        return UInt16.random(in: 50000..<60000)
    }

    private func isPortAvailable(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    deinit {
        stop()
    }
}

// MARK: - Error Types

enum SSHTunnelError: LocalizedError {
    case authMethodNotSupported
    case noPrivateKeyFound
    case keyTypeNotSupported(String)
    case invalidKeyFormat
    case handshakeFailed(String)
    case tunnelClosed
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .authMethodNotSupported:
            return "SSH authentication method not supported by server"
        case .noPrivateKeyFound:
            return "No SSH private key found. Please specify a key path or use password authentication."
        case .keyTypeNotSupported(let type):
            return "\(type) key type is not currently supported. Please use Ed25519 keys."
        case .invalidKeyFormat:
            return "Invalid SSH private key format"
        case .handshakeFailed(let msg):
            return "SSH handshake failed: \(msg)"
        case .tunnelClosed:
            return "SSH tunnel closed unexpectedly"
        case .connectionFailed(let msg):
            return "SSH connection failed: \(msg)"
        }
    }
}
