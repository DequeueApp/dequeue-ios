//
//  RecurringTaskService.swift
//  Dequeue
//
//  Manages recurring task logic: calculates next dates, creates next occurrences
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "RecurringTaskService")

@MainActor
final class RecurringTaskService {
    private let modelContext: ModelContext
    private let eventService: EventService
    private let syncManager: SyncManager?

    init(modelContext: ModelContext, userId: String, deviceId: String, syncManager: SyncManager? = nil) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        self.syncManager = syncManager
    }

    // MARK: - Next Occurrence

    /// Creates the next occurrence of a recurring task after it's completed.
    /// Returns the new task instance, or nil if recurrence has ended.
    @discardableResult
    func createNextOccurrence(for completedTask: QueueTask) async throws -> QueueTask? {
        guard let rule = completedTask.recurrenceRule else {
            logger.info("Task \(completedTask.id) has no recurrence rule, skipping")
            return nil
        }

        // Check if recurrence has ended
        let newOccurrenceCount = completedTask.completedOccurrences + 1

        switch rule.end {
        case .never:
            break
        case .afterOccurrences(let maxCount):
            if newOccurrenceCount >= maxCount {
                logger.info("Recurrence ended: reached max \(maxCount) occurrences")
                return nil
            }
        case .onDate(let endDate):
            if Date() >= endDate {
                logger.info("Recurrence ended: past end date")
                return nil
            }
        }

        // Calculate next due date
        let referenceDate = completedTask.dueTime ?? completedTask.createdAt
        guard let nextDueDate = calculateNextDate(from: referenceDate, rule: rule) else {
            logger.warning("Could not calculate next date for recurrence")
            return nil
        }

        // Check end date against next occurrence
        if case .onDate(let endDate) = rule.end, nextDueDate > endDate {
            logger.info("Next occurrence would be past end date, stopping recurrence")
            return nil
        }

        // Calculate next start date if original had one
        var nextStartDate: Date?
        if let originalStart = completedTask.startTime, let originalDue = completedTask.dueTime {
            let leadTime = originalDue.timeIntervalSince(originalStart)
            nextStartDate = nextDueDate.addingTimeInterval(-leadTime)
        }

        guard let stack = completedTask.stack else {
            logger.warning("Completed recurring task has no stack, cannot create next occurrence")
            return nil
        }

        // Create next task instance
        let nextTask = QueueTask(
            title: completedTask.title,
            taskDescription: completedTask.taskDescription,
            startTime: nextStartDate,
            dueTime: nextDueDate,
            tags: completedTask.tags,
            status: .pending,
            priority: completedTask.priority,
            sortOrder: stack.pendingTasks.count,
            stack: stack,
            parentTaskId: completedTask.parentTaskId,
            recurrenceRuleData: completedTask.recurrenceRuleData,
            recurrenceParentId: completedTask.recurrenceParentId ?? completedTask.id,
            isRecurrenceTemplate: false,
            completedOccurrences: newOccurrenceCount
        )

        modelContext.insert(nextTask)
        stack.tasks.append(nextTask)

        // Update the completed task's occurrence count
        completedTask.completedOccurrences = newOccurrenceCount

        try await eventService.recordTaskCreated(nextTask)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        logger.info("Created next occurrence: \(nextTask.id) due \(nextDueDate)")
        return nextTask
    }

    // MARK: - Date Calculation

    /// Calculates the next occurrence date based on the recurrence rule.
    /// Uses the reference date (typically the previous due date) to compute the next one.
    func calculateNextDate(from referenceDate: Date, rule: RecurrenceRule) -> Date? {
        let calendar = Calendar.current

        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: rule.interval, to: referenceDate)

        case .weekly:
            return calculateNextWeeklyDate(from: referenceDate, rule: rule, calendar: calendar)

        case .monthly:
            return calculateNextMonthlyDate(from: referenceDate, rule: rule, calendar: calendar)

        case .yearly:
            return calendar.date(byAdding: .year, value: rule.interval, to: referenceDate)
        }
    }

    // MARK: - Weekly Calculation

    private func calculateNextWeeklyDate(
        from referenceDate: Date,
        rule: RecurrenceRule,
        calendar: Calendar
    ) -> Date? {
        // If no specific days selected, just add N weeks
        if rule.daysOfWeek.isEmpty {
            return calendar.date(byAdding: .weekOfYear, value: rule.interval, to: referenceDate)
        }

        let currentWeekday = calendar.component(.weekday, from: referenceDate)
        let sortedDays = rule.daysOfWeek.sorted { $0.rawValue < $1.rawValue }

        // Find next day in the same week (after current day)
        if let nextDay = sortedDays.first(where: { $0.rawValue > currentWeekday }) {
            let daysToAdd = nextDay.rawValue - currentWeekday
            return calendar.date(byAdding: .day, value: daysToAdd, to: referenceDate)
        }

        // No more days this week — go to first day of next interval
        guard let firstDay = sortedDays.first else { return nil }
        let daysUntilFirstDay = (7 - currentWeekday + firstDay.rawValue) + (7 * (rule.interval - 1))
        return calendar.date(byAdding: .day, value: daysUntilFirstDay, to: referenceDate)
    }

    // MARK: - Monthly Calculation

    private func calculateNextMonthlyDate(
        from referenceDate: Date,
        rule: RecurrenceRule,
        calendar: Calendar
    ) -> Date? {
        guard let nextMonth = calendar.date(byAdding: .month, value: rule.interval, to: referenceDate) else {
            return nil
        }

        guard let targetDay = rule.dayOfMonth else {
            return nextMonth
        }

        // Clamp to valid day for the target month
        var components = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: nextMonth)
        let range = calendar.range(of: .day, in: .month, for: nextMonth)
        let maxDay = range?.count ?? 28
        components.day = min(targetDay, maxDay)

        return calendar.date(from: components)
    }

    // MARK: - Query Helpers

    /// Fetches all recurring tasks (tasks with a recurrence rule) in a given stack
    func recurringTasks(in stack: Stack) -> [QueueTask] {
        stack.tasks.filter { $0.recurrenceRuleData != nil && !$0.isDeleted }
    }

    /// Fetches all tasks in a recurrence series (sharing the same parent ID)
    func seriesTasks(parentId: String) -> [QueueTask] {
        let descriptor = FetchDescriptor<QueueTask>(
            predicate: #Predicate<QueueTask> { task in
                (task.recurrenceParentId == parentId || task.id == parentId) && !task.isDeleted
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetches the latest pending occurrence of a recurring task series
    func latestPendingOccurrence(parentId: String) -> QueueTask? {
        let descriptor = FetchDescriptor<QueueTask>(
            predicate: #Predicate<QueueTask> { task in
                (task.recurrenceParentId == parentId || task.id == parentId)
                    && task.status == .pending
                    && !task.isDeleted
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Modify Recurrence

    /// Updates the recurrence rule for a task (and optionally future occurrences)
    func updateRecurrence(for task: QueueTask, newRule: RecurrenceRule?) async throws {
        task.recurrenceRuleData = newRule?.toData()
        task.updatedAt = Date()
        task.syncState = .pending

        try await eventService.recordTaskUpdated(task, changes: [
            "recurrenceUpdated": newRule != nil ? "true" : "removed"
        ])
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    /// Stops recurrence for a task series (removes rule from latest pending occurrence)
    func stopRecurrence(for task: QueueTask) async throws {
        let parentId = task.recurrenceParentId ?? task.id
        if let latestPending = latestPendingOccurrence(parentId: parentId) {
            latestPending.recurrenceRuleData = nil
            latestPending.updatedAt = Date()
            latestPending.syncState = .pending

            try await eventService.recordTaskUpdated(latestPending, changes: [
                "recurrenceStopped": "true"
            ])
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        logger.info("Stopped recurrence for series \(parentId)")
    }
}
