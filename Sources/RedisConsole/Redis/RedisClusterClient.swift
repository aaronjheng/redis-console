import Combine
import Foundation

struct RedisEndpoint: Codable, Hashable, Sendable {
    var host: String
    var port: UInt16

    var address: String {
        "\(host):\(port)"
    }

    static func parse(_ value: String, defaultPort: UInt16 = 6379) -> RedisEndpoint? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("://"), let components = URLComponents(string: trimmed), let host = components.host {
            return RedisEndpoint(host: host, port: UInt16(components.port ?? Int(defaultPort)))
        }

        if trimmed.hasPrefix("["), let closeIndex = trimmed.firstIndex(of: "]") {
            let hostStart = trimmed.index(after: trimmed.startIndex)
            let host = String(trimmed[hostStart..<closeIndex])
            let afterClose = trimmed.index(after: closeIndex)
            if afterClose < trimmed.endIndex, trimmed[afterClose] == ":" {
                let portStart = trimmed.index(after: afterClose)
                if let port = UInt16(trimmed[portStart...]) {
                    return RedisEndpoint(host: host, port: port)
                }
            }
            return RedisEndpoint(host: host, port: defaultPort)
        }

        if let colonIndex = trimmed.lastIndex(of: ":"), colonIndex > trimmed.startIndex {
            let portStart = trimmed.index(after: colonIndex)
            if let port = UInt16(trimmed[portStart...]) {
                let host = String(trimmed[..<colonIndex])
                return RedisEndpoint(host: host, port: port)
            }
        }

        return RedisEndpoint(host: trimmed, port: defaultPort)
    }

    static func parseList(_ value: String, defaultPort: UInt16 = 6379) -> [RedisEndpoint] {
        let separators = CharacterSet(charactersIn: ",;\n\t ")
        let parts = value.components(separatedBy: separators)
        return unique(parts.compactMap { RedisEndpoint.parse($0, defaultPort: defaultPort) })
    }

    static func unique(_ endpoints: [RedisEndpoint]) -> [RedisEndpoint] {
        var seen: Set<RedisEndpoint> = []
        var result: [RedisEndpoint] = []
        for endpoint in endpoints where !endpoint.host.isEmpty {
            if seen.insert(endpoint).inserted {
                result.append(endpoint)
            }
        }
        return result
    }
}

enum RedisConnectionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case standalone
    case cluster

    var title: String {
        switch self {
        case .standalone: return "Standalone"
        case .cluster: return "Cluster"
        }
    }
}

struct RedisScanResult: Sendable {
    let nextCursor: String
    let keys: [String]

    init(nextCursor: String, keys: [String]) {
        self.nextCursor = nextCursor
        self.keys = keys
    }

    init(response: RESPValue) throws {
        let values = response.arrayValues
        guard values.count >= 2, let cursor = values[0]?.string else {
            throw RedisError.parseError("Unexpected SCAN response")
        }
        nextCursor = cursor
        keys = values[1]?.arrayValues.compactMap { $0?.string } ?? []
    }
}

enum RedisClusterNodeRole: String, Hashable, Sendable {
    case primary
    case replica

    var title: String {
        switch self {
        case .primary: return "Primary"
        case .replica: return "Replica"
        }
    }
}

struct RedisClusterSlotRangeSummary: Hashable, Sendable {
    let start: Int
    let end: Int

    var label: String {
        start == end ? "\(start)" : "\(start)-\(end)"
    }

    var count: Int {
        max(0, end - start + 1)
    }
}

struct RedisClusterNodeSummary: Identifiable, Hashable, Sendable {
    let endpoint: RedisEndpoint
    let role: RedisClusterNodeRole
    let slotRanges: [RedisClusterSlotRangeSummary]
    let replicaOf: RedisEndpoint?

    var id: String {
        endpoint.address
    }

    var slotSummary: String {
        guard !slotRanges.isEmpty else { return "-" }
        return slotRanges.map(\.label).joined(separator: ", ")
    }

    var coveredSlotCount: Int {
        slotRanges.reduce(0) { $0 + $1.count }
    }
}

protocol RedisSession: AnyObject, Sendable {
    var mode: RedisConnectionMode { get }
    var isConnected: Bool { get }
    var lastError: String? { get }

