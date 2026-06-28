import Foundation

// MARK: - Fake Redis Data

struct FakeRedisData: Sendable {
    struct Key: Sendable {
        let name: String
        let type: String
        let stringValue: String
        let hashFields: [(String, String)]
        let listElements: [String]
        let setMembers: [String]
        let zsetMembers: [(String, Double)]
        let ttl: Int
        let memoryUsage: Int
    }

    struct SlowLogItem: Sendable {
        let id: Int
        let timestamp: Int
        let duration: Int
        let command: [String]
        let clientIP: String
        let clientName: String
    }

    let keys: [Key]
    let serverInfoText: String
    let moduleList: [[(String, String)]]
    let slowLogEntries: [SlowLogItem]

    static let `default` = FakeRedisData(
        keys: [
            Key(
                name: "user:1001", type: "hash", stringValue: "",
                hashFields: [
                    ("name", "Alice"), ("email", "alice@example.com"), ("age", "30"), ("created_at", "2024-01-15"),
                    ("last_login", "2026-06-20"),
                ],
                listElements: [], setMembers: [], zsetMembers: [], ttl: 3600, memoryUsage: 128),
            Key(
                name: "user:1002", type: "hash", stringValue: "",
                hashFields: [("name", "Bob"), ("email", "bob@example.com"), ("age", "25"), ("created_at", "2024-03-10")],
                listElements: [], setMembers: [], zsetMembers: [], ttl: -1, memoryUsage: 96),
            Key(
                name: "session:abc123", type: "string",
                stringValue: "{\"user_id\":1001,\"token\":\"abc123\",\"expires\":\"2026-06-27T00:00:00Z\"}",
                hashFields: [], listElements: [], setMembers: [], zsetMembers: [], ttl: 1800, memoryUsage: 72),
            Key(
                name: "session:def456", type: "string",
                stringValue: "{\"user_id\":1002,\"token\":\"def456\",\"expires\":\"2026-06-27T00:00:00Z\"}",
                hashFields: [], listElements: [], setMembers: [], zsetMembers: [], ttl: 1800, memoryUsage: 72),
            Key(
                name: "config:app:port", type: "string", stringValue: "6379",
                hashFields: [], listElements: [], setMembers: [], zsetMembers: [], ttl: -1, memoryUsage: 24),
            Key(
                name: "config:app:name", type: "string", stringValue: "Redis Console",
                hashFields: [], listElements: [], setMembers: [], zsetMembers: [], ttl: -1, memoryUsage: 32),
            Key(
                name: "cache:product:42", type: "string",
                stringValue:
                    "Product 42 is a premium widget with advanced features including smart connectivity, voice control, and energy-efficient operation. Designed for modern homes and offices.",
                hashFields: [], listElements: [], setMembers: [], zsetMembers: [], ttl: 7200, memoryUsage: 184),
            Key(
                name: "leaderboard:daily", type: "zset", stringValue: "",
                hashFields: [], listElements: [], setMembers: [],
                zsetMembers: [
                    ("player_one", 1500), ("player_two", 1350), ("player_three", 1200), ("player_four", 1100), ("player_five", 950),
                    ("player_six", 800), ("player_seven", 650), ("player_eight", 500),
                ],
                ttl: -1, memoryUsage: 256),
            Key(
                name: "tags:popular", type: "set", stringValue: "",
                hashFields: [], listElements: [],
                setMembers: ["redis", "database", "cache", "nosql", "persistence"],
                zsetMembers: [], ttl: -1, memoryUsage: 80),
            Key(
                name: "queue:emails", type: "list", stringValue: "",
                hashFields: [],
                listElements: [
                    "welcome_user_1001", "verify_email_alice", "newsletter_weekly", "password_reset_abc", "notification_def456",
                ],
                setMembers: [], zsetMembers: [], ttl: -1, memoryUsage: 160),
            Key(
                name: "user:1001:cart", type: "list", stringValue: "",
                hashFields: [],
                listElements: ["product:42", "product:17", "product:88"],
                setMembers: [], zsetMembers: [], ttl: -1, memoryUsage: 72),
            Key(
                name: "metrics:requests", type: "hash", stringValue: "",
                hashFields: [("total", "45230"), ("errors", "12"), ("avg_latency_ms", "3"), ("p99_latency_ms", "15")],
                listElements: [], setMembers: [], zsetMembers: [], ttl: -1, memoryUsage: 88),
            Key(
                name: "feature:flags", type: "hash", stringValue: "",
                hashFields: [("new_ui", "true"), ("beta_features", "false"), ("dark_mode", "true"), ("ssh_tunnels", "true")],
                listElements: [], setMembers: [], zsetMembers: [], ttl: -1, memoryUsage: 96),
            Key(
                name: "counter:visits", type: "string", stringValue: "12345",
                hashFields: [], listElements: [], setMembers: [], zsetMembers: [], ttl: -1, memoryUsage: 24),
            Key(
                name: "log:recent", type: "list", stringValue: "",
                hashFields: [],
                listElements: [
                    "[INFO] Server started", "[INFO] Client connected", "[WARN] High memory usage", "[ERROR] Connection timeout",
                    "[INFO] Backup completed", "[INFO] Client disconnected", "[WARN] Slow query detected", "[INFO] Cleanup finished",
                ],
                setMembers: [], zsetMembers: [], ttl: -1, memoryUsage: 240),
        ],
        serverInfoText: """
            # Server
            redis_version:7.2.0
            redis_git_sha1:0
            redis_git_dirty:0
            redis_build_id:1234567
            redis_mode:standalone
            os:Darwin 24.0.0
            arch_bits:64
            monotonic_clock:1234567890
            multiplexing_api:kqueue
            process_id:1234
            run_id:abc123def456
            tcp_port:6379
            server_time_usec:1719417600000000
            uptime_in_seconds:86400
            uptime_in_days:1
            hz:10
            configured_hz:10
            lru_clock:12345678
            executable:/usr/local/bin/redis-server
            config_file:/etc/redis/redis.conf
            io_threads_active:0
            listener0:name=tcp,bind=127.0.0.1,port=6379

            # Clients
            connected_clients:3
            cluster_connections:0
            maxclients:10000
            client_recent_max_input_buffer:2048
            client_recent_max_output_buffer:0
            blocked_clients:0
            tracking_clients:0
            pubsub_clients:0
            watching_clients:0
            clients_in_timeout_table:0
            total_watched_keys:0
            total_blocking_keys:0
            total_blocking_keys_on_nokey:0

            # Memory
            used_memory:1048576
            used_memory_human:1.00M
            used_memory_rss:2097152
            used_memory_rss_human:2.00M
            used_memory_peak:1572864
            used_memory_peak_human:1.50M
            used_memory_peak_perc:66.67%
            used_memory_overhead:524288
            used_memory_startup:524288
            used_memory_dataset:524288
            used_memory_dataset_perc:50.00%
            allocator_allocated:1048576
            allocator_active:2097152
            allocator_resident:2097152
            total_system_memory:17179869184
            total_system_memory_human:16.00G
            used_memory_lua:32768
            used_memory_vm_eval:32768
            used_memory_lua_human:32.00K
            used_memory_scripts:0
            used_memory_scripts_human:0B
            number_of_cached_scripts:0
            number_of_functions:0
            number_of_libraries:0
            maxmemory:0
            maxmemory_human:0B
            maxmemory_policy:noeviction
            allocator_frag_ratio:2.00
            allocator_frag_bytes:1048576
            allocator_rss_ratio:1.00
            allocator_rss_bytes:0
            rss_overhead_ratio:1.00
            rss_overhead_bytes:0
            mem_fragmentation_ratio:2.00
            mem_fragmentation_bytes:1048576
            mem_not_counted_for_evict:0
            mem_replication_backlog:0
            mem_total_replication_buffers:0
            mem_clients_slaves:0
            mem_clients_normal:10240
            mem_cluster_links:0
            mem_aof_buffer:0
            mem_allocator:libmalloc

            # Persistence
            loading:0
            async_loading:0
            current_cow_peak:0
            current_cow_size:0
            current_cow_size_age:0
            current_fork_perc:0.00
            current_save_keys_processed:0
            current_save_keys_total:0
            rdb_changes_since_last_save:0
            rdb_bgsave_in_progress:0
            rdb_last_save_time:1719414000
            rdb_last_bgsave_status:ok
            rdb_last_bgsave_time_sec:1
            rdb_current_bgsave_time_sec:-1
            rdb_saves:1
            rdb_last_cow_size:0
            rdb_last_load_keys_expired:0
            rdb_last_load_keys_loaded:15
            aof_enabled:0
            aof_rewrite_in_progress:0
            aof_rewrite_scheduled:0
            aof_last_rewrite_time_sec:-1
            aof_current_rewrite_time_sec:-1
            aof_last_bgrewrite_status:ok
            aof_last_write_status:ok
            aof_last_cow_size:0
            module_fork_in_progress:0
            module_fork_last_cow_size:0

            # Stats
            total_connections_received:15
            total_commands_processed:1234
            instantaneous_ops_per_sec:5
            total_net_input_bytes:56789
            total_net_output_bytes:98765
            instantaneous_input_kbps:0.05
            instantaneous_output_kbps:0.10
            rejected_connections:0
            sync_full:0
            sync_partial_ok:0
            sync_partial_err:0
            expired_keys:2
            expired_stale_perc:0.00
            expired_time_cap_reached_count:0
            expire_cycle_cpu_milliseconds:10
            evicted_keys:0
            evicted_clients:0
            evicted_scripts:0
            total_eviction_exceeded_time:0
            current_eviction_exceeded_time:0
            keyspace_hits:150
            keyspace_misses:30
            pubsub_channels:0
            pubsub_patterns:0
            pubsubshard_channels:0
            latest_fork_usec:500
            total_forks:1
            migrate_cached_sockets:0
            slave_expires_tracked_keys:0
            active_defrag_hits:0
            active_defrag_misses:0
            active_defrag_key_hits:0
            active_defrag_key_misses:0
            total_active_defrag_time:0
            current_active_defrag_time:0
            tracking_total_keys:0
            tracking_total_items:0
            tracking_total_prefixes:0
            unexpected_error_replies:0
            total_error_replies:0
            dump_payload_sanitizations:0
            total_reads_processed:1234
            total_writes_processed:1234
            io_threaded_reads_processed:0
            io_threaded_writes_processed:0
            client_query_buffer_limit_disconnections:0
            client_output_buffer_limit_disconnections:0
            reply_buffer_shrinks:0
            reply_buffer_expands:0
            eventloop_cycles:100000
            eventloop_duration_sum:500000
            eventloop_duration_cmd_sum:100000
            instantaneous_eventloop_cycles_per_sec:100
            instantaneous_eventloop_duration_usec:5
            acl_access_denied_auth:0
            acl_access_denied_cmd:0
            acl_access_denied_key:0
            acl_access_denied_channel:0

            # Replication
            role:master
            connected_slaves:0
            master_failover_state:no-failover
            master_replid:abc123def456abc123def456abc123de
            master_replid2:0000000000000000000000000000000000000000
            master_repl_offset:0
            second_repl_offset:-1
            repl_backlog_active:0
            repl_backlog_size:1048576
            repl_backlog_first_byte_offset:0
            repl_backlog_histlen:0

            # CPU
            used_cpu_sys:0.500000
            used_cpu_user:1.200000
            used_cpu_sys_children:0.000000
            used_cpu_user_children:0.000000
            used_cpu_sys_main_thread:0.500000
            used_cpu_user_main_thread:1.200000

            # Modules
            module:name=ReJSON,ver=20000,api=1,filters=0,usedby=[],using=[],options=[]
            module:name=search,ver=21000,api=1,filters=0,usedby=[],using=[],options=[]

            # Commandstats
            cmdstat_get:calls=150,usec=500,usec_per_call=3.33,rejected_calls=0,failed_calls=0
            cmdstat_set:calls=50,usec=200,usec_per_call=4.00,rejected_calls=0,failed_calls=0
            cmdstat_keys:calls=5,usec=100,usec_per_call=20.00,rejected_calls=0,failed_calls=0
            cmdstat_type:calls=15,usec=30,usec_per_call=2.00,rejected_calls=0,failed_calls=0
            cmdstat_scan:calls=10,usec=80,usec_per_call=8.00,rejected_calls=0,failed_calls=0

            # Errorstats
            errorstat_ERR:count=0
            errorstat_WRONGTYPE:count=0

            # Latencystats
            latency_percentiles_usec_get:p50=3,p99=10,p99.9=15
            latency_percentiles_usec_set:p50=4,p99=15,p99.9=20
            latency_percentiles_usec_scan:p50=8,p99=30,p99.9=50

            # Keyspace
            db0:keys=15,expires=4,avg_ttl=2700000
            """,
        moduleList: [
            [("name", "ReJSON"), ("ver", "20000"), ("api", "1"), ("filters", "0"), ("usedby", "[]"), ("using", "[]"), ("options", "[]")],
            [("name", "search"), ("ver", "21000"), ("api", "1"), ("filters", "0"), ("usedby", "[]"), ("using", "[]"), ("options", "[]")],
        ],
        slowLogEntries: [
            SlowLogItem(
                id: 5, timestamp: 1_719_417_600, duration: 15_000, command: ["KEYS", "*"], clientIP: "127.0.0.1:54321", clientName: ""),
            SlowLogItem(
                id: 4, timestamp: 1_719_417_500, duration: 8_500, command: ["SMEMBERS", "tags:popular"], clientIP: "127.0.0.1:54321",
                clientName: ""),
            SlowLogItem(
                id: 3, timestamp: 1_719_417_400, duration: 3_200, command: ["HGETALL", "user:1001"], clientIP: "127.0.0.1:54322",
                clientName: ""),
            SlowLogItem(
                id: 2, timestamp: 1_719_417_300, duration: 1_500, command: ["LRANGE", "queue:emails", "0", "-1"],
                clientIP: "127.0.0.1:54321", clientName: ""),
            SlowLogItem(
                id: 1, timestamp: 1_719_417_200, duration: 800, command: ["GET", "config:app:port"], clientIP: "127.0.0.1:54323",
                clientName: ""),
        ]
    )

