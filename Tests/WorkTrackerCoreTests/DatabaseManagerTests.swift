import XCTest
import SQLite3
@testable import SillyTrackCore

final class DatabaseManagerTests: XCTestCase {
    private var dbURL: URL!
    private var db: DatabaseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        useFreshDatabase()
    }

    override func tearDownWithError() throws {
        db = nil
        removeDatabaseArtifacts()
        try super.tearDownWithError()
    }

    func testEntriesAndStatsAreSplitAcrossMidnight() throws {
        try insertEntry(
            date: "2026-03-05",
            type: "work",
            startTime: "2026-03-05T23:30:00",
            endTime: "2026-03-06T01:15:00"
        )

        let march5 = db.getEntries(for: "2026-03-05")
        XCTAssertEqual(march5.count, 1)
        XCTAssertEqual(march5[0].duration(), 30 * 60, accuracy: 1)

        let march6 = db.getEntries(for: "2026-03-06")
        XCTAssertEqual(march6.count, 1)
        XCTAssertEqual(march6[0].duration(), 75 * 60, accuracy: 1)

        let stats = db.getStats(from: "2026-03-05", to: "2026-03-06")
        let statsByDate = Dictionary(uniqueKeysWithValues: stats.map { ($0.date, $0) })
        XCTAssertEqual(statsByDate["2026-03-05"]?.work ?? -1, 30 * 60, accuracy: 1)
        XCTAssertEqual(statsByDate["2026-03-06"]?.work ?? -1, 75 * 60, accuracy: 1)
    }

    func testDeletingLinearNoteAlsoDeletesSyncMarker() {
        let noteId = db.addNoteReturningId(
            date: "2026-03-06",
            content: "[Linear ENG-1] Restore sync marker"
        )

        let issue = LinearIssue(
            id: "issue-1",
            identifier: "ENG-1",
            title: "Restore sync marker",
            completedAt: "2026-03-06T10:00:00.000Z"
        )
        db.markIssueSynced(issue, noteId: noteId)

        XCTAssertTrue(db.isIssueSynced(issue.id))
        db.deleteNote(id: noteId)
        XCTAssertFalse(db.isIssueSynced(issue.id))
    }

    func testWorkEditRestrictionAndAdjustHoursForSafeDays() throws {
        try insertEntry(
            date: "2026-03-04",
            type: "work",
            startTime: "2026-03-04T09:00:00",
            endTime: "2026-03-04T10:00:00"
        )
        try insertEntry(
            date: "2026-03-04",
            type: "work",
            startTime: "2026-03-04T11:00:00",
            endTime: "2026-03-04T12:00:00"
        )

        XCTAssertNil(db.workEditRestriction(for: "2026-03-04"))
        XCTAssertTrue(db.adjustWorkHours(date: "2026-03-04", targetSeconds: 90 * 60))

        let total = db
            .getEntries(for: "2026-03-04")
            .reduce(0.0) { $0 + $1.duration() }
        XCTAssertEqual(total, 90 * 60, accuracy: 1)
    }

    func testOpenWorkBlocksTodayButClosedCrossMidnightWorkCanBeEdited() throws {
        let today = DatabaseManager.todayStr()
        let todayStart = today + "T00:00:00"
        try insertEntry(
            date: today,
            type: "work",
            startTime: todayStart,
            endTime: nil
        )

        XCTAssertEqual(
            db.workEditRestriction(for: today),
            "Stop the active timer first"
        )

        useFreshDatabase()
        try insertEntry(
            date: "2026-03-05",
            type: "work",
            startTime: "2026-03-05T23:30:00",
            endTime: "2026-03-06T00:30:00"
        )

        XCTAssertNil(db.workEditRestriction(for: "2026-03-06"))
        XCTAssertTrue(db.adjustWorkHours(date: "2026-03-06", targetSeconds: 15 * 60))
        XCTAssertEqual(db.getEntries(for: "2026-03-05").first?.duration() ?? -1, 30 * 60, accuracy: 1)
        XCTAssertEqual(db.getEntries(for: "2026-03-06").first?.duration() ?? -1, 15 * 60, accuracy: 1)
    }

    func testNarrowStatsKeepLongRunningAndOffsetEntries() throws {
        try insertEntry(
            date: "2026-03-01", type: "work",
            startTime: "2026-03-01T23:00:00", endTime: "2026-03-08T00:00:00"
        )
        try insertEntry(
            date: "2026-02-01", type: "work",
            startTime: "2026-02-01T09:00:00", endTime: "2026-02-01T10:00:00"
        )
        let day = "2026-03-06"
        let bounds = try XCTUnwrap(DatabaseManager.dayBounds(for: day))
        let offset = ISO8601DateFormatter()
        offset.timeZone = TimeZone(secondsFromGMT: 14 * 3600)
        try insertEntry(
            date: "2026-03-06", type: "break",
            startTime: offset.string(from: bounds.start.addingTimeInterval(3600)),
            endTime: offset.string(from: bounds.start.addingTimeInterval(7200))
        )
        let entries = db.getEntries(for: day)
        XCTAssertEqual(entries.map(\.type), [.work, .break])
        let stats = try XCTUnwrap(db.getStats(from: day, to: day).first)
        XCTAssertEqual(stats.work, bounds.end.timeIntervalSince(bounds.start), accuracy: 1)
        XCTAssertEqual(stats.breakTime, 3600, accuracy: 1)
    }

    func testWorkEditRestrictionUsesEarliestOpenWorkButIgnoresOpenBreak() throws {
        try insertEntry(date: "2026-03-01", type: "break", startTime: "2026-03-01T12:00:00", endTime: nil)
        XCTAssertNil(db.activeWorkStart())
        try insertEntry(date: "2026-03-04", type: "work", startTime: "2026-03-04T12:00:00", endTime: nil)
        try insertEntry(date: "2026-03-06", type: "work", startTime: "2026-03-06T12:00:00", endTime: nil)
        XCTAssertEqual(db.activeWorkStart(), DatabaseManager.parseDate("2026-03-04T12:00:00"))
        XCTAssertNil(db.workEditRestriction(for: "2026-03-03"))
        XCTAssertEqual(db.workEditRestriction(for: "2026-03-05"), "Stop the active timer first")
    }

    func testReadOnlyStatsMatchesWriterAndCanCancelMidRead() throws {
        try insertEntry(
            date: "2026-03-05", type: "work",
            startTime: "2026-03-05T23:30:00", endTime: "2026-03-06T01:15:00"
        )
        let start = "2026-03-05"
        let end = "2026-03-06"
        let read = try XCTUnwrap(DatabaseManager.readStats(path: dbURL.path, from: start, to: end))
        XCTAssertEqual(read.map(\.work), db.getStats(from: start, to: end).map(\.work))
        var checks = 0
        XCTAssertNil(DatabaseManager.readStats(path: dbURL.path, from: start, to: end) {
            checks += 1
            return checks >= 3
        })
        XCTAssertGreaterThanOrEqual(checks, 3)
    }

    func testBackupRoundTripKeepsLinearNoteLink() throws {
        let day = "2026-03-06"
        let firstID = db.addNoteReturningId(date: day, content: "Deleted note leaves a gap")
        db.deleteNote(id: firstID)
        let noteID = db.addNoteReturningId(date: day, content: "[Linear ENG-8] Keep note link")
        let issue = LinearIssue(id: "issue-8", identifier: "ENG-8", title: "Keep note link", completedAt: "2026-03-06T10:00:00Z")
        db.markIssueSynced(issue, noteId: noteID)
        let backup = try XCTUnwrap(db.exportAll())
        XCTAssertTrue(db.importAll(from: backup))
        let restored = try XCTUnwrap(db.getNotes(for: day).first)
        XCTAssertEqual(restored.id, noteID)
        XCTAssertTrue(db.isIssueSynced(issue.id))
        db.deleteNote(id: restored.id)
        XCTAssertFalse(db.isIssueSynced(issue.id))
    }

    func testFailedBackupImportRollsBackExistingData() throws {
        let day = "2026-03-06"
        db.addNote(date: day, content: "Keep this if import fails")
        let badNote = ["id": "42", "date": day, "content": "Duplicate ID", "created_at": day + "T14:00:00"]
        let backup = DatabaseManager.FullExport(entries: [], notes: [badNote, badNote], summaries: [], linearSynced: [])
        XCTAssertFalse(db.importAll(from: try JSONEncoder().encode(backup)))
        XCTAssertEqual(db.getNotes(for: day).map(\.content), ["Keep this if import fails"])
    }

    func testLegacyBackupWithoutIDsCanStillImport() throws {
        let day = "2026-03-06"
        let note = ["date": day, "content": "Legacy note", "created_at": day + "T14:00:00"]
        let backup = DatabaseManager.FullExport(entries: [], notes: [note], summaries: [], linearSynced: [])
        XCTAssertTrue(db.importAll(from: try JSONEncoder().encode(backup)))
        XCTAssertEqual(db.getNotes(for: day).map(\.content), ["Legacy note"])
    }

    private func insertEntry(date: String, type: String, startTime: String, endTime: String?) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }

        let sql = "INSERT INTO entries (date, type, start_time, end_time) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, (type as NSString).utf8String, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, (startTime as NSString).utf8String, -1, sqliteTransient)
        if let endTime {
            sqlite3_bind_text(stmt, 4, (endTime as NSString).utf8String, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 4)
        }

        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }

    private func removeDatabaseArtifacts() {
        let fm = FileManager.default
        let paths = [
            dbURL?.path,
            dbURL?.path.appending("-wal"),
            dbURL?.path.appending("-shm")
        ].compactMap { $0 }

        for path in paths where fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
    }

    private func useFreshDatabase() {
        db = nil
        if dbURL != nil { removeDatabaseArtifacts() }
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        db = DatabaseManager(path: dbURL.path)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