    func connect() async throws
    func disconnect()
    func send(_ args: String...) async throws -> RESPValue
    func send(_ args: [String]) async throws -> RESPValue
    func sendPipeline(_ commands: [[String]]) async throws -> [RESPValue]
    func scan(cursor: String, match: String, count: Int) async throws -> RedisScanResult
}

protocol RedisClusterEndpointResolver: Sendable {
    func clientEndpoint(for endpoint: RedisEndpoint) async throws -> RedisEndpoint
    func disconnect() async
}

extension RedisClient: RedisSession {
    var mode: RedisConnectionMode { .standalone }

    func scan(cursor: String, match: String, count: Int) async throws -> RedisScanResult {
        let response = try await send("SCAN", cursor, "MATCH", match, "COUNT", "\(count)")
        return try RedisScanResult(response: response)
    }
}

final class RedisClusterClient: ObservableObject, RedisSession, @unchecked Sendable {
    private let seedNodes: [RedisEndpoint]
    private let makeClient: @Sendable (RedisEndpoint) -> RedisClient
    private let endpointResolver: (any RedisClusterEndpointResolver)?
    private let state = RedisClusterState()

    @Published var isConnected = false
    @Published var lastError: String?

    var mode: RedisConnectionMode { .cluster }

    init(
        seedNodes: [RedisEndpoint],
        username: String? = nil,
        password: String? = nil,
        tlsEnabled: Bool = false,
        verifyServerCertificate: Bool = true,
        caCertificatePath: String = "",
        clientCertificatePath: String = "",
        clientKeyPath: String = "",
        preferredProtocolVersion: RESPProtocolVersion = .resp3,
        endpointResolver: (any RedisClusterEndpointResolver)? = nil
    ) {
        self.seedNodes = RedisEndpoint.unique(seedNodes)
        self.endpointResolver = endpointResolver
        self.makeClient = { endpoint in
            RedisClient(
                host: endpoint.host,
                port: endpoint.port,
                username: username,
                password: password,
                tlsEnabled: tlsEnabled,
                verifyServerCertificate: verifyServerCertificate,
                caCertificatePath: caCertificatePath,
                clientCertificatePath: clientCertificatePath,
                clientKeyPath: clientKeyPath,
                preferredProtocolVersion: preferredProtocolVersion
            )
        }
    }

    func connect() async throws {
        guard !seedNodes.isEmpty else {
            throw RedisError.commandError("At least one Redis Cluster seed node is required")
        }

        do {
            try await refreshTopology(preferredEndpoint: seedNodes.first)
            let primaries = await state.primaryEndpoints()
            guard !primaries.isEmpty else {
                throw RedisError.commandError("Redis Cluster topology has no primary nodes")
            }
            isConnected = true
            lastError = nil
        } catch {
            isConnected = false
            lastError = error.localizedDescription
            throw error
        }
    }

    func disconnect() {
        disconnect(publishState: true)
    }

    func send(_ args: String...) async throws -> RESPValue {
        try await send(args)
    }

    func send(_ args: [String]) async throws -> RESPValue {
        guard isConnected else {
            throw RedisError.notConnected
        }
        guard !args.isEmpty else {
            throw RedisError.commandError("Redis command is empty")
        }

        var forcedEndpoint: RedisEndpoint?
        var shouldSendAsking = false
        var attempt = 0
        let maxRedirects = 5

        while attempt <= maxRedirects {
            let endpoint: RedisEndpoint
            if let forcedEndpoint {
                endpoint = forcedEndpoint
            } else {
                endpoint = try await routeEndpoint(for: args)
            }
            let response = try await sendDirect(args, to: endpoint, asking: shouldSendAsking)

            if case .error(let message) = response {
                if let redirect = RedisClusterRedirect(message: message, fallbackHost: endpoint.host) {
                    attempt += 1
                    switch redirect.kind {
                    case .moved:
                        await state.replaceOwner(slot: redirect.slot, with: redirect.endpoint)
                        try? await refreshTopology(preferredEndpoint: redirect.endpoint)
                        forcedEndpoint = redirect.endpoint
                        shouldSendAsking = false
                    case .ask:
                        forcedEndpoint = redirect.endpoint
                        shouldSendAsking = true
                    }
                    continue
                }
            }

            return response
        }

        throw RedisError.commandError("Too many Redis Cluster redirects")
    }