    func key(_ name: String) -> Key? {
        keys.first { $0.name == name }
    }
}

// MARK: - Fake Redis Session

final class FakeRedisSession: RedisSession, @unchecked Sendable {
    let data: FakeRedisData

    init(data: FakeRedisData = .default) {
        self.data = data
    }

    var mode: RedisConnectionMode { .standalone }
    var isConnected: Bool { true }
    var lastError: String? { nil }

    func connect() async throws {}

    func disconnect() {}

    func send(_ args: String...) async throws -> RESPValue {
        try await send(args)
    }

    func send(_ args: [String]) async throws -> RESPValue {
        guard let command = args.first?.uppercased() else {
            return .null
        }

        switch command {
        case "PING":
            return .simpleString("PONG")

        case "TYPE":
            let keyName = args[safe: 1] ?? ""
            return .simpleString(data.key(keyName)?.type ?? "none")

        case "GET":
            let keyName = args[safe: 1] ?? ""
            guard let key = data.key(keyName), key.type == "string" else {
                return .null
            }
            return .bulkString(key.stringValue)

        case "LRANGE":
            let keyName = args[safe: 1] ?? ""
            let start = Int(args[safe: 2] ?? "0") ?? 0
            let stop = Int(args[safe: 3] ?? "-1") ?? -1
            guard let key = data.key(keyName), key.type == "list" else {
                return .array([])
            }
            let elements = key.listElements
            let resolvedStart = start < 0 ? max(0, elements.count + start) : start
            let resolvedStop = stop < 0 ? elements.count - 1 : min(stop, elements.count - 1)
            guard resolvedStart <= resolvedStop, resolvedStart < elements.count else {
                return .array([])
            }
            let slice = Array(elements[resolvedStart...resolvedStop])
            return .array(slice.map { .bulkString($0) })

        case "HSCAN":
            return scanCollection(args, type: "hash")

        case "SSCAN":
            return scanCollection(args, type: "set")

        case "ZSCAN":
            return scanCollection(args, type: "zset")

        case "ZRANGE", "ZREVRANGE":
            let keyName = args[safe: 1] ?? ""
            let start = Int(args[safe: 2] ?? "0") ?? 0
            let stop = Int(args[safe: 3] ?? "-1") ?? -1
            let withScores = args.contains { $0.uppercased() == "WITHSCORES" }
            guard let key = data.key(keyName), key.type == "zset" else {
                return .array([])
            }
            var members = key.zsetMembers
            if command == "ZREVRANGE" {
                members = members.reversed()
            }
            let resolvedStart = start < 0 ? max(0, members.count + start) : start
            let resolvedStop = stop < 0 ? members.count - 1 : min(stop, members.count - 1)
            guard resolvedStart <= resolvedStop, resolvedStart < members.count else {
                return .array([])
            }
            let slice = Array(members[resolvedStart...resolvedStop])
            if withScores {
                var result: [RESPValue?] = []
                for (member, score) in slice {
                    result.append(.array([.bulkString(member), .bulkString(String(score))]))
                }
                return .array(result)
            }
            return .array(slice.map { .bulkString($0.0) })

        case "INFO":
            return .bulkString(data.serverInfoText)

        case "DBSIZE":
            return .integer(data.keys.count)

        case "SLOWLOG":
            let subcommand = args[safe: 1]?.uppercased() ?? ""
            if subcommand == "GET" {
                let entries: [RESPValue?] = data.slowLogEntries.map { entry in
                    .array([
                        .integer(entry.id),
                        .integer(entry.timestamp),
                        .integer(entry.duration),
                        .array(entry.command.map { .bulkString($0) }),
                        .bulkString(entry.clientIP),
                        .bulkString(entry.clientName),
                    ])
                }
                return .array(entries)
            }
            if subcommand == "LEN" {
                return .integer(data.slowLogEntries.count)
            }
            return .array([])

        case "MODULE":
            let subcommand = args[safe: 1]?.uppercased() ?? ""
            if subcommand == "LIST" {
                let modules: [RESPValue?] = data.moduleList.map { moduleFields in
                    var pairs: [RESPValue?] = []
                    for (key, value) in moduleFields {
                        pairs.append(.bulkString(key))
                        pairs.append(.bulkString(value))
                    }
                    return .array(pairs)
                }
                return .array(modules)
            }
            return .array([])

        case "TTL":
            let keyName = args[safe: 1] ?? ""
            return .integer(data.key(keyName)?.ttl ?? -1)

        case "MEMORY":
            let subcommand = args[safe: 1]?.uppercased() ?? ""
            if subcommand == "USAGE" {
                let keyName = args[safe: 2] ?? ""
                return .integer(data.key(keyName)?.memoryUsage ?? 0)
            }
            return .null

        case "STRLEN":
            let keyName = args[safe: 1] ?? ""
            guard let key = data.key(keyName), key.type == "string" else {
                return .integer(0)
            }
            return .integer(key.stringValue.count)

        case "HLEN":
            let keyName = args[safe: 1] ?? ""
            guard let key = data.key(keyName), key.type == "hash" else {
                return .integer(0)
            }
            return .integer(key.hashFields.count)

        case "LLEN":
            let keyName = args[safe: 1] ?? ""
            guard let key = data.key(keyName), key.type == "list" else {
                return .integer(0)
            }
            return .integer(key.listElements.count)

        case "SCARD":
            let keyName = args[safe: 1] ?? ""
            guard let key = data.key(keyName), key.type == "set" else {
                return .integer(0)
            }
            return .integer(key.setMembers.count)

        case "ZCARD":
            let keyName = args[safe: 1] ?? ""
            guard let key = data.key(keyName), key.type == "zset" else {
                return .integer(0)
            }
            return .integer(key.zsetMembers.count)

        case "CLUSTER":
            let subcommand = args[safe: 1]?.uppercased() ?? ""
            if subcommand == "INFO" {
                return .bulkString(
                    "cluster_enabled:0\r\ncluster_state:ok\r\ncluster_slots_assigned:0\r\ncluster_slots_ok:0\r\ncluster_slots_pfail:0\r\ncluster_slots_fail:0\r\ncluster_known_nodes:1\r\ncluster_size:0\r\n"
                )
            }
            if subcommand == "NODES" {
                return .bulkString("")
            }
            return .null

        case "HELLO":
            return .simpleString("redis")

        case "COMMAND":
            return .array([])

        case "CLIENT":
            return .simpleString("OK")

        case "CONFIG":
            return .array([])

        default:
            return .null
        }
    }

