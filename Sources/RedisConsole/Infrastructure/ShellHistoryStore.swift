import Foundation
import SQLite3
import Synchronization

// MARK: - Shell History Store

/// SQLite-backed persistence for shell command history.
///
/// A single database file (`shell-history.sqlite`, next to the connections
/// JSON in Application Support) holds history for all connections, bucketed by
/// `connection_id`. `libsqlite3` is a system framework, so no third-party
/// dependency is added. All access is serialized with a `Mutex`, and the
/// connection is opened with `SQLITE_OPEN_FULLMUTEX` as a second layer.
final class ShellHistoryStore: @unchecked Sendable {
    static let shared = ShellHistoryStore()

    private let mutex = Mutex(())
    private let db: OpaquePointer?

    /// SQLite's `SQLITE_TRANSIENT` destructor, not exported to Swift as a
    /// constant (it is a C macro). Signals SQLite to copy the bound text.
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            db = nil
            return
        }
        let dir = appSupport.appendingPathComponent("redis.console", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("shell-history.sqlite").path

        var dbHandle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &dbHandle, flags, nil) == SQLITE_OK, let dbHandle else {
            db = nil
            return
        }
        db = dbHandle
        createSchema(dbHandle)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func createSchema(_ db: OpaquePointer) {
        let schema = """
            CREATE TABLE IF NOT EXISTS shell_history (
                id TEXT PRIMARY KEY,
                connection_id TEXT NOT NULL,
                command TEXT NOT NULL,
                result TEXT NOT NULL,
                timestamp REAL NOT NULL,
                is_error INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_shell_history_connection
                ON shell_history (connection_id, timestamp);
            """
        _ = sqlite3_exec(db, schema, nil, nil, nil)
    }

    /// Loads the history for a connection, ordered oldest-first (matching the
    /// in-memory array order), capped at `limit`.
    func load(connectionID: UUID, limit: Int) -> [ShellHistoryEntry] {
        guard let db else { return [] }
        return mutex.withLock { _ in
            let sql = """
                SELECT id, command, result, timestamp, is_error
                FROM shell_history
                WHERE connection_id = ?
                ORDER BY timestamp DESC, rowid DESC
                LIMIT ?
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, connectionID.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var entries: [ShellHistoryEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCString = sqlite3_column_text(stmt, 0),
                    let id = UUID(uuidString: String(cString: idCString)),
                    let commandCString = sqlite3_column_text(stmt, 1),
                    let resultCString = sqlite3_column_text(stmt, 2)
                else { continue }
                entries.append(
                    ShellHistoryEntry(
                        id: id,
                        command: String(cString: commandCString),
                        result: String(cString: resultCString),
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                        isError: sqlite3_column_int(stmt, 4) != 0
                    ))
            }
            return entries.reversed()
        }
    }

    /// Appends an entry and prunes the connection's history to `limit` rows.
    func append(_ entry: ShellHistoryEntry, connectionID: UUID, limit: Int) {
        guard let db else { return }
        mutex.withLock { _ in
            var stmt: OpaquePointer?
            let sql = """
                INSERT OR REPLACE INTO shell_history (id, connection_id, command, result, timestamp, is_error)
                VALUES (?, ?, ?, ?, ?, ?)
                """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, connectionID.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, entry.command, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 4, entry.result, -1, Self.sqliteTransient)
            sqlite3_bind_double(stmt, 5, entry.timestamp.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 6, entry.isError ? 1 : 0)
            sqlite3_step(stmt)

            prune(connectionID: connectionID, limit: limit, db: db)
        }
    }

    /// Deletes a single entry.
    func delete(id: UUID, connectionID: UUID) {
        guard let db else { return }
        mutex.withLock { _ in
            var stmt: OpaquePointer?
            let sql = "DELETE FROM shell_history WHERE id = ? AND connection_id = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, connectionID.uuidString, -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }
    }

    /// Removes all history for a connection.
    func clear(connectionID: UUID) {
        guard let db else { return }
        mutex.withLock { _ in
            var stmt: OpaquePointer?
            let sql = "DELETE FROM shell_history WHERE connection_id = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, connectionID.uuidString, -1, Self.sqliteTransient)
            sqlite3_step(stmt)
        }
    }

    /// Inserts a batch of entries in a single transaction. Used by the
    /// one-shot migration from the legacy JSON file.
    func importEntries(_ entries: [ShellHistoryEntry], connectionID: UUID) {
        guard let db, !entries.isEmpty else { return }
        mutex.withLock { _ in
            _ = sqlite3_exec(db, "BEGIN", nil, nil, nil)
            defer { _ = sqlite3_exec(db, "COMMIT", nil, nil, nil) }

            var stmt: OpaquePointer?
            let sql = """
                INSERT OR REPLACE INTO shell_history (id, connection_id, command, result, timestamp, is_error)
                VALUES (?, ?, ?, ?, ?, ?)
                """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for entry in entries {
                sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, Self.sqliteTransient)
                sqlite3_bind_text(stmt, 2, connectionID.uuidString, -1, Self.sqliteTransient)
                sqlite3_bind_text(stmt, 3, entry.command, -1, Self.sqliteTransient)
                sqlite3_bind_text(stmt, 4, entry.result, -1, Self.sqliteTransient)
                sqlite3_bind_double(stmt, 5, entry.timestamp.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 6, entry.isError ? 1 : 0)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
            }
        }
    }

    // MARK: - Private

    /// Drops rows beyond the newest `limit` for a connection.
    private func prune(connectionID: UUID, limit: Int, db: OpaquePointer) {
        let sql = """
            DELETE FROM shell_history
            WHERE connection_id = ?1 AND id NOT IN (
                SELECT id FROM shell_history
                WHERE connection_id = ?1
                ORDER BY timestamp DESC, rowid DESC
                LIMIT ?2
            )
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, connectionID.uuidString, -1, Self.sqliteTransient)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        sqlite3_step(stmt)
    }
}
