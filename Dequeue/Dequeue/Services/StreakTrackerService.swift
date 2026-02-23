//
//  StreakTrackerService.swift
//  Dequeue
//
//  Tracks daily task completion streaks and productivity metrics.
//  Gamifies task completion to encourage consistent daily progress.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.dequeue", category: "StreakTracker")

// MARK: - Daily Record

/// A record of productivity metrics for a single day.
struct DailyProductivityRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String { dateString }

    /// ISO date string (yyyy-MM-dd) for this day
    let dateString: String

    /// Number of tasks completed
    var tasksCompleted: Int

    /// Number of tasks created
    var tasksCreated: Int

    /// Number of stacks completed
    var stacksCompleted: Int

    /// Total focus time in seconds (from FocusTimerService)
    var focusTimeSeconds: TimeInterval

    /// Whether this day counts as "active" (met the minimum threshold)
    var isActive: Bool {
        tasksCompleted >= StreakTrackerService.minimumTasksForStreak
    }
}

// MARK: - Streak Info

/// Summary of the user's current and best streaks.
struct StreakInfo: Equatable, Sendable {
    /// Current consecutive active days
    let currentStreak: Int

    /// Longest streak ever achieved
    let longestStreak: Int

    /// Total tasks completed all time
    let totalTasksCompleted: Int

    /// Total active days
    let totalActiveDays: Int

    /// Whether today has been active
    let isTodayActive: Bool

    /// Tasks completed today
    let todayTasksCompleted: Int

    /// Tasks remaining to maintain streak today
    let tasksRemainingForStreak: Int

    /// This week's daily activity (last 7 days, Mon-Sun)
    let weekActivity: [DayActivity]

    /// This month's daily activity (for heatmap)
    let monthActivity: [DayActivity]
}

/// Activity status for a single day (for visualization).
struct DayActivity: Equatable, Sendable, Identifiable {
    var id: String { dateString }
    let dateString: String
    let date: Date
    let tasksCompleted: Int
    let isActive: Bool

    /// Intensity level for heatmap (0-4)
    var intensityLevel: Int {
        switch tasksCompleted {
        case 0: return 0
        case 1: return 1
        case 2...3: return 2
        case 4...6: return 3
        default: return 4
        }
    }
}

// MARK: - Streak Milestones

/// Streak milestones for celebrations.
enum StreakMilestone: Int, CaseIterable, Sendable {
    case three = 3
    case seven = 7
    case fourteen = 14
    case thirty = 30
    case sixty = 60
    case ninety = 90
    case oneHundred = 100
    case threeHundredSixtyFive = 365

    var emoji: String {
        switch self {
        case .three: return "🔥"
        case .seven: return "⭐"
        case .fourteen: return "💫"
        case .thirty: return "🏆"
        case .sixty: return "💎"
        case .ninety: return "🥇"
        case .oneHundred: return "💯"
        case .threeHundredSixtyFive: return "👑"
        }
    }

    var title: String {
        switch self {
        case .three: return "On Fire!"
        case .seven: return "Week Warrior"
        case .fourteen: return "Two Week Titan"
        case .thirty: return "Month Master"
        case .sixty: return "Diamond Focus"
        case .ninety: return "Gold Standard"
        case .oneHundred: return "Century Club"
        case .threeHundredSixtyFive: return "Year Champion"
        }
    }
}

// MARK: - Streak Tracker Service

/// Tracks daily task completion streaks and productivity history.
///
/// Records are stored per-day in UserDefaults and persist across sessions.
/// The tracker calculates current/longest streaks, weekly/monthly activity,
/// and milestone achievements.
@MainActor
final class StreakTrackerService: ObservableObject {
    /// Minimum tasks per day to count as an "active" day for streak purposes
    static let minimumTasksForStreak = 1

    // MARK: - Published State

    @Published private(set) var streakInfo: StreakInfo
    @Published private(set) var recentMilestone: StreakMilestone?

    // MARK: - Private

    private var records: [String: DailyProductivityRecord] = [:]
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let storageKey = "streakTrackerRecords"

    // MARK: - Init

    init(
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.streakInfo = StreakInfo(
            currentStreak: 0,
            longestStreak: 0,
            totalTasksCompleted: 0,
            totalActiveDays: 0,
            isTodayActive: false,
            todayTasksCompleted: 0,
            tasksRemainingForStreak: Self.minimumTasksForStreak,
            weekActivity: [],
            monthActivity: []
        )
        loadRecords()
        recalculate()
    }

    // MARK: - Public API

    /// Record a task completion for today.
    func recordTaskCompletion() {
        var record = todayRecord()
        record.tasksCompleted += 1
        records[record.dateString] = record
        saveRecords()
        recalculate()
        logger.info("Task completed. Today: \(record.tasksCompleted)")
    }

