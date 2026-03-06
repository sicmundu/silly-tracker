import XCTest
import SQLite3
@testable import WorkTrackerCore

final class DatabaseManagerTests: XCTestCase {
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        useFreshDatabase()
    }

    override func tearDownWithError() throws {
        removeDatabaseArtifacts()
        UserDefaults.standard.removeObject(forKey: "dbPath")
        try super.tearDownWithError()
    }

    func testEntriesAndStatsAreSplitAcrossMidnight() throws {
        try insertEntry(
            date: "2026-03-05",
            type: "work",
            startTime: "2026-03-05T23:30:00",
            endTime: "2026-03-06T01:15:00"
        )

        let march5 = DatabaseManager.shared.getEntries(for: "2026-03-05")
        XCTAssertEqual(march5.count, 1)
        XCTAssertEqual(march5[0].duration(), 30 * 60, accuracy: 1)

        let march6 = DatabaseManager.shared.getEntries(for: "2026-03-06")
        XCTAssertEqual(march6.count, 1)
        XCTAssertEqual(march6[0].duration(), 75 * 60, accuracy: 1)

        let stats = DatabaseManager.shared.getStats(from: "2026-03-05", to: "2026-03-06")
        let statsByDate = Dictionary(uniqueKeysWithValues: stats.map { ($0.date, $0) })
        XCTAssertEqual(statsByDate["2026-03-05"]?.work ?? -1, 30 * 60, accuracy: 1)
        XCTAssertEqual(statsByDate["2026-03-06"]?.work ?? -1, 75 * 60, accuracy: 1)
    }

    func testDeletingLinearNoteAlsoDeletesSyncMarker() {
        let noteId = DatabaseManager.shared.addNoteReturningId(
            date: "2026-03-06",
            content: "[Linear ENG-1] Restore sync marker"
        )

        let issue = LinearIssue(
            id: "issue-1",
            identifier: "ENG-1",
            title: "Restore sync marker",
            completedAt: "2026-03-06T10:00:00.000Z"
        )
        DatabaseManager.shared.markIssueSynced(issue, noteId: noteId)

        XCTAssertTrue(DatabaseManager.shared.isIssueSynced(issue.id))
        DatabaseManager.shared.deleteNote(id: noteId)
        XCTAssertFalse(DatabaseManager.shared.isIssueSynced(issue.id))
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

        XCTAssertNil(DatabaseManager.shared.workEditRestriction(for: "2026-03-04"))
        XCTAssertTrue(DatabaseManager.shared.adjustWorkHours(date: "2026-03-04", targetSeconds: 90 * 60))

        let total = DatabaseManager.shared
            .getEntries(for: "2026-03-04")
            .reduce(0.0) { $0 + $1.duration() }
        XCTAssertEqual(total, 90 * 60, accuracy: 1)
    }

    func testWorkEditRestrictionBlocksOpenAndCrossMidnightDays() throws {
        let today = DatabaseManager.todayStr()
        let todayStart = today + "T00:01:00"
        try insertEntry(
            date: today,
            type: "work",
            startTime: todayStart,
            endTime: nil
        )

        XCTAssertEqual(
            DatabaseManager.shared.workEditRestriction(for: today),
            "Stop the active timer first"
        )

        useFreshDatabase()
        try insertEntry(
            date: "2026-03-05",
            type: "work",
            startTime: "2026-03-05T23:30:00",
            endTime: "2026-03-06T00:30:00"
        )

        XCTAssertEqual(
            DatabaseManager.shared.workEditRestriction(for: "2026-03-06"),
            "Cross-midnight work can't be edited as a single total"
        )
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
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        UserDefaults.standard.set(dbURL.path, forKey: "dbPath")
        removeDatabaseArtifacts()
        DatabaseManager.shared.reopen()
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