    func sendPipeline(_ commands: [[String]]) async throws -> [RESPValue] {
        guard isConnected else {
            throw RedisError.notConnected
        }
        guard !commands.isEmpty else { return [] }
        guard commands.allSatisfy({ !$0.isEmpty }) else {
            throw RedisError.commandError("Redis command is empty")
        }

        var groupedCommands: [RedisEndpoint: [(index: Int, command: [String])]] = [:]
        for (index, command) in commands.enumerated() {
            let endpoint = try await routeEndpoint(for: command)
            groupedCommands[endpoint, default: []].append((index, command))
        }

        let groupedBatches = groupedCommands.map { endpoint, commands in
            (endpoint: endpoint, commands: commands)
        }
        var orderedResponses = [RESPValue?](repeating: nil, count: commands.count)

        try await withThrowingTaskGroup(
            of: [(index: Int, command: [String], endpoint: RedisEndpoint, response: RESPValue)].self
        ) { group in
            for batch in groupedBatches {
                group.addTask { [self] in
                    let batchCommands = batch.commands.map(\.command)
                    let responses = try await sendDirectPipeline(batchCommands, to: batch.endpoint)
                    return zip(batch.commands, responses).map { indexedCommand, response in
                        (
                            index: indexedCommand.index,
                            command: indexedCommand.command,
                            endpoint: batch.endpoint,
                            response: response
                        )
                    }
                }
            }

            for try await batchResponses in group {
                for batchResponse in batchResponses {
                    if case .error(let message) = batchResponse.response {
                        let redirect = RedisClusterRedirect(message: message, fallbackHost: batchResponse.endpoint.host)
                        if redirect != nil {
                            orderedResponses[batchResponse.index] = try await send(batchResponse.command)
                            continue
                        }
                    }
                    orderedResponses[batchResponse.index] = batchResponse.response
                }
            }
        }

        var responses: [RESPValue] = []
        responses.reserveCapacity(commands.count)
        for response in orderedResponses {
            guard let response else {
                throw RedisError.parseError("Missing Redis pipeline response")
            }
            responses.append(response)
        }
        return responses
    }

    func scan(cursor: String, match: String, count: Int) async throws -> RedisScanResult {
        guard isConnected else {
            throw RedisError.notConnected
        }

        var primaries = await state.primaryEndpoints()
        if primaries.isEmpty {
            try await refreshTopology(preferredEndpoint: nil)
            primaries = await state.primaryEndpoints()
        }
        guard !primaries.isEmpty else {
            throw RedisError.commandError("Redis Cluster topology has no primary nodes")
        }

        var scanCursor = RedisClusterScanCursor.parse(cursor)
        if scanCursor.nodeIndex >= primaries.count {
            scanCursor = RedisClusterScanCursor(nodeIndex: 0, nodeCursor: "0")
        }

        var keys: [String] = []
        var nextCursor = cursor
        var attempts = 0
        let maxAttempts = max(1, primaries.count * 3)

        repeat {
            let endpoint = primaries[scanCursor.nodeIndex]
            let response = try await sendDirect(
                ["SCAN", scanCursor.nodeCursor, "MATCH", match, "COUNT", "\(count)"],
                to: endpoint,
                asking: false
            )
            if case .error(let message) = response {
                throw RedisError.commandError(message)
            }

            let result = try RedisScanResult(response: response)
            keys.append(contentsOf: result.keys)

            if result.nextCursor == "0" {
                scanCursor = RedisClusterScanCursor(nodeIndex: scanCursor.nodeIndex + 1, nodeCursor: "0")
            } else {
                scanCursor = RedisClusterScanCursor(nodeIndex: scanCursor.nodeIndex, nodeCursor: result.nextCursor)
            }

            if scanCursor.nodeIndex >= primaries.count {
                nextCursor = "0"
            } else {
                nextCursor = scanCursor.storageValue
            }

            attempts += 1
        } while keys.isEmpty && nextCursor != "0" && attempts < maxAttempts

        return RedisScanResult(nextCursor: nextCursor, keys: keys)
    }

