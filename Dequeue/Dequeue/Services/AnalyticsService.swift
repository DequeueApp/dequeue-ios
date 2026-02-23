//
//  AnalyticsService.swift
//  Dequeue
//
//  Computes productivity analytics — completion rates, time-to-complete,
//  productivity by day/hour, tag/stack breakdown.
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "Analytics")

// MARK: - Analytics Models

/// Summary of productivity metrics for a time period
struct ProductivitySummary: Sendable {
    let totalTasks: Int
    let completedTasks: Int
    let pendingTasks: Int
    let overdueTasks: Int
    let blockedTasks: Int

    var completionRate: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    var completionPercentage: Int {
        Int(completionRate * 100)
    }
}

/// Completion data for a single day (for charts)
struct DailyCompletionData: Identifiable, Sendable {
    let date: Date
    let completed: Int
    let created: Int

    var id: Date { date }

    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

/// Breakdown by tag
struct TagAnalytics: Identifiable, Sendable {
    let tag: String
    let totalTasks: Int
    let completedTasks: Int

    var id: String { tag }

    var completionRate: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }
}

/// Breakdown by stack
struct StackAnalytics: Identifiable, Sendable {
    let stackId: String
    let stackTitle: String
    let totalTasks: Int
    let completedTasks: Int
    let avgCompletionDays: Double?

    var id: String { stackId }

    var completionRate: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }
}

/// Hourly productivity distribution
struct HourlyProductivity: Identifiable, Sendable {
    let hour: Int
    let completions: Int

    var id: Int { hour }

    var label: String {
        let displayHour = hour.isMultiple(of: 12) ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(displayHour)\(ampm)"
    }
}

// MARK: - Analytics Service

@MainActor
final class AnalyticsService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Summary

    /// Computes overall productivity summary
    func getProductivitySummary() -> ProductivitySummary {
        let allTasks = fetchAllTasks()
        let now = Date()

        let completed = allTasks.filter { $0.status == .completed }
        let pending = allTasks.filter { $0.status == .pending }
        let overdue = allTasks.filter { task in
            task.status == .pending && (task.dueTime ?? .distantFuture) < now
        }
        let blocked = allTasks.filter { $0.status == .blocked }

        return ProductivitySummary(
            totalTasks: allTasks.count,
            completedTasks: completed.count,
            pendingTasks: pending.count,
            overdueTasks: overdue.count,
            blockedTasks: blocked.count
        )
    }

    // MARK: - Daily Completions

    /// Gets completion counts per day for the last N days
    func getDailyCompletions(days: Int = 14) -> [DailyCompletionData] {
        let calendar = Calendar.current
        let allTasks = fetchAllTasks()

        return (0..<days).reversed().compactMap { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) else { return nil }
            let startOfDay = calendar.startOfDay(for: date)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }

            let completed = allTasks.filter { task in
                task.status == .completed &&
                task.updatedAt >= startOfDay &&
                task.updatedAt < endOfDay
            }.count

            let created = allTasks.filter { task in
                task.createdAt >= startOfDay &&
                task.createdAt < endOfDay
            }.count

            return DailyCompletionData(date: startOfDay, completed: completed, created: created)
        }
    }

    // MARK: - Tag Analytics

    /// Gets completion metrics broken down by tag
    func getTagAnalytics() -> [TagAnalytics] {
        let allTasks = fetchAllTasks()
        var tagMap: [String: (total: Int, completed: Int)] = [:]

        for task in allTasks {
            for tag in task.tags {
                var entry = tagMap[tag, default: (total: 0, completed: 0)]
                entry.total += 1
                if task.status == .completed {
                    entry.completed += 1
                }
                tagMap[tag] = entry
            }
        }

        return tagMap.map { tag, data in
            TagAnalytics(tag: tag, totalTasks: data.total, completedTasks: data.completed)
        }
        .sorted { $0.totalTasks > $1.totalTasks }
    }

    // MARK: - Stack Analytics

    /// Accumulator for stack metric computation
    private struct StackAccumulator {
        var title: String
        var total: Int = 0
        var completed: Int = 0
        var completionDays: [Double] = []
    }

    /// Gets completion metrics broken down by stack
    func getStackAnalytics() -> [StackAnalytics] {
        let allTasks = fetchAllTasks()
        var stackMap: [String: StackAccumulator] = [:]

        for task in allTasks {
            guard let stack = task.stack else { continue }
            var entry = stackMap[stack.id, default: StackAccumulator(title: stack.title)]
            entry.total += 1
            if task.status == .completed {
                entry.completed += 1
                let days = task.updatedAt.timeIntervalSince(task.createdAt) / 86_400
                entry.completionDays.append(max(0, days))
            }
            stackMap[stack.id] = entry
        }

        return stackMap.map { stackId, data in
            let avgDays = data.completionDays.isEmpty ? nil :
                data.completionDays.reduce(0, +) / Double(data.completionDays.count)

            return StackAnalytics(
                stackId: stackId,
                stackTitle: data.title,
                totalTasks: data.total,
                completedTasks: data.completed,
                avgCompletionDays: avgDays
            )
        }
        .sorted { $0.totalTasks > $1.totalTasks }
    }

    // MARK: - Hourly Productivity

    /// Gets completion counts by hour of day (last 30 days)
    func getHourlyProductivity() -> [HourlyProductivity] {
        let calendar = Calendar.current
        let allTasks = fetchAllTasks()
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) else {
            return (0..<24).map { HourlyProductivity(hour: $0, completions: 0) }
        }

        var hourCounts = [Int](repeating: 0, count: 24)

        for task in allTasks where task.status == .completed && task.updatedAt >= thirtyDaysAgo {
            let hour = calendar.component(.hour, from: task.updatedAt)
            hourCounts[hour] += 1
        }

        return (0..<24).map { hour in
            HourlyProductivity(hour: hour, completions: hourCounts[hour])
        }
    }

    // MARK: - Average Time to Complete

    /// Computes average days from creation to completion
    func averageTimeToComplete() -> Double? {
        let allTasks = fetchAllTasks()
        let completed = allTasks.filter { $0.status == .completed }

        guard !completed.isEmpty else { return nil }

        let totalDays = completed.reduce(0.0) { sum, task in
            sum + max(0, task.updatedAt.timeIntervalSince(task.createdAt) / 86_400)
        }

        return totalDays / Double(completed.count)
    }

    // MARK: - Streak

    /// Computes the current streak of consecutive days with at least 1 completion
    func getCurrentStreak() -> Int {
        let calendar = Calendar.current
        let allTasks = fetchAllTasks()
        let completed = allTasks.filter { $0.status == .completed }

        // Build set of dates with completions
        var completionDates: Set<String> = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for task in completed {
            completionDates.insert(formatter.string(from: task.updatedAt))
        }

        var streak = 0
        var date = Date()

        while true {
            let dateStr = formatter.string(from: date)
            if completionDates.contains(dateStr) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { break }
                date = prev
            } else if streak == 0 {
                // Check yesterday if today hasn't had completions yet
                guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { break }
                date = prev
                continue
            } else {
                break
            }

            // Safety: don't look back more than 365 days
            if streak > 365 { break }
        }

        return streak
    }

    // MARK: - Private

    private func fetchAllTasks() -> [QueueTask] {
        let predicate = #Predicate<QueueTask> { task in
            task.isDeleted == false
        }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch tasks for analytics: \(error)")
            return []
        }
    }
}
