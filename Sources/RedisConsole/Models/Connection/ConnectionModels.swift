import Foundation
import SwiftUI

// MARK: - Connection Environment

enum ConnectionEnvironment: String, Codable, CaseIterable {
    case unspecified = "Unspecified"
    case development = "Development"
    case production = "Production"

    var color: Color {
        switch self {
        case .unspecified: return .secondary
        case .development: return AppColor.success
        case .production: return AppColor.error
        }
    }

    var icon: String {
        switch self {
        case .unspecified: return "circle"
        case .development: return "hammer"
        case .production: return "shield"
        }
    }

    var badgeForegroundColor: Color { color }

    var badgeBackgroundColor: Color { AppColor.badgeBackground(color) }
}

// MARK: - SSH Tunnel Mode

/// How the SSH tunnel is established.
///
/// - `builtIn`: NIO-based SSH implementation inside the app. Supports
///   password and (unencrypted) Ed25519/ECDSA keys, but ignores the local
///   SSH infrastructure (`~/.ssh/config`, agents, ProxyJump, certificates).
/// - `external`: delegates to the local `/usr/bin/ssh`, so agent identities,
///   `~/.ssh/config` (including ProxyJump), `known_hosts` and certificates
///   work exactly like in Terminal. Tunnels to the same SSH destination
///   share one multiplexed master connection. Passwords are ignored in this
///   mode — use `ssh-agent` for passphrases.
enum SSHTunnelMode: String, Codable, Hashable, Sendable, CaseIterable {
    case builtIn
    case external

    var title: String {
        switch self {
        case .builtIn: return "Built-in"
        case .external: return "System SSH"
        }
    }
}

struct SSHConfig: Codable, Hashable {
    var enabled: Bool = false
    var mode: SSHTunnelMode = .builtIn
    var host: String = ""
    var port: UInt16 = 22
    var user: String = ""
    var password: String = ""
    var privateKeyPath: String = ""
    var privateKeyPassphrase: String = ""

    // Timeout settings (in seconds). Deliberately not persisted — there is no
    // UI to edit them, so stored values would freeze old defaults forever and
    // shipped fixes could never reach existing connections.
    // `setupTimeout` bounds the whole tunnel setup; it must be generous
    // because System SSH may run interactive flows (e.g. `tsh proxy` opening
    // a browser for login) that legitimately take minutes.
    var setupTimeout: TimeInterval = 180
    var connectionAttemptTimeout: TimeInterval = 10
    var maxConnectionAttempts: Int = 4
    var authTimeout: TimeInterval = 10

    enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case host
        case port
        case user
        case password
        case privateKeyPath
        case privateKeyPassphrase
    }

    init(
        enabled: Bool = false,
        mode: SSHTunnelMode = .builtIn,
        host: String = "",
        port: UInt16 = 22,
        user: String = "",
        password: String = "",
        privateKeyPath: String = "",
        privateKeyPassphrase: String = "",
        setupTimeout: TimeInterval = 180,
        connectionAttemptTimeout: TimeInterval = 10,
        maxConnectionAttempts: Int = 4,
        authTimeout: TimeInterval = 10
    ) {
        self.enabled = enabled
        self.mode = mode
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.privateKeyPath = privateKeyPath
        self.privateKeyPassphrase = privateKeyPassphrase
        self.setupTimeout = setupTimeout
        self.connectionAttemptTimeout = connectionAttemptTimeout
        self.maxConnectionAttempts = maxConnectionAttempts
        self.authTimeout = authTimeout
    }

    // Custom decoding with `decodeIfPresent` everywhere so connections saved
    // before a field existed (e.g. `mode`) still load with sane defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try container.decodeIfPresent(SSHTunnelMode.self, forKey: .mode) ?? .builtIn
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 22
        user = try container.decodeIfPresent(String.self, forKey: .user) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath) ?? ""
        privateKeyPassphrase = try container.decodeIfPresent(String.self, forKey: .privateKeyPassphrase) ?? ""
    }
}

