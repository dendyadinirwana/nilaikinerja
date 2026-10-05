import Foundation
import SQLite3

/// A block of work. `endedAt == nil` means the timer is still running.
struct WorkSession: Identifiable, Equatable {
    let id: Int64
    let startedAt: Date
    var endedAt: Date?
    var title: String?
    var detail: String?
    var outcome: String?
    var endedCause: EndCause?
    /// True once the checkpoint prompt has been answered, so the daily report
    /// can distinguish "confirmed" work from a bare timer the user skipped.
    var recorded: Bool

    enum EndCause: String {
        case manual
        case idle
        case meeting
        case dayEnd
    }

    var isRunning: Bool { endedAt == nil }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    /// Unnamed sessions are excluded from the report — a timer the user never
    /// titled carries no evidence of what was done.
    var isReportable: Bool {
        guard let title else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct Attachment: Identifiable, Equatable {
    let id: Int64
    let sessionID: Int64
    let filename: String
    let storedPath: String
    let kind: Kind
    let bytes: Int

    enum Kind: String {
        case image
        case pdf
        case other
    }

    var url: URL { URL(fileURLWithPath: storedPath) }
}

/// Reads and writes the session log. Single writer, called from the main actor
/// and the timer tick — the db queue inside `Database` serialises the SQL.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [WorkSession] = []
    @Published private(set) var attachments: [Int64: [Attachment]] = [:]

    private let db = Database.shared
    private var currentID: Int64?

    /// The one running session, if any.
    var active: WorkSession? {
        sessions.first { $0.isRunning }
    }

    init() {
        reload()
    }

    // MARK: - Test-support

    /// Deletes every row. Only used by the selftest, which runs against a
    /// throwaway database.
    func deleteAll() {
        db.run("DELETE FROM session;")
        db.run("DELETE FROM revision;")
        reload()
    }

    /// Executes raw SQL. Only used by the selftest to construct states that
    /// are awkward to reach through the public API.
    func runRaw(_ sql: String) {
        db.run(sql)
    }

    // MARK: - Queries

    func reload() {
        let loaded: [WorkSession] = db.query("""
            SELECT id, started_at, ended_at, title, detail, outcome, ended_cause, recorded
            FROM session
            ORDER BY started_at DESC
            """) { statement in
            var rows: [WorkSession] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let endedRaw = sqlite3_column_type(statement, 2) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                rows.append(
                    WorkSession(
                        id: sqlite3_column_int64(statement, 0),
                        startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                        endedAt: endedRaw,
                        title: SessionStore.string(statement, 3),
                        detail: SessionStore.string(statement, 4),
                        outcome: SessionStore.string(statement, 5),
                        endedCause: endedRaw.flatMap { raw in
                            SessionStore.string(statement, 6).flatMap(WorkSession.EndCause.init)
                        },
                        recorded: sqlite3_column_int(statement, 7) == 1
                    )
                )
            }
            return rows
        } ?? []

        sessions = loaded
        currentID = loaded.first { $0.isRunning }?.id
        reloadAttachments()
    }

    private func reloadAttachments() {
        var grouped: [Int64: [Attachment]] = [:]
        db.eachRow("""
            SELECT id, session_id, filename, stored_path, kind, bytes
            FROM attachment ORDER BY id
            """) { statement in
            let item = Attachment(
                id: sqlite3_column_int64(statement, 0),
                sessionID: sqlite3_column_int64(statement, 1),
                filename: SessionStore.string(statement, 2) ?? "",
                storedPath: SessionStore.string(statement, 3) ?? "",
                kind: Attachment.Kind(
                    rawValue: SessionStore.string(statement, 4) ?? "other"
                ) ?? .other,
                bytes: Int(sqlite3_column_int64(statement, 5))
            )
            grouped[item.sessionID, default: []].append(item)
        }
        attachments = grouped
    }

    // MARK: - Mutations

