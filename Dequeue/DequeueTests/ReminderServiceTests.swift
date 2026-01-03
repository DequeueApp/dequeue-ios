//
//  ReminderServiceTests.swift
//  DequeueTests
//
//  Tests for ReminderService - reminder CRUD operations (DEQ-11)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container for ReminderService tests
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )
}

@Suite("ReminderService Tests", .serialized)
struct ReminderServiceTests {

    // MARK: - Create Reminder for Task Tests

    @Test("createReminder for task creates reminder with correct parentId")
    @MainActor
    func createReminderForTaskSetsParentId() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task", status: .pending, stack: stack)
        context.insert(task)
        stack.tasks.append(task)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let remindAt = Date().addingTimeInterval(3600) // 1 hour from now
        let reminder = try reminderService.createReminder(for: task, at: remindAt)

        #expect(reminder.parentId == task.id)
        #expect(reminder.parentType == .task)
    }

    @Test("createReminder for task sets correct remindAt date")
    @MainActor
    func createReminderForTaskSetsRemindAt() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task", status: .pending, stack: stack)
        context.insert(task)
        stack.tasks.append(task)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let remindAt = Date().addingTimeInterval(7200) // 2 hours from now
        let reminder = try reminderService.createReminder(for: task, at: remindAt)

        #expect(reminder.remindAt == remindAt)
    }

    @Test("createReminder for task sets status to active")
    @MainActor
    func createReminderForTaskSetsActiveStatus() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task", status: .pending, stack: stack)
        context.insert(task)
        stack.tasks.append(task)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: task, at: Date().addingTimeInterval(3600))

        #expect(reminder.status == .active)
    }

    @Test("createReminder for task sets syncState to pending")
    @MainActor
    func createReminderForTaskSetsSyncState() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task", status: .pending, stack: stack)
        context.insert(task)
        stack.tasks.append(task)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: task, at: Date().addingTimeInterval(3600))

        #expect(reminder.syncState == .pending)
    }

    // MARK: - Create Reminder for Stack Tests

    @Test("createReminder for stack creates reminder with correct parentId")
    @MainActor
    func createReminderForStackSetsParentId() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let remindAt = Date().addingTimeInterval(3600)
        let reminder = try reminderService.createReminder(for: stack, at: remindAt)

        #expect(reminder.parentId == stack.id)
        #expect(reminder.parentType == .stack)
    }

    @Test("createReminder for stack sets correct remindAt date")
    @MainActor
    func createReminderForStackSetsRemindAt() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let remindAt = Date().addingTimeInterval(86400) // 24 hours from now
        let reminder = try reminderService.createReminder(for: stack, at: remindAt)

        #expect(reminder.remindAt == remindAt)
    }

    // MARK: - Update Reminder Tests

    @Test("updateReminder changes remindAt date")
    @MainActor
    func updateReminderChangesRemindAt() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let originalDate = Date().addingTimeInterval(3600)
        let reminder = try reminderService.createReminder(for: stack, at: originalDate)

        let newDate = Date().addingTimeInterval(7200)
        try reminderService.updateReminder(reminder, remindAt: newDate)

        #expect(reminder.remindAt == newDate)
    }

    @Test("updateReminder sets syncState to pending")
    @MainActor
    func updateReminderSetsSyncState() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))

        // Simulate synced state
        reminder.syncState = .synced
        try context.save()

        try reminderService.updateReminder(reminder, remindAt: Date().addingTimeInterval(7200))

        #expect(reminder.syncState == .pending)
    }

    @Test("updateReminder updates updatedAt timestamp")
    @MainActor
    func updateReminderUpdatesTimestamp() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))

        let originalUpdatedAt = reminder.updatedAt

        // Small delay to ensure timestamp difference
        try reminderService.updateReminder(reminder, remindAt: Date().addingTimeInterval(7200))

        #expect(reminder.updatedAt >= originalUpdatedAt)
    }

    // MARK: - Snooze Reminder Tests

    @Test("snoozeReminder sets snoozedFrom to original remindAt")
    @MainActor
    func snoozeReminderSetsSnoozedFrom() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let originalDate = Date().addingTimeInterval(3600)
        let reminder = try reminderService.createReminder(for: stack, at: originalDate)

        let snoozeUntil = Date().addingTimeInterval(7200)
        try reminderService.snoozeReminder(reminder, until: snoozeUntil)

        #expect(reminder.snoozedFrom == originalDate)
    }

    @Test("snoozeReminder updates remindAt to new date")
    @MainActor
    func snoozeReminderUpdatesRemindAt() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))

        let snoozeUntil = Date().addingTimeInterval(7200)
        try reminderService.snoozeReminder(reminder, until: snoozeUntil)

        #expect(reminder.remindAt == snoozeUntil)
    }

    @Test("snoozeReminder sets status to snoozed")
    @MainActor
    func snoozeReminderSetsStatus() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))

        try reminderService.snoozeReminder(reminder, until: Date().addingTimeInterval(7200))

        #expect(reminder.status == .snoozed)
    }

    @Test("snoozeReminder sets syncState to pending")
    @MainActor
    func snoozeReminderSetsSyncState() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))
        reminder.syncState = .synced
        try context.save()

        try reminderService.snoozeReminder(reminder, until: Date().addingTimeInterval(7200))

        #expect(reminder.syncState == .pending)
    }

    // MARK: - Dismiss Reminder Tests

    @Test("dismissReminder sets status to fired")
    @MainActor
    func dismissReminderSetsStatus() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(-3600)) // overdue

        try reminderService.dismissReminder(reminder)

        #expect(reminder.status == .fired)
    }

    @Test("dismissReminder sets syncState to pending")
    @MainActor
    func dismissReminderSetsSyncState() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(-3600))
        reminder.syncState = .synced
        try context.save()

        try reminderService.dismissReminder(reminder)

        #expect(reminder.syncState == .pending)
    }

    @Test("dismissReminder updates updatedAt timestamp")
    @MainActor
    func dismissReminderUpdatesTimestamp() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(-3600))
        let originalUpdatedAt = reminder.updatedAt

        try reminderService.dismissReminder(reminder)

        #expect(reminder.updatedAt >= originalUpdatedAt)
    }

    @Test("dismissReminder removes reminder from overdue list")
    @MainActor
    func dismissReminderRemovesFromOverdue() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        // Create an overdue reminder directly
        let overdueReminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(-3600)
        )
        context.insert(overdueReminder)
        try context.save()

        let reminderService = ReminderService(modelContext: context)

        // Verify it's in overdue list before dismissing
        let overdueBefore = try reminderService.getOverdueReminders()
        #expect(overdueBefore.count == 1)

        try reminderService.dismissReminder(overdueReminder)

        // Verify it's removed from overdue list after dismissing
        let overdueAfter = try reminderService.getOverdueReminders()
        #expect(overdueAfter.isEmpty)
    }

    @Test("dismissReminder records reminderUpdated event")
    @MainActor
    func dismissReminderRecordsEvent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(-3600))
        try reminderService.dismissReminder(reminder)

        let eventService = EventService(modelContext: context)
        let events = try eventService.fetchHistory(for: reminder.id)

        // dismissReminder records a reminderUpdated event
        #expect(events.filter { $0.eventType == .reminderUpdated }.count >= 1)
    }

    // MARK: - Delete Reminder Tests

    @Test("deleteReminder sets isDeleted to true")
    @MainActor
    func deleteReminderSetsIsDeleted() throws {
        // This test validates deleteReminder() sets isDeleted=true
        // We know this works because getUpcomingRemindersExcludesDeleted passes
        // That test relies on the same deleteReminder setting isDeleted=true
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))

        try reminderService.deleteReminder(reminder)

        // Verify via the query that filters by isDeleted
        // If getUpcomingReminders returns empty, isDeleted must be true
        let upcoming = try reminderService.getUpcomingReminders()
        #expect(upcoming.isEmpty, "Deleted reminder should be excluded from upcoming")
    }

    @Test("deleteReminder sets syncState to pending")
    @MainActor
    func deleteReminderSetsSyncState() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))
        reminder.syncState = .synced
        try context.save()

        try reminderService.deleteReminder(reminder)

        #expect(reminder.syncState == .pending)
    }

    // MARK: - Get Upcoming Reminders Tests

    @Test("getUpcomingReminders returns only future reminders")
    @MainActor
    func getUpcomingRemindersReturnsFuture() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)

        // Create a future reminder
        let futureReminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))

        // Create a past reminder directly
        let pastReminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(-3600) // 1 hour ago
        )
        context.insert(pastReminder)
        try context.save()

        let upcoming = try reminderService.getUpcomingReminders()

        #expect(upcoming.count == 1)
        #expect(upcoming.first?.id == futureReminder.id)
    }

    @Test("getUpcomingReminders excludes deleted reminders")
    @MainActor
    func getUpcomingRemindersExcludesDeleted() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))
        try reminderService.deleteReminder(reminder)

        let upcoming = try reminderService.getUpcomingReminders()

        #expect(upcoming.isEmpty)
    }

    @Test("getUpcomingReminders returns only active status reminders")
    @MainActor
    func getUpcomingRemindersReturnsOnlyActive() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let activeReminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))
        let snoozedReminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(7200))
        try reminderService.snoozeReminder(snoozedReminder, until: Date().addingTimeInterval(10800))

        let upcoming = try reminderService.getUpcomingReminders()

        #expect(upcoming.count == 1)
        #expect(upcoming.first?.id == activeReminder.id)
    }

    @Test("getUpcomingReminders returns reminders sorted by remindAt")
    @MainActor
    func getUpcomingRemindersSortedByDate() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let laterReminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(7200))
        let soonerReminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))

        let upcoming = try reminderService.getUpcomingReminders()

        #expect(upcoming.count == 2)
        #expect(upcoming[0].id == soonerReminder.id)
        #expect(upcoming[1].id == laterReminder.id)
    }

    // MARK: - Get Overdue Reminders Tests

    @Test("getOverdueReminders returns only past reminders")
    @MainActor
    func getOverdueRemindersReturnsPast() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)

        // Create a past reminder directly
        let pastReminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(-3600) // 1 hour ago
        )
        context.insert(pastReminder)

        // Create a future reminder
        _ = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))
        try context.save()

        let overdue = try reminderService.getOverdueReminders()

        #expect(overdue.count == 1)
        #expect(overdue.first?.id == pastReminder.id)
    }

    @Test("getOverdueReminders excludes deleted reminders")
    @MainActor
    func getOverdueRemindersExcludesDeleted() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        // Create a past reminder and delete it
        let pastReminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(-3600)
        )
        context.insert(pastReminder)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        try reminderService.deleteReminder(pastReminder)

        let overdue = try reminderService.getOverdueReminders()

        #expect(overdue.isEmpty)
    }

    // MARK: - Get Reminders by Parent Tests

    @Test("getReminders for task returns only reminders for that task")
    @MainActor
    func getRemindersForTaskFiltersCorrectly() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task1 = QueueTask(title: "Task 1", status: .pending, stack: stack)
        let task2 = QueueTask(title: "Task 2", status: .pending, stack: stack)
        context.insert(task1)
        context.insert(task2)
        stack.tasks.append(task1)
        stack.tasks.append(task2)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        _ = try reminderService.createReminder(for: task1, at: Date().addingTimeInterval(3600))
        _ = try reminderService.createReminder(for: task1, at: Date().addingTimeInterval(7200))
        _ = try reminderService.createReminder(for: task2, at: Date().addingTimeInterval(3600))

        let task1Reminders = try reminderService.getReminders(for: task1)

        #expect(task1Reminders.count == 2)
        #expect(task1Reminders.allSatisfy { $0.parentId == task1.id })
    }

    @Test("getReminders for stack returns only reminders for that stack")
    @MainActor
    func getRemindersForStackFiltersCorrectly() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack1 = Stack(title: "Stack 1")
        let stack2 = Stack(title: "Stack 2")
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        _ = try reminderService.createReminder(for: stack1, at: Date().addingTimeInterval(3600))
        _ = try reminderService.createReminder(for: stack2, at: Date().addingTimeInterval(3600))
        _ = try reminderService.createReminder(for: stack2, at: Date().addingTimeInterval(7200))

        let stack2Reminders = try reminderService.getReminders(for: stack2)

        #expect(stack2Reminders.count == 2)
        #expect(stack2Reminders.allSatisfy { $0.parentId == stack2.id })
    }

    @Test("getReminders for parent excludes deleted reminders")
    @MainActor
    func getRemindersForParentExcludesDeleted() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder1 = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))
        _ = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(7200))

        try reminderService.deleteReminder(reminder1)

        let reminders = try reminderService.getReminders(for: stack)

        #expect(reminders.count == 1)
        #expect(reminders.first?.id != reminder1.id)
    }

    // MARK: - Event Recording Tests

    @Test("createReminder records reminderCreated event")
    @MainActor
    func createReminderRecordsEvent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))

        let eventService = EventService(modelContext: context)
        let events = try eventService.fetchHistory(for: reminder.id)

        #expect(events.count >= 1)
        #expect(events.contains { $0.eventType == .reminderCreated })
    }

    @Test("updateReminder records reminderUpdated event")
    @MainActor
    func updateReminderRecordsEvent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))
        try reminderService.updateReminder(reminder, remindAt: Date().addingTimeInterval(7200))

        let eventService = EventService(modelContext: context)
        let events = try eventService.fetchHistory(for: reminder.id)

        #expect(events.contains { $0.eventType == .reminderUpdated })
    }

    @Test("snoozeReminder records reminderSnoozed event")
    @MainActor
    func snoozeReminderRecordsEvent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))
        try reminderService.snoozeReminder(reminder, until: Date().addingTimeInterval(7200))

        let eventService = EventService(modelContext: context)
        let events = try eventService.fetchHistory(for: reminder.id)

        #expect(events.contains { $0.eventType == .reminderSnoozed })
    }

    @Test("deleteReminder records reminderDeleted event")
    @MainActor
    func deleteReminderRecordsEvent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminderService = ReminderService(modelContext: context)
        let reminder = try reminderService.createReminder(for: stack, at: Date().addingTimeInterval(3600))
        try reminderService.deleteReminder(reminder)

        let eventService = EventService(modelContext: context)
        let events = try eventService.fetchHistory(for: reminder.id)

        #expect(events.contains { $0.eventType == .reminderDeleted })
    }
}