    func clusterNodes() async throws -> [RedisClusterNodeSummary] {
        guard isConnected else {
            throw RedisError.notConnected
        }

        var nodes = await state.nodeSummaries()
        if nodes.isEmpty {
            try await refreshTopology(preferredEndpoint: nil)
            nodes = await state.nodeSummaries()
        }
        return nodes
    }

    func send(_ args: [String], to endpoint: RedisEndpoint) async throws -> RESPValue {
        guard isConnected else {
            throw RedisError.notConnected
        }
        return try await sendDirect(args, to: endpoint, asking: false)
    }

    private func routeEndpoint(for args: [String]) async throws -> RedisEndpoint {
        let keys = try RedisClusterCommandKeys.keys(in: args)
        guard !keys.isEmpty else {
            if let endpoint = await state.defaultEndpoint() {
                return endpoint
            }
            return seedNodes[0]
        }

        let slots = Set(keys.map { RedisClusterHash.slot(for: $0) })
        guard slots.count == 1, let slot = slots.first else {
            throw RedisError.commandError("Command keys do not hash to the same Redis Cluster slot")
        }

        if let endpoint = await state.owner(for: slot) {
            return endpoint
        }

        try await refreshTopology(preferredEndpoint: nil)
        if let endpoint = await state.owner(for: slot) {
            return endpoint
        }

        throw RedisError.commandError("Redis Cluster topology does not cover slot \(slot)")
    }

    private func sendDirect(_ args: [String], to endpoint: RedisEndpoint, asking: Bool) async throws -> RESPValue {
        let client = try await state.client(
            for: endpoint,
            endpointResolver: endpointResolver,
            makeClient: makeClient
        )
        if asking {
            let response = try await client.send("ASKING")
            if case .error = response {
                return response
            }
        }
        return try await client.send(args)
    }

    private func sendDirectPipeline(_ commands: [[String]], to endpoint: RedisEndpoint) async throws -> [RESPValue] {
        let client = try await state.client(
            for: endpoint,
            endpointResolver: endpointResolver,
            makeClient: makeClient
        )
        return try await client.sendPipeline(commands)
    }

    private func refreshTopology(preferredEndpoint: RedisEndpoint?) async throws {
        var candidates: [RedisEndpoint] = []
        if let preferredEndpoint {
            candidates.append(preferredEndpoint)
        }
        candidates.append(contentsOf: await state.primaryEndpoints())
        candidates.append(contentsOf: seedNodes)
        candidates = RedisEndpoint.unique(candidates)

        var lastError: Error?
        for endpoint in candidates {
            do {
                let client = try await state.client(
                    for: endpoint,
                    endpointResolver: endpointResolver,
                    makeClient: makeClient
                )
                let response = try await client.send("CLUSTER", "SLOTS")
                if case .error(let message) = response {
                    throw RedisError.commandError(
                        "Selected mode is Cluster, but \(endpoint.address) did not return cluster slots: \(message)"
                    )
                }

                let ranges = try Self.parseClusterSlots(response, fallbackHost: endpoint.host)
                await state.updateTopology(ranges, defaultEndpoint: endpoint)
                try await validateClusterState(using: client, endpoint: endpoint)
                return
            } catch {
                lastError = error
                AppLogger.debug("cluster topology refresh failed endpoint=\(endpoint.address) error=\(error)")
            }
        }

        throw lastError ?? RedisError.commandError("Unable to load Redis Cluster topology")
    }

