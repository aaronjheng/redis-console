import Darwin
import Foundation

extension ConnectionState {
    // MARK: - Key Browser

    func scanKeys(reset: Bool = false) async {
        if isScanningKeysRequest {
            pendingResetScan = pendingResetScan || reset
            return
        }

        guard let client = activeClient, client.isConnected else {
            isLoadingKeys = false
            return
        }

        isScanningKeysRequest = true
        if reset {
            scanCursor = "0"
            keys = []
            clearSelectedKeyDetail()
            hasMoreKeys = true
            keyTotalCount = nil
            keyScannedCount = 0
            keyScanIterationCount = 0
            keyScanLimitReached = false
        }
        isLoadingKeys = true

        let isPattern = keyFilter.contains("*") || keyFilter.contains("?") || keyFilter.contains("[")

        do {
            if reset {
                await refreshKeyTotalCount(using: client)
            }

            if !isPattern {
                let typeResult = try? await client.send("TYPE", keyFilter)
                if let typeName = typeResult?.string, typeName != "none" {
                    let entry = RedisKeyEntry(key: keyFilter, type: typeName, ttl: nil, size: nil)
                    keys = [entry]
                    loadKeyMetadata(for: [entry])
                } else {
                    keys = []
                    clearSelectedKeyDetail()
                }
                hasMoreKeys = false
                keyScannedCount = keyTotalCount ?? keys.count
            } else {
                let scanAll = keyFilter != "*"
                var iterations = 0
                let maxIterations = scanAll ? keyPatternScanIterationLimit : 1
                repeat {
                    let result = try await client.scan(cursor: scanCursor, match: keyFilter, count: keyScanCount)
                    scanCursor = result.nextCursor
                    hasMoreKeys = scanCursor != "0"
                    let newKeyNames = result.keys
                    keyScannedCount += result.scannedCount
                    normalizeKeyScanProgress()
                    var seenKeys = Set(keys.map { $0.key })
                    let newEntries = newKeyNames.compactMap { keyName -> RedisKeyEntry? in
                        guard seenKeys.insert(keyName).inserted else { return nil }
                        return RedisKeyEntry(key: keyName, type: "", ttl: nil, size: nil)
                    }
                    keys.append(contentsOf: newEntries)
                    iterations += 1
                    keyScanIterationCount += 1
                } while hasMoreKeys && iterations < maxIterations && (scanAll || keys.isEmpty)
                keyScanLimitReached = hasMoreKeys && iterations >= maxIterations
                normalizeKeyScanProgress()
            }
        } catch {
            connectionError = error.localizedDescription
        }

        let shouldRestart = pendingResetScan
        pendingResetScan = false
        isScanningKeysRequest = false
        isLoadingKeys = false

        if isPattern {
            let entriesNeedingMetadata = keys.filter { entry in
                entry.type.isEmpty
            }
            loadKeyMetadata(for: entriesNeedingMetadata)
        }

        if shouldRestart {
            await scanKeys(reset: true)
        }
    }

    func clearSelectedKeyDetail() {
        selectedKey = nil
        keyDetail = ""
        keyDetailRows = []
        keyType = ""
        valueSize = nil
        keyDetailLength = nil
        keyDetailError = nil
        keyDetailOffset = 0
        keyDetailCursor = "0"
        keyDetailHasMoreRows = false
        keyDetailSearchText = ""
        keyDetailLastRefreshedAt = nil
        isLoadingDetail = false
    }

    @discardableResult
    func insertCreatedKeyIntoBrowser(name: String, type: String) -> RedisKeyEntry? {
        noteKeyCreated()
        guard keyMatchesCurrentFilter(name) else { return nil }

        let entry = RedisKeyEntry(key: name, type: type, ttl: nil, size: nil)
        if isCurrentKeyFilterPattern {
            keys.removeAll { $0.key == name }
            keys.insert(entry, at: 0)
            keyScannedCount = max(keyScannedCount, keys.count)
        } else {
            keys = [entry]
            scanCursor = "0"
            hasMoreKeys = false
            keyScannedCount = keyTotalCount ?? 1
            keyScanIterationCount = 0
            keyScanLimitReached = false
        }
        normalizeKeyScanProgress()

        loadKeyMetadata(for: [entry])
        return entry
    }