struct TLSConfig: Codable, Hashable {
    var enabled: Bool = false
    var verifyServerCertificate: Bool = true
    var caCertificatePath: String = ""
    var clientCertificatePath: String = ""
    var clientKeyPath: String = ""
}

struct RedisConnectionConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var mode: RedisConnectionMode = .standalone
    var host: String
    var port: UInt16 = 6379
    var seedNodes: [RedisEndpoint] = []

    var username: String = ""
    var password: String = ""

    var ssh: SSHConfig = SSHConfig()
    var tls: TLSConfig = TLSConfig()
    var environment: ConnectionEnvironment = .unspecified

    // Timeout settings (in seconds)
    var connectionTimeout: TimeInterval = 10
    var pingTimeout: TimeInterval = 5

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case host
        case port
        case seedNodes
        case username
        case ssh
        case password
        case tls
        case environment
        case connectionTimeout
        case pingTimeout
    }

    static let `default` = RedisConnectionConfig(name: "localhost", host: "127.0.0.1")

    var effectiveSeedNodes: [RedisEndpoint] {
        [RedisEndpoint(host: host, port: port)]
    }

    var address: String {
        switch mode {
        case .standalone:
            return "\(host):\(port)"
        case .cluster:
            return effectiveSeedNodes.map(\.address).joined(separator: ", ")
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        mode: RedisConnectionMode = .standalone,
        host: String,
        port: UInt16 = 6379,
        seedNodes: [RedisEndpoint] = [],
        username: String = "",
        password: String = "",
        ssh: SSHConfig = SSHConfig(),
        tls: TLSConfig = TLSConfig(),
        environment: ConnectionEnvironment = .unspecified,
        connectionTimeout: TimeInterval = 10,
        pingTimeout: TimeInterval = 5
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.host = host
        self.port = port
        self.seedNodes = seedNodes
        self.username = username
        self.password = password
        self.ssh = ssh
        self.tls = tls
        self.environment = environment
        self.connectionTimeout = connectionTimeout
        self.pingTimeout = pingTimeout
    }

    static func parseURI(_ uri: String) -> RedisConnectionConfig? {
        guard let components = URLComponents(string: uri),
            let scheme = components.scheme,
            scheme == "redis" || scheme == "rediss"
        else { return nil }

        let host = components.host ?? "127.0.0.1"
        let port = UInt16(components.port ?? 6379)
        let useTLS = scheme == "rediss"

        var username = ""
        var password = ""

        if let pwd = components.password {
            username = components.user ?? ""
            password = pwd
        } else if let user = components.user {
            password = user
        }

        return RedisConnectionConfig(
            name: host,
            mode: .standalone,
            host: host,
            port: port,
            seedNodes: [],
            username: username,
            password: password,
            tls: TLSConfig(enabled: useTLS)
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        mode = try container.decodeIfPresent(RedisConnectionMode.self, forKey: .mode) ?? .standalone
        host = try container.decode(String.self, forKey: .host)
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 6379
        seedNodes = try container.decodeIfPresent([RedisEndpoint].self, forKey: .seedNodes) ?? []
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        ssh = try container.decodeIfPresent(SSHConfig.self, forKey: .ssh) ?? SSHConfig()
        tls = try container.decodeIfPresent(TLSConfig.self, forKey: .tls) ?? TLSConfig()
        environment = try container.decodeIfPresent(ConnectionEnvironment.self, forKey: .environment) ?? .unspecified
        connectionTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .connectionTimeout) ?? 10
        pingTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .pingTimeout) ?? 5
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(mode, forKey: .mode)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(seedNodes, forKey: .seedNodes)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(ssh, forKey: .ssh)
        try container.encode(tls, forKey: .tls)
        try container.encode(environment, forKey: .environment)
        try container.encode(connectionTimeout, forKey: .connectionTimeout)
        try container.encode(pingTimeout, forKey: .pingTimeout)
    }
}