    private func validateClusterState(using client: RedisClient, endpoint: RedisEndpoint) async throws {
        let response = try await client.send("CLUSTER", "INFO")
        if case .error(let message) = response {
            throw RedisError.commandError("Unable to read Redis Cluster state from \(endpoint.address): \(message)")
        }
        guard let info = response.string else { return }
        guard
            info.components(separatedBy: "\n").contains(where: { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines) == "cluster_state:ok"
            })
        else {
            throw RedisError.commandError("Redis Cluster state is not ok on \(endpoint.address)")
        }
    }

    private static func parseClusterSlots(_ value: RESPValue, fallbackHost: String) throws -> [RedisClusterSlotRange] {
        let items = value.arrayValues
        var ranges: [RedisClusterSlotRange] = []

        for item in items {
            guard let entry = item?.arrayValues, entry.count >= 3,
                let start = entry[0]?.intValue,
                let end = entry[1]?.intValue,
                let primaryNode = entry[2]?.arrayValues
            else {
                continue
            }

            let primary = try parseNodeEndpoint(primaryNode, fallbackHost: fallbackHost)
            let replicas = entry.dropFirst(3).compactMap { node -> RedisEndpoint? in
                guard let values = node?.arrayValues else { return nil }
                return try? parseNodeEndpoint(values, fallbackHost: fallbackHost)
            }
            ranges.append(RedisClusterSlotRange(start: start, end: end, primary: primary, replicas: replicas))
        }

        guard !ranges.isEmpty else {
            throw RedisError.parseError("Unexpected CLUSTER SLOTS response")
        }
        return ranges
    }

    private static func parseNodeEndpoint(_ values: [RESPValue?], fallbackHost: String) throws -> RedisEndpoint {
        guard values.count >= 2,
            let portValue = values[1]?.intValue,
            let port = UInt16(exactly: portValue)
        else {
            throw RedisError.parseError("Unexpected CLUSTER SLOTS node endpoint")
        }

        let rawHost = values[0]?.string ?? ""
        let host = rawHost.isEmpty || rawHost == "?" ? fallbackHost : rawHost
        return RedisEndpoint(host: host, port: port)
    }

    deinit {
        disconnect(publishState: false)
    }

    private func disconnect(publishState: Bool) {
        if publishState {
            isConnected = false
        }
        let state = state
        let endpointResolver = endpointResolver
        Task {
            await state.disconnectAll()
            await endpointResolver?.disconnect()
        }
    }
}