    @discardableResult
    func startSession(at date: Date = Date()) -> Int64? {
        // Never run two timers at once. Ending the stale one keeps the log
        // linear even if the app was killed without closing it.
        if active != nil {
            endSession(cause: .manual, at: date)
        }
        let now = date.timeIntervalSince1970
        guard db.run("""
            INSERT INTO session (started_at, recorded) VALUES (\(now), 0);
            """) else { return nil }
        reload()
        return currentID
    }

    @discardableResult
    func endSession(cause: WorkSession.EndCause, at date: Date = Date()) {
        guard let id = active?.id else { return }
        let now = date.timeIntervalSince1970
        db.run("""
            UPDATE session
            SET ended_at = \(now), ended_cause = '\(cause.rawValue)'
            WHERE id = \(id);
            """)
        reload()
    }

    /// Title, detail and outcome are all editable after the fact — users
    /// remember what they did at the end of the day, not at the checkpoint.
    func update(
        sessionID: Int64,
        title: String?,
        detail: String?,
        outcome: String?,
        markRecorded: Bool
    ) {
        let fields = [
            "title = \(SessionStore.quote(title))",
            "detail = \(SessionStore.quote(detail))",
            "outcome = \(SessionStore.quote(outcome))",
            "recorded = \(markRecorded ? 1 : 0)"
        ].joined(separator: ", ")

        guard db.run("UPDATE session SET \(fields) WHERE id = \(sessionID);") else { return }

        // Record what changed so a corrected report stays auditable.
        for (field, value) in [("title", title), ("detail", detail), ("outcome", outcome)] {
            // `query` returns an Optional around the closure's Optional result,
            // so flatten once before comparing.
            let previous: String? = db.query("""
                SELECT \(field) FROM session WHERE id = \(sessionID);
                """) { statement -> String? in
                guard sqlite3_step(statement) == SQLITE_ROW,
                      sqlite3_column_type(statement, 0) != SQLITE_NULL
                else { return nil }
                return String(cString: sqlite3_column_text(statement, 0))
            } ?? nil
            if previous != value {
                let now = Date().timeIntervalSince1970
                db.run("""
                    INSERT INTO revision (session_id, at, field, old_value, new_value)
                    VALUES (\(sessionID), \(now), '\(field)',
                            \(SessionStore.quote(previous)), \(SessionStore.quote(value)));
                    """)
            }
        }
        reload()
    }

    func delete(sessionID: Int64) {
        db.run("DELETE FROM session WHERE id = \(sessionID);")
        reload()
    }

    /// Records a past activity, for when the user remembers work they did
    /// earlier but the timer was not running. The session is created closed
    /// with explicit start/end, then optionally made the running one.
    ///
    /// This backs "Tambah kegiatan": the common case is a user who worked on
    /// something 09:00–11:00 but only opened the app at lunch.
    @discardableResult
    func logPastActivity(
        title: String,
        detail: String?,
        outcome: String?,
        from: Date,
        to: Date,
        attachments: [(filename: String, path: String, kind: Attachment.Kind, bytes: Int, sha: String)] = []
    ) -> Int64? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, to > from else { return nil }

        let start = from.timeIntervalSince1970
        let end = to.timeIntervalSince1970
        guard let id = db.runAndReturnID("""
            INSERT INTO session (started_at, ended_at, title, detail, outcome, ended_cause, recorded)
            VALUES (\(start), \(end), \(SessionStore.quote(trimmed)),
                    \(SessionStore.quote(detail)), \(SessionStore.quote(outcome)),
                    'manual', 1);
            """) else { return nil }

