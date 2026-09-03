import Foundation

extension ConnectionState {
    // MARK: - Shell

    func connectShellClient() async {
        guard let config = selectedConnection else { return }
        shellClient?.disconnect()
        shellClient = nil

        do {
            var connectHost = config.host
            var connectPort = config.port

            if config.ssh.enabled {
                // Reuse existing SSH tunnel if available
                if let existingTunnel = sshTunnel, existingTunnel.isRunning {
                    connectHost = "127.0.0.1"
                    connectPort = existingTunnel.localPort
                } else if let clusterManager = sshClusterTunnelManager {
                    let resolver = clusterManager
                    let endpoint = try await resolver.clientEndpoint(for: RedisEndpoint(host: config.host, port: config.port))
                    connectHost = endpoint.host
                    connectPort = endpoint.port
                } else {
                    // Create a dedicated tunnel for shell and save the reference
                    // so it is properly cleaned up by disconnect() on teardown.
                    let tunnel = SSHTunnel()
                    tunnel.setupTimeoutSeconds = config.ssh.setupTimeout
                    tunnel.connectionAttemptTimeout = .seconds(Int64(config.ssh.connectionAttemptTimeout))
                    tunnel.maxConnectionAttempts = config.ssh.maxConnectionAttempts
                    tunnel.authTimeoutSeconds = config.ssh.authTimeout
                    try await tunnel.start(
                        sshHost: config.ssh.host,
                        sshPort: config.ssh.port,
                        sshUser: config.ssh.user,
                        sshPassword: config.ssh.password.isEmpty ? nil : config.ssh.password,
                        privateKeyPath: config.ssh.privateKeyPath.isEmpty ? nil : config.ssh.privateKeyPath,
                        remoteHost: config.host,
                        remotePort: config.port,
                        mode: config.ssh.mode
                    )
                    sshTunnel = tunnel
                    connectHost = "127.0.0.1"
                    connectPort = tunnel.localPort
                }
            }

            let client: any RedisSession
            switch config.mode {
            case .standalone:
                client = RedisClient(
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
                client = RedisClusterClient(
                    seedNodes: config.effectiveSeedNodes,
                    username: config.username.isEmpty ? nil : config.username,
                    password: config.password.isEmpty ? nil : config.password,
                    tlsEnabled: config.tls.enabled,
                    verifyServerCertificate: config.tls.verifyServerCertificate,
                    caCertificatePath: config.tls.caCertificatePath,
                    clientCertificatePath: config.tls.clientCertificatePath,
                    clientKeyPath: config.tls.clientKeyPath,
                    connectionTimeout: config.connectionTimeout,
                    endpointResolver: sshClusterTunnelManager
                )
            }

            try await client.connect()
            shellClient = client
        } catch {
            AppLogger.error("shell client connect failed error=\(error)", category: "Shell")
        }
    }

    func disconnectShellClient() {
        shellClient?.disconnect()
        shellClient = nil
    }

    func executeCommand(_ input: String) async {
        guard let client = shellClient, client.isConnected else { return }
        let redacted = redactSensitiveCommand(input)
        do {
            let parts = try parseCommand(input)
            guard !parts.isEmpty else { return }
            let result = try await client.send(parts)
            let resultString = truncateForHistory(result.displayString)
            let entry = ShellHistoryEntry(
                command: redacted,
                result: resultString,
                timestamp: Date(),
                isError: {
                    if case .error = result { return true }
                    return false
                }()
            )
            appendShellHistory(entry)
        } catch {
            let entry = ShellHistoryEntry(
                command: redacted,
                result: truncateForHistory(error.localizedDescription),
                timestamp: Date(),
                isError: true
            )
            appendShellHistory(entry)
        }
        shellInput = ""
    }

    private func parseCommand(_ input: String) throws -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var isEscaping = false
        var hasToken = false
        var quoteChar: Character = "\""

        for char in input {
            if isEscaping {
                current.append(unescapedShellCharacter(char))
                hasToken = true
                isEscaping = false
            } else if char == "\\" {
                isEscaping = true
                hasToken = true
            } else if char == "\"" || char == "'" {
                if inQuotes && char == quoteChar {
                    inQuotes = false
                } else if !inQuotes {
                    inQuotes = true
                    quoteChar = char
                    hasToken = true
                } else {
                    current.append(char)
                }
            } else if char.isWhitespace && !inQuotes {
                if hasToken {
                    parts.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(char)
                hasToken = true
            }
        }

        if isEscaping {
            current.append("\\")
        }
        if inQuotes {
            throw RedisError.commandError("Unclosed quote in command")
        }
        if hasToken {
            parts.append(current)
        }
        return parts
    }

    private func unescapedShellCharacter(_ character: Character) -> Character {
        switch character {
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        default: return character
        }
    }

    // MARK: - Sensitive Command Redaction

    /// Maximum length of a shell result stored in history (keeps history
    /// files compact).
    private static let maxShellResultBytes = 4096

    /// Commands whose arguments should be redacted in history.
    /// The first token is the command verb (case-insensitive); the rest is the
    /// sensitive payload that will be replaced with `****`.
    private static let fullyRedactedCommands: Set<String> = [
        "AUTH"
    ]

    /// Redacts sensitive information from a shell command string before
    /// persisting it to history. The original `input` is left untouched so the
    /// actual execution is unaffected.
    private func redactSensitiveCommand(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first?.uppercased() else { return input }

        // Fully redacted commands: AUTH <password>
        if Self.fullyRedactedCommands.contains(first) {
            return "\(first) ****"
        }

        // CONFIG SET <key> <value> — redact value if key is a password-related setting
        if first == "CONFIG" {
            return redactConfigCommand(trimmed)
        }

        // ACL SETUSER <user> … — redact password arguments (>…)
        if first == "ACL" {
            return redactAclCommand(trimmed)
        }

        // MIGRATE … AUTH <password> — redact the token after AUTH
        if first == "MIGRATE" {
            return redactMigrateCommand(trimmed)
        }

        // HELLO AUTH <username> <password>
        if first == "HELLO" {
            return redactHelloCommand(trimmed)
        }

        return input
    }

    private func redactConfigCommand(_ input: String) -> String {
        let parts = input.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[1].uppercased() == "SET" else { return input }

        let sensitiveKeys: Set<String> = [
            "requirepass", "masterauth", "masteruser",
        ]
        let key = String(parts[2]).lowercased()
        if sensitiveKeys.contains(key) {
            // Redact the value
            if parts.count >= 4 {
                return "\(parts[0]) \(parts[1]) \(parts[2]) ****"
            }
        }
        return input
    }

    private func redactAclCommand(_ input: String) -> String {
        let parts = input.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[1].uppercased() == "SETUSER" else { return input }

        // Redact tokens that start with '>' (add password) or '<' (remove password)
        let tokens = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let redacted = tokens.map { token -> String in
            if token.hasPrefix(">") { return ">****" }
            if token.hasPrefix("<") { return "<****" }
            return token
        }
        return redacted.joined(separator: " ")
    }

    private func redactMigrateCommand(_ input: String) -> String {
        let parts = input.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return input }

        let tokens = parts[1].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var redacted: [String] = []
        var index = 0
        while index < tokens.count {
            let upper = tokens[index].uppercased()
            if upper == "AUTH" && index + 1 < tokens.count {
                redacted.append(tokens[index])
                redacted.append("****")
                index += 2
            } else if upper == "AUTH2" && index + 2 < tokens.count {
                redacted.append(tokens[index])
                redacted.append("****")
                redacted.append("****")
                index += 3
            } else {
                redacted.append(tokens[index])
                index += 1
            }
        }
        return "\(parts[0]) \(redacted.joined(separator: " "))"
    }

    private func redactHelloCommand(_ input: String) -> String {
        let tokens = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        // HELLO [protover] [AUTH username password] [SETNAME name]
        // Find "AUTH" at any position after the command verb
        if let authIndex = tokens.firstIndex(where: { $0.uppercased() == "AUTH" }), authIndex + 2 < tokens.count {
            var redacted = tokens
            redacted[authIndex + 1] = "****"
            redacted[authIndex + 2] = "****"
            return redacted.joined(separator: " ")
        }

        return input
    }

    /// Truncates a shell result string to `maxShellResultBytes` for compact
    /// history storage.
    private func truncateForHistory(_ string: String) -> String {
        guard string.utf8.count > Self.maxShellResultBytes else { return string }
        return String(string.prefix(Self.maxShellResultBytes)) + "\u{2026}"
    }
}
