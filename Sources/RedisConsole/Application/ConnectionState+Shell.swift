import Foundation

extension ConnectionState {
    // MARK: - Shell

    func executeCommand(_ input: String) async {
        guard let client = activeClient, client.isConnected else { return }
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