private actor RedisClusterState {
    private final class PendingConnectionClientBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedClient: RedisClient?

        func set(_ client: RedisClient) {
            lock.lock()
            storedClient = client
            lock.unlock()
        }

        func client() -> RedisClient? {
            lock.lock()
            defer { lock.unlock() }
            return storedClient
        }

        func disconnect() {
            client()?.disconnect()
        }
    }

    private struct PendingConnection {
        let id: UUID
        let generation: Int
        let clientBox: PendingConnectionClientBox
        let task: Task<RedisClient, Error>
    }

    private var clients: [RedisEndpoint: RedisClient] = [:]
    private var connectionTasks: [RedisEndpoint: PendingConnection] = [:]
    private var slotOwners = [RedisEndpoint?](repeating: nil, count: RedisClusterHash.slotCount)
    private var primaries: [RedisEndpoint] = []
    private var slotRanges: [RedisClusterSlotRange] = []
    private var fallbackEndpoint: RedisEndpoint?
    private var generation = 0

    func client(
        for endpoint: RedisEndpoint,
        endpointResolver: (any RedisClusterEndpointResolver)?,
        makeClient: @Sendable @escaping (RedisEndpoint) -> RedisClient
    ) async throws -> RedisClient {
        if let client = clients[endpoint], client.isConnected {
            return client
        }

        if let pendingConnection = connectionTasks[endpoint] {
            return try await resolveConnectionTask(pendingConnection, endpoint: endpoint)
        }

        let clientBox = PendingConnectionClientBox()
        let task = Task { [endpointResolver, makeClient] in
            let clientEndpoint: RedisEndpoint
            if let endpointResolver {
                clientEndpoint = try await endpointResolver.clientEndpoint(for: endpoint)
            } else {
                clientEndpoint = endpoint
            }
            try Task.checkCancellation()
            let client = makeClient(clientEndpoint)
            clientBox.set(client)
            try await client.connect()
            return client
        }
        let pendingConnection = PendingConnection(
            id: UUID(),
            generation: generation,
            clientBox: clientBox,
            task: task
        )
        connectionTasks[endpoint] = pendingConnection

        return try await resolveConnectionTask(pendingConnection, endpoint: endpoint)
    }

    private func resolveConnectionTask(
        _ pendingConnection: PendingConnection,
        endpoint: RedisEndpoint
    ) async throws -> RedisClient {
        do {
            let client = try await pendingConnection.task.value
            guard pendingConnection.generation == generation else {
                clearConnectionTask(pendingConnection, endpoint: endpoint)
                client.disconnect()
                throw RedisError.notConnected
            }
            clients[endpoint] = client
            clearConnectionTask(pendingConnection, endpoint: endpoint)
            return client
        } catch {
            clearConnectionTask(pendingConnection, endpoint: endpoint)
            removeCachedClient(for: endpoint, matching: pendingConnection)
            pendingConnection.clientBox.disconnect()
            throw error
        }
    }

    private func removeCachedClient(for endpoint: RedisEndpoint, matching pendingConnection: PendingConnection) {
        guard let pendingClient = pendingConnection.clientBox.client(), let client = clients[endpoint] else { return }
        guard ObjectIdentifier(client) == ObjectIdentifier(pendingClient) else { return }
        clients[endpoint] = nil
    }

    private func clearConnectionTask(_ pendingConnection: PendingConnection, endpoint: RedisEndpoint) {
        guard let current = connectionTasks[endpoint],
            current.generation == pendingConnection.generation,
            current.id == pendingConnection.id
        else {
            return
        }
        connectionTasks[endpoint] = nil
    }

    func updateTopology(_ ranges: [RedisClusterSlotRange], defaultEndpoint: RedisEndpoint) {
        var owners = [RedisEndpoint?](repeating: nil, count: RedisClusterHash.slotCount)
        var primarySet: Set<RedisEndpoint> = []
        var nextPrimaries: [RedisEndpoint] = []

        for range in ranges {
            guard range.start >= 0, range.end < RedisClusterHash.slotCount, range.start <= range.end else {
                continue
            }
            for slot in range.start...range.end {
                owners[slot] = range.primary
            }
            if primarySet.insert(range.primary).inserted {
                nextPrimaries.append(range.primary)
            }
        }

        slotOwners = owners
        primaries = nextPrimaries.sorted { $0.address < $1.address }
        slotRanges = ranges
        fallbackEndpoint = defaultEndpoint
    }

    func owner(for slot: Int) -> RedisEndpoint? {
        guard slot >= 0, slot < slotOwners.count else { return nil }
        return slotOwners[slot]
    }

    func replaceOwner(slot: Int, with endpoint: RedisEndpoint) {
        guard slot >= 0, slot < slotOwners.count else { return }
        slotOwners[slot] = endpoint
        if !primaries.contains(endpoint) {
            primaries.append(endpoint)
            primaries.sort { $0.address < $1.address }
        }
    }

    func primaryEndpoints() -> [RedisEndpoint] {
        primaries
    }

    func nodeSummaries() -> [RedisClusterNodeSummary] {
        var slotRangesByEndpoint: [RedisEndpoint: [RedisClusterSlotRangeSummary]] = [:]
        var replicaOfByEndpoint: [RedisEndpoint: RedisEndpoint] = [:]
        var rolesByEndpoint: [RedisEndpoint: RedisClusterNodeRole] = [:]

        for range in slotRanges {
            let summary = RedisClusterSlotRangeSummary(start: range.start, end: range.end)
            slotRangesByEndpoint[range.primary, default: []].append(summary)
            rolesByEndpoint[range.primary] = .primary

            for replica in range.replicas {
                replicaOfByEndpoint[replica] = range.primary
                rolesByEndpoint[replica] = .replica
            }
        }

        return rolesByEndpoint.keys.sorted { left, right in
            let leftRole = rolesByEndpoint[left] ?? .replica
            let rightRole = rolesByEndpoint[right] ?? .replica
            if leftRole != rightRole {
                return leftRole == .primary
            }
            return left.address < right.address
        }.map { endpoint in
            RedisClusterNodeSummary(
                endpoint: endpoint,
                role: rolesByEndpoint[endpoint] ?? .replica,
                slotRanges: (slotRangesByEndpoint[endpoint] ?? []).sorted { $0.start < $1.start },
                replicaOf: replicaOfByEndpoint[endpoint]
            )
        }
    }

    func defaultEndpoint() -> RedisEndpoint? {
        fallbackEndpoint ?? primaries.first
    }

    func disconnectAll() {
        generation += 1

        let pendingConnections = Array(connectionTasks.values)
        let connectedClients = Array(clients.values)

        connectionTasks.removeAll()
        clients.removeAll()

        for pendingConnection in pendingConnections {
            pendingConnection.task.cancel()
            pendingConnection.clientBox.disconnect()
        }

        for client in connectedClients {
            client.disconnect()
        }

        slotOwners = [RedisEndpoint?](repeating: nil, count: RedisClusterHash.slotCount)
        primaries = []
        slotRanges = []
        fallbackEndpoint = nil
    }
}