    private var isCurrentKeyFilterPattern: Bool {
        keyFilter.contains("*") || keyFilter.contains("?") || keyFilter.contains("[")
    }

    private func keyMatchesCurrentFilter(_ keyName: String) -> Bool {
        let filter = keyFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = filter.isEmpty ? "*" : filter
        guard pattern.contains("*") || pattern.contains("?") || pattern.contains("[") else {
            return pattern == keyName
        }
        return fnmatch(pattern, keyName, 0) == 0
    }

    private func refreshKeyTotalCount(using client: any RedisSession) async {
        do {
            keyTotalCount = try await client.totalKeyCount()
        } catch {
            keyTotalCount = nil
            AppLogger.debug("failed to load key total: \(error)", category: "Browser")
        }
    }

    private func normalizeKeyScanProgress() {
        guard let total = keyTotalCount else { return }
        if !hasMoreKeys || keyScannedCount > total {
            keyScannedCount = total
        }
    }

    private func noteKeyCreated() {
        if let total = keyTotalCount {
            keyTotalCount = total + 1
        }
        keyScannedCount += 1
        normalizeKeyScanProgress()
    }

    private func noteKeyDeleted() {
        if let total = keyTotalCount {
            keyTotalCount = max(0, total - 1)
        }
        keyScannedCount = max(0, keyScannedCount - 1)
        normalizeKeyScanProgress()
    }

    private func loadKeyMetadata(for entries: [RedisKeyEntry]) {
        guard let client = activeClient, client.isConnected else { return }
        guard !entries.isEmpty else { return }

        Task { @MainActor in
            for batchStart in stride(from: 0, to: entries.count, by: keyMetadataPipelineBatchSize) {
                let batchEnd = min(batchStart + keyMetadataPipelineBatchSize, entries.count)
                let batchEntries = Array(entries[batchStart..<batchEnd])
                let commands = batchEntries.map { entry in
                    ["TYPE", entry.key]
                }

                do {
                    let metadataResults = try await client.sendPipeline(commands)
                    applyMetadataResults(metadataResults, to: batchEntries)
                } catch {
                    connectionError = error.localizedDescription
                }
            }
        }
    }

    private func applyMetadataResults(_ results: [RESPValue], to entries: [RedisKeyEntry]) {
        for (entryIndex, entry) in entries.enumerated() {
            guard entryIndex < results.count else { continue }

            if let typeName = results[entryIndex].string {
                if typeName == "none" {
                    keys.removeAll { $0.key == entry.key }
                    if selectedKey?.key == entry.key {
                        clearSelectedKeyDetail()
                    }
                    continue
                }
                entry.type = typeName
            }

            if selectedKey?.key == entry.key {
                keyType = entry.type
            }
        }
    }

    func selectKey(_ entry: RedisKeyEntry) async {
        selectedKey = entry
        keyDetailSearchText = ""
        keyDetailZSetOrder = .ascending
        resetKeyDetailPaging(clearRows: true)
        await loadSelectedKeyDetail(append: false)
    }

    func loadMoreSelectedKeyDetailRows() async {
        guard keyDetailHasMoreRows, !isLoadingDetail else { return }
        await loadSelectedKeyDetail(append: true)
    }

    func searchSelectedKeyDetail(_ searchText: String) async {
        keyDetailSearchText = searchText
        resetKeyDetailPaging(clearRows: true)
        await loadSelectedKeyDetail(append: false)
    }

    func updateSelectedZSetOrder(_ order: KeyDetailZSetOrder) async {
        guard keyDetailZSetOrder != order else { return }
        keyDetailZSetOrder = order
        resetKeyDetailPaging(clearRows: true)
        await loadSelectedKeyDetail(append: false)
    }

