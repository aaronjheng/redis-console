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
                    // Create a dedicated tunnel for shell
                    let tunnel = SSHTunnel()
                    try await tunnel.start(
                        sshHost: config.ssh.host,
                        sshPort: config.ssh.port,
                        sshUser: config.ssh.user.isEmpty ? NSUserName() : config.ssh.user,
                        sshPassword: config.ssh.password.isEmpty ? nil : config.ssh.password,
                        privateKeyPath: config.ssh.privateKeyPath.isEmpty ? nil : config.ssh.privateKeyPath,
                        remoteHost: config.host,
                        remotePort: config.port
                    )
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
                    clientKeyPath: config.tls.clientKeyPath
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
        do {
            let parts = try parseCommand(input)
            guard !parts.isEmpty else { return }
            let result = try await client.send(parts)
            let entry = ShellHistoryEntry(
                command: input,
                result: result.displayString,
                timestamp: Date(),
                isError: {
                    if case .error = result { return true }
                    return false
                }()
            )
            appendShellHistory(entry)
        } catch {
            let entry = ShellHistoryEntry(
                command: input,
                result: error.localizedDescription,
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
}