private struct RedisClusterSlotRange: Sendable {
    let start: Int
    let end: Int
    let primary: RedisEndpoint
    let replicas: [RedisEndpoint]
}

private struct RedisClusterScanCursor: Sendable {
    let nodeIndex: Int
    let nodeCursor: String

    var storageValue: String {
        "cluster:\(nodeIndex):\(nodeCursor)"
    }

    static func parse(_ value: String) -> RedisClusterScanCursor {
        guard value.hasPrefix("cluster:") else {
            return RedisClusterScanCursor(nodeIndex: 0, nodeCursor: value.isEmpty ? "0" : value)
        }

        let parts = value.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let index = Int(parts[1]) else {
            return RedisClusterScanCursor(nodeIndex: 0, nodeCursor: "0")
        }

        return RedisClusterScanCursor(nodeIndex: index, nodeCursor: parts[2])
    }
}

private enum RedisClusterRedirectKind: Sendable {
    case moved
    case ask
}

private struct RedisClusterRedirect: Sendable {
    let kind: RedisClusterRedirectKind
    let slot: Int
    let endpoint: RedisEndpoint

    init?(message: String, fallbackHost: String) {
        let parts = message.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3, let slot = Int(parts[1]) else { return nil }

        switch parts[0].uppercased() {
        case "MOVED":
            kind = .moved
        case "ASK":
            kind = .ask
        default:
            return nil
        }

        guard let endpoint = RedisEndpoint.parse(parts[2]) else { return nil }
        self.slot = slot
        if endpoint.host.isEmpty {
            self.endpoint = RedisEndpoint(host: fallbackHost, port: endpoint.port)
        } else {
            self.endpoint = endpoint
        }
    }
}

private enum RedisClusterCommandKeys {
    private static let noKeyCommands: Set<String> = [
        "AUTH", "CLIENT", "CLUSTER", "COMMAND", "CONFIG", "DBSIZE", "ECHO", "HELLO", "INFO",
        "LASTSAVE", "PING", "QUIT", "READONLY", "READWRITE", "ROLE", "SCAN", "SELECT",
        "SLOWLOG", "TIME",
    ]

    private static let firstKeyCommands: Set<String> = [
        "APPEND", "BITCOUNT", "BITFIELD", "BITOP", "BITPOS", "DECR", "DECRBY", "DUMP",
        "EXPIRE", "EXPIREAT", "GET", "GETBIT", "GETDEL", "GETEX", "GETRANGE", "GETSET",
        "HDEL", "HEXISTS", "HGET", "HGETALL", "HINCRBY", "HINCRBYFLOAT", "HKEYS", "HLEN",
        "HMGET", "HMSET", "HRANDFIELD", "HSCAN", "HSET", "HSETNX", "HSTRLEN", "HVALS",
        "INCR", "INCRBY", "INCRBYFLOAT", "LINDEX", "LINSERT", "LLEN", "LMOVE", "LPOP",
        "LPOS", "LPUSH", "LPUSHX", "LRANGE", "LREM", "LSET", "LTRIM", "OBJECT", "PERSIST",
        "PEXPIRE", "PEXPIREAT", "PFADD", "PFCOUNT", "PFMERGE", "PSETEX", "PTTL", "RESTORE",
        "RPOP", "RPOPLPUSH", "RPUSH", "RPUSHX", "SADD", "SCARD", "SDIFF", "SINTER",
        "SISMEMBER", "SMEMBERS", "SMISMEMBER", "SMOVE", "SORT", "SPOP", "SRANDMEMBER",
        "SREM", "SSCAN", "STRLEN", "TOUCH", "TTL", "TYPE", "UNLINK", "WATCH", "ZADD",
        "ZCARD", "ZCOUNT", "ZINCRBY", "ZLEXCOUNT", "ZPOPMAX", "ZPOPMIN", "ZRANDMEMBER",
        "ZRANGE", "ZRANGEBYLEX", "ZRANGEBYSCORE", "ZRANGESTORE", "ZRANK", "ZREM",
        "ZREMRANGEBYLEX", "ZREMRANGEBYRANK", "ZREMRANGEBYSCORE", "ZREVRANGE",
        "ZREVRANGEBYLEX", "ZREVRANGEBYSCORE", "ZREVRANK", "ZSCAN", "ZSCORE",
    ]

