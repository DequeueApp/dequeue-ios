//
//  ReminderService.swift
//  Dequeue
//
//  Business logic for Reminder operations
//

import Foundation
import SwiftData

@MainActor
final class ReminderService {
    private let modelContext: ModelContext
    private let eventService: EventService
    private let syncManager: SyncManager?

    init(modelContext: ModelContext, userId: String, deviceId: String, syncManager: SyncManager? = nil) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        self.syncManager = syncManager
    }

    // MARK: - Create

    func createReminder(for task: QueueTask, at remindAt: Date) throws -> Reminder {
        let reminder = Reminder(
            parentId: task.id,
            parentType: .task,
            remindAt: remindAt
        )

        modelContext.insert(reminder)
        task.reminders.append(reminder)
        try eventService.recordReminderCreated(reminder)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return reminder
    }

    func createReminder(for stack: Stack, at remindAt: Date) throws -> Reminder {
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: remindAt
        )

        modelContext.insert(reminder)
        stack.reminders.append(reminder)
        try eventService.recordReminderCreated(reminder)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return reminder
    }

    func createReminder(for arc: Arc, at remindAt: Date) throws -> Reminder {
        let reminder = Reminder(
            parentId: arc.id,
            parentType: .arc,
            remindAt: remindAt
        )

        modelContext.insert(reminder)
        arc.reminders.append(reminder)
        try eventService.recordReminderCreated(reminder)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return reminder
    }

    // MARK: - Update

    func updateReminder(_ reminder: Reminder, remindAt: Date) throws {
        reminder.remindAt = remindAt
        reminder.updatedAt = Date()
        reminder.syncState = .pending

        try eventService.recordReminderUpdated(reminder)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Snooze

    func snoozeReminder(_ reminder: Reminder, until: Date) throws {
        reminder.snoozedFrom = reminder.remindAt
        reminder.remindAt = until
        reminder.status = .snoozed
        reminder.updatedAt = Date()
        reminder.syncState = .pending

        try eventService.recordReminderSnoozed(reminder)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Dismiss

    /// Dismisses an overdue reminder, marking it as handled without deleting it.
    /// This removes it from the active/overdue lists and decreases the badge count.
    func dismissReminder(_ reminder: Reminder) throws {
        reminder.status = .fired
        reminder.updatedAt = Date()
        reminder.syncState = .pending

        try eventService.recordReminderUpdated(reminder)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Delete

    func deleteReminder(_ reminder: Reminder) throws {
        reminder.isDeleted = true
        reminder.updatedAt = Date()
        reminder.syncState = .pending

        try eventService.recordReminderDeleted(reminder)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Queries

    func getUpcomingReminders() throws -> [Reminder] {
        let activeReminders = try fetchActiveReminders()
        let now = Date()
        return activeReminders
            .filter { $0.remindAt > now }
            .sorted { $0.remindAt < $1.remindAt }
    }

    func getOverdueReminders() throws -> [Reminder] {
        let activeReminders = try fetchActiveReminders()
        let now = Date()
        return activeReminders
            .filter { $0.remindAt <= now }
            .sorted { $0.remindAt < $1.remindAt }
    }

    // MARK: - Fetch by Parent

    func getReminders(for task: QueueTask) throws -> [Reminder] {
        let taskId = task.id
        let predicate = #Predicate<Reminder> { reminder in
            reminder.parentId == taskId &&
            reminder.isDeleted == false
        }
        let descriptor = FetchDescriptor<Reminder>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.remindAt)]
        )
        return try modelContext.fetch(descriptor)
            .filter { $0.parentType == .task }
    }

    func getReminders(for stack: Stack) throws -> [Reminder] {
        let stackId = stack.id
        let predicate = #Predicate<Reminder> { reminder in
            reminder.parentId == stackId &&
            reminder.isDeleted == false
        }
        let descriptor = FetchDescriptor<Reminder>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.remindAt)]
        )
        return try modelContext.fetch(descriptor)
            .filter { $0.parentType == .stack }
    }

    func getReminders(for arc: Arc) throws -> [Reminder] {
        let arcId = arc.id
        let predicate = #Predicate<Reminder> { reminder in
            reminder.parentId == arcId &&
            reminder.isDeleted == false
        }
        let descriptor = FetchDescriptor<Reminder>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.remindAt)]
        )
        return try modelContext.fetch(descriptor)
            .filter { $0.parentType == .arc }
    }

    // MARK: - Private Helpers

    private func fetchActiveReminders() throws -> [Reminder] {
        let predicate = #Predicate<Reminder> { reminder in
            reminder.isDeleted == false
        }
        let descriptor = FetchDescriptor<Reminder>(predicate: predicate)
        return try modelContext.fetch(descriptor)
            .filter { $0.status == .active }
    }
}
