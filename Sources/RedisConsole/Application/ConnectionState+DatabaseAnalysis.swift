import Foundation

extension ConnectionState {
    // MARK: - Database Analysis

    private static let analysisSampleLimit = 10_000
    private static let analysisTopKeysCount = 50

    func runDatabaseAnalysis() async {
        guard let client = activeClient, client.isConnected else { return }
        isLoadingAnalysis = true
        analysisError = nil
        analysis = nil

        let analysisTask = Task { @MainActor in
            var result = DatabaseAnalysis()

            do {
                // 1. Server Metrics from INFO
                let infoResult = try await client.send("INFO")
                if case .error(let message) = infoResult {
                    throw RedisError.commandError(message)
                }
                if let infoStr = infoResult.string {
                    let parsed = parseServerInfoForAnalysis(infoStr)
                    result.serverMetrics = parsed.metrics
                    result.totalKeys = parsed.totalKeys
                }

                try Task.checkCancellation()

                // 2. Scan keys for sampling
                var sampledKeys: [String] = []
                var cursor = "0"
                var hasMore = true

                while hasMore && sampledKeys.count < Self.analysisSampleLimit {
                    let scanResult = try await client.scan(
                        cursor: cursor, match: "*", count: Self.analysisSampleLimit
                    )
                    cursor = scanResult.nextCursor
                    hasMore = cursor != "0"
                    sampledKeys.append(contentsOf: scanResult.keys)
                }

                result.keysSampled = sampledKeys.count
                result.isEstimate = hasMore && sampledKeys.count >= Self.analysisSampleLimit

                try Task.checkCancellation()

                guard !sampledKeys.isEmpty else {
                    result.analyzedAt = Date()
                    analysis = result
                    isLoadingAnalysis = false
                    return
                }

                // 3. Type Distribution via pipeline
                let typeCommands = sampledKeys.map { ["TYPE", $0] }
                let typeResults = try await client.sendPipeline(typeCommands)

                var typeCount: [String: Int] = [:]
                for typeResult in typeResults {
                    let typeName = typeResult.string ?? "unknown"
                    typeCount[typeName, default: 0] += 1
                }

                try Task.checkCancellation()

                // 4. Memory usage and TTL for top keys
                let memoryCommands = sampledKeys.map { ["MEMORY", "USAGE", $0, "SAMPLES", "0"] }
                let memoryResults = try await client.sendPipeline(memoryCommands)

                let ttlCommands = sampledKeys.map { ["TTL", $0] }
                let ttlResults = try await client.sendPipeline(ttlCommands)

                var keyMemoryEntries: [KeyMemoryEntry] = []
                var typeMemory: [String: Int] = [:]
                var typeCountFinal: [String: Int] = [:]
                var expirationBuckets: [String: (count: Int, memory: Int)] = [
                    "< 1h": (0, 0), "1-6h": (0, 0), "6-24h": (0, 0),
                    "1-7d": (0, 0), "7-30d": (0, 0), "> 30d": (0, 0), "No expiry": (0, 0),
                ]

                for (index, key) in sampledKeys.enumerated() {
                    let typeName = index < typeResults.count ? typeResults[index].string ?? "unknown" : "unknown"
                    let memory = index < memoryResults.count ? memoryResults[index].intValue ?? 0 : 0
                    let ttl = index < ttlResults.count ? ttlResults[index].intValue : nil

                    typeCountFinal[typeName, default: 0] += 1
                    typeMemory[typeName, default: 0] += memory
                    result.totalMemory += memory

                    keyMemoryEntries.append(KeyMemoryEntry(
                        key: key, type: typeName, memory: memory, length: 0, ttl: ttl
                    ))

                    // Expiration buckets
                    let bucketLabel = expirationBucketLabel(for: ttl)
                    var bucket = expirationBuckets[bucketLabel] ?? (0, 0)
                    bucket.count += 1
                    bucket.memory += memory
                    expirationBuckets[bucketLabel] = bucket
                }

                // Type distribution
                for (type, count) in typeCountFinal {
                    let mem = typeMemory[type] ?? 0
                    result.typeDistribution[type] = TypeStats(count: count, memory: mem)
                }

                // Top keys by memory (sorted descending)
                result.topKeysByMemory = Array(keyMemoryEntries
                    .sorted { $0.memory > $1.memory }
                    .prefix(Self.analysisTopKeysCount))

                // Namespace aggregation
                let separator = namespaceSeparator.isEmpty ? ":" : namespaceSeparator
                var namespaceAgg: [String: (count: Int, memory: Int, types: [String: Int])] = [:]
                for entry in keyMemoryEntries {
                    let ns = namespaceFromKey(entry.key, separator: separator)
                    var agg = namespaceAgg[ns] ?? (0, 0, [:])
                    agg.count += 1
                    agg.memory += entry.memory
                    agg.types[entry.type, default: 0] += 1
                    namespaceAgg[ns] = agg
                }
                result.topNamespaces = namespaceAgg
                    .map { NamespaceStats(namespace: $0.key, keyCount: $0.value.count, totalMemory: $0.value.memory, types: $0.value.types) }
                    .sorted { $0.totalMemory > $1.totalMemory }
                    .prefix(20)
                    .map { $0 }

                // Expiration summary
                result.expirationSummary = expirationBuckets
                    .map { ExpirationBucket(label: $0.key, keyCount: $0.value.count, estimatedMemory: $0.value.memory) }
                    .sorted { bucketSortIndex($0.label) < bucketSortIndex($1.label) }

                result.analyzedAt = Date()
                analysis = result
                isLoadingAnalysis = false
            } catch is CancellationError {
                isLoadingAnalysis = false
            } catch {
                analysisError = error.localizedDescription
                isLoadingAnalysis = false
            }
        }

        analysisTaskHandle = analysisTask
        await analysisTask.value
    }

