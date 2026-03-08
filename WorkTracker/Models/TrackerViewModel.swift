import Foundation
import Combine
import SwiftUI

@MainActor
final class TrackerViewModel: ObservableObject {

    // MARK: - Published state

    @Published var activeEntry: TrackerEntry?
    @Published var todayEntries: [TrackerEntry] = []
    @Published var todayNotes: [DayNote] = []
    @Published var todaySummary: DaySummary?

    @Published var selectedDate: Date = Date()
    @Published var selectedEntries: [TrackerEntry] = []
    @Published var selectedNotes: [DayNote] = []
    @Published var selectedSummary: DaySummary?

    @Published var weekStats: [DayStats] = []
    @Published var elapsed: TimeInterval = 0
    @Published var elapsedFormatted: String = "00:00:00"
    @Published var syncStatus: LinearSyncStatus = .init()
    @Published var isSyncing = false
    @Published var toastMessage: String?

    /// Current time — updated every second only while a timer is active.
    @Published var now = Date()

    // AI summary
    @Published var isGeneratingSummary = false

    // Edit hours
    @Published var isEditingHours = false
    @Published var editingHoursValue: String = ""
    @Published var editingDate: String = ""

    // Stats period
    @Published var statsPeriod: StatsPeriod = .week
    @Published var customStatsStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @Published var customStatsEnd: Date = Date()

    // MARK: - App Preferences
    @AppStorage("isMiniMode") var isMiniMode: Bool = false
    @AppStorage("dailyGoalHours") var dailyGoalHours: Double = 8.0
    @AppStorage("syncInterval") private var syncIntervalSeconds: Double = 300

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

    deinit {
        timer?.invalidate()
        syncTimer?.invalidate()
    }

    // MARK: - Timers

    private func startTimers() {
        if activeEntry != nil {
            startTickTimer()
        }
        reloadSyncTimer()
        Task { await linearSync(silent: true) }
    }

    private func startTickTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTickTimer() {
        timer?.invalidate()
        timer = nil
    }

