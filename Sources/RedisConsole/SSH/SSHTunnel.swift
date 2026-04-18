import Crypto
import Foundation
import NIO
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH

class SSHTunnel: @unchecked Sendable {
    enum TunnelMode: String {
        case nioSSH
    }

    private var group: MultiThreadedEventLoopGroup?
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

        // Create event loop group
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        do {
            AppLogger.info("starting tunnel mode=nioSSH", category: "SSHTunnel")
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

    private func connectSSH(group: EventLoopGroup) async throws -> Channel {
        let authDelegate = SSHAuthDelegateBox(value: createAuthDelegate())
        let serverHostKeyDelegate = SSHServerAuthDelegateBox(value: AcceptAllServerHostKeysDelegate())
        let handshakePromise = group.next().makePromise(of: Void.self)

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
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

    private func startLocalServer(group: EventLoopGroup, sshChannel: Channel) async throws -> Channel {
        let sshHandler = try await sshChannel.pipeline.handler(type: NIOSSHHandler.self)
            .map { SSHHandlerBox(value: $0) }
            .get()

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
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
        guard let keyString = String(data: keyData, encoding: .utf8) else {
            throw SSHTunnelError.invalidKeyFormat
        }

        if keyString.contains("BEGIN OPENSSH PRIVATE KEY") {
            return try parseOpenSSHPrivateKey(keyString)
        }

        if keyString.contains("BEGIN") {
            return try parsePEMPrivateKey(keyString)
        }

        throw SSHTunnelError.invalidKeyFormat
    }

    private func parsePEMPrivateKey(_ pem: String) throws -> NIOSSHPrivateKey {
        if let p256Key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
            return NIOSSHPrivateKey(p256Key: p256Key)
        }
        if let p384Key = try? P384.Signing.PrivateKey(pemRepresentation: pem) {
            return NIOSSHPrivateKey(p384Key: p384Key)
        }
        if let p521Key = try? P521.Signing.PrivateKey(pemRepresentation: pem) {
            return NIOSSHPrivateKey(p521Key: p521Key)
        }
        throw SSHTunnelError.invalidKeyFormat
    }

    private func parseOpenSSHPrivateKey(_ pem: String) throws -> NIOSSHPrivateKey {
        let base64Lines =
            pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined()
        guard let binary = Data(base64Encoded: base64Lines) else {
            throw SSHTunnelError.invalidKeyFormat
        }

        var reader = OpenSSHDataReader(data: binary)
        let magic = try reader.readNullTerminatedString()
        guard magic == "openssh-key-v1" else {
            throw SSHTunnelError.invalidKeyFormat
        }

        let cipherName = try reader.readString()
        let kdfName = try reader.readString()
        _ = try reader.readData()
        let keyCount = try reader.readUInt32()

        guard cipherName == "none", kdfName == "none" else {
            throw SSHTunnelError.connectionFailed("Encrypted OpenSSH private keys are not supported yet")
        }
        guard keyCount == 1 else {
            throw SSHTunnelError.invalidKeyFormat
        }

        _ = try reader.readData()  // public key blob
        let privateBlob = try reader.readData()
        var privateReader = OpenSSHDataReader(data: privateBlob)

        let check1 = try privateReader.readUInt32()
        let check2 = try privateReader.readUInt32()
        guard check1 == check2 else {
            throw SSHTunnelError.connectionFailed("OpenSSH private key checkints do not match")
        }

        let keyType = try privateReader.readString()
        switch keyType {
        case "ssh-ed25519":
            _ = try privateReader.readData()  // public key
            let privateAndPublic = try privateReader.readData()
            guard privateAndPublic.count >= 64 else {
                throw SSHTunnelError.invalidKeyFormat
            }
            let privateKeyBytes = privateAndPublic.prefix(32)
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyBytes)
            _ = try privateReader.readString()  // comment
            return NIOSSHPrivateKey(ed25519Key: privateKey)
        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            let curveName = try privateReader.readString()
            _ = try privateReader.readData()  // public key blob
            let privateScalar = try privateReader.readMPIntData()
            _ = try privateReader.readString()  // comment
            return try makeECDSAPrivateKey(curveName: curveName, privateScalar: privateScalar)
        case "ssh-rsa":
            throw SSHTunnelError.keyTypeNotSupported("RSA")
        default:
            throw SSHTunnelError.keyTypeNotSupported(keyType)
        }
    }

