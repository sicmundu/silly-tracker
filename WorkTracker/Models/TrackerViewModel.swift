import Foundation
import Combine
import SwiftUI

@MainActor
final class TrackerViewModel: ObservableObject {

    // MARK: - Published state

    @Published var activeEntry: TrackerEntry?
    @Published var todayEntries: [TrackerEntry] = []
    @Published var todayNotes: [DayNote] = []
    @Published var weekStats: [DayStats] = []
    @Published var elapsed: TimeInterval = 0
    @Published var elapsedFormatted: String = "00:00:00"
    @Published var syncStatus: LinearSyncStatus = .init()
    @Published var isSyncing = false
    @Published var toastMessage: String?

    /// Ticks every second — views that read `now` re-render automatically.
    @Published var now = Date()

    // AI summary
    @Published var todaySummary: DaySummary?
    @Published var isGeneratingSummary = false

    // Edit hours
    @Published var isEditingHours = false
    @Published var editingHoursValue: String = ""
    @Published var editingDate: String = ""

    // Section collapse state
    @Published var isLogCollapsed = false
    @Published var isStatsCollapsed = false
    @Published var isExportCollapsed = true

    // Stats period
    @Published var statsPeriod: StatsPeriod = .week
    @Published var customStatsStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @Published var customStatsEnd: Date = Date()

    // MARK: - App Preferences
    @AppStorage("isMiniMode") var isMiniMode: Bool = false
    @AppStorage("dailyGoalHours") var dailyGoalHours: Double = 8.0

    // MARK: - Private

    private let db = DatabaseManager.shared
    private let linear = LinearClient.shared
    private var timer: Timer?
    private var syncTimer: Timer?

    // MARK: - Init

    init() {
        refresh()
        startTimers()
    }

    // MARK: - Timers

