//
//  NotificationServiceTests.swift
//  DequeueTests
//
//  Tests for NotificationService - local notification management (DEQ-12)
//

import Testing
import SwiftData
import Foundation
import UserNotifications
@testable import Dequeue

// MARK: - Mock Notification Center

/// Mock implementation of NotificationCenterProtocol for testing
final class MockNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    var authorizationGranted = true
    var authorizationError: Error?
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []
    var allPendingRemoved = false
    var pendingRequests: [UNNotificationRequest] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        if let error = authorizationError {
            throw error
        }
        return authorizationGranted
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        pendingRequests.removeAll { identifiers.contains($0.identifier) }
    }

    func removeAllPendingNotificationRequests() {
        allPendingRemoved = true
        pendingRequests.removeAll()
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        return pendingRequests
    }

    func reset() {
        authorizationGranted = true
        authorizationError = nil
        addedRequests.removeAll()
        removedIdentifiers.removeAll()
        allPendingRemoved = false
        pendingRequests.removeAll()
    }
}

// MARK: - Test Helpers

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

// MARK: - Tests

@Suite("NotificationService Tests", .serialized)
struct NotificationServiceTests {

    // MARK: - Permission Tests

    @Test("requestPermission returns true when authorization is granted")
    @MainActor
    func requestPermissionGranted() async throws {
        let container = try makeTestContainer()
        let mockCenter = MockNotificationCenter()
        mockCenter.authorizationGranted = true

        let service = NotificationService(
            modelContext: container.mainContext,
            notificationCenter: mockCenter
        )

        let result = await service.requestPermission()
        #expect(result == true)
    }

    @Test("requestPermission returns false when authorization is denied")
    @MainActor
    func requestPermissionDenied() async throws {
        let container = try makeTestContainer()
        let mockCenter = MockNotificationCenter()
        mockCenter.authorizationGranted = false

        let service = NotificationService(
            modelContext: container.mainContext,
            notificationCenter: mockCenter
        )

        let result = await service.requestPermission()
        #expect(result == false)
    }

    @Test("requestPermission returns false when authorization throws error")
    @MainActor
    func requestPermissionError() async throws {
        let container = try makeTestContainer()
        let mockCenter = MockNotificationCenter()
        mockCenter.authorizationError = NSError(domain: "test", code: 1)

        let service = NotificationService(
            modelContext: container.mainContext,
            notificationCenter: mockCenter
        )

        let result = await service.requestPermission()
        #expect(result == false)
    }

    // MARK: - Schedule Notification Tests