    func cancelAnalysis() {
        analysisTaskHandle?.cancel()
        analysisTaskHandle = nil
    }

    private func parseServerInfoForAnalysis(_ infoStr: String) -> (metrics: ServerMetrics, totalKeys: Int) {
        var metrics = ServerMetrics()
        var totalKeys = 0
        var currentSection = ""

        for line in infoStr.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                currentSection = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let separatorIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separatorIndex])
            let valueStart = trimmed.index(after: separatorIndex)
            let value = String(trimmed[valueStart...])

            switch currentSection {
            case "Memory":
                switch key {
                case "used_memory": metrics.usedMemory = Int(value) ?? 0
                case "used_memory_human": metrics.usedMemoryHuman = value
                case "used_memory_rss": metrics.usedMemoryRSS = Int(value) ?? 0
                case "mem_fragmentation_ratio": metrics.memoryFragmentationRatio = Double(value) ?? 0
                default: break
                }
            case "Stats":
                switch key {
                case "keyspace_hits": metrics.keyspaceHits = Int(value) ?? 0
                case "keyspace_misses": metrics.keyspaceMisses = Int(value) ?? 0
                case "instantaneous_ops_per_sec": metrics.opsPerSecond = Int(value) ?? 0
                case "evicted_keys": metrics.evictedKeys = Int(value) ?? 0
                case "expired_keys": metrics.expiredKeys = Int(value) ?? 0
                default: break
                }
            case "Clients":
                switch key {
                case "connected_clients": metrics.connectedClients = Int(value) ?? 0
                case "blocked_clients": metrics.blockedClients = Int(value) ?? 0
                default: break
                }
            case "Server":
                if key == "uptime_in_seconds" {
                    metrics.uptimeInSeconds = Int(value) ?? 0
                }
            case "Keyspace":
                if key.hasPrefix("db") {
                    // db0:keys=12345,expires=234,avg_ttl=45678
                    if let keysRange = value.range(of: "keys="),
                       let commaRange = value[keysRange.upperBound...].firstIndex(of: ",") {
                        let keysStr = value[keysRange.upperBound..<commaRange]
                        totalKeys += Int(keysStr) ?? 0
                    }
                }
            default:
                break
            }
        }

        let totalOps = metrics.keyspaceHits + metrics.keyspaceMisses
        metrics.hitRate = totalOps > 0 ? Double(metrics.keyspaceHits) / Double(totalOps) * 100 : 0

        return (metrics, totalKeys)
    }

    private func expirationBucketLabel(for ttl: Int?) -> String {
        guard let ttl, ttl > 0 else { return "No expiry" }
        switch ttl {
        case ..<3600: return "< 1h"
        case ..<21600: return "1-6h"
        case ..<86400: return "6-24h"
        case ..<604800: return "1-7d"
        case ..<2592000: return "7-30d"
        default: return "> 30d"
        }
    }

    private func bucketSortIndex(_ label: String) -> Int {
        switch label {
        case "< 1h": return 0
        case "1-6h": return 1
        case "6-24h": return 2
        case "1-7d": return 3
        case "7-30d": return 4
        case "> 30d": return 5
        case "No expiry": return 6
        default: return 7
        }
    }

    private func namespaceFromKey(_ key: String, separator: String) -> String {
        guard !separator.isEmpty else { return "default" }
        if let range = key.range(of: separator) {
            return String(key[..<range.lowerBound])
        }
        return "default"
    }
}