    private func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }

        let interval = UserDefaults.standard.double(forKey: "syncInterval")
        let syncSec = interval > 0 ? interval : 300
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncSec, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.linearSync(silent: true)
            }
        }

        Task { await linearSync(silent: true) }
    }

    private func tick() {
        now = Date()
        if let active = activeEntry {
            elapsed = now.timeIntervalSince(active.startTime)
            let total = Int(elapsed)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            elapsedFormatted = String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            elapsed = 0
            elapsedFormatted = "00:00:00"
        }
    }

    // MARK: - Actions

    func startActivity(_ type: ActivityType) {
        db.startActivity(type)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            refresh()
        }
        showToast("\(type.label) started")
    }

    func stopActivity() {
        if let stopped = db.stopActive() {
            showToast("\(stopped.type.label) stopped")
        } else {
            showToast("Nothing running")
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            refresh()
        }
    }

    func addNote(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        db.addNote(date: DatabaseManager.todayStr(), content: content)
        withAnimation(.easeOut(duration: 0.25)) {
            refreshNotes()
        }
    }

    func deleteNote(_ note: DayNote) {
        db.deleteNote(id: note.id)
        withAnimation(.easeOut(duration: 0.2)) {
            refreshNotes()
        }
    }

    // MARK: - Edit hours

    func beginEditHours(date: String, currentHours: Double) {
        editingDate = date
        let h = Int(currentHours)
        let m = Int((currentHours - Double(h)) * 60)
        editingHoursValue = "\(h):\(String(format: "%02d", m))"
        isEditingHours = true
    }

    func commitEditHours() {
        isEditingHours = false
        let targetSeconds: Double
        if editingHoursValue.contains(":") {
            let parts = editingHoursValue.split(separator: ":")
            let h = Double(parts[0]) ?? 0
            let m = parts.count > 1 ? (Double(parts[1]) ?? 0) : 0
            targetSeconds = h * 3600 + m * 60
        } else {
            let h = Double(editingHoursValue) ?? 0
            targetSeconds = h * 3600
        }

        guard targetSeconds >= 0 else { return }
        db.adjustWorkHours(date: editingDate, targetSeconds: targetSeconds)
        withAnimation(.easeOut(duration: 0.3)) { refresh() }
        showToast("Hours updated")
    }

    // MARK: - AI Summary

    func generateSummary() async {
        withAnimation { isGeneratingSummary = true }
        let today = DatabaseManager.todayStr()

        let totals = todayTotals
        let stats: [String: Double] = [
            "work": totals[.work] ?? 0,
            "lunch": totals[.lunch] ?? 0,
            "break": totals[.break] ?? 0
        ]

        let notes = todayNotes.map { ["content": $0.content, "created_at": $0.createdAt] }

        let (summary, error) = await AIClient.shared.generateSummary(
            date: today,
            notes: notes,
            stats: stats
        )

        withAnimation(.easeOut(duration: 0.3)) {
            isGeneratingSummary = false
        }

        if let summary {
            db.saveSummary(date: today, summary: summary)
            withAnimation(.easeOut(duration: 0.3)) {
                todaySummary = DaySummary(date: today, summary: summary, generatedAt: DatabaseManager.nowISO())
            }
            showToast("Summary generated")
        } else if let error {
            showToast("AI error: \(error)")
        }
    }

    // MARK: - Export

    func exportData(period: String, format: String) -> (data: Data, filename: String)? {
        let rows = db.getExportRows(period: period)
        guard !rows.isEmpty else { return nil }

        let fname = "work-tracker-\(period)"

        if format == "json" {
            let jsonRows = rows.map { row -> [String: Any] in
                ["date": row.date, "hours": row.hours, "summary": row.summary]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: jsonRows, options: .prettyPrinted) else {
                return nil
            }
            return (data, fname + ".json")
        } else {
            var csv = "date,hours,summary\n"
            var totalHours = 0.0
            for row in rows {
                let h = Int(row.hours)
                let m = Int((row.hours - Double(h)) * 60)
                let hStr = "\(h):\(String(format: "%02d", m))"
                let safeSummary = row.summary.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\(row.date),\(hStr),\"\(safeSummary)\"\n"
                totalHours += row.hours
            }
            let th = Int(totalHours)
            let tm = Int((totalHours - Double(th)) * 60)
            csv += "TOTAL,\(th):\(String(format: "%02d", tm)),\n"
            return (Data(csv.utf8), fname + ".csv")
        }
    }

    // MARK: - Linear sync

    func linearSync(silent: Bool = false) async {
        guard linear.isConfigured else {
            if !silent { showToast("Set Linear API key in Settings") }
            return
        }

        withAnimation { isSyncing = true }
        let (added, _, error) = await linear.syncToNotes()
        withAnimation { isSyncing = false }

        syncStatus = db.getSyncStatus()

        if let error {
            syncStatus.lastError = error
            if !silent { showToast("Sync error: \(error)") }
        } else {
            if added > 0 {
                withAnimation { refreshNotes() }
                if !silent { showToast("Synced \(added) new tasks") }
            } else if !silent {
                showToast("Already up to date")
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        activeEntry = db.getActive()
        todayEntries = db.getTodayEntries()
        refreshNotes()
        refreshStats()
        refreshSummary()
        tick()
    }

    private func refreshNotes() {
        todayNotes = db.getNotes(for: DatabaseManager.todayStr())
    }

    private static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func refreshStats() {
        let today = Date()
        let cal = Calendar.current

        let startDate: Date
        let endDate: Date

        switch statsPeriod {
        case .today:
            startDate = today
            endDate = today
        case .week:
            startDate = cal.date(byAdding: .day, value: -6, to: today)!
            endDate = today
        case .month:
            startDate = cal.date(from: cal.dateComponents([.year, .month], from: today))!
            endDate = today
        case .year:
            startDate = cal.date(from: cal.dateComponents([.year], from: today))!
            endDate = today
        case .all:
            startDate = cal.date(from: DateComponents(year: 2000, month: 1, day: 1))!
            endDate = today
        case .custom:
            startDate = customStatsStart
            endDate = customStatsEnd
        }

        weekStats = db.getStats(from: Self.ymdFormatter.string(from: startDate), to: Self.ymdFormatter.string(from: endDate))
    }

    func setStatsPeriod(_ period: StatsPeriod) {
        withAnimation(.easeOut(duration: 0.3)) {
            statsPeriod = period
            refreshStats()
        }
    }

    func setCustomRange(start: Date, end: Date) {
        customStatsStart = start
        customStatsEnd = end
        withAnimation(.easeOut(duration: 0.3)) {
            statsPeriod = .custom
            refreshStats()
        }
    }

    private func refreshSummary() {
        todaySummary = db.getSummary(for: DatabaseManager.todayStr())
    }

    // MARK: - Toast

    private func showToast(_ msg: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toastMessage = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                if self.toastMessage == msg { self.toastMessage = nil }
            }
        }
    }

    // MARK: - Computed

    var todayTotals: [ActivityType: TimeInterval] {
        var totals: [ActivityType: TimeInterval] = [:]
        for entry in todayEntries {
            let dur = entry.duration(now: now)
            totals[entry.type, default: 0] += dur
        }
        return totals
    }

    var todayWorkHours: Double {
        (todayTotals[.work] ?? 0) / 3600.0
    }

    var periodTotalWork: TimeInterval {
        weekStats.reduce(0) { $0 + $1.work }
    }

    var periodTotalAll: TimeInterval {
        weekStats.reduce(0) { $0 + $1.total }
    }

    private static let mmmdFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df
    }()

    var statsPeriodLabel: String {
        switch statsPeriod {
        case .custom:
            return "\(Self.mmmdFormatter.string(from: customStatsStart)) - \(Self.mmmdFormatter.string(from: customStatsEnd))"
        default:
            return statsPeriod.label
        }
    }
}
