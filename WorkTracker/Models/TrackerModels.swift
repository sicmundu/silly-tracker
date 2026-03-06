import Foundation
import SwiftUI

// MARK: - Activity Type

enum ActivityType: String, CaseIterable, Identifiable {
    case work
    case lunch
    case `break`

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .work: return "bolt.fill"
        case .lunch: return "fork.knife"
        case .break: return "cup.and.saucer.fill"
        }
    }

    var label: String {
        switch self {
        case .work: return "Work"
        case .lunch: return "Lunch"
        case .break: return "Break"
        }
    }

    var accentColor: Color {
        switch self {
        case .work: return Color(red: 0.29, green: 0.87, blue: 0.50)   // #4ade80
        case .lunch: return Color(red: 0.98, green: 0.80, blue: 0.08)  // #facc15
        case .break: return Color(red: 0.13, green: 0.83, blue: 0.93)  // #22d3ee
        }
    }

    var bgColor: Color {
        accentColor.opacity(0.08)
    }
}

// MARK: - Entry

struct TrackerEntry: Identifiable {
    let id: Int64
    let date: String
    let type: ActivityType
    let startTime: Date
    let endTime: Date?

    var isRunning: Bool { endTime == nil }

    func duration(now: Date = Date()) -> TimeInterval {
        let end = endTime ?? now
        return end.timeIntervalSince(startTime)
    }

    func formattedDuration(now: Date = Date()) -> String {
        let total = Int(duration(now: now))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Day Note

struct DayNote: Identifiable {
    let id: Int64
    let date: String
    let content: String
    let createdAt: String

    var isFromLinear: Bool {
        content.hasPrefix("[Linear ")
    }

    var timeOnly: String {
        if createdAt.count >= 16 {
            return String(createdAt.dropFirst(11).prefix(5))
        }
        return ""
    }
}

// MARK: - Day Stats

struct DayStats: Identifiable {
    var id: String { date }
    let date: String
    var work: TimeInterval = 0
    var lunch: TimeInterval = 0
    var breakTime: TimeInterval = 0

    var total: TimeInterval { work + lunch + breakTime }
    var workHours: Double { work / 3600.0 }

    var formattedWork: String {
        let h = work / 3600
        return String(format: "%.1fh", h)
    }

    var formattedWorkHM: String {
        let total = Int(work)
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h):\(String(format: "%02d", m))"
    }

    var shortDate: String {
        guard date.count >= 10 else { return date }
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(parts[1]) ?? 0
        let d = Int(parts[2]) ?? 0
        return m > 0 && m <= 12 ? "\(months[m]) \(d)" : String(date.suffix(5))
    }
}

// MARK: - Stats Period

enum StatsPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case year
    case all
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .all: return "All"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Day Summary

struct DaySummary {
    let date: String
    let summary: String
    let generatedAt: String
}

// MARK: - Export Row

struct ExportRow {
    let date: String
    let hours: Double
    let summary: String
}

// MARK: - Linear Issue

struct LinearIssue {
    let id: String
    let identifier: String
    let title: String
    let completedAt: String
}

// MARK: - Sync Status

struct LinearSyncStatus {
    var totalSynced: Int = 0
    var lastSync: Date?
    var lastError: String?
}
