import Foundation
import SQLite3

/// SQLite wrapper. The session log is the app's source of truth, so it gets
/// WAL journalling (survives a crash mid-write) and an explicit migration list
/// rather than an ad-hoc "create if missing" on every launch.
final class Database {
    static let shared = Database()

    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "id.simbang.nilaikinerja.db")

    private(set) var url: URL

    private init() {
        // The selftest points the database at a throwaway path so a test run
        // can never modify the real performance log. Read at init because
        // `shared` is constructed lazily on first access.
        if let override = ProcessInfo.processInfo.environment["NK_SELFTEST_DB"] {
            let scratch = URL(fileURLWithPath: override)
            try? FileManager.default.createDirectory(
                at: scratch.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            url = scratch
        } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
                ?? URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/Application Support")

            let dir = support.appendingPathComponent("NilaiKinerja", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("nilai.sqlite")
        }

        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            NSLog("[DB] open failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
        migrate()
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    // MARK: - Migration

    private var schemaVersion: Int {
        guard let handle else { return 0 }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            handle,
            "PRAGMA user_version;",
            -1, &statement, nil
        ) == SQLITE_OK, let statement else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func setSchemaVersion(_ version: Int) {
        exec("PRAGMA user_version = \(version);")
    }

    private func migrate() {
        // WAL keeps reads fast and, more importantly, survives a hard kill
        // without losing the current session.
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA foreign_keys = ON;")
        exec("PRAGMA busy_timeout = 3000;")

        let current = schemaVersion

        if current < 1 {
            NSLog("[DB] applying migration 1")
            exec("""
            CREATE TABLE IF NOT EXISTS session (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at  REAL    NOT NULL,
                ended_at    REAL,
                title       TEXT,
                detail      TEXT,
                outcome     TEXT,
                ended_cause TEXT,
                recorded    INTEGER NOT NULL DEFAULT 0
            );
            """)
            exec("""
            CREATE TABLE IF NOT EXISTS attachment (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id  INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
                filename    TEXT    NOT NULL,
                stored_path TEXT    NOT NULL,
                kind        TEXT    NOT NULL,
                bytes       INTEGER NOT NULL,
                sha256      TEXT    NOT NULL
            );
            """)
            // Revisions are kept rather than overwritten in place: an ASN
            // performance report is often corrected after submission, and we
            // need to show what changed and when.
            exec("""
            CREATE TABLE IF NOT EXISTS revision (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
                at         REAL    NOT NULL,
                field      TEXT    NOT NULL,
                old_value  TEXT,
                new_value  TEXT
            );
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_session_started ON session(started_at);")
            exec("CREATE INDEX IF NOT EXISTS idx_session_ended ON session(ended_at);")
            exec("CREATE INDEX IF NOT EXISTS idx_attachment_session ON attachment(session_id);")
            exec("CREATE INDEX IF NOT EXISTS idx_revision_session ON revision(session_id);")
            setSchemaVersion(1)
        }
    }

    // MARK: - Execution

    @discardableResult
    func exec(_ sql: String) -> Bool {
        guard let handle else { return false }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        if result != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            NSLog("[DB] exec failed: \(message)\nSQL: \(sql)")
            errorPointer.map { sqlite3_free($0) }
            return false
        }
        return true
    }

    /// Runs `body` with a prepared statement. Serialized on the db queue so
    /// concurrent timer ticks and UI writes can't interleave.
    @discardableResult
    func query<T>(
        _ sql: String,
        _ body: (OpaquePointer) -> T
    ) -> T? {
        var result: T?
        queue.sync {
            guard let handle else { return }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                NSLog("[DB] prepare failed: \(String(cString: sqlite3_errmsg(handle)))\nSQL: \(sql)")
                return
            }
            defer { sqlite3_finalize(statement) }
            result = body(statement)
        }
        return result
    }

    /// Steps through a statement, invoking `body` once per row.
    func eachRow(_ sql: String, _ body: (OpaquePointer) -> Void) {
        query(sql) { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                body(statement)
            }
        }
    }

    @discardableResult
    func run(_ sql: String) -> Bool {
        var ok = false
        queue.sync { ok = exec(sql) }
        return ok
    }

    @discardableResult
    func runAndReturnID(_ sql: String) -> Int64? {
        var id: Int64?
        queue.sync {
            guard exec(sql), let handle else { return }
            id = sqlite3_last_insert_rowid(handle)
        }
        return id
    }
}

enum DBValue {
    case text(String)
    case int(Int64)
    case double(Double)
    case null

    static func text(_ value: String?) -> DBValue { value.map { .text($0) } ?? .null }
    static func double(_ value: Double?) -> DBValue { value.map { .double($0) } ?? .null }
}

/// Builds `?`-placeholder SQL with escaped literals, so no value is ever
/// interpolated into a statement.
enum SQLBuilder {
    static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    static func bind(_ values: [DBValue], to statement: OpaquePointer) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let string):
                sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            case .int(let number):
                sqlite3_bind_int64(statement, index, number)
            case .double(let number):
                sqlite3_bind_double(statement, index, number)
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
