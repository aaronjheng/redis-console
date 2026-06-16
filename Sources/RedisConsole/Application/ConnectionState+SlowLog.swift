import Foundation

extension ConnectionState {
    // MARK: - Slow Log

    var slowLogConfigKey: String {
        guard let connection = selectedConnection else { return "com.redisconsole.slowlog.default" }
        return "com.redisconsole.slowlog.\(connection.id.uuidString)"
    }

    func loadSlowLogConfig() {
        guard
            let data = UserDefaults.standard.data(forKey: slowLogConfigKey),
            let config = try? JSONDecoder().decode(SlowLogConfig.self, from: data)
        else { return }
        slowLogConfig = config
    }

    func saveSlowLogConfig() {
        guard let data = try? JSONEncoder().encode(slowLogConfig) else { return }
        UserDefaults.standard.set(data, forKey: slowLogConfigKey)
    }

    func fetchSlowLog() async {
        guard let client = activeClient, client.isConnected else { return }
        isLoadingSlowLog = true
        slowLogError = nil

        do {
            let result = try await client.send("SLOWLOG", "GET", "\(slowLogFetchCount)")
            if case .error(let message) = result {
                throw RedisError.commandError(message)
            }

            let entries = parseSlowLogEntries(result)
            await MainActor.run {
                slowLogEntries = entries
                isLoadingSlowLog = false
            }
        } catch {
            await MainActor.run {
                slowLogError = error.localizedDescription
                isLoadingSlowLog = false
            }
        }
    }

    func fetchSlowLogLen() async -> Int {
        guard let client = activeClient, client.isConnected else { return 0 }
        do {
            let result = try await client.send("SLOWLOG", "LEN")
            return result.intValue ?? 0
        } catch {
            return 0
        }
    }

    func resetSlowLog() async {
        guard let client = activeClient, client.isConnected else { return }
        do {
            let result = try await client.send("SLOWLOG", "RESET")
            if case .error(let message) = result {
                throw RedisError.commandError(message)
            }
            slowLogEntries = []
        } catch {
            slowLogError = error.localizedDescription
        }
    }

    func fetchSlowLogConfig() async {
        guard let client = activeClient, client.isConnected else { return }
        do {
            let thresholdResult = try await client.send("CONFIG", "GET", "slowlog-log-slower-than")
            if let thresholdStr = thresholdResult.arrayValues.first??.string, let threshold = Int(thresholdStr) {
                await MainActor.run { slowLogConfig.threshold = threshold }
            }

            let maxLenResult = try await client.send("CONFIG", "GET", "slowlog-max-len")
            if let maxLenStr = maxLenResult.arrayValues.first??.string, let maxLen = Int(maxLenStr) {
                await MainActor.run { slowLogConfig.maxLen = maxLen }
            }
        } catch {}
    }

    func updateSlowLogThreshold(_ value: Int) async {
        guard let client = activeClient, client.isConnected else { return }
        do {
            let result = try await client.send("CONFIG", "SET", "slowlog-log-slower-than", "\(value)")
            if case .error(let message) = result {
                throw RedisError.commandError(message)
            }
            await MainActor.run {
                slowLogConfig.threshold = value
                saveSlowLogConfig()
            }
        } catch {
            slowLogError = error.localizedDescription
        }
    }

    func updateSlowLogMaxLen(_ value: Int) async {
        guard let client = activeClient, client.isConnected else { return }
        do {
            let result = try await client.send("CONFIG", "SET", "slowlog-max-len", "\(value)")
            if case .error(let message) = result {
                throw RedisError.commandError(message)
            }
            await MainActor.run {
                slowLogConfig.maxLen = value
                saveSlowLogConfig()
            }
        } catch {
            slowLogError = error.localizedDescription
        }
    }

    private func parseSlowLogEntries(_ value: RESPValue) -> [SlowLogEntry] {
        guard case .array(let entries) = value else { return [] }

        return entries.compactMap { entry -> SlowLogEntry? in
            guard let entry else { return nil }
            let fields = entry.arrayValues.compactMap { $0 }

            guard fields.count >= 6 else { return nil }

            let id = fields[0].intValue ?? 0
            let timestampInt = fields[1].intValue ?? 0
            let duration = fields[2].intValue ?? 0
            let commandArr = fields[3].arrayValues.compactMap { $0?.string }
            let clientIP = fields[4].string ?? ""
            let clientName = fields[5].string ?? ""

            return SlowLogEntry(
                id: id,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestampInt)),
                duration: duration,
                command: commandArr,
                clientIP: clientIP,
                clientName: clientName
            )
        }
        .sorted { $0.id > $1.id }
    }
}