        for item in attachments {
            addAttachment(
                sessionID: id,
                filename: item.filename,
                storedPath: item.path,
                kind: item.kind,
                bytes: item.bytes,
                sha256: item.sha
            )
        }
        reload()
        return id
    }

    // MARK: - Attachments

    func addAttachment(
        sessionID: Int64,
        filename: String,
        storedPath: String,
        kind: Attachment.Kind,
        bytes: Int,
        sha256: String
    ) {
        db.run("""
            INSERT INTO attachment (session_id, filename, stored_path, kind, bytes, sha256)
            VALUES (\(sessionID), \(SessionStore.quote(filename)),
                    \(SessionStore.quote(storedPath)), '\(kind.rawValue)',
                    \(bytes), \(SessionStore.quote(sha256)));
            """)
        reloadAttachments()
    }

    func removeAttachment(_ attachment: Attachment) {
        db.run("DELETE FROM attachment WHERE id = \(attachment.id);")
        try? FileManager.default.removeItem(at: attachment.url)
        reloadAttachments()
    }

    // MARK: - Reporting queries

    /// Sessions overlapping [interval], oldest first. Half-open so a session
    /// that straddles midnight is reported once, at its start, not twice.
    func sessions(in interval: DateInterval) -> [WorkSession] {
        let lower = interval.start.timeIntervalSince1970
        let upper = interval.end.timeIntervalSince1970
        return db.query("""
            SELECT id, started_at, ended_at, title, detail, outcome, ended_cause, recorded
            FROM session
            WHERE started_at >= \(lower) AND started_at < \(upper)
            ORDER BY started_at ASC
            """) { statement in
            var rows: [WorkSession] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let endedRaw = sqlite3_column_type(statement, 2) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                rows.append(
                    WorkSession(
                        id: sqlite3_column_int64(statement, 0),
                        startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                        endedAt: endedRaw,
                        title: SessionStore.string(statement, 3),
                        detail: SessionStore.string(statement, 4),
                        outcome: SessionStore.string(statement, 5),
                        endedCause: endedRaw.flatMap { _ in
                            SessionStore.string(statement, 6).flatMap(WorkSession.EndCause.init)
                        },
                        recorded: sqlite3_column_int(statement, 7) == 1
                    )
                )
            }
            return rows
        } ?? []
    }

    /// Distinct titles ordered by how recently and how often they were used.
    /// Feeds autocomplete so the user picks an existing entry instead of
    /// retyping — typing at a checkpoint is where friction kills the habit.
    func titleSuggestions(limit: Int = 8) -> [String] {
        db.query("""
            SELECT title, MAX(started_at) AS last_used, COUNT(*) AS uses
            FROM session
            WHERE title IS NOT NULL AND TRIM(title) <> ''
            GROUP BY title
            ORDER BY last_used DESC, uses DESC
            LIMIT \(limit)
            """) { statement in
            var titles: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = SessionStore.string(statement, 0) {
                    titles.append(text)
                }
            }
            return titles
        } ?? []
    }

    /// Split an unfinished session at `date` so a run that spans a break does
    /// not inflate the daily total. Returns a new id for the tail half.
    @discardableResult
    func split(sessionID: Int64, at date: Date) -> Int64? {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let end = session.endedAt,
              date > session.startedAt,
              date < end
        else { return nil }

        let cut = date.timeIntervalSince1970
        let endRaw = end.timeIntervalSince1970

        db.run("UPDATE session SET ended_at = \(cut) WHERE id = \(sessionID);")
        guard db.run("""
            INSERT INTO session (started_at, ended_at, title, detail, outcome, recorded)
            VALUES (\(cut), \(endRaw), \(SessionStore.quote(session.title)),
                    \(SessionStore.quote(session.detail)), \(SessionStore.quote(session.outcome)),
                    \(session.recorded ? 1 : 0));
            """) else { return nil }
        reload()
        return sessions.first { $0.startedAt == date }?.id
    }

    // MARK: - Helpers

    private static func string(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, column)
        else { return nil }
        return String(cString: text)
    }

    /// Single-quote escaping. All user text goes through here.
    static func quote(_ value: String?) -> String {
        guard let value else { return "NULL" }
        return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