    /// Record a task creation for today.
    func recordTaskCreation() {
        var record = todayRecord()
        record.tasksCreated += 1
        records[record.dateString] = record
        saveRecords()
    }

    /// Record a stack completion for today.
    func recordStackCompletion() {
        var record = todayRecord()
        record.stacksCompleted += 1
        records[record.dateString] = record
        saveRecords()
        recalculate()
    }

    /// Add focus time for today.
    func addFocusTime(_ seconds: TimeInterval) {
        var record = todayRecord()
        record.focusTimeSeconds += seconds
        records[record.dateString] = record
        saveRecords()
    }

    /// Get the current milestone if the streak just hit one.
    func checkMilestone() -> StreakMilestone? {
        StreakMilestone.allCases.first { $0.rawValue == streakInfo.currentStreak }
    }

    /// Dismiss the milestone notification.
    func dismissMilestone() {
        recentMilestone = nil
    }

    // MARK: - Calculation

    private func recalculate() {
        let today = dateString(for: Date())
        let todayRec = records[today] ?? emptyRecord(for: today)

        let currentStreak = calculateCurrentStreak()
        let longestStreak = calculateLongestStreak()
        let totalCompleted = records.values.reduce(0) { $0 + $1.tasksCompleted }
        let activeDays = records.values.filter(\.isActive).count
        let remaining = max(0, Self.minimumTasksForStreak - todayRec.tasksCompleted)

        streakInfo = StreakInfo(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalTasksCompleted: totalCompleted,
            totalActiveDays: activeDays,
            isTodayActive: todayRec.isActive,
            todayTasksCompleted: todayRec.tasksCompleted,
            tasksRemainingForStreak: remaining,
            weekActivity: calculateWeekActivity(),
            monthActivity: calculateMonthActivity()
        )

        // Check for milestone
        if let milestone = StreakMilestone.allCases.first(where: { $0.rawValue == currentStreak }) {
            recentMilestone = milestone
        }
    }

    private func calculateCurrentStreak() -> Int {
        var streak = 0
        var date = Date()

        // Check if today is active
        let todayStr = dateString(for: date)
        let todayActive = records[todayStr]?.isActive ?? false

        if todayActive {
            streak = 1
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }

        // Walk backwards checking consecutive days
        while true {
            let dateStr = dateString(for: date)
            guard let record = records[dateStr], record.isActive else {
                break
            }
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else {
                break
            }
            date = prev
        }

        return streak
    }

    private func calculateLongestStreak() -> Int {
        guard !records.isEmpty else { return 0 }

        // Sort all dates
        let sortedDates = records.keys.sorted()
        var longestStreak = 0
        var currentStreak = 0

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = calendar.timeZone

        var previousDate: Date?

        for dateStr in sortedDates {
            guard let record = records[dateStr], record.isActive else {
                currentStreak = 0
                previousDate = nil
                continue
            }

            guard let date = dateFormatter.date(from: dateStr) else {
                continue
            }

            if let prev = previousDate,
               let dayDiff = calendar.dateComponents([.day], from: prev, to: date).day,
               dayDiff == 1 {
                currentStreak += 1
            } else {
                currentStreak = 1
            }

            longestStreak = max(longestStreak, currentStreak)
            previousDate = date
        }

        return longestStreak
    }

    private func calculateWeekActivity() -> [DayActivity] {
        var activities: [DayActivity] = []
        let today = Date()

        for offset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }
            let dateStr = dateString(for: date)
            let record = records[dateStr]

            activities.append(DayActivity(
                dateString: dateStr,
                date: date,
                tasksCompleted: record?.tasksCompleted ?? 0,
                isActive: record?.isActive ?? false
            ))
        }

        return activities
    }

    private func calculateMonthActivity() -> [DayActivity] {
        var activities: [DayActivity] = []
        let today = Date()

        for offset in (0..<30).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }
            let dateStr = dateString(for: date)
            let record = records[dateStr]

            activities.append(DayActivity(
                dateString: dateStr,
                date: date,
                tasksCompleted: record?.tasksCompleted ?? 0,
                isActive: record?.isActive ?? false
            ))
        }

        return activities
    }

    // MARK: - Helpers

    private func todayRecord() -> DailyProductivityRecord {
        let today = dateString(for: Date())
        return records[today] ?? emptyRecord(for: today)
    }

    private func emptyRecord(for dateString: String) -> DailyProductivityRecord {
        DailyProductivityRecord(
            dateString: dateString,
            tasksCompleted: 0,
            tasksCreated: 0,
            stacksCompleted: 0,
            focusTimeSeconds: 0
        )
    }

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: DailyProductivityRecord].self, from: data) else {
            records = [:]
            return
        }
        records = decoded
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
