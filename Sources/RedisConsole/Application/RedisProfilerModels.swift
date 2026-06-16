import Foundation

// MARK: - Profiler

final class RedisProfilerTaskBag: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Task<Void, Never>] = []

    func add(_ task: Task<Void, Never>) {
        lock.lock()
        tasks.append(task)
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        let tasks = tasks
        self.tasks.removeAll()
        lock.unlock()

        for task in tasks {
            task.cancel()
        }
    }
}

struct RedisProfilerCapture: Sendable {
    let node: RedisEndpoint?
    let line: String
}

struct RedisProfilerStream {
    let stream: AsyncThrowingStream<RedisProfilerCapture, Error>
    let monitorClients: [RedisMonitorClient]
    let monitorTasks: RedisProfilerTaskBag?
    let tunnel: SSHTunnel?
    let tunnelManager: SSHClusterTunnelManager?
}

struct RedisProfilerEntry: Identifiable, Hashable {
    private struct ParsedLine {
        let timestamp: Date
        let database: Int?
        let source: String
        let commandName: String
        let commandText: String
        let arguments: [String]
    }

    let id = UUID()
    let timestamp: Date
    let database: Int?
    let source: String
    let commandName: String
    let commandText: String
    let arguments: [String]
    let rawLine: String
    let node: RedisEndpoint?

    init(rawLine: String, node: RedisEndpoint? = nil, capturedAt: Date = Date()) {
        self.rawLine = rawLine
        self.node = node

        let parsed = Self.parse(rawLine: rawLine, capturedAt: capturedAt)
        timestamp = parsed.timestamp
        database = parsed.database
        source = parsed.source
        commandName = parsed.commandName
        commandText = parsed.commandText
        arguments = parsed.arguments
    }

    var databaseText: String {
        database.map(String.init) ?? "-"
    }

    var nodeText: String {
        node?.address ?? "-"
    }