    private func loadSelectedKeyDetail(append: Bool) async {
        guard let entry = selectedKey else { return }
        guard let client = activeClient else { return }

        isLoadingDetail = true
        keyDetailError = nil
        if !append {
            keyDetail = ""
            keyDetailRows = []
            valueSize = nil
            keyDetailLength = nil
        }

        do {
            let typeResult = try await client.send("TYPE", entry.key)
            try throwIfRedisError(typeResult)
            keyType = typeResult.string ?? "string"
            guard keyType != "none" else {
                keys.removeAll { $0.key == entry.key }
                clearSelectedKeyDetail()
                return
            }
            entry.type = keyType
            keyDetailLength = await loadLength(for: entry.key, type: keyType, using: client)
            entry.length = keyDetailLength

            switch keyType {
            case "string":
                let value = try await client.send("GET", entry.key)
                try throwIfRedisError(value)
                keyDetail = value.string ?? "(nil)"
                keyDetailHasMoreRows = false
            case "list":
                try await loadListDetail(key: entry.key, append: append, using: client)
            case "hash":
                try await loadHashDetail(key: entry.key, append: append, using: client)
            case "set":
                try await loadSetDetail(key: entry.key, append: append, using: client)
            case "zset":
                try await loadZSetDetail(key: entry.key, append: append, using: client)
            default:
                let value = try await client.send("GET", entry.key)
                try throwIfRedisError(value)
                keyDetail = value.string ?? "(nil)"
                keyDetailHasMoreRows = false
            }

            await refreshMetadata(for: entry, using: client)
            keyDetailLastRefreshedAt = Date()
        } catch {
            reportKeyOperationError(error)
        }
        isLoadingDetail = false
    }

    private func resetKeyDetailPaging(clearRows: Bool) {
        keyDetailOffset = 0
        keyDetailCursor = "0"
        keyDetailHasMoreRows = false
        keyDetailError = nil
        if clearRows {
            keyDetailRows = []
            keyDetail = ""
        }
    }

    private func refreshMetadata(for entry: RedisKeyEntry, using client: any RedisSession) async {
        do {
            let results = try await client.sendPipeline([
                ["TTL", entry.key],
                ["MEMORY", "USAGE", entry.key, "SAMPLES", "0"],
            ])
            entry.ttl = results.first?.intValue
            entry.size = results.dropFirst().first?.intValue
            valueSize = entry.size
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private func loadLength(for key: String, type: String, using client: any RedisSession) async -> Int? {
        let command: [String]?
        switch type {
        case "string": command = ["STRLEN", key]
        case "list": command = ["LLEN", key]
        case "hash": command = ["HLEN", key]
        case "set": command = ["SCARD", key]
        case "zset": command = ["ZCARD", key]
        default: command = nil
        }
        guard let command, let result = try? await client.send(command) else { return nil }
        return result.intValue
    }

    private func loadListDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        let start = append ? keyDetailOffset : 0
        let stop = start + keyDetailPageSize - 1
        let value = try await client.send("LRANGE", key, "\(start)", "\(stop)")
        try throwIfRedisError(value)
        let rows = value.arrayValues.enumerated().compactMap { index, value -> (String, String)? in
            guard let value else { return nil }
            return ("\(start + index)", value.string ?? value.displayString)
        }
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailOffset = start + rows.count
        if let keyDetailLength {
            keyDetailHasMoreRows = keyDetailOffset < keyDetailLength
        } else {
            keyDetailHasMoreRows = rows.count == keyDetailPageSize
        }
    }

    private func loadHashDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        var args = ["HSCAN", key, append ? keyDetailCursor : "0"]
        if let pattern = keyDetailMatchPattern {
            args.append(contentsOf: ["MATCH", pattern])
        }
        args.append(contentsOf: ["COUNT", "\(keyDetailPageSize)"])

        let response = try await client.send(args)
        let result = try parseScanValues(response, context: "HSCAN")
        let rows = keyValueRows(from: result.values)
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailCursor = result.nextCursor
        keyDetailHasMoreRows = result.nextCursor != "0"
    }

    private func loadSetDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        var args = ["SSCAN", key, append ? keyDetailCursor : "0"]
        if let pattern = keyDetailMatchPattern {
            args.append(contentsOf: ["MATCH", pattern])
        }
        args.append(contentsOf: ["COUNT", "\(keyDetailPageSize)"])

