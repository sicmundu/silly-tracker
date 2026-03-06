import Foundation
import SQLite3

/// Direct SQLite manager — no external dependencies.
/// Uses the same schema as the Python tracker so the DB is fully shared.
final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "db.serial", qos: .userInitiated)

    var dbPath: String {
        let custom = UserDefaults.standard.string(forKey: "dbPath") ?? ""
        if !custom.isEmpty { return custom }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WorkTracker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tracker.db").path
    }

    private init() {
        open()
        createTables()
    }

    // MARK: - Connection

    private func open() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open DB at \(dbPath)")
        }
        exec("PRAGMA journal_mode=WAL")
    }

    func reopen() {
        queue.sync {
            if db != nil { sqlite3_close(db) }
            db = nil
            open()
            createTables()
        }
    }

    private func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                type TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS day_notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS day_summaries (
                date TEXT PRIMARY KEY,
                summary TEXT NOT NULL,
                generated_at TEXT NOT NULL
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS linear_synced_issues (
                issue_id TEXT PRIMARY KEY,
                identifier TEXT NOT NULL,
                title TEXT NOT NULL,
                completed_at TEXT NOT NULL,
                synced_at TEXT NOT NULL,
                note_id INTEGER
            )
        """)
    }

    // MARK: - Helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            print("SQL error: \(msg)")
            sqlite3_free(err)
            return false
        }
        return true
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let simpleFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseDate(_ s: String) -> Date {
        isoFormatter.date(from: s)
            ?? simpleFmt.date(from: s)
            ?? Date()
    }

    static func nowISO() -> String {
        simpleFmt.string(from: Date())
    }

    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func todayStr() -> String {
        return todayFormatter.string(from: Date())
    }

    // MARK: - Entries

    func getActive() -> TrackerEntry? {
        queue.sync {
            let sql = "SELECT id, date, type, start_time FROM entries WHERE end_time IS NULL LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let date = String(cString: sqlite3_column_text(stmt, 1))
                let typeStr = String(cString: sqlite3_column_text(stmt, 2))
                let startStr = String(cString: sqlite3_column_text(stmt, 3))
                return TrackerEntry(
                    id: id,
                    date: date,
                    type: ActivityType(rawValue: typeStr) ?? .work,
                    startTime: Self.parseDate(startStr),
                    endTime: nil
                )
            }
            return nil
        }
    }

    func stopActive() -> TrackerEntry? {
        queue.sync {
            let sql = "SELECT id, date, type, start_time FROM entries WHERE end_time IS NULL LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }

            var entry: TrackerEntry?
            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let date = String(cString: sqlite3_column_text(stmt, 1))
                let typeStr = String(cString: sqlite3_column_text(stmt, 2))
                let startStr = String(cString: sqlite3_column_text(stmt, 3))
                entry = TrackerEntry(
                    id: id,
                    date: date,
                    type: ActivityType(rawValue: typeStr) ?? .work,
                    startTime: Self.parseDate(startStr),
                    endTime: Date()
                )
            }
            sqlite3_finalize(stmt)

            if let e = entry {
                let now = Self.nowISO()
                exec("UPDATE entries SET end_time = '\(now)' WHERE id = \(e.id)")
            }
            return entry
        }
    }

    func startActivity(_ type: ActivityType) {
        queue.sync {
            let now = Self.nowISO()
            exec("UPDATE entries SET end_time = '\(now)' WHERE end_time IS NULL")

            let today = Self.todayStr()
            exec("""
                INSERT INTO entries (date, type, start_time) VALUES ('\(today)', '\(type.rawValue)', '\(now)')
            """)
        }
    }

    func getTodayEntries() -> [TrackerEntry] {
        queue.sync {
            let today = Self.todayStr()
            let sql = "SELECT id, date, type, start_time, end_time FROM entries WHERE date = ? ORDER BY start_time"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (today as NSString).utf8String, -1, nil)

            var results: [TrackerEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let date = String(cString: sqlite3_column_text(stmt, 1))
                let typeStr = String(cString: sqlite3_column_text(stmt, 2))
                let startStr = String(cString: sqlite3_column_text(stmt, 3))
                let endStr = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

                results.append(TrackerEntry(
                    id: id,
                    date: date,
                    type: ActivityType(rawValue: typeStr) ?? .work,
                    startTime: Self.parseDate(startStr),
                    endTime: endStr.map { Self.parseDate($0) }
                ))
            }
            return results
        }
    }

    // MARK: - Stats

    func getStats(from startDate: String, to endDate: String) -> [DayStats] {
        queue.sync {
            let sql = """
                SELECT date, type, start_time, end_time FROM entries
                WHERE date >= ? AND date <= ? ORDER BY date, start_time
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (startDate as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (endDate as NSString).utf8String, -1, nil)

            var days: [String: DayStats] = [:]
            let now = Date()

            while sqlite3_step(stmt) == SQLITE_ROW {
                let date = String(cString: sqlite3_column_text(stmt, 0))
                let typeStr = String(cString: sqlite3_column_text(stmt, 1))
                let startStr = String(cString: sqlite3_column_text(stmt, 2))
                let endStr = sqlite3_column_text(stmt, 3).map { String(cString: $0) }

                let s = Self.parseDate(startStr)
                let e = endStr.map { Self.parseDate($0) } ?? now
                let sec = e.timeIntervalSince(s)

                if days[date] == nil { days[date] = DayStats(date: date) }
                switch typeStr {
                case "work": days[date]!.work += sec
                case "lunch": days[date]!.lunch += sec
                case "break": days[date]!.breakTime += sec
                default: break
                }
            }

            return days.values.sorted { $0.date > $1.date }
        }
    }

    // MARK: - Adjust Work Hours

    func adjustWorkHours(date: String, targetSeconds: Double) {
        queue.sync {
            let sql = "SELECT id, start_time, end_time FROM entries WHERE date = ? AND type = 'work' ORDER BY start_time"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

            struct WorkEntry {
                let id: Int64
                let start: Date
                let end: Date
                let dur: Double
                let isOpen: Bool
            }

            var entries: [WorkEntry] = []
            let now = Date()

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let startStr = String(cString: sqlite3_column_text(stmt, 1))
                let endStr = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let s = Self.parseDate(startStr)
                let e = endStr.map { Self.parseDate($0) } ?? now
                let dur = e.timeIntervalSince(s)
                entries.append(WorkEntry(id: id, start: s, end: e, dur: dur, isOpen: endStr == nil))
            }
            sqlite3_finalize(stmt)

            guard !entries.isEmpty else { return }

            if targetSeconds <= 0 {
                exec("DELETE FROM entries WHERE date = '\(date)' AND type = 'work'")
                return
            }

            let total = entries.reduce(0.0) { $0 + $1.dur }
            let diff = targetSeconds - total

            // Adjust the last work entry
            let last = entries.last!
            let newDur = last.dur + diff

            if newDur < 0 {
                // Walk forward and trim
                var remaining = targetSeconds
                for e in entries {
                    if remaining <= 0 {
                        exec("DELETE FROM entries WHERE id = \(e.id)")
                    } else if e.dur <= remaining {
                        remaining -= e.dur
                    } else {
                        let newEnd = e.start.addingTimeInterval(remaining)
                        let newEndStr = Self.simpleFmt.string(from: newEnd)
                        exec("UPDATE entries SET end_time = '\(newEndStr)' WHERE id = \(e.id)")
                        remaining = 0
                    }
                }
            } else {
                let newEnd = last.start.addingTimeInterval(newDur)
                let newEndStr = Self.simpleFmt.string(from: newEnd)
                exec("UPDATE entries SET end_time = '\(newEndStr)' WHERE id = \(last.id)")
            }
        }
    }

    // MARK: - Notes

    func getNotes(for date: String) -> [DayNote] {
        queue.sync {
            let sql = "SELECT id, date, content, created_at FROM day_notes WHERE date = ? ORDER BY created_at"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)

            var results: [DayNote] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(DayNote(
                    id: sqlite3_column_int64(stmt, 0),
                    date: String(cString: sqlite3_column_text(stmt, 1)),
                    content: String(cString: sqlite3_column_text(stmt, 2)),
                    createdAt: String(cString: sqlite3_column_text(stmt, 3))
                ))
            }
            return results
        }
    }

    func addNote(date: String, content: String) {
        queue.sync {
            let now = Self.nowISO()
            let sql = "INSERT INTO day_notes (date, content, created_at) VALUES (?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
    }

    func deleteNote(id: Int64) {
        queue.sync {
            exec("DELETE FROM day_notes WHERE id = \(id)")
        }
    }

    // MARK: - Summaries

    func getSummary(for date: String) -> DaySummary? {
        queue.sync {
            let sql = "SELECT date, summary, generated_at FROM day_summaries WHERE date = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW {
                return DaySummary(
                    date: String(cString: sqlite3_column_text(stmt, 0)),
                    summary: String(cString: sqlite3_column_text(stmt, 1)),
                    generatedAt: String(cString: sqlite3_column_text(stmt, 2))
                )
            }
            return nil
        }
    }

    func saveSummary(date: String, summary: String) {
        queue.sync {
            let now = Self.nowISO()
            let sql = """
                INSERT INTO day_summaries (date, summary, generated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET summary=excluded.summary, generated_at=excluded.generated_at
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (summary as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Export

    func getExportRows(period: String) -> [ExportRow] {
        queue.sync {
            let today = Date()
            let cal = Calendar.current
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"

            let startDate: String
            let endDate = f.string(from: today)

            switch period {
            case "week":
                let weekStart = cal.date(byAdding: .day, value: -(cal.component(.weekday, from: today) - 2), to: today)!
                startDate = f.string(from: weekStart)
            case "month":
                let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today))!
                startDate = f.string(from: monthStart)
            case "year":
                let yearStart = cal.date(from: cal.dateComponents([.year], from: today))!
                startDate = f.string(from: yearStart)
            case "all":
                startDate = "2000-01-01"
            default:
                startDate = endDate
            }

            // Get entries
            let entrySql = """
                SELECT date, type, start_time, end_time FROM entries
                WHERE date >= ? AND date <= ? ORDER BY date, start_time
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, entrySql, -1, &stmt, nil) == SQLITE_OK else { return [] }

            sqlite3_bind_text(stmt, 1, (startDate as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (endDate as NSString).utf8String, -1, nil)

            var dailyWork: [String: Double] = [:]
            let now = Date()

            while sqlite3_step(stmt) == SQLITE_ROW {
                let date = String(cString: sqlite3_column_text(stmt, 0))
                let typeStr = String(cString: sqlite3_column_text(stmt, 1))
                let startStr = String(cString: sqlite3_column_text(stmt, 2))
                let endStr = sqlite3_column_text(stmt, 3).map { String(cString: $0) }

                if typeStr == "work" {
                    let s = Self.parseDate(startStr)
                    let e = endStr.map { Self.parseDate($0) } ?? now
                    dailyWork[date, default: 0] += e.timeIntervalSince(s)
                }
            }
            sqlite3_finalize(stmt)

            // Get summaries
            let sumSql = "SELECT date, summary FROM day_summaries WHERE date >= ? AND date <= ?"
            var sumStmt: OpaquePointer?
            var summaries: [String: String] = [:]
            if sqlite3_prepare_v2(db, sumSql, -1, &sumStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(sumStmt, 1, (startDate as NSString).utf8String, -1, nil)
                sqlite3_bind_text(sumStmt, 2, (endDate as NSString).utf8String, -1, nil)
                while sqlite3_step(sumStmt) == SQLITE_ROW {
                    let date = String(cString: sqlite3_column_text(sumStmt, 0))
                    let summary = String(cString: sqlite3_column_text(sumStmt, 1))
                    summaries[date] = summary
                }
                sqlite3_finalize(sumStmt)
            }

            return dailyWork.keys.sorted().map { date in
                let hours = (dailyWork[date] ?? 0) / 3600.0
                return ExportRow(date: date, hours: round(hours * 100) / 100, summary: summaries[date] ?? "")
            }
        }
    }

    // MARK: - Linear Sync Deduplication

    func isIssueSynced(_ issueId: String) -> Bool {
        queue.sync {
            let sql = "SELECT 1 FROM linear_synced_issues WHERE issue_id = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (issueId as NSString).utf8String, -1, nil)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    func markIssueSynced(_ issue: LinearIssue, noteId: Int64) {
        queue.sync {
            let now = Self.nowISO()
            let sql = """
                INSERT OR IGNORE INTO linear_synced_issues
                (issue_id, identifier, title, completed_at, synced_at, note_id)
                VALUES (?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (issue.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (issue.identifier as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (issue.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (issue.completedAt as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (now as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 6, noteId)
            sqlite3_step(stmt)
        }
    }

    func addNoteReturningId(date: String, content: String) -> Int64 {
        queue.sync {
            let now = Self.nowISO()
            let sql = "INSERT INTO day_notes (date, content, created_at) VALUES (?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            return sqlite3_last_insert_rowid(db)
        }
    }

    func getSyncStatus() -> LinearSyncStatus {
        queue.sync {
            let sql = "SELECT COUNT(*), MAX(synced_at) FROM linear_synced_issues"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return LinearSyncStatus()
            }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                let count = Int(sqlite3_column_int(stmt, 0))
                let lastSync = sqlite3_column_text(stmt, 1).map { Self.parseDate(String(cString: $0)) }
                return LinearSyncStatus(totalSynced: count, lastSync: lastSync)
            }
            return LinearSyncStatus()
        }
    }

    // MARK: - Delete day

    func deleteDay(_ date: String) {
        queue.sync {
            exec("DELETE FROM entries WHERE date = '\(date)'")
            exec("DELETE FROM day_notes WHERE date = '\(date)'")
        }
    }
}