    func reloadSyncTimer() {
        syncTimer?.invalidate()

        let interval = syncIntervalSeconds > 0 ? syncIntervalSeconds : 300
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.linearSync(silent: true)
            }
        }
    }

    private func tick() {
        let current = Date()
        if let active = activeEntry {
            now = current
            elapsed = current.timeIntervalSince(active.startTime)
            let total = Int(elapsed)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            elapsedFormatted = String(format: "%02d:%02d:%02d", h, m, s)
        }
        // When idle, don't update any @Published properties — avoids unnecessary view redraws.
    }

    // MARK: - Actions

    func startActivity(_ type: ActivityType) {
        db.startActivity(type)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            refresh()
        }
        startTickTimer()
        showToast("\(type.label) started")
    }

    func stopActivity() {
        if let stopped = db.stopActive() {
            showToast("\(stopped.type.label) stopped")
        } else {
            showToast("Nothing running")
        }
        stopTickTimer()
        elapsed = 0
        elapsedFormatted = "00:00:00"
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            refresh()
        }
    }

    func addNote(_ content: String, on date: String? = nil) {
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        db.addNote(date: date ?? selectedDateString, content: content)
        withAnimation(.easeOut(duration: 0.25)) {
            refresh()
        }
    }

    func deleteNote(_ note: DayNote) {
        db.deleteNote(id: note.id)
        withAnimation(.easeOut(duration: 0.2)) {
            refresh()
        }
    }

    func setSelectedDate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        withAnimation(.easeOut(duration: 0.2)) {
            refreshSelectedDay()
        }
    }

    func jumpToToday() {
        setSelectedDate(Date())
    }

    // MARK: - Edit hours

    func beginEditHours(date: String, currentHours: Double) {
        guard let restriction = db.workEditRestriction(for: date) else {
            editingDate = date
            let totalMinutes = Int((currentHours * 60).rounded())
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            editingHoursValue = "\(h):\(String(format: "%02d", m))"
            isEditingHours = true
            return
        }

        showToast(restriction)
    }

    func commitEditHours() {
        isEditingHours = false

        guard db.workEditRestriction(for: editingDate) == nil else {
            showToast("Work hours can't be edited for this day")
            return
        }

        let targetSeconds: Double
        if editingHoursValue.contains(":") {
            let parts = editingHoursValue.split(separator: ":")
            let h = Double(parts.first ?? "0") ?? 0
            let m = parts.count > 1 ? (Double(parts[1]) ?? 0) : 0
            targetSeconds = h * 3600 + m * 60
        } else {
            let h = Double(editingHoursValue) ?? 0
            targetSeconds = h * 3600
        }

        guard targetSeconds >= 0 else {
            showToast("Hours must be positive")
            return
        }

        guard db.adjustWorkHours(date: editingDate, targetSeconds: targetSeconds) else {
            showToast("Hours couldn't be updated")
            return
        }

        withAnimation(.easeOut(duration: 0.3)) {
            refresh()
        }
        showToast("Hours updated")
    }

    // MARK: - AI Summary

    func generateSummary(for date: Date? = nil) async {
        withAnimation { isGeneratingSummary = true }

        let targetDate = date ?? selectedDate
        let dayString = Self.ymdFormatter.string(from: targetDate)
        let stats = db.getStats(from: dayString, to: dayString).first ?? DayStats(date: dayString)
        let notes = db.getNotes(for: dayString).map { ["content": $0.content, "created_at": $0.createdAt] }

        let payload: [String: Double] = [
            "work": stats.work,
            "lunch": stats.lunch,
            "break": stats.breakTime
        ]

        let (summary, error) = await AIClient.shared.generateSummary(
            date: dayString,
            notes: notes,
            stats: payload
        )

        withAnimation(.easeOut(duration: 0.3)) {
            isGeneratingSummary = false
        }

        if let summary {
            db.saveSummary(date: dayString, summary: summary)
            withAnimation(.easeOut(duration: 0.3)) {
                refresh()
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
                let totalMinutes = Int((row.hours * 60).rounded())
                let h = totalMinutes / 60
                let m = totalMinutes % 60
                let hStr = "\(h):\(String(format: "%02d", m))"
                let safeSummary = row.summary.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\(row.date),\(hStr),\"\(safeSummary)\"\n"
                totalHours += row.hours
            }

            let totalMinutes = Int((totalHours * 60).rounded())
            let th = totalMinutes / 60
            let tm = totalMinutes % 60
            csv += "TOTAL,\(th):\(String(format: "%02d", tm)),\n"
            return (Data(csv.utf8), fname + ".csv")
        }
    }

    // MARK: - Linear sync

    func linearSync(silent: Bool = false, lookbackDays: Int? = nil) async {
        guard linear.isConfigured else {
            if !silent { showToast("Set Linear API key in Settings") }
            return
        }

        withAnimation { isSyncing = true }
        let (added, skipped, error) = await linear.syncToNotes(lookbackDays: lookbackDays)
        withAnimation { isSyncing = false }

        syncStatus = db.getSyncStatus()

        if let error {
            syncStatus.lastError = error
            if !silent { showToast("Sync error: \(error)") }
            return
        }

        if added > 0 {
            withAnimation { refresh() }
            if !silent { showToast("Synced \(added) tasks") }
        } else if !silent {
            showToast(skipped > 0 ? "No new tasks" : "Nothing to sync")
        }
    }

    // MARK: - Refresh

    func refresh() {
        activeEntry = db.getActive()
        refreshTodayData()
        refreshSelectedDay()
        refreshStats()
        syncStatus = db.getSyncStatus()
        tick()
    }

    private func refreshTodayData() {
        let today = DatabaseManager.todayStr()
        todayEntries = db.getEntries(for: today)
        todayNotes = db.getNotes(for: today)
        todaySummary = db.getSummary(for: today)
    }

    private func refreshSelectedDay() {
        if isViewingToday {
            selectedEntries = todayEntries
            selectedNotes = todayNotes
            selectedSummary = todaySummary
            return
        }

        selectedEntries = db.getEntries(for: selectedDateString)
        selectedNotes = db.getNotes(for: selectedDateString)
        selectedSummary = db.getSummary(for: selectedDateString)
    }

    private static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func refreshStats() {
        let range = statsRange
        weekStats = db.getStats(
            from: Self.ymdFormatter.string(from: range.start),
            to: Self.ymdFormatter.string(from: range.end)
        )
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

    var selectedDateString: String {
        Self.ymdFormatter.string(from: selectedDate)
    }

    var isViewingToday: Bool {
        selectedDateString == DatabaseManager.todayStr()
    }

    var todayTotals: [ActivityType: TimeInterval] {
        totals(for: todayEntries)
    }

    var selectedDayTotals: [ActivityType: TimeInterval] {
        totals(for: selectedEntries)
    }

    var todayWorkHours: Double {
        (todayTotals[.work] ?? 0) / 3600.0
    }

    var selectedDayWorkHours: Double {
        (selectedDayTotals[.work] ?? 0) / 3600.0
    }

    var periodTotalWork: TimeInterval {
        weekStats.reduce(0) { $0 + $1.work }
    }

    var periodTotalAll: TimeInterval {
        weekStats.reduce(0) { $0 + $1.total }
    }

    var periodAveragePerDay: TimeInterval {
        periodTotalWork / Double(max(statsRangeDayCount, 1))
    }

    var periodGoalDelta: TimeInterval {
        periodTotalWork - (Double(statsRangeDayCount) * dailyGoalHours * 3600)
    }

    var periodBestDay: DayStats? {
        weekStats.max { $0.work < $1.work }
    }

    var periodCurrentStreak: Int {
        let calendar = Calendar.current
        let map = Dictionary(uniqueKeysWithValues: weekStats.map { ($0.date, $0.work) })
        let range = statsRange
        let start = calendar.startOfDay(for: range.start)
        var cursor = calendar.startOfDay(for: range.end)
        var streak = 0

        while cursor >= start {
            let key = Self.ymdFormatter.string(from: cursor)
            guard (map[key] ?? 0) > 0 else { break }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    var noteReminderMessage: String? {
        guard let active = activeEntry, active.type == .work else { return nil }
        let threshold: TimeInterval = 45 * 60

        let baseline: Date
        if let lastNote = todayNotes.last,
           let createdAt = DatabaseManager.parseDate(lastNote.createdAt) {
            baseline = createdAt
        } else {
            baseline = active.startTime
        }

        guard now.timeIntervalSince(baseline) >= threshold else { return nil }
        return "No note for 45m. Capture progress before it gets fuzzy."
    }

    func editHoursRestriction(for date: String) -> String? {
        db.workEditRestriction(for: date)
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

    private var statsRange: (start: Date, end: Date) {
        let today = Date()
        let cal = Calendar.current

        switch statsPeriod {
        case .today:
            return (today, today)
        case .week:
            return (cal.date(byAdding: .day, value: -6, to: today) ?? today, today)
        case .month:
            return (cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today, today)
        case .year:
            return (cal.date(from: cal.dateComponents([.year], from: today)) ?? today, today)
        case .all:
            return (cal.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? today, today)
        case .custom:
            return (customStatsStart, customStatsEnd)
        }
    }

    private var statsRangeDayCount: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: statsRange.start)
        let end = cal.startOfDay(for: statsRange.end)
        return (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    private func totals(for entries: [TrackerEntry]) -> [ActivityType: TimeInterval] {
        var totals: [ActivityType: TimeInterval] = [:]
        for entry in entries {
            totals[entry.type, default: 0] += entry.duration(now: now)
        }
        return totals
    }
}