        let response = try await client.send(args)
        let result = try parseScanValues(response, context: "SSCAN")
        let baseIndex = append ? keyDetailRows.count : 0
        let rows = result.values.enumerated().compactMap { index, value -> (String, String)? in
            guard let value else { return nil }
            return ("[\(baseIndex + index)]", value.string ?? value.displayString)
        }
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailCursor = result.nextCursor
        keyDetailHasMoreRows = result.nextCursor != "0"
    }

    private func loadZSetDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        if keyDetailMatchPattern != nil {
            try await loadScannedZSetDetail(key: key, append: append, using: client)
            return
        }

        let start = append ? keyDetailOffset : 0
        let stop = start + keyDetailPageSize - 1
        let command = keyDetailZSetOrder == .descending ? "ZREVRANGE" : "ZRANGE"
        let value = try await client.send(command, key, "\(start)", "\(stop)", "WITHSCORES")
        try throwIfRedisError(value)
        let rows = scoredRows(from: value.arrayValues)
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailOffset = start + rows.count
        if let keyDetailLength {
            keyDetailHasMoreRows = keyDetailOffset < keyDetailLength
        } else {
            keyDetailHasMoreRows = rows.count == keyDetailPageSize
        }
    }

    private func loadScannedZSetDetail(key: String, append: Bool, using client: any RedisSession) async throws {
        var args = ["ZSCAN", key, append ? keyDetailCursor : "0"]
        if let pattern = keyDetailMatchPattern {
            args.append(contentsOf: ["MATCH", pattern])
        }
        args.append(contentsOf: ["COUNT", "\(keyDetailPageSize)"])

        let response = try await client.send(args)
        let result = try parseScanValues(response, context: "ZSCAN")
        let rows = scoredRows(from: result.values)
        if append {
            keyDetailRows.append(contentsOf: rows)
        } else {
            keyDetailRows = rows
        }
        keyDetailCursor = result.nextCursor
        keyDetailHasMoreRows = result.nextCursor != "0"
    }

    private var keyDetailMatchPattern: String? {
        let trimmed = keyDetailSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("*") || trimmed.contains("?") || trimmed.contains("[") {
            return trimmed
        }
        return "*\(trimmed)*"
    }

    private func parseScanValues(
        _ response: RESPValue,
        context: String
    ) throws -> (nextCursor: String, values: [RESPValue?]) {
        try throwIfRedisError(response)
        let values = response.arrayValues
        guard values.count >= 2, let cursor = values[0]?.string else {
            throw RedisError.parseError("Unexpected \(context) response")
        }
        return (nextCursor: cursor, values: values[1]?.arrayValues ?? [])
    }

    private func keyValueRows(from values: [RESPValue?]) -> [(String, String)] {
        var rows: [(String, String)] = []
        for value in values {
            guard let value else { continue }
            if case .array(let pair) = value, pair.count >= 2 {
                let key = pair[0]?.string ?? pair[0]?.displayString ?? ""
                let val = pair[1]?.string ?? pair[1]?.displayString ?? ""
                rows.append((key, val))
            }
        }
        if !rows.isEmpty { return rows }
        var itemIndex = 0
        while itemIndex + 1 < values.count {
            guard let key = values[itemIndex] else {
                itemIndex += 2
                continue
            }
            let value = values[itemIndex + 1]
            rows.append((key.string ?? key.displayString, value?.string ?? value?.displayString ?? ""))
            itemIndex += 2
        }
        return rows
    }

    private func scoredRows(from values: [RESPValue?]) -> [(String, String)] {
        var rows: [(String, String)] = []
        for value in values {
            guard let value else { continue }
            if case .array(let pair) = value, pair.count >= 2 {
                let member = pair[0]?.string ?? pair[0]?.displayString ?? ""
                let score = pair[1]?.string ?? pair[1]?.displayString ?? ""
                rows.append((score, member))
            }
        }
        if !rows.isEmpty { return rows }
        var itemIndex = 0
        while itemIndex + 1 < values.count {
            let member = values[itemIndex]?.string ?? values[itemIndex]?.displayString ?? ""
            let score = values[itemIndex + 1]?.string ?? values[itemIndex + 1]?.displayString ?? ""
            rows.append((score, member))
            itemIndex += 2
        }
        return rows
    }

    private func throwIfRedisError(_ value: RESPValue) throws {
        if case .error(let message) = value {
            throw RedisError.commandError(message)
        }
    }

    private func reportKeyOperationError(_ error: Error) {
        let message = error.localizedDescription
        connectionError = message
        keyDetailError = message
        keyDetail = "Error: \(message)"
    }

    func deleteKey(_ entry: RedisKeyEntry) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("DEL", entry.key)
            try throwIfRedisError(result)
            if (result.intValue ?? 0) > 0 {
                noteKeyDeleted()
            }
            keys.removeAll { $0.key == entry.key }
            if selectedKey?.key == entry.key {
                clearSelectedKeyDetail()
            }
        } catch {
            reportKeyOperationError(error)
        }
    }

    func renameKey(old: String, new: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("RENAMENX", old, new)
            try throwIfRedisError(result)
            guard result.intValue != 0 else {
                throw RedisError.commandError("Key \"\(new)\" already exists")
            }
            await scanKeys(reset: true)
        } catch {
            reportKeyOperationError(error)
        }
    }

    // MARK: - Key Editing

    func updateKeyTTL(_ entry: RedisKeyEntry, ttl: Int) async {
        guard let client = activeClient else { return }

        do {
            if ttl == -1 {
                let currentTTL = try? await client.send("TTL", entry.key)
                if (currentTTL?.intValue ?? -1) > 0 {
                    let result = try await client.send("PERSIST", entry.key)
                    try throwIfRedisError(result)
                }
                entry.ttl = -1
            } else {
                let result = try await client.send("EXPIRE", entry.key, "\(ttl)")
                try throwIfRedisError(result)
                if result.intValue == 0 || ttl == 0 {
                    if ttl == 0 {
                        noteKeyDeleted()
                    }
                    keys.removeAll { $0.key == entry.key }
                    if selectedKey?.key == entry.key {
                        clearSelectedKeyDetail()
                    }
                    return
                }
                entry.ttl = ttl
            }
        } catch {
            reportKeyOperationError(error)
        }
    }

    func updateStringValue(key: String, value: String) async {
        guard let client = activeClient else { return }
        do {
            let ttlResult = try await client.send("TTL", key)
            try throwIfRedisError(ttlResult)
            let ttl = ttlResult.intValue ?? -1

            let setResult = try await client.send("SET", key, value, "XX")
            try throwIfRedisError(setResult)
            guard setResult.string != nil else {
                throw RedisError.commandError("Key \"\(key)\" no longer exists")
            }

            if ttl > 0 {
                let expireResult = try await client.send("EXPIRE", key, "\(ttl)")
                try throwIfRedisError(expireResult)
            }
        } catch {
            reportKeyOperationError(error)
        }
    }

    func addHashField(key: String, field: String, value: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("HSET", key, field, value)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func updateHashField(key: String, field: String, value: String) async {
        await addHashField(key: key, field: field, value: value)
    }

    func deleteHashField(key: String, field: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("HDEL", key, field)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func addListElement(key: String, value: String, tail: Bool = false) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send(tail ? "RPUSHX" : "LPUSHX", key, value)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func updateListElement(key: String, index: Int, value: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("LSET", key, "\(index)", value)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func deleteListElement(key: String, index: Int) async {
        guard let client = activeClient else { return }
        let marker = "__redis_console_delete_\(UUID().uuidString)__"
        do {
            let setResult = try await client.send("LSET", key, "\(index)", marker)
            try throwIfRedisError(setResult)
            let removeResult = try await client.send("LREM", key, "1", marker)
            try throwIfRedisError(removeResult)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func addSetMember(key: String, member: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("SADD", key, member)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func deleteSetMember(key: String, member: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("SREM", key, member)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func addZSetMember(key: String, member: String, score: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("ZADD", key, "NX", score, member)
            try throwIfRedisError(result)
            guard result.intValue != 0 else {
                throw RedisError.commandError("Sorted set member already exists")
            }
        } catch {
            reportKeyOperationError(error)
        }
    }

    func updateZSetScore(key: String, member: String, score: String) async {
        guard let client = activeClient else { return }
        do {
            let currentScore = try await client.send("ZSCORE", key, member)
            try throwIfRedisError(currentScore)
            guard currentScore.string != nil else {
                throw RedisError.commandError("Sorted set member no longer exists")
            }

            let result = try await client.send("ZADD", key, "XX", "CH", score, member)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func deleteZSetMember(key: String, member: String) async {
        guard let client = activeClient else { return }
        do {
            let result = try await client.send("ZREM", key, member)
            try throwIfRedisError(result)
        } catch {
            reportKeyOperationError(error)
        }
    }

    func refreshSelectedKey() async {
        guard let selectedKey else { return }
        resetKeyDetailPaging(clearRows: true)
        await loadSelectedKeyDetail(append: false)
    }
}
