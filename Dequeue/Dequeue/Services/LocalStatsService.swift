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
import SwiftUI

private let logger = Logger(subsystem: "com.dequeue", category: "LocalStatsService")

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
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? startOfToday

        let createdToday = allTasks.filter { $0.createdAt >= startOfToday }.count
        let completedToday = allTasks.filter { task in
            guard task.status == .completed else { return false }
            let completionDate = task.completedAt ?? task.updatedAt
            return completionDate >= startOfToday
        }.count

        let createdThisWeek = allTasks.filter { $0.createdAt >= startOfWeek }.count
        let completedThisWeek = allTasks.filter { task in
            guard task.status == .completed else { return false }
            let completionDate = task.completedAt ?? task.updatedAt
            return completionDate >= startOfWeek
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
            case 3: high += 1
            case 2: medium += 1
            case 1: low += 1
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

        let completedTasks = allTasks.filter { $0.status == .completed }

        // Build a set of date strings that had at least one completion
        var activeDateStrings = Set<String>()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for task in completedTasks {
            let completionDate = task.completedAt ?? task.updatedAt
            // Only consider completions within last 90 days
            if completionDate >= (calendar.date(byAdding: .day, value: -90, to: today) ?? today) {
                activeDateStrings.insert(dateFormatter.string(from: completionDate))
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
