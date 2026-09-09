import Foundation
import CSQLite

final class Database {
    private var db: OpaquePointer?
    init(_ url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw NotifyError("storage_error", "Could not open notification database.", exitCode: 5) }
        chmod(url.path, 0o600)
        sqlite3_busy_timeout(db, 5000)
        try run("PRAGMA journal_mode=WAL")
        try run("PRAGMA synchronous=FULL")
        let version = try rows("PRAGMA user_version").first?.first ?? "0"
        guard version == "0" || version == "1" else { throw NotifyError("storage_error", "Database version is newer than this app. Upgrade AgentNotify.", exitCode: 5) }
        try run("CREATE TABLE IF NOT EXISTS notifications (id TEXT PRIMARY KEY, group_name TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, status TEXT NOT NULL, json TEXT NOT NULL)")
        try run("CREATE INDEX IF NOT EXISTS notification_group ON notifications(group_name, status)")
        try run("CREATE TABLE IF NOT EXISTS changes (seq INTEGER PRIMARY KEY AUTOINCREMENT, notification_id TEXT NOT NULL, kind TEXT NOT NULL, json TEXT NOT NULL)")
        try run("CREATE TABLE IF NOT EXISTS requests (id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, result TEXT NOT NULL)")
        try run("CREATE TABLE IF NOT EXISTS waiters (notification_id TEXT PRIMARY KEY, token TEXT NOT NULL, expires REAL NOT NULL)")
        // Additive to v1: earlier binaries leave these local preferences intact.
        try run("CREATE TABLE IF NOT EXISTS preferences (id INTEGER PRIMARY KEY CHECK(id=1), json TEXT NOT NULL)")
        try run("CREATE TABLE IF NOT EXISTS app_setup (key TEXT PRIMARY KEY)")
        try run("PRAGMA user_version=1")
    }
    deinit { sqlite3_close(db) }
    func rows(_ sql: String, _ args: [String] = []) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        for (index, arg) in args.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), arg, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw error() }
        }
        var result: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw error() }
            result.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            })
        }
    }
    func run(_ sql: String, _ args: [String] = []) throws { _ = try rows(sql, args) }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try run("BEGIN IMMEDIATE")
        do { let value = try body(); try run("COMMIT"); return value }
        catch { try? run("ROLLBACK"); throw error }
    }
    private func error() -> NotifyError { NotifyError("storage_error", String(cString: sqlite3_errmsg(db)), exitCode: 5) }
}