    @Test("scheduleNotification adds notification request")
    @MainActor
    func scheduleNotificationAddsRequest() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            status: .active,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        #expect(mockCenter.addedRequests.count == 1)
        #expect(mockCenter.addedRequests.first?.identifier == reminder.id)
    }

    @Test("scheduleNotification uses reminder ID as identifier")
    @MainActor
    func scheduleNotificationUsesReminderId() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        #expect(mockCenter.addedRequests.first?.identifier == reminder.id)
    }

    @Test("scheduleNotification includes parent title in content")
    @MainActor
    func scheduleNotificationIncludesParentTitle() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "My Important Stack")
        context.insert(stack)
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        let content = mockCenter.addedRequests.first?.content
        #expect(content?.title == "My Important Stack")
    }

    @Test("scheduleNotification includes task title for task reminders")
    @MainActor
    func scheduleNotificationIncludesTaskTitle() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Parent Stack")
        context.insert(stack)
        let task = QueueTask(title: "My Important Task", stack: stack)
        context.insert(task)
        let reminder = Reminder(
            parentId: task.id,
            parentType: .task,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        let content = mockCenter.addedRequests.first?.content
        #expect(content?.title == "My Important Task")
    }

    @Test("scheduleNotification skips deleted reminders")
    @MainActor
    func scheduleNotificationSkipsDeleted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        // Create a reminder that we'll mark as deleted
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        // Create a separate active reminder to verify service works
        let activeReminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(7200)
        )
        context.insert(activeReminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        // Schedule the deleted reminder - mark it deleted in-flight
        reminder.isDeleted = true
        try await service.scheduleNotification(for: reminder)

        // Verify only the active reminder would be scheduled
        try await service.scheduleNotification(for: activeReminder)

        // Only the active reminder should have been scheduled
        #expect(mockCenter.addedRequests.count == 1)
        #expect(mockCenter.addedRequests.first?.identifier == activeReminder.id)
    }

    @Test("scheduleNotification skips non-active reminders")
    @MainActor
    func scheduleNotificationSkipsNonActive() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            status: .snoozed,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        #expect(mockCenter.addedRequests.isEmpty)
    }

    @Test("scheduleNotification skips past reminders")
    @MainActor
    func scheduleNotificationSkipsPastReminders() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(-3600) // 1 hour ago
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        #expect(mockCenter.addedRequests.isEmpty)
    }

    // MARK: - Cancel Notification Tests

    @Test("cancelNotification removes notification by reminder ID")
    @MainActor
    func cancelNotificationRemovesById() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        service.cancelNotification(for: reminder)

        #expect(mockCenter.removedIdentifiers.contains(reminder.id))
    }

    @Test("cancelNotifications removes multiple notifications")
    @MainActor
    func cancelNotificationsRemovesMultiple() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let reminder1 = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(3600)
        )
        let reminder2 = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(7200)
        )
        context.insert(reminder1)
        context.insert(reminder2)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        service.cancelNotifications(for: [reminder1, reminder2])

        #expect(mockCenter.removedIdentifiers.contains(reminder1.id))
        #expect(mockCenter.removedIdentifiers.contains(reminder2.id))
    }

    // MARK: - Reschedule All Tests

    @Test("rescheduleAllNotifications removes all pending first")
    @MainActor
    func rescheduleAllRemovesAllPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        await service.rescheduleAllNotifications()

        #expect(mockCenter.allPendingRemoved == true)
    }

    @Test("rescheduleAllNotifications schedules active upcoming reminders")
    @MainActor
    func rescheduleAllSchedulesActiveUpcoming() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        // Active upcoming reminder - should be scheduled
        let upcomingReminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            status: .active,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(upcomingReminder)

        // Past reminder - should not be scheduled
        let pastReminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            status: .active,
            remindAt: Date().addingTimeInterval(-3600)
        )
        context.insert(pastReminder)

        // Deleted reminder - should not be scheduled
        let deletedReminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            status: .active,
            remindAt: Date().addingTimeInterval(7200)
        )
        context.insert(deletedReminder)

        try context.save()

        // Mark as deleted after save (SwiftData quirk)
        deletedReminder.isDeleted = true
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        await service.rescheduleAllNotifications()

        #expect(mockCenter.addedRequests.count == 1)
        #expect(mockCenter.addedRequests.first?.identifier == upcomingReminder.id)
    }

    @Test("rescheduleAllNotifications skips snoozed reminders")
    @MainActor
    func rescheduleAllSkipsSnoozed() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let snoozedReminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            status: .snoozed,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(snoozedReminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        await service.rescheduleAllNotifications()

        #expect(mockCenter.addedRequests.isEmpty)
    }

    // MARK: - Notification Content Tests

    @Test("notification content has sound enabled")
    @MainActor
    func notificationContentHasSound() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        let content = mockCenter.addedRequests.first?.content
        #expect(content?.sound != nil)
    }

    @Test("notification body includes type label for stack")
    @MainActor
    func notificationBodyIncludesStackLabel() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        let content = mockCenter.addedRequests.first?.content
        #expect(content?.body.contains("Stack:") == true)
    }

    @Test("notification body includes type label for task")
    @MainActor
    func notificationBodyIncludesTaskLabel() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Parent Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(task)
        let reminder = Reminder(
            parentId: task.id,
            parentType: .task,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        let content = mockCenter.addedRequests.first?.content
        #expect(content?.body.contains("Task:") == true)
    }

    @Test("notification uses fallback title when parent not found")
    @MainActor
    func notificationUsesFallbackTitle() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        // Create reminder with non-existent parent
        let reminder = Reminder(
            parentId: "non-existent-id",
            parentType: .stack,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        let content = mockCenter.addedRequests.first?.content
        #expect(content?.title == "Reminder")
    }

    // MARK: - Trigger Tests

    @Test("notification uses calendar trigger with correct date")
    @MainActor
    func notificationUsesCalendarTrigger() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockCenter = MockNotificationCenter()

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let remindAt = Date().addingTimeInterval(3600)
        let reminder = Reminder(
            parentId: stack.id,
            parentType: .stack,
            remindAt: remindAt
        )
        context.insert(reminder)
        try context.save()

        let service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )

        try await service.scheduleNotification(for: reminder)

        let trigger = mockCenter.addedRequests.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger != nil)
        #expect(trigger?.repeats == false)

        // Verify the date components match
        let expectedComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: remindAt
        )
        #expect(trigger?.dateComponents.year == expectedComponents.year)
        #expect(trigger?.dateComponents.month == expectedComponents.month)
        #expect(trigger?.dateComponents.day == expectedComponents.day)
        #expect(trigger?.dateComponents.hour == expectedComponents.hour)
        #expect(trigger?.dateComponents.minute == expectedComponents.minute)
    }
}