    private static let allKeyCommands: Set<String> = [
        "DEL", "EXISTS", "MGET",
    ]

    private static let blockingMultiKeyWithTimeoutCommands: Set<String> = [
        "BLMOVE", "BLPOP", "BRPOP", "BRPOPLPUSH", "BZPOPMAX", "BZPOPMIN",
    ]

    static func keys(in args: [String]) throws -> [String] {
        guard let command = args.first?.uppercased() else { return [] }

        if noKeyCommands.contains(command) {
            return []
        }

        if firstKeyCommands.contains(command) {
            return args.count > 1 ? [args[1]] : []
        }

        if allKeyCommands.contains(command) {
            return Array(args.dropFirst())
        }

        switch command {
        case "MSET", "MSETNX":
            return stride(from: 1, to: args.count, by: 2).map { args[$0] }
        case "RENAME", "RENAMENX", "COPY":
            return Array(args.dropFirst().prefix(2))
        case "MEMORY":
            if args.count > 2, args[1].uppercased() == "USAGE" {
                return [args[2]]
            }
            return []
        case "EVAL", "EVALSHA", "EVAL_RO", "EVALSHA_RO":
            guard args.count > 2, let keyCount = Int(args[2]) else { return [] }
            guard keyCount > 0 else { return [] }
            let start = 3
            let end = min(args.count, start + keyCount)
            return Array(args[start..<end])
        case "XREAD", "XREADGROUP":
            guard let streamsIndex = args.firstIndex(where: { $0.uppercased() == "STREAMS" }) else { return [] }
            let remaining = args[(streamsIndex + 1)...]
            return Array(remaining.prefix(remaining.count / 2))
        case "ZUNION", "ZINTER", "ZDIFF":
            guard args.count > 2, let keyCount = Int(args[1]) else { return [] }
            let start = 2
            let end = min(args.count, start + keyCount)
            return Array(args[start..<end])
        case "ZUNIONSTORE", "ZINTERSTORE", "ZDIFFSTORE", "SUNIONSTORE", "SINTERSTORE", "SDIFFSTORE":
            guard args.count > 3, let keyCount = Int(args[2]) else {
                return args.count > 1 ? [args[1]] : []
            }
            let start = 3
            let end = min(args.count, start + keyCount)
            return [args[1]] + Array(args[start..<end])
        default:
            if blockingMultiKeyWithTimeoutCommands.contains(command), args.count > 2 {
                return Array(args.dropFirst().dropLast())
            }
            return []
        }
    }
}

private enum RedisClusterHash {
    static let slotCount = 16_384

    static func slot(for key: String) -> Int {
        let bytes = Array(key.utf8)
        let hashBytes = hashTagBytes(in: bytes)
        return Int(crc16(hashBytes) % UInt16(slotCount))
    }

    private static func hashTagBytes(in bytes: [UInt8]) -> [UInt8] {
        guard let openIndex = bytes.firstIndex(of: UInt8(ascii: "{")) else {
            return bytes
        }

        let tagStart = openIndex + 1
        guard tagStart < bytes.count else {
            return bytes
        }

        guard let closeIndex = bytes[tagStart...].firstIndex(of: UInt8(ascii: "}")),
            closeIndex > tagStart
        else {
            return bytes
        }

        return Array(bytes[tagStart..<closeIndex])
    }

    private static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc &<< 1) ^ 0x1021
                } else {
                    crc = crc &<< 1
                }
            }
        }
        return crc
    }
}