    private func makeECDSAPrivateKey(curveName: String, privateScalar: Data) throws -> NIOSSHPrivateKey {
        switch curveName {
        case "nistp256":
            let key = try P256.Signing.PrivateKey(rawRepresentation: normalizeScalar(privateScalar, targetLength: 32))
            return NIOSSHPrivateKey(p256Key: key)
        case "nistp384":
            let key = try P384.Signing.PrivateKey(rawRepresentation: normalizeScalar(privateScalar, targetLength: 48))
            return NIOSSHPrivateKey(p384Key: key)
        case "nistp521":
            let key = try P521.Signing.PrivateKey(rawRepresentation: normalizeScalar(privateScalar, targetLength: 66))
            return NIOSSHPrivateKey(p521Key: key)
        default:
            throw SSHTunnelError.keyTypeNotSupported("ECDSA \(curveName)")
        }
    }

    private func normalizeScalar(_ scalar: Data, targetLength: Int) -> Data {
        let trimmedScalar = scalar.drop { $0 == 0 }
        if trimmedScalar.count >= targetLength {
            return Data(trimmedScalar.suffix(targetLength))
        }
        return Data(repeating: 0, count: targetLength - trimmedScalar.count) + trimmedScalar
    }
}

private struct OpenSSHDataReader {
    private let data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw SSHTunnelError.invalidKeyFormat
        }
        let value = data[offset..<(offset + 4)].reduce(UInt32(0)) { partialResult, byte in
            (partialResult << 8) | UInt32(byte)
        }
        offset += 4
        return value
    }

    mutating func readData() throws -> Data {
        let length = Int(try readUInt32())
        guard offset + length <= data.count else {
            throw SSHTunnelError.invalidKeyFormat
        }
        let value = data[offset..<(offset + length)]
        offset += length
        return Data(value)
    }

    mutating func readString() throws -> String {
        let value = try readData()
        guard let string = String(data: value, encoding: .utf8) else {
            throw SSHTunnelError.invalidKeyFormat
        }
        return string
    }

    mutating func readNullTerminatedString() throws -> String {
        guard let endIndex = data[offset...].firstIndex(of: 0) else {
            throw SSHTunnelError.invalidKeyFormat
        }
        let value = data[offset..<endIndex]
        offset = endIndex + 1
        guard let string = String(data: value, encoding: .utf8) else {
            throw SSHTunnelError.invalidKeyFormat
        }
        return string
    }

    mutating func readMPIntData() throws -> Data {
        let value = try readData()
        if value.first == 0 {
            return Data(value.dropFirst())
        }
        return value
    }
}

private class AcceptAllServerHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        // Accept all host keys (in production, you should verify the host key)
        validationCompletePromise.succeed(())
    }
}

private struct SSHAuthDelegateBox: @unchecked Sendable {
    let value: NIOSSHClientUserAuthenticationDelegate
}

private struct SSHServerAuthDelegateBox: @unchecked Sendable {
    let value: AcceptAllServerHostKeysDelegate
}

private struct SSHHandlerBox: @unchecked Sendable {
    let value: NIOSSHHandler
}

// MARK: - SSH Handlers

private final class HandshakeHandler: ChannelInboundHandler, @unchecked Sendable {
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

private final class DataForwarder: ChannelInboundHandler, @unchecked Sendable {
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

private final class SSHWrapperHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = unwrapInboundIn(data)

        guard case .channel = data.type, case .byteBuffer(let buffer) = data.data else {
            context.fireErrorCaught(SSHTunnelError.handshakeFailed("Unexpected SSH channel data"))
            return
        }

        context.fireChannelRead(wrapInboundOut(buffer))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = unwrapOutboundIn(data)
        let wrapped = SSHChannelData(type: .channel, data: .byteBuffer(data))
        context.write(wrapOutboundOut(wrapped), promise: promise)
    }
}

private final class ErrorHandler: ChannelInboundHandler, @unchecked Sendable {
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