    var timeText: String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: timestamp)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        let millisecond = (components.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d", hour, minute, second, millisecond)
    }

    var argumentsText: String {
        guard arguments.count > 1 else { return "" }
        return arguments.dropFirst().map(Self.displayArgument).joined(separator: " ")
    }

    var searchText: String {
        ([databaseText, nodeText, source, commandName, commandText, rawLine] + arguments)
            .joined(separator: " ")
            .lowercased()
    }

    var isNoiseCommand: Bool {
        switch commandName {
        case "PING":
            return true
        case "CLUSTER":
            guard arguments.count > 1 else { return false }
            return Self.noiseClusterSubcommands.contains(arguments[1].uppercased())
        default:
            return false
        }
    }

    private static let noiseClusterSubcommands: Set<String> = [
        "INFO",
        "NODES",
        "SHARDS",
        "SLOTS",
    ]

    private static func parse(
        rawLine: String,
        capturedAt: Date
    ) -> ParsedLine {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestampEnd = trimmed.firstIndex(of: " ") ?? trimmed.endIndex
        let timestampText = String(trimmed[..<timestampEnd])
        let timestamp = Double(timestampText).map { Date(timeIntervalSince1970: $0) } ?? capturedAt

        var remainder =
            timestampEnd < trimmed.endIndex
            ? String(trimmed[trimmed.index(after: timestampEnd)...]).trimmingCharacters(in: .whitespaces)
            : ""

        var database: Int?
        var source = "-"

        if remainder.first == "[", let closeBracketIndex = remainder.firstIndex(of: "]") {
            let metadataStart = remainder.index(after: remainder.startIndex)
            let metadata = String(remainder[metadataStart..<closeBracketIndex])
            let parts = metadata.split(separator: " ", maxSplits: 1).map(String.init)
            database = parts.first.flatMap(Int.init)
            if parts.count > 1 {
                source = parts[1]
            } else if !metadata.isEmpty {
                source = metadata
            }

            let commandStart = remainder.index(after: closeBracketIndex)
            remainder = String(remainder[commandStart...]).trimmingCharacters(in: .whitespaces)
        }

        let arguments = parseArguments(remainder)
        let commandName = arguments.first?.uppercased() ?? "-"
        let commandText = arguments.isEmpty ? remainder : arguments.map(displayArgument).joined(separator: " ")
        return ParsedLine(
            timestamp: timestamp,
            database: database,
            source: source,
            commandName: commandName,
            commandText: commandText,
            arguments: arguments
        )
    }

    private static func parseArguments(_ value: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in value {
            if isQuoted {
                if isEscaped {
                    current.append(unescaped(character))
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    arguments.append(current)
                    current = ""
                    isQuoted = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                isQuoted = true
            }
        }

        if isQuoted || !current.isEmpty {
            arguments.append(current)
        }

        return arguments
    }

    private static func unescaped(_ character: Character) -> Character {
        switch character {
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        default: return character
        }
    }

    private static func displayArgument(_ value: String) -> String {
        if value.isEmpty {
            return "\"\""
        }

        let needsQuoting = value.contains { character in
            character.isWhitespace || character == "\""
        }
        guard needsQuoting else { return value }

        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

// MARK: - Profiler Statistics

struct ProfilerStats {
    var commandFrequency: [(command: String, count: Int)] = []
    var commandTypeDistribution: [(type: String, count: Int)] = []
    var databaseDistribution: [(database: String, count: Int)] = []
    var sourceDistribution: [(source: String, count: Int)] = []

    static func compute(from entries: [RedisProfilerEntry]) -> ProfilerStats {
        var cmdCounts: [String: Int] = [:]
        var typeCounts: [String: Int] = [:]
        var dbCounts: [String: Int] = [:]
        var srcCounts: [String: Int] = [:]

        for entry in entries {
            cmdCounts[entry.commandName, default: 0] += 1

            let cmdType = commandCategory(entry.commandName)
            typeCounts[cmdType, default: 0] += 1

            let db = entry.database.map(String.init) ?? "-"
            dbCounts[db, default: 0] += 1

            srcCounts[entry.source, default: 0] += 1
        }

        return ProfilerStats(
            commandFrequency: cmdCounts
                .sorted { $0.value > $1.value }
                .prefix(10)
                .map { ($0.key, $0.value) },
            commandTypeDistribution: typeCounts
                .sorted { $0.value > $1.value }
                .map { ($0.key, $0.value) },
            databaseDistribution: dbCounts
                .sorted { $0.key < $1.key }
                .map { ($0.key, $0.value) },
            sourceDistribution: srcCounts
                .sorted { $0.value > $1.value }
                .prefix(10)
                .map { ($0.key, $0.value) }
        )
    }

    private static func commandCategory(_ command: String) -> String {
        let readCommands: Set<String> = ["GET", "MGET", "HGET", "HGETALL", "HMGET", "HEXISTS", "HKEYS", "HLEN", "HSTRLEN", "HVALS", "LINDEX", "LLEN", "LRANGE", "SCARD", "SDIFF", "SINTER", "SISMEMBER", "SMEMBERS", "SRANDMEMBER", "SUNION", "ZCOUNT", "ZCARD", "ZRANGE", "ZRANK", "ZREVRANK", "ZREVRANGE", "ZSCORE", "ZLEXCOUNT", "TYPE", "EXISTS", "TTL", "PTTL", "KEYS", "SCAN", "RANDOMKEY", "DBSIZE", "INFO", "TIME", "CLIENT", "SLOWLOG", "COMMAND", "ACL", "MEMORY", "OBJECT", "PING", "ECHO", "SELECT"]
        let writeCommands: Set<String> = ["SET", "SETEX", "PSETEX", "SETNX", "MSET", "MSETNX", "GETSET", "APPEND", "INCR", "INCRBY", "INCRBYFLOAT", "DECR", "DECRBY", "HSET", "HMSET", "HSETNX", "HDEL", "HINCRBY", "HINCRBYFLOAT", "LPUSH", "LPUSHX", "RPUSH", "RPUSHX", "LINSERT", "LSET", "LREM", "LPOP", "RPOP", "RPOPLPUSH", "SADD", "SREM", "SMOVE", "SPOP", "ZADD", "ZINCRBY", "ZREM", "ZREMRANGEBYSCORE", "ZREMRANGEBYRANK", "ZREMRANGEBYLEX", "DEL", "UNLINK", "EXPIRE", "EXPIREAT", "PEXPIRE", "PEXPIREAT", "RENAME", "RENAMENX", "MOVE", "RESTORE", "SWAPDB", "COPY", "FLUSHDB", "FLUSHALL", "SORT"]
        let adminCommands: Set<String> = ["CONFIG", "SHUTDOWN", "DEBUG", "SLAVEOF", "REPLICAOF", "ROLE", "REPLCONF", "CLUSTER", "BGREWRITEAOF", "BGSAVE", "SAVE", "LASTSAVE", "MONITOR", "SYNC", "PSYNC", "CLIENT", "SLOWLOG", "COMMAND", "ACL", "MEMORY", "OBJECT", "LATENCY", "MODULE", "SUBSCRIBE", "UNSUBSCRIBE", "PUBLISH", "PUBSUB", "PFADD", "PFCOUNT", "PFMERGE", "GEOADD", "GEODIST", "GEOHASH", "GEOPOS", "GEORADIUS", "GEORADIUSBYMEMBER", "XADD", "XREAD", "XDEL", "XTRIM", "XLEN", "XRANGE", "XREVRANGE", "XGROUP", "XREADGROUP", "XACK", "XCLAIM", "XPENDING", "XINFO"]

        if readCommands.contains(command) { return "Read" }
        if writeCommands.contains(command) { return "Write" }
        if adminCommands.contains(command) { return "Admin" }
        return "Other"
    }
}
