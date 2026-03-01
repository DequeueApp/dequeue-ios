//
//  LocalStatsService.swift
//  Dequeue
//
//  Computes task statistics from local SwiftData store.
//  Works offline and doesn't depend on the API stats endpoint.
//

import Foundation
import os.log
import SwiftData

// nonisolated(unsafe) because this is accessed from both @MainActor and nonisolated
// static contexts in LocalStatsService. Logger is thread-safe.
nonisolated(unsafe) private let logger = Logger(subsystem: "com.dequeue", category: "LocalStatsService")

// MARK: - Local Stats Service

/// Computes statistics from SwiftData models, providing offline-first stats.
///
/// Provides two usage patterns:
/// 1. **Static `compute()`** — Pure function for `@Query`-driven reactive views.
///    The view owns the data via `@Query` and passes pre-fetched collections.
/// 2. **Instance `getStats()`** — Convenience for callers with a `ModelContext`.
///    Fetches data from SwiftData and delegates to `compute()`.
@MainActor
final class LocalStatsService {
    private let modelContext: ModelContext

    /// Maximum number of days to look back for completion streak calculation.
    nonisolated static let streakWindowDays = 90

    /// Creates a date formatter for streak calculation. Uses POSIX locale to ensure
    /// consistent date strings regardless of device calendar settings.
    /// Created per-call rather than shared to avoid DateFormatter thread-safety issues
    /// (DateFormatter is not thread-safe and compute() is nonisolated).
    nonisolated private static func makeStreakDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Computes aggregate statistics from the local SwiftData store.
    ///
    /// Fetches all data from ModelContext and delegates to the static `compute()` method.
    /// - Returns: Complete statistics matching the `StatsResponse` format
    func getStats() throws -> StatsResponse {
        let allTasks = try fetchAllTasks()
        let allStacks = try fetchAllStacks()
        let allArcs = try fetchAllArcs()

        return Self.compute(from: allTasks, stacks: allStacks, arcs: allArcs)
    }

    // MARK: - Static Computation (Pure Function)

    // swiftlint:disable cyclomatic_complexity
    // Complexity is 16 (limit 15) due to intentional single-pass aggregation
    // that folds task stats, priority, and streak into one O(n) loop.

    /// Computes statistics from pre-fetched collections.
    ///
    /// Pure function with no side effects — suitable for calling from `@Query`-driven
    /// SwiftUI views where the view framework manages data observation and reactivity.
    /// Uses true single-pass aggregation over tasks for minimal computation time.
    ///
    /// - Parameters:
    ///   - tasks: Non-deleted tasks (recurrence templates will be filtered out)
    ///   - stacks: Non-deleted, non-draft stacks
    ///   - arcs: Non-deleted arcs
    ///   - now: Reference time for relative calculations (defaults to current time)
    /// - Returns: Complete statistics matching the `StatsResponse` format
    nonisolated static func compute(
        from tasks: [QueueTask],
        stacks: [Stack],
        arcs: [Arc],
        now: Date = Date()
    ) -> StatsResponse {
        // Exclude recurrence templates — they are synthetic placeholders used by
        // RecurringTaskService and not real user tasks.
        let filteredTasks = tasks.filter { !$0.isRecurrenceTemplate }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        // Uses Calendar.current which respects the user's locale for first day of week
        // (Sunday in US, Monday in most of Europe). This is intentional for a local-only
        // display — "this week" should match the user's expectations on their device.
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) ?? startOfToday

        // True single-pass aggregation — task stats, priority breakdown, and streak
        // data are all computed in one O(n) loop over the task list.
        var total = 0, completed = 0, active = 0, overdue = 0
        var createdToday = 0, createdThisWeek = 0, completedToday = 0, completedThisWeek = 0
        var highPriority = 0, mediumPriority = 0, lowPriority = 0, nonePriority = 0

        // Streak: collect completion date strings in the window
        let today = startOfToday
        let windowStart = calendar.date(
            byAdding: .day, value: -streakWindowDays, to: today
        ) ?? today
        let formatter = makeStreakDateFormatter()
        var completionDateStrings = Set<String>()

