import Crypto
import Foundation
import NIO
import NIOCore
import NIOPosix
import NIOSSH

class SSHTunnel: @unchecked Sendable {
    enum TunnelMode: String {
        case nioSSH
        case systemSSH
    }

    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var localServer: Channel?
    private var sshProcess: Process?
    private var sshProcessStderr: Pipe?
    private(set) var localPort: UInt16 = 0
    private(set) var isRunning = false
    private(set) var mode: TunnelMode = .nioSSH
    private let lock = NSLock()

    // SSH configuration
    private var sshHost: String = ""
    private var sshPort: UInt16 = 22
    private var sshUsername: String = ""
    private var sshPassword: String?
    private var privateKeyPath: String?
    private var remoteHost: String = ""
    private var remotePort: UInt16 = 6379

    func start(
        sshHost: String,
        sshPort: UInt16,
        sshUsername: String,
        sshPassword: String?,
        privateKeyPath: String?,
        remoteHost: String,
        remotePort: UInt16
    ) async throws {
        AppLogger.info(
            "start requested ssh=\(sshHost):\(sshPort) user=\(sshUsername) remote=\(remoteHost):\(remotePort) hasPassword=\(!(sshPassword ?? "").isEmpty) keyPath=\(privateKeyPath ?? "")",
            category: "SSHTunnel"
        )
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.sshPassword = sshPassword
        self.privateKeyPath = privateKeyPath
        self.remoteHost = remoteHost
        self.remotePort = remotePort

        // Find available local port
        self.localPort = findAvailablePort()

        // Prefer system ssh for compatibility when password auth is not required.
        if sshPassword == nil || sshPassword?.isEmpty == true {
            do {
                AppLogger.info("trying tunnel mode=systemSSH", category: "SSHTunnel")
                try await startWithSystemSSH()
                self.mode = .systemSSH
                self.isRunning = true
                AppLogger.info("tunnel mode=systemSSH ready local=127.0.0.1:\(localPort)", category: "SSHTunnel")
                return
            } catch {
                AppLogger.error("tunnel mode=systemSSH failed error=\(error), fallback to nioSSH", category: "SSHTunnel")
            }
        }

        // Create event loop group
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        do {
            AppLogger.info("trying tunnel mode=nioSSH", category: "SSHTunnel")
            // Connect SSH channel
            let sshChannel = try await connectSSH(group: group)
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

        if let process = sshProcess {
            if process.isRunning {
                process.terminate()
            }
            sshProcess = nil
            sshProcessStderr = nil
        }

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

    private func startWithSystemSSH() async throws {
        let process = Process()
        let stderr = Pipe()
        let stdout = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        var args = [
            "ssh",
            "-N",
            "-T",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=1",
            "-p", "\(sshPort)",
            "-L", "127.0.0.1:\(localPort):\(remoteHost):\(remotePort)",
        ]
        if let keyPath = privateKeyPath, !keyPath.isEmpty {
            let expandedPath = (keyPath as NSString).expandingTildeInPath
            args.append(contentsOf: ["-i", expandedPath])
        }
        args.append("\(sshUsername)@\(sshHost)")

        process.arguments = args
        process.standardError = stderr
        process.standardOutput = stdout
        process.standardInput = Pipe()

        do {
            try process.run()
            AppLogger.info("system ssh launched pid=\(process.processIdentifier)", category: "SSHTunnel")
        } catch {
            throw SSHTunnelError.connectionFailed("failed to launch ssh: \(error.localizedDescription)")
        }

        // Fast-fail window for auth/host/forward errors.
        try await Task.sleep(nanoseconds: 900_000_000)

        if !process.isRunning {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message =
                String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = message.isEmpty ? "ssh exited before tunnel was ready" : message
            throw SSHTunnelError.connectionFailed(detail)
        }

        self.sshProcess = process
        self.sshProcessStderr = stderr
    }

    // MARK: - SSH Connection

    private func connectSSH(group: EventLoopGroup) async throws -> Channel {
        let authDelegate = createAuthDelegate()
        let serverHostKeyDelegate = AcceptAllServerHostKeysDelegate()
        let handshakePromise = group.next().makePromise(of: Void.self)

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                let sshHandler = NIOSSHHandler(
                    role: .client(
                        .init(
                            userAuthDelegate: authDelegate,
                            serverAuthDelegate: serverHostKeyDelegate
                        )),
                    allocator: channel.allocator,
                    inboundChildChannelInitializer: nil
                )

                return channel.pipeline.addHandlers([
                    sshHandler,
                    HandshakeHandler(promise: handshakePromise),
                    ErrorHandler(),
                ])
            }

        do {
            let channel = try await bootstrap.connect(host: sshHost, port: Int(sshPort)).get()

            // Wait for SSH authentication to complete.
            do {
                try await withTimeout(10, context: "SSH authentication") {
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
            return PasswordAuthDelegate(username: sshUsername, password: password)
        } else if let keyPath = privateKeyPath, !keyPath.isEmpty {
            let expandedPath = (keyPath as NSString).expandingTildeInPath
            return KeyAuthDelegate(username: sshUsername, keyPath: expandedPath)
        } else {
            // Try default key locations
            return KeyAuthDelegate(username: sshUsername, keyPath: nil)
        }
    }

    // MARK: - Local TCP Server

    private func startLocalServer(group: EventLoopGroup, sshChannel: Channel) async throws -> Channel {
        let sshHandler = try await sshChannel.pipeline.handler(type: NIOSSHHandler.self).get()

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                self.forwardToSSHChannel(
                    localChannel: channel,
                    sshHandler: sshHandler,
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
                    ErrorHandler()
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

                return localChannel.closeFuture.flatMap {
                    sshChildChannel.closeFuture
                }
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

// MARK: - SSH Authentication Delegates

private class PasswordAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let password: String
    private var hasTried = false

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !hasTried else {
            nextChallengePromise.succeed(nil)
            return
        }
        hasTried = true

        if availableMethods.contains(.password) {
            let offer = NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "ssh-connection",
                offer: .password(.init(password: password))
            )
            nextChallengePromise.succeed(offer)
        } else if availableMethods.contains(.publicKey) {
            nextChallengePromise.succeed(nil)
        } else {
            nextChallengePromise.fail(SSHTunnelError.authMethodNotSupported)
        }
    }
}

private class KeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let keyPath: String?
    private var hasTried = false

    init(username: String, keyPath: String?) {
        self.username = username
        self.keyPath = keyPath
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !hasTried else {
            nextChallengePromise.succeed(nil)
            return
        }
        hasTried = true

        guard availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(SSHTunnelError.authMethodNotSupported)
            return
        }

        do {
            let key = try loadPrivateKey()
            let offer = NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "ssh-connection",
                offer: .privateKey(.init(privateKey: key))
            )
            nextChallengePromise.succeed(offer)
        } catch {
            nextChallengePromise.fail(error)
        }
    }