    func sendPipeline(_ commands: [[String]]) async throws -> [RESPValue] {
        try await withThrowingTaskGroup(of: RESPValue.self) { group in
            for command in commands {
                group.addTask { [self] in
                    try await self.send(command)
                }
            }
            var results: [RESPValue] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }

    func scan(cursor: String, match: String, count: Int) async throws -> RedisScanResult {
        let pattern = match.isEmpty ? "*" : match
        let matchingKeys = data.keys.compactMap { key -> String? in
            if fnmatch(pattern, key.name, 0) == 0 {
                return key.name
            }
            return nil
        }
        return RedisScanResult(nextCursor: "0", keys: matchingKeys, scannedCount: matchingKeys.count)
    }

    func totalKeyCount() async throws -> Int? {
        data.keys.count
    }

    // MARK: - Private Helpers

    private func scanCollection(_ args: [String], type: String) -> RESPValue {
        let keyName = args[safe: 1] ?? ""
        guard let key = data.key(keyName), key.type == type else {
            return .array([.bulkString("0"), .array([])])
        }

        let hasMatch = args.contains { $0.uppercased() == "MATCH" }
        var matchPattern = "*"
        if hasMatch, let matchIndex = args.firstIndex(where: { $0.uppercased() == "MATCH" }) {
            matchIndex + 1 < args.count ? { matchPattern = args[matchIndex + 1] }() : ()
        }

        switch type {
        case "hash":
            let filtered = key.hashFields.filter { fnmatch(matchPattern, $0.0, 0) == 0 }
            var values: [RESPValue?] = []
            for (field, value) in filtered {
                values.append(.array([.bulkString(field), .bulkString(value)]))
            }
            return .array([.bulkString("0"), .array(values)])

        case "set":
            let filtered = key.setMembers.filter { fnmatch(matchPattern, $0, 0) == 0 }
            return .array([.bulkString("0"), .array(filtered.map { .bulkString($0) })])

        case "zset":
            let filtered = key.zsetMembers.filter { fnmatch(matchPattern, $0.0, 0) == 0 }
            var values: [RESPValue?] = []
            for (member, score) in filtered {
                values.append(.array([.bulkString(member), .bulkString(String(score))]))
            }
            return .array([.bulkString("0"), .array(values)])

        default:
            return .array([.bulkString("0"), .array([])])
        }
    }
}

// MARK: - Array Safe Subscript

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