        for task in filteredTasks {
            total += 1

            switch task.status {
            case .completed:
                completed += 1
                // Only count tasks with explicit completedAt; tasks completed before that field
                // was tracked are excluded from time-based counts to avoid skew from updatedAt
                // being bumped by subsequent sync/sort/tag updates.
                if let completedAt = task.completedAt {
                    if completedAt >= startOfToday { completedToday += 1 }
                    if completedAt >= startOfWeek { completedThisWeek += 1 }
                    // Collect for streak calculation
                    if completedAt >= windowStart {
                        completionDateStrings.insert(formatter.string(from: completedAt))
                    }
                }
            case .pending, .blocked:
                active += 1
                if let dueTime = task.dueTime, dueTime < now {
                    overdue += 1
                }
                // Priority breakdown (active tasks only)
                switch TaskPriorityLevel(rawValue: task.priority ?? TaskPriorityLevel.none.rawValue) {
                case .high: highPriority += 1
                case .medium: mediumPriority += 1
                case .low: lowPriority += 1
                case .some(.none), nil:
                    nonePriority += 1
                    // Log unexpected raw values for debugging (nil from unknown rawValue)
                    if let priority = task.priority, TaskPriorityLevel(rawValue: priority) == nil {
                        logger.warning("Unknown priority raw value: \(priority, privacy: .public)")
                    }
                }
            default:
                break
            }

            if task.createdAt >= startOfToday { createdToday += 1 }
            if task.createdAt >= startOfWeek { createdThisWeek += 1 }
        }

        let taskStats = TaskStats(
            total: total,
            active: active,
            completed: completed,
            overdue: overdue,
            completedToday: completedToday,
            completedThisWeek: completedThisWeek,
            createdToday: createdToday,
            createdThisWeek: createdThisWeek
        )

        let priorityBreakdown = PriorityBreakdown(
            none: nonePriority,
            low: lowPriority,
            medium: mediumPriority,
            high: highPriority
        )

        // Stack stats
        // Uses raw value comparison because Stack stores status as a String in SwiftData
        // (@Attribute), not a typed enum. The computed `status` property parses the raw
        // value but using it in a filter closure triggers SwiftData Predicate limitations.
        let stackStats = StackStats(
            total: stacks.count,
            active: stacks.filter { $0.statusRawValue == StackStatus.active.rawValue }.count,
            totalArcs: arcs.count
        )

        // Completion streak
        let streak = computeCompletionStreak(
            from: completionDateStrings,
            today: today,
            calendar: calendar
        )

        return StatsResponse(
            tasks: taskStats,
            priority: priorityBreakdown,
            stacks: stackStats,
            completionStreak: streak
        )
    }
    // swiftlint:enable cyclomatic_complexity

    // MARK: - Streak Calculation

    /// Computes the completion streak from a set of date strings with completions.
    ///
    /// Counts consecutive days backward from today (or yesterday if today has no
    /// completions yet). Maximum streak is `streakWindowDays` (90) when today
    /// has completions, or `streakWindowDays - 1` (89) when it doesn't.
    nonisolated private static func computeCompletionStreak(
        from completionDateStrings: Set<String>,
        today: Date,
        calendar: Calendar
    ) -> Int {
        let formatter = makeStreakDateFormatter()
        var streak = 0
        var checkDate = today

        let todayString = formatter.string(from: today)
        let todayHasCompletions = completionDateStrings.contains(todayString)

        if todayHasCompletions {
            streak = 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        } else {
            // Start from yesterday
            checkDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }

        // Count consecutive days backward. Loop limit ensures total streak ≤ streakWindowDays.
        // Cap at (streakWindowDays - 1) remaining to avoid examining dates beyond the window
        // when today has no completions (otherwise the loop could check streakWindowDays days
        // starting from yesterday = streakWindowDays + 1 days from today).
        let remainingDays = streakWindowDays - 1
        for _ in 0..<remainingDays {
            let dateString = formatter.string(from: checkDate)
            if completionDateStrings.contains(dateString) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        return streak
    }

    // MARK: - SwiftData Queries

    private func fetchAllTasks() throws -> [QueueTask] {
        // Fetch non-deleted tasks and filter in-memory to avoid Predicate macro
        // limitations with compound expressions on enum/Bool fields.
        let descriptor = FetchDescriptor<QueueTask>(
            predicate: #Predicate<QueueTask> { !$0.isDeleted }
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchAllStacks() throws -> [Stack] {
        let descriptor = FetchDescriptor<Stack>(
            predicate: #Predicate<Stack> { !$0.isDeleted && !$0.isDraft }
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchAllArcs() throws -> [Arc] {
        // Arc does not have an isDraft property (only Stack does), so
        // filtering by isDeleted is sufficient.
        let descriptor = FetchDescriptor<Arc>(
            predicate: #Predicate<Arc> { !$0.isDeleted }
        )
        return try modelContext.fetch(descriptor)
    }
}
