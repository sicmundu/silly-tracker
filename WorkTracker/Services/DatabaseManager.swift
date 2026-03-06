import Foundation
import SQLite3

/// Direct SQLite manager — no external dependencies.
/// Uses the same schema as the Python tracker so the DB is fully shared.
final class DatabaseManager {
    static let shared = DatabaseManager()

    private struct EntryRecord {
        let id: Int64
        let storedDate: String
        let type: ActivityType
        let startTime: Date
        let endTime: Date?
    }

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "db.serial", qos: .userInitiated)
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static let defaultDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WorkTracker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var defaultDbPath: String {
        defaultDir.appendingPathComponent("tracker.db").path
    }

    var dbPath: String {
        Self.defaultDbPath
    }

    /// Migrate DB from old ~/Documents/WorkTracker location to Application Support.
    /// Called once on first launch after the update.
    private func migrateFromDocumentsIfNeeded() {
        let fm = FileManager.default
        let oldDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WorkTracker")
        let oldDb = oldDir.appendingPathComponent("tracker.db")
        let newDb = URL(fileURLWithPath: Self.defaultDbPath)

        // Only migrate if old DB exists and new one does not
        guard fm.fileExists(atPath: oldDb.path),
              !fm.fileExists(atPath: newDb.path) else { return }

        do {
            try fm.copyItem(at: oldDb, to: newDb)
            // Also move WAL/SHM if present
            for ext in ["-wal", "-shm"] {
                let oldFile = oldDir.appendingPathComponent("tracker.db\(ext)")
                let newFile = Self.defaultDir.appendingPathComponent("tracker.db\(ext)")
                if fm.fileExists(atPath: oldFile.path) {
                    try? fm.copyItem(at: oldFile, to: newFile)
                }
            }
            print("Migrated DB from \(oldDb.path) to \(newDb.path)")
        } catch {
            print("DB migration failed: \(error)")
        }
    }

    private init() {
        migrateFromDocumentsIfNeeded()
        // Clear legacy custom dbPath from UserDefaults
        UserDefaults.standard.removeObject(forKey: "dbPath")
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
        exec("CREATE INDEX IF NOT EXISTS idx_entries_date ON entries(date)")
        exec("CREATE INDEX IF NOT EXISTS idx_entries_start_time ON entries(start_time)")
        exec("CREATE INDEX IF NOT EXISTS idx_notes_date_created ON day_notes(date, created_at)")
        exec("CREATE INDEX IF NOT EXISTS idx_linear_note_id ON linear_synced_issues(note_id)")
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

    private func prepareStatement(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
            print("SQL prepare error: \(msg)")
            return nil
        }
        return stmt
    }

    private func bind(_ value: String, to stmt: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, transient)
    }

    private static let isoFormatterWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let simpleFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        isoFormatterWithFraction.date(from: s)
            ?? isoFormatter.date(from: s)
            ?? simpleFmt.date(from: s)
    }

    static func nowISO() -> String {
        simpleFmt.string(from: Date())
    }

    static func todayStr() -> String {
        dayFormatter.string(from: Date())
    }

    static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func dateFromDayString(_ value: String) -> Date? {
        dayFormatter.date(from: value)
    }

    static func dayBounds(for value: String) -> (start: Date, end: Date)? {
        guard let start = dateFromDayString(value),
              let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return (start, end)
    }

    private func loadEntryRecordsLocked() -> [EntryRecord] {
        let sql = "SELECT id, date, type, start_time, end_time FROM entries ORDER BY start_time"
        guard let stmt = prepareStatement(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [EntryRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let storedDate = String(cString: sqlite3_column_text(stmt, 1))
            let type = ActivityType(rawValue: String(cString: sqlite3_column_text(stmt, 2))) ?? .work
            let startStr = String(cString: sqlite3_column_text(stmt, 3))
            let endStr = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

            guard let start = Self.parseDate(startStr) else {
                print("Skipping entry \(id): invalid start_time \(startStr)")
                continue
            }

            if let endStr, let end = Self.parseDate(endStr) {
                results.append(EntryRecord(id: id, storedDate: storedDate, type: type, startTime: start, endTime: end))
            } else if let endStr {
                print("Skipping entry \(id): invalid end_time \(endStr)")
            } else {
                results.append(EntryRecord(id: id, storedDate: storedDate, type: type, startTime: start, endTime: nil))
            }
        }

        return results
    }

    private func entriesLocked(for date: String) -> [TrackerEntry] {
        guard let bounds = Self.dayBounds(for: date) else { return [] }
        let now = Date()

        return loadEntryRecordsLocked().compactMap { record in
            let effectiveEnd = record.endTime ?? now
            let sliceStart = max(record.startTime, bounds.start)
            let sliceEnd = min(effectiveEnd, bounds.end)
            guard sliceEnd > sliceStart else { return nil }

            let displayEnd: Date?
            if record.endTime == nil && sliceEnd == now {
                displayEnd = nil
            } else {
                displayEnd = sliceEnd
            }

            return TrackerEntry(
                id: record.id,
                date: date,
                type: record.type,
                startTime: sliceStart,
                endTime: displayEnd
            )
        }
        .sorted { $0.startTime < $1.startTime }
    }

    private func workEditRestrictionLocked(for date: String) -> String? {
        guard let bounds = Self.dayBounds(for: date) else { return "Invalid date" }
        let now = Date()

        let overlappingWork = loadEntryRecordsLocked().filter { record in
            guard record.type == .work else { return false }
            let effectiveEnd = record.endTime ?? now
            return effectiveEnd > bounds.start && record.startTime < bounds.end
        }

        guard !overlappingWork.isEmpty else { return "No work entries" }

        if overlappingWork.contains(where: { $0.endTime == nil }) {
            return "Stop the active timer first"
        }

        if overlappingWork.contains(where: {
            $0.startTime < bounds.start || (($0.endTime ?? bounds.end) > bounds.end)
        }) {
            return "Cross-midnight work can't be edited as a single total"
        }

        return nil
    }

    // MARK: - Entries

    func getActive() -> TrackerEntry? {
        queue.sync {
            let sql = "SELECT id, date, type, start_time FROM entries WHERE end_time IS NULL ORDER BY start_time DESC LIMIT 1"
            guard let stmt = prepareStatement(sql) else { return nil }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let id = sqlite3_column_int64(stmt, 0)
            let date = String(cString: sqlite3_column_text(stmt, 1))
            let typeStr = String(cString: sqlite3_column_text(stmt, 2))
            let startStr = String(cString: sqlite3_column_text(stmt, 3))
            guard let startTime = Self.parseDate(startStr) else {
                print("Skipping active entry \(id): invalid start_time \(startStr)")
                return nil
            }

            return TrackerEntry(
                id: id,
                date: date,
                type: ActivityType(rawValue: typeStr) ?? .work,
                startTime: startTime,
                endTime: nil
            )
        }
    }

    func stopActive() -> TrackerEntry? {
        queue.sync {
            let selectSQL = "SELECT id, date, type, start_time FROM entries WHERE end_time IS NULL ORDER BY start_time DESC LIMIT 1"
            guard let selectStmt = prepareStatement(selectSQL) else { return nil }
            defer { sqlite3_finalize(selectStmt) }

            guard sqlite3_step(selectStmt) == SQLITE_ROW else { return nil }

            let id = sqlite3_column_int64(selectStmt, 0)
            let date = String(cString: sqlite3_column_text(selectStmt, 1))
            let typeStr = String(cString: sqlite3_column_text(selectStmt, 2))
            let startStr = String(cString: sqlite3_column_text(selectStmt, 3))
            guard let startTime = Self.parseDate(startStr) else {
                print("Skipping active entry \(id): invalid start_time \(startStr)")
                return nil
            }

            let endTime = Date()
            let updateSQL = "UPDATE entries SET end_time = ? WHERE id = ?"
            guard let updateStmt = prepareStatement(updateSQL) else { return nil }
            defer { sqlite3_finalize(updateStmt) }

            bind(Self.nowISO(), to: updateStmt, at: 1)
            sqlite3_bind_int64(updateStmt, 2, id)
            guard sqlite3_step(updateStmt) == SQLITE_DONE else { return nil }

            return TrackerEntry(
                id: id,
                date: date,
                type: ActivityType(rawValue: typeStr) ?? .work,
                startTime: startTime,
                endTime: endTime
            )
        }
    }

    func startActivity(_ type: ActivityType) {
        queue.sync {
            let now = Self.nowISO()

            if let closeStmt = prepareStatement("UPDATE entries SET end_time = ? WHERE end_time IS NULL") {
                bind(now, to: closeStmt, at: 1)
                sqlite3_step(closeStmt)
                sqlite3_finalize(closeStmt)
            }

            let insertSQL = "INSERT INTO entries (date, type, start_time) VALUES (?, ?, ?)"
            guard let insertStmt = prepareStatement(insertSQL) else { return }
            defer { sqlite3_finalize(insertStmt) }

            bind(Self.todayStr(), to: insertStmt, at: 1)
            bind(type.rawValue, to: insertStmt, at: 2)
            bind(now, to: insertStmt, at: 3)
            sqlite3_step(insertStmt)
        }
    }

    func getTodayEntries() -> [TrackerEntry] {
        getEntries(for: Self.todayStr())
    }

    func getEntries(for date: String) -> [TrackerEntry] {
        queue.sync {
            entriesLocked(for: date)
        }
    }

    // MARK: - Stats

    func getStats(from startDate: String, to endDate: String) -> [DayStats] {
        queue.sync {
            guard let startBounds = Self.dayBounds(for: startDate),
                  let endBounds = Self.dayBounds(for: toDateFloor(to: endDate)) else {
                return []
            }

            let rangeStart = startBounds.start
            let rangeEnd = endBounds.end
            let calendar = Calendar.current
            let now = Date()
            var days: [String: DayStats] = [:]

            for record in loadEntryRecordsLocked() {
                let effectiveEnd = record.endTime ?? now
                guard effectiveEnd > rangeStart, record.startTime < rangeEnd else { continue }

                var cursor = calendar.startOfDay(for: max(record.startTime, rangeStart))
                while cursor < effectiveEnd && cursor < rangeEnd {
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }

                    let sliceStart = max(record.startTime, cursor, rangeStart)
                    let sliceEnd = min(effectiveEnd, nextDay, rangeEnd)
                    if sliceEnd > sliceStart {
                        let key = Self.dayString(from: cursor)
                        var day = days[key] ?? DayStats(date: key)
                        let seconds = sliceEnd.timeIntervalSince(sliceStart)
                        switch record.type {
                        case .work: day.work += seconds
                        case .lunch: day.lunch += seconds
                        case .break: day.breakTime += seconds
                        }
                        days[key] = day
                    }

                    cursor = nextDay
                }
            }

            return days.values.sorted { $0.date > $1.date }
        }
    }

    // MARK: - Adjust Work Hours

    @discardableResult
    func adjustWorkHours(date: String, targetSeconds: Double) -> Bool {
        queue.sync {
            guard workEditRestrictionLocked(for: date) == nil else { return false }

            let sql = "SELECT id, start_time, end_time FROM entries WHERE date = ? AND type = 'work' ORDER BY start_time"
            guard let stmt = prepareStatement(sql) else { return false }
            bind(date, to: stmt, at: 1)

            struct WorkEntry {
                let id: Int64
                let start: Date
                let duration: Double
            }

            var entries: [WorkEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let startStr = String(cString: sqlite3_column_text(stmt, 1))
                let endStr = sqlite3_column_text(stmt, 2).map { String(cString: $0) }

                guard let start = Self.parseDate(startStr),
                      let endStr,
                      let end = Self.parseDate(endStr) else {
                    continue
                }

                entries.append(WorkEntry(id: id, start: start, duration: end.timeIntervalSince(start)))
            }
            sqlite3_finalize(stmt)

            guard !entries.isEmpty else { return false }

            if targetSeconds <= 0 {
                let deleteSQL = "DELETE FROM entries WHERE date = ? AND type = 'work'"
                guard let deleteStmt = prepareStatement(deleteSQL) else { return false }
                defer { sqlite3_finalize(deleteStmt) }
                bind(date, to: deleteStmt, at: 1)
                return sqlite3_step(deleteStmt) == SQLITE_DONE
            }

            let total = entries.reduce(0.0) { $0 + $1.duration }
            let diff = targetSeconds - total
            let last = entries.last!
            let newDuration = last.duration + diff

            if newDuration < 0 {
                var remaining = targetSeconds
                for entry in entries {
                    if remaining <= 0 {
                        guard let deleteStmt = prepareStatement("DELETE FROM entries WHERE id = ?") else { return false }
                        sqlite3_bind_int64(deleteStmt, 1, entry.id)
                        sqlite3_step(deleteStmt)
                        sqlite3_finalize(deleteStmt)
                        continue
                    }

                    if entry.duration <= remaining {
                        remaining -= entry.duration
                        continue
                    }

                    let newEnd = entry.start.addingTimeInterval(remaining)
                    guard let updateStmt = prepareStatement("UPDATE entries SET end_time = ? WHERE id = ?") else { return false }
                    bind(Self.simpleFmt.string(from: newEnd), to: updateStmt, at: 1)
                    sqlite3_bind_int64(updateStmt, 2, entry.id)
                    sqlite3_step(updateStmt)
                    sqlite3_finalize(updateStmt)
                    remaining = 0
                }
            } else {
                let newEnd = last.start.addingTimeInterval(newDuration)
                guard let updateStmt = prepareStatement("UPDATE entries SET end_time = ? WHERE id = ?") else { return false }
                defer { sqlite3_finalize(updateStmt) }
                bind(Self.simpleFmt.string(from: newEnd), to: updateStmt, at: 1)
                sqlite3_bind_int64(updateStmt, 2, last.id)
                guard sqlite3_step(updateStmt) == SQLITE_DONE else { return false }
            }

            return true
        }
    }

    func workEditRestriction(for date: String) -> String? {
        queue.sync {
            workEditRestrictionLocked(for: date)
        }
    }

    // MARK: - Notes

    func getNotes(for date: String) -> [DayNote] {
        queue.sync {
            let sql = "SELECT id, date, content, created_at FROM day_notes WHERE date = ? ORDER BY created_at"
            guard let stmt = prepareStatement(sql) else { return [] }
            defer { sqlite3_finalize(stmt) }

            bind(date, to: stmt, at: 1)

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
        _ = addNoteReturningId(date: date, content: content)
    }

    func deleteNote(id: Int64) {
        queue.sync {
            if let syncStmt = prepareStatement("DELETE FROM linear_synced_issues WHERE note_id = ?") {
                sqlite3_bind_int64(syncStmt, 1, id)
                sqlite3_step(syncStmt)
                sqlite3_finalize(syncStmt)
            }

            if let noteStmt = prepareStatement("DELETE FROM day_notes WHERE id = ?") {
                sqlite3_bind_int64(noteStmt, 1, id)
                sqlite3_step(noteStmt)
                sqlite3_finalize(noteStmt)
            }
        }
    }

    // MARK: - Summaries

    func getSummary(for date: String) -> DaySummary? {
        queue.sync {
            let sql = "SELECT date, summary, generated_at FROM day_summaries WHERE date = ?"
            guard let stmt = prepareStatement(sql) else { return nil }
            defer { sqlite3_finalize(stmt) }

            bind(date, to: stmt, at: 1)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return DaySummary(
                date: String(cString: sqlite3_column_text(stmt, 0)),
                summary: String(cString: sqlite3_column_text(stmt, 1)),
                generatedAt: String(cString: sqlite3_column_text(stmt, 2))
            )
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
            guard let stmt = prepareStatement(sql) else { return }
            defer { sqlite3_finalize(stmt) }

            bind(date, to: stmt, at: 1)
            bind(summary, to: stmt, at: 2)
            bind(now, to: stmt, at: 3)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Export

    func getExportRows(period: String) -> [ExportRow] {
        let today = Date()
        let calendar = Calendar.current

        let startDate: Date
        switch period {
        case "week":
            startDate = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case "month":
            startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        case "year":
            startDate = calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
        case "all":
            startDate = Self.dateFromDayString("2000-01-01") ?? today
        default:
            startDate = today
        }

        let startDay = Self.dayString(from: startDate)
        let endDay = Self.dayString(from: today)
        let stats = getStats(from: startDay, to: endDay)
        let summaries = getSummaries(from: startDay, to: endDay)

        return stats
            .sorted { $0.date < $1.date }
            .map { day in
                let hours = round((day.work / 3600.0) * 100) / 100
                return ExportRow(date: day.date, hours: hours, summary: summaries[day.date] ?? "")
            }
    }

    private func getSummaries(from startDate: String, to endDate: String) -> [String: String] {
        queue.sync {
            let sql = "SELECT date, summary FROM day_summaries WHERE date >= ? AND date <= ?"
            guard let stmt = prepareStatement(sql) else { return [:] }
            defer { sqlite3_finalize(stmt) }

            bind(startDate, to: stmt, at: 1)
            bind(endDate, to: stmt, at: 2)

            var summaries: [String: String] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let date = String(cString: sqlite3_column_text(stmt, 0))
                let summary = String(cString: sqlite3_column_text(stmt, 1))
                summaries[date] = summary
            }
            return summaries
        }
    }

    // MARK: - Linear Sync Deduplication

    func isIssueSynced(_ issueId: String) -> Bool {
        queue.sync {
            let sql = "SELECT 1 FROM linear_synced_issues WHERE issue_id = ? LIMIT 1"
            guard let stmt = prepareStatement(sql) else { return false }
            defer { sqlite3_finalize(stmt) }

            bind(issueId, to: stmt, at: 1)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    func markIssueSynced(_ issue: LinearIssue, noteId: Int64) {
        queue.sync {
            let now = Self.nowISO()
            let sql = """
                INSERT OR REPLACE INTO linear_synced_issues
                (issue_id, identifier, title, completed_at, synced_at, note_id)
                VALUES (?, ?, ?, ?, ?, ?)
            """
            guard let stmt = prepareStatement(sql) else { return }
            defer { sqlite3_finalize(stmt) }

            bind(issue.id, to: stmt, at: 1)
            bind(issue.identifier, to: stmt, at: 2)
            bind(issue.title, to: stmt, at: 3)
            bind(issue.completedAt, to: stmt, at: 4)
            bind(now, to: stmt, at: 5)
            sqlite3_bind_int64(stmt, 6, noteId)
            sqlite3_step(stmt)
        }
    }

    func addNoteReturningId(date: String, content: String) -> Int64 {
        queue.sync {
            let now = Self.nowISO()
            let sql = "INSERT INTO day_notes (date, content, created_at) VALUES (?, ?, ?)"
            guard let stmt = prepareStatement(sql) else { return -1 }
            defer { sqlite3_finalize(stmt) }

            bind(date, to: stmt, at: 1)
            bind(content, to: stmt, at: 2)
            bind(now, to: stmt, at: 3)
            guard sqlite3_step(stmt) == SQLITE_DONE else { return -1 }
            return sqlite3_last_insert_rowid(db)
        }
    }

    func getSyncStatus() -> LinearSyncStatus {
        queue.sync {
            let sql = "SELECT COUNT(*), MAX(synced_at) FROM linear_synced_issues"
            guard let stmt = prepareStatement(sql) else {
                return LinearSyncStatus()
            }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else {
                return LinearSyncStatus()
            }

            let count = Int(sqlite3_column_int(stmt, 0))
            let lastSync = sqlite3_column_text(stmt, 1)
                .map { String(cString: $0) }
                .flatMap(Self.parseDate)
            return LinearSyncStatus(totalSynced: count, lastSync: lastSync)
        }
    }

    // MARK: - Delete day

    func deleteDay(_ date: String) {
        queue.sync {
            guard let bounds = Self.dayBounds(for: date) else { return }
            let startISO = Self.simpleFmt.string(from: bounds.start)
            let endISO = Self.simpleFmt.string(from: bounds.end)

            if let syncStmt = prepareStatement("""
                DELETE FROM linear_synced_issues
                WHERE note_id IN (SELECT id FROM day_notes WHERE date = ?)
            """) {
                bind(date, to: syncStmt, at: 1)
                sqlite3_step(syncStmt)
                sqlite3_finalize(syncStmt)
            }

            if let notesStmt = prepareStatement("DELETE FROM day_notes WHERE date = ?") {
                bind(date, to: notesStmt, at: 1)
                sqlite3_step(notesStmt)
                sqlite3_finalize(notesStmt)
            }

            if let summaryStmt = prepareStatement("DELETE FROM day_summaries WHERE date = ?") {
                bind(date, to: summaryStmt, at: 1)
                sqlite3_step(summaryStmt)
                sqlite3_finalize(summaryStmt)
            }

            if let entriesStmt = prepareStatement("""
                DELETE FROM entries
                WHERE start_time >= ? AND start_time < ?
            """) {
                bind(startISO, to: entriesStmt, at: 1)
                bind(endISO, to: entriesStmt, at: 2)
                sqlite3_step(entriesStmt)
                sqlite3_finalize(entriesStmt)
            }
        }
    }

    private func toDateFloor(to value: String) -> String {
        value
    }

    // MARK: - Full Export / Import / Reset

    struct FullExport: Codable {
        var entries: [[String: String]]
        var notes: [[String: String]]
        var summaries: [[String: String]]
        var linearSynced: [[String: String]]
    }

    func exportAll() -> Data? {
        queue.sync {
            var export = FullExport(entries: [], notes: [], summaries: [], linearSynced: [])

            // entries
            if let stmt = prepareStatement("SELECT id, date, type, start_time, end_time FROM entries ORDER BY start_time") {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String: String] = [:]
                    row["id"] = "\(sqlite3_column_int64(stmt, 0))"
                    row["date"] = String(cString: sqlite3_column_text(stmt, 1))
                    row["type"] = String(cString: sqlite3_column_text(stmt, 2))
                    row["start_time"] = String(cString: sqlite3_column_text(stmt, 3))
                    if let end = sqlite3_column_text(stmt, 4) { row["end_time"] = String(cString: end) }
                    export.entries.append(row)
                }
                sqlite3_finalize(stmt)
            }

            // notes
            if let stmt = prepareStatement("SELECT id, date, content, created_at FROM day_notes ORDER BY created_at") {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String: String] = [:]
                    row["id"] = "\(sqlite3_column_int64(stmt, 0))"
                    row["date"] = String(cString: sqlite3_column_text(stmt, 1))
                    row["content"] = String(cString: sqlite3_column_text(stmt, 2))
                    row["created_at"] = String(cString: sqlite3_column_text(stmt, 3))
                    export.notes.append(row)
                }
                sqlite3_finalize(stmt)
            }

            // summaries
            if let stmt = prepareStatement("SELECT date, summary, generated_at FROM day_summaries ORDER BY date") {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String: String] = [:]
                    row["date"] = String(cString: sqlite3_column_text(stmt, 0))
                    row["summary"] = String(cString: sqlite3_column_text(stmt, 1))
                    row["generated_at"] = String(cString: sqlite3_column_text(stmt, 2))
                    export.summaries.append(row)
                }
                sqlite3_finalize(stmt)
            }

            // linear synced
            if let stmt = prepareStatement("SELECT issue_id, identifier, title, completed_at, synced_at, note_id FROM linear_synced_issues ORDER BY synced_at") {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String: String] = [:]
                    row["issue_id"] = String(cString: sqlite3_column_text(stmt, 0))
                    row["identifier"] = String(cString: sqlite3_column_text(stmt, 1))
                    row["title"] = String(cString: sqlite3_column_text(stmt, 2))
                    row["completed_at"] = String(cString: sqlite3_column_text(stmt, 3))
                    row["synced_at"] = String(cString: sqlite3_column_text(stmt, 4))
                    if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
                        row["note_id"] = "\(sqlite3_column_int64(stmt, 5))"
                    }
                    export.linearSynced.append(row)
                }
                sqlite3_finalize(stmt)
            }

            return try? JSONEncoder().encode(export)
        }
    }

    func importAll(from data: Data) -> Bool {
        queue.sync {
            guard let export = try? JSONDecoder().decode(FullExport.self, from: data) else { return false }

            // Clear existing data
            exec("DELETE FROM linear_synced_issues")
            exec("DELETE FROM day_summaries")
            exec("DELETE FROM day_notes")
            exec("DELETE FROM entries")

            // Import entries
            for row in export.entries {
                guard let date = row["date"], let type = row["type"], let start = row["start_time"] else { continue }
                if let endTime = row["end_time"] {
                    let sql = "INSERT INTO entries (date, type, start_time, end_time) VALUES (?, ?, ?, ?)"
                    if let stmt = prepareStatement(sql) {
                        bind(date, to: stmt, at: 1)
                        bind(type, to: stmt, at: 2)
                        bind(start, to: stmt, at: 3)
                        bind(endTime, to: stmt, at: 4)
                        sqlite3_step(stmt)
                        sqlite3_finalize(stmt)
                    }
                } else {
                    let sql = "INSERT INTO entries (date, type, start_time) VALUES (?, ?, ?)"
                    if let stmt = prepareStatement(sql) {
                        bind(date, to: stmt, at: 1)
                        bind(type, to: stmt, at: 2)
                        bind(start, to: stmt, at: 3)
                        sqlite3_step(stmt)
                        sqlite3_finalize(stmt)
                    }
                }
            }

            // Import notes
            for row in export.notes {
                guard let date = row["date"], let content = row["content"], let createdAt = row["created_at"] else { continue }
                let sql = "INSERT INTO day_notes (date, content, created_at) VALUES (?, ?, ?)"
                if let stmt = prepareStatement(sql) {
                    bind(date, to: stmt, at: 1)
                    bind(content, to: stmt, at: 2)
                    bind(createdAt, to: stmt, at: 3)
                    sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
            }

            // Import summaries
            for row in export.summaries {
                guard let date = row["date"], let summary = row["summary"], let gen = row["generated_at"] else { continue }
                let sql = "INSERT OR REPLACE INTO day_summaries (date, summary, generated_at) VALUES (?, ?, ?)"
                if let stmt = prepareStatement(sql) {
                    bind(date, to: stmt, at: 1)
                    bind(summary, to: stmt, at: 2)
                    bind(gen, to: stmt, at: 3)
                    sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
            }

            // Import linear synced
            for row in export.linearSynced {
                guard let issueId = row["issue_id"], let identifier = row["identifier"],
                      let title = row["title"], let completedAt = row["completed_at"],
                      let syncedAt = row["synced_at"] else { continue }
                let sql = "INSERT OR REPLACE INTO linear_synced_issues (issue_id, identifier, title, completed_at, synced_at, note_id) VALUES (?, ?, ?, ?, ?, ?)"
                if let stmt = prepareStatement(sql) {
                    bind(issueId, to: stmt, at: 1)
                    bind(identifier, to: stmt, at: 2)
                    bind(title, to: stmt, at: 3)
                    bind(completedAt, to: stmt, at: 4)
                    bind(syncedAt, to: stmt, at: 5)
                    if let noteIdStr = row["note_id"], let noteId = Int64(noteIdStr) {
                        sqlite3_bind_int64(stmt, 6, noteId)
                    } else {
                        sqlite3_bind_null(stmt, 6)
                    }
                    sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
            }

            return true
        }
    }

    func resetAll() {
        queue.sync {
            exec("DELETE FROM linear_synced_issues")
            exec("DELETE FROM day_summaries")
            exec("DELETE FROM day_notes")
            exec("DELETE FROM entries")
        }
    }
}
