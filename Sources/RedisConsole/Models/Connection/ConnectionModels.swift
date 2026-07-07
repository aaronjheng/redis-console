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

    var badgeBackgroundColor: Color { color.opacity(0.12) }
}

// MARK: - Connection Config

struct SSHConfig: Codable, Hashable {
    var enabled: Bool = false
    var host: String = ""
    var port: UInt16 = 22
    var user: String = ""
    var password: String = ""
    var privateKeyPath: String = ""
    var privateKeyPassphrase: String = ""

    // Timeout settings (in seconds)
    var setupTimeout: TimeInterval = 30
    var connectionAttemptTimeout: TimeInterval = 5
    var maxConnectionAttempts: Int = 4
    var authTimeout: TimeInterval = 10
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
        try container.encode(ssh, forKey: .ssh)
        try container.encode(tls, forKey: .tls)
        try container.encode(environment, forKey: .environment)
        try container.encode(connectionTimeout, forKey: .connectionTimeout)
        try container.encode(pingTimeout, forKey: .pingTimeout)
    }
}