    private func loadPrivateKey() throws -> NIOSSHPrivateKey {
        // Try specified key path first
        if let keyPath = keyPath {
            let expandedPath = (keyPath as NSString).expandingTildeInPath
            if let key = try? loadKeyFromFile(path: expandedPath) {
                return key
            }
        }

        // Try default key locations
        let defaultPaths = [
            "~/.ssh/id_ed25519",
            "~/.ssh/id_ecdsa",
            "~/.ssh/id_rsa",
        ]

        for path in defaultPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedPath) else { continue }

            if let key = try? loadKeyFromFile(path: expandedPath) {
                return key
            }
        }

        throw SSHTunnelError.noPrivateKeyFound
    }

    private func loadKeyFromFile(path: String) throws -> NIOSSHPrivateKey {
        let keyData = try Data(contentsOf: URL(fileURLWithPath: path))
        let keyString = String(data: keyData, encoding: .utf8) ?? ""

        // Check for Ed25519 key
        if keyString.contains("ssh-ed25519") || path.hasSuffix("id_ed25519") {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData.suffix(32))
            return NIOSSHPrivateKey(ed25519Key: key)
        }

        // Check for ECDSA key
        if keyString.contains("ecdsa-sha2") || path.hasSuffix("id_ecdsa") {
            // Try to parse ECDSA key (simplified - may need P256/P384/P521)
            throw SSHTunnelError.keyTypeNotSupported("ECDSA")
        }

        // Check for RSA key
        if keyString.contains("ssh-rsa") || path.hasSuffix("id_rsa") {
            throw SSHTunnelError.keyTypeNotSupported("RSA")
        }

        throw SSHTunnelError.invalidKeyFormat
    }
}

private class AcceptAllServerHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        // Accept all host keys (in production, you should verify the host key)
        validationCompletePromise.succeed(())
    }
}

// MARK: - SSH Handlers

private class HandshakeHandler: ChannelInboundHandler {
    typealias InboundIn = Any
    typealias InboundOut = Any

    private let promise: EventLoopPromise<Void>
    private var completed = false

    init(promise: EventLoopPromise<Void>) {
        self.promise = promise
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if !completed, event is UserAuthSuccessEvent {
            completed = true
            promise.succeed(())
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !completed {
            completed = true
            promise.fail(SSHTunnelError.tunnelClosed)
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if !completed {
            completed = true
            promise.fail(error)
        }
        context.fireErrorCaught(error)
    }
}

private class DataForwarder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    private let target: Channel

    init(target: Channel) {
        self.target = target
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        target.writeAndFlush(buffer, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        target.close(promise: nil)
        context.fireChannelInactive()
    }
}

private class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[SSHTunnel] Channel error: \(error)")
        context.close(promise: nil)
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
