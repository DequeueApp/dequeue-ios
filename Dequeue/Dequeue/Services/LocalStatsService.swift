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
import SwiftUI  // Required for EnvironmentKey and EnvironmentValues

private let logger = Logger(subsystem: "com.dequeue", category: "LocalStatsService")

// MARK: - Priority Constants

/// Priority level constants matching the API convention.
/// See `PriorityBreakdown` in StatsService.swift for mapping documentation.
private enum TaskPriority {
    static let none = 0
    static let low = 1
    static let medium = 2
    static let high = 3
}

// MARK: - Local Stats Service

/// Computes statistics from SwiftData models, providing offline-first stats.
///
/// This replaces the network-only StatsService for native apps, computing
/// all stats locally from the event-sourced SwiftData store.
@MainActor
final class LocalStatsService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Computes aggregate statistics from the local SwiftData store.
    ///
    /// Runs synchronously on the main thread. For typical task counts (hundreds to
    /// low thousands), this completes in sub-millisecond time. If performance becomes
    /// a concern with very large datasets, consider offloading to a background context.
    /// - Returns: Complete statistics matching the `StatsResponse` format
    func getStats() throws -> StatsResponse {
        let allTasks = try fetchAllTasks()
        let allStacks = try fetchAllStacks()
        let allArcs = try fetchAllArcs()

        let taskStats = computeTaskStats(from: allTasks)
        let priorityBreakdown = computePriorityBreakdown(from: allTasks)
        let stackStats = computeStackStats(stacks: allStacks, arcs: allArcs)
        let completionStreak = computeCompletionStreak(from: allTasks)

        return StatsResponse(
            tasks: taskStats,
            priority: priorityBreakdown,
            stacks: stackStats,
            completionStreak: completionStreak
        )
    }

    // MARK: - Task Stats

    private func computeTaskStats(from allTasks: [QueueTask]) -> TaskStats {
        let total = allTasks.count
        let completed = allTasks.filter { $0.status == .completed }.count
        let active = allTasks.filter { $0.status == .pending || $0.status == .blocked }.count
        let overdue = allTasks.filter { task in
            guard let dueTime = task.dueTime else { return false }
            return dueTime < Date() && task.status != .completed && task.status != .closed
        }.count

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        // Uses Calendar.current which respects the user's locale for first day of week
        // (Sunday in US, Monday in most of Europe). This is intentional for a local-only
        // display — "this week" should match the user's expectations on their device.
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? startOfToday

        let createdToday = allTasks.filter { $0.createdAt >= startOfToday }.count
        // Only count tasks with explicit completedAt; tasks completed before that field
        // was tracked are excluded from time-based counts to avoid skew from updatedAt
        // being bumped by subsequent sync/sort/tag updates.
        let completedToday = allTasks.filter { task in
            guard task.status == .completed, let completedAt = task.completedAt else { return false }
            return completedAt >= startOfToday
        }.count

        let createdThisWeek = allTasks.filter { $0.createdAt >= startOfWeek }.count
        let completedThisWeek = allTasks.filter { task in
            guard task.status == .completed, let completedAt = task.completedAt else { return false }
            return completedAt >= startOfWeek
        }.count

        return TaskStats(
            total: total,
            active: active,
            completed: completed,
            overdue: overdue,
            completedToday: completedToday,
            completedThisWeek: completedThisWeek,
            createdToday: createdToday,
            createdThisWeek: createdThisWeek
        )
    }

    // MARK: - Priority Breakdown

    private func computePriorityBreakdown(from allTasks: [QueueTask]) -> PriorityBreakdown {
        let activeTasks = allTasks.filter { $0.status == .pending || $0.status == .blocked }

        var high = 0
        var medium = 0
        var low = 0
        var none = 0

        for task in activeTasks {
            switch task.priority {
            case TaskPriority.high: high += 1
            case TaskPriority.medium: medium += 1
            case TaskPriority.low: low += 1
            default: none += 1
            }
        }

        return PriorityBreakdown(none: none, low: low, medium: medium, high: high)
    }

    // MARK: - Stack Stats

    private func computeStackStats(stacks: [Stack], arcs: [Arc]) -> StackStats {
        let total = stacks.count
        let active = stacks.filter { $0.statusRawValue == StackStatus.active.rawValue }.count
        let totalArcs = arcs.count

        return StackStats(total: total, active: active, totalArcs: totalArcs)
    }

    // MARK: - Completion Streak

    private func computeCompletionStreak(from allTasks: [QueueTask]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Only use tasks with explicit completedAt for streak calculation
        let completedTasks = allTasks.filter { $0.status == .completed && $0.completedAt != nil }

        // Build a set of date strings that had at least one completion.
        // POSIX locale ensures consistent date strings regardless of device
        // calendar settings (Buddhist, Islamic, Hebrew, etc.).
        var activeDateStrings = Set<String>()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for task in completedTasks {
            guard let completedAt = task.completedAt else { continue }
            // Only consider completions within last 90 days
            if completedAt >= (calendar.date(byAdding: .day, value: -90, to: today) ?? today) {
                activeDateStrings.insert(dateFormatter.string(from: completedAt))
            }
        }

        // Count consecutive days backward from today (or yesterday if today has no completions yet)
        var streak = 0
        var checkDate = today

        let todayString = dateFormatter.string(from: today)
        let todayHasCompletions = activeDateStrings.contains(todayString)

        if todayHasCompletions {
            streak = 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        } else {
            // Start from yesterday
            checkDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }

        // Count consecutive days backward
        for _ in 0..<90 {
            let dateString = dateFormatter.string(from: checkDate)
            if activeDateStrings.contains(dateString) {
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
        let tasks = try modelContext.fetch(descriptor)
        // Exclude recurrence templates — they are synthetic placeholders used by
        // RecurringTaskService and not real user tasks.
        return tasks.filter { !$0.isRecurrenceTemplate }
    }

    private func fetchAllStacks() throws -> [Stack] {
        let descriptor = FetchDescriptor<Stack>(
            predicate: #Predicate<Stack> { !$0.isDeleted && !$0.isDraft }
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchAllArcs() throws -> [Arc] {
        let descriptor = FetchDescriptor<Arc>(
            predicate: #Predicate<Arc> { !$0.isDeleted }
        )
        return try modelContext.fetch(descriptor)
    }
}

// MARK: - Environment Key

private struct LocalStatsServiceKey: EnvironmentKey {
    @MainActor static let defaultValue: LocalStatsService? = nil
}

extension EnvironmentValues {
    var localStatsService: LocalStatsService? {
        get { self[LocalStatsServiceKey.self] }
        set { self[LocalStatsServiceKey.self] = newValue }
    }
}
