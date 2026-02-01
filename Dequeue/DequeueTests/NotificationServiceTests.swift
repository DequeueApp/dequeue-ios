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
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
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

    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        return authorizationStatus
    }

    var setCategories: Set<UNNotificationCategory> = []
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        setCategories = categories
    }

    var badgeCount: Int = 0
    func updateBadgeCount(_ count: Int) async throws {
        badgeCount = count
    }
}

// MARK: - Test Context

/// Shared test context to reduce setup duplication
@MainActor
private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
    let mockCenter: MockNotificationCenter
    let service: NotificationService

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Stack.self,
            QueueTask.self,
            Reminder.self,
            Event.self,
            configurations: config
        )
        context = container.mainContext
        mockCenter = MockNotificationCenter()
        service = NotificationService(
            modelContext: context,
            notificationCenter: mockCenter
        )
    }

    func createStack(title: String = "Test Stack") -> Stack {
        let stack = Stack(title: title)
        context.insert(stack)
        return stack
    }

    func createTask(title: String = "Test Task", stack: Stack) -> QueueTask {
        let task = QueueTask(title: title, stack: stack)
        context.insert(task)
        return task
    }

    func createReminder(
        parentId: String,
        parentType: ParentType,
        status: ReminderStatus = .active,
        remindAt: Date = Date().addingTimeInterval(3_600)
    ) -> Reminder {
        let reminder = Reminder(
            parentId: parentId,
            parentType: parentType,
            status: status,
            remindAt: remindAt
        )
        context.insert(reminder)
        return reminder
    }

    func createStackReminder(
        stack: Stack,
        status: ReminderStatus = .active,
        remindAt: Date = Date().addingTimeInterval(3_600)
    ) -> Reminder {
        createReminder(parentId: stack.id, parentType: .stack, status: status, remindAt: remindAt)
    }

    func createTaskReminder(
        task: QueueTask,
        status: ReminderStatus = .active,
        remindAt: Date = Date().addingTimeInterval(3_600)
    ) -> Reminder {
        createReminder(parentId: task.id, parentType: .task, status: status, remindAt: remindAt)
    }

    func save() throws {
        try context.save()
    }
}

// MARK: - Tests

@Suite("NotificationService Tests", .serialized)
@MainActor
struct NotificationServiceTests {
    // MARK: - Permission Tests

    @Test("requestPermission returns true when authorization is granted")
    @MainActor
    func requestPermissionGranted() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationGranted = true

        let result = await ctx.service.requestPermission()
        #expect(result == true)
    }

    @Test("requestPermission returns false when authorization is denied")
    @MainActor
    func requestPermissionDenied() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationGranted = false

        let result = await ctx.service.requestPermission()
        #expect(result == false)
    }

    @Test("requestPermission returns false when authorization throws error")
    @MainActor
    func requestPermissionError() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationError = NSError(domain: "test", code: 1)

        let result = await ctx.service.requestPermission()
        #expect(result == false)
    }

    @Test("requestPermissionWithError returns true when authorization is granted")
    @MainActor
    func requestPermissionWithErrorGranted() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationGranted = true

        let result = try await ctx.service.requestPermissionWithError()
        #expect(result == true)
    }

    @Test("requestPermissionWithError returns false when authorization is denied")
    @MainActor
    func requestPermissionWithErrorDenied() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationGranted = false

        let result = try await ctx.service.requestPermissionWithError()
        #expect(result == false)
    }

    @Test("requestPermissionWithError throws when authorization fails")
    @MainActor
    func requestPermissionWithErrorThrows() async throws {
        let ctx = try TestContext()
        let expectedError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        ctx.mockCenter.authorizationError = expectedError

        await #expect(throws: Error.self) {
            try await ctx.service.requestPermissionWithError()
        }
    }

    // MARK: - Schedule Notification Tests

    @Test("scheduleNotification adds notification request")
    @MainActor
    func scheduleNotificationAddsRequest() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let reminder = ctx.createStackReminder(stack: stack)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.count == 1)
        #expect(ctx.mockCenter.addedRequests.first?.identifier == reminder.id)
    }

    @Test("scheduleNotification uses reminder ID as identifier")
    @MainActor
    func scheduleNotificationUsesReminderId() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let reminder = ctx.createStackReminder(stack: stack)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.first?.identifier == reminder.id)
    }

    @Test("scheduleNotification includes parent title in content")
    @MainActor
    func scheduleNotificationIncludesParentTitle() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack(title: "My Important Stack")
        let reminder = ctx.createStackReminder(stack: stack)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.first?.content.title == "My Important Stack")
    }

    @Test("scheduleNotification includes task title for task reminders")
    @MainActor
    func scheduleNotificationIncludesTaskTitle() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack(title: "Parent Stack")
        let task = ctx.createTask(title: "My Important Task", stack: stack)
        let reminder = ctx.createTaskReminder(task: task)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.first?.content.title == "My Important Task")
    }

    @Test("scheduleNotification skips deleted reminders")
    @MainActor
    func scheduleNotificationSkipsDeleted() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let deletedReminder = ctx.createStackReminder(stack: stack)
        let activeReminder = ctx.createStackReminder(stack: stack, remindAt: Date().addingTimeInterval(7_200))
        try ctx.save()

        // Mark deleted in-flight (SwiftData quirk)
        deletedReminder.isDeleted = true
        try await ctx.service.scheduleNotification(for: deletedReminder)
        try await ctx.service.scheduleNotification(for: activeReminder)

        #expect(ctx.mockCenter.addedRequests.count == 1)
        #expect(ctx.mockCenter.addedRequests.first?.identifier == activeReminder.id)
    }

    @Test("scheduleNotification skips non-active reminders")
    @MainActor
    func scheduleNotificationSkipsNonActive() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let reminder = ctx.createStackReminder(stack: stack, status: .snoozed)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.isEmpty)
    }

    @Test("scheduleNotification skips past reminders")
    @MainActor
    func scheduleNotificationSkipsPastReminders() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let reminder = ctx.createStackReminder(stack: stack, remindAt: Date().addingTimeInterval(-3_600))
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.isEmpty)
    }

    // MARK: - Cancel Notification Tests

    @Test("cancelNotification removes notification by reminder ID")
    @MainActor
    func cancelNotificationRemovesById() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let reminder = ctx.createStackReminder(stack: stack)
        try ctx.save()

        ctx.service.cancelNotification(for: reminder)

        #expect(ctx.mockCenter.removedIdentifiers.contains(reminder.id))
    }

    @Test("cancelNotifications removes multiple notifications")
    @MainActor
    func cancelNotificationsRemovesMultiple() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let reminder1 = ctx.createStackReminder(stack: stack)
        let reminder2 = ctx.createStackReminder(stack: stack, remindAt: Date().addingTimeInterval(7_200))
        try ctx.save()

        ctx.service.cancelNotifications(for: [reminder1, reminder2])

        #expect(ctx.mockCenter.removedIdentifiers.contains(reminder1.id))
        #expect(ctx.mockCenter.removedIdentifiers.contains(reminder2.id))
    }

    // MARK: - Reschedule All Tests

    @Test("rescheduleAllNotifications removes all pending first")
    @MainActor
    func rescheduleAllRemovesAllPending() async throws {
        let ctx = try TestContext()

        await ctx.service.rescheduleAllNotifications()

        #expect(ctx.mockCenter.allPendingRemoved == true)
    }

    @Test("rescheduleAllNotifications schedules active upcoming reminders")
    @MainActor
    func rescheduleAllSchedulesActiveUpcoming() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()

        let upcomingReminder = ctx.createStackReminder(stack: stack)
        _ = ctx.createStackReminder(stack: stack, remindAt: Date().addingTimeInterval(-3_600)) // past
        let deletedReminder = ctx.createStackReminder(stack: stack, remindAt: Date().addingTimeInterval(7_200))
        try ctx.save()

        deletedReminder.isDeleted = true
        try ctx.save()

        await ctx.service.rescheduleAllNotifications()

        #expect(ctx.mockCenter.addedRequests.count == 1)
        #expect(ctx.mockCenter.addedRequests.first?.identifier == upcomingReminder.id)
    }

    @Test("rescheduleAllNotifications skips snoozed reminders")
    @MainActor
    func rescheduleAllSkipsSnoozed() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        _ = ctx.createStackReminder(stack: stack, status: .snoozed)
        try ctx.save()

        await ctx.service.rescheduleAllNotifications()

        #expect(ctx.mockCenter.addedRequests.isEmpty)
    }

    // MARK: - Notification Content Tests

    @Test("notification content has sound enabled")
    @MainActor
    func notificationContentHasSound() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let reminder = ctx.createStackReminder(stack: stack)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.first?.content.sound != nil)
    }

    @Test("notification body includes type label for stack")
    @MainActor
    func notificationBodyIncludesStackLabel() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let reminder = ctx.createStackReminder(stack: stack)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.first?.content.body.contains("Stack:") == true)
    }

    @Test("notification body includes type label for task")
    @MainActor
    func notificationBodyIncludesTaskLabel() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack(title: "Parent Stack")
        let task = ctx.createTask(title: "Test Task", stack: stack)
        let reminder = ctx.createTaskReminder(task: task)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.first?.content.body.contains("Task:") == true)
    }

    @Test("notification uses fallback title when parent not found")
    @MainActor
    func notificationUsesFallbackTitle() async throws {
        let ctx = try TestContext()
        let reminder = ctx.createReminder(parentId: "non-existent-id", parentType: .stack)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        #expect(ctx.mockCenter.addedRequests.first?.content.title == "Reminder")
    }

    // MARK: - Trigger Tests

    @Test("notification uses calendar trigger with correct date")
    @MainActor
    func notificationUsesCalendarTrigger() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let remindAt = Date().addingTimeInterval(3_600)
        let reminder = ctx.createStackReminder(stack: stack, remindAt: remindAt)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        let trigger = ctx.mockCenter.addedRequests.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger != nil)
        #expect(trigger?.repeats == false)

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

    // MARK: - Authorization Status Tests

    @Test("getAuthorizationStatus returns notDetermined when not requested")
    @MainActor
    func getAuthorizationStatusNotDetermined() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationStatus = .notDetermined

        let status = await ctx.service.getAuthorizationStatus()
        #expect(status == .notDetermined)
    }

    @Test("getAuthorizationStatus returns authorized when granted")
    @MainActor
    func getAuthorizationStatusAuthorized() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationStatus = .authorized

        let status = await ctx.service.getAuthorizationStatus()
        #expect(status == .authorized)
    }

    @Test("getAuthorizationStatus returns denied when denied")
    @MainActor
    func getAuthorizationStatusDenied() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationStatus = .denied

        let status = await ctx.service.getAuthorizationStatus()
        #expect(status == .denied)
    }

    @Test("hasPermissionBeenRequested returns false when notDetermined")
    @MainActor
    func hasPermissionBeenRequestedFalse() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationStatus = .notDetermined

        let result = await ctx.service.hasPermissionBeenRequested()
        #expect(result == false)
    }

    @Test("hasPermissionBeenRequested returns true when authorized")
    @MainActor
    func hasPermissionBeenRequestedTrueAuthorized() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationStatus = .authorized

        let result = await ctx.service.hasPermissionBeenRequested()
        #expect(result == true)
    }

    @Test("hasPermissionBeenRequested returns true when denied")
    @MainActor
    func hasPermissionBeenRequestedTrueDenied() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationStatus = .denied

        let result = await ctx.service.hasPermissionBeenRequested()
        #expect(result == true)
    }

    @Test("isAuthorized returns true when authorized")
    @MainActor
    func isAuthorizedTrue() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationStatus = .authorized

        let result = await ctx.service.isAuthorized()
        #expect(result == true)
    }

    @Test("isAuthorized returns false when denied")
    @MainActor
    func isAuthorizedFalseDenied() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationStatus = .denied

        let result = await ctx.service.isAuthorized()
        #expect(result == false)
    }

    @Test("isAuthorized returns false when notDetermined")
    @MainActor
    func isAuthorizedFalseNotDetermined() async throws {
        let ctx = try TestContext()
        ctx.mockCenter.authorizationStatus = .notDetermined

        let result = await ctx.service.isAuthorized()
        #expect(result == false)
    }

    // MARK: - Notification Action Tests

    @Test("configureNotificationCategories sets reminder category")
    @MainActor
    func configureNotificationCategoriesSetsCategory() async throws {
        let ctx = try TestContext()

        ctx.service.configureNotificationCategories()

        #expect(ctx.mockCenter.setCategories.count == 1)
        let category = ctx.mockCenter.setCategories.first
        #expect(category?.identifier == NotificationConstants.categoryIdentifier)
    }

    @Test("configureNotificationCategories includes complete and snooze actions")
    @MainActor
    func configureNotificationCategoriesIncludesActions() async throws {
        let ctx = try TestContext()

        ctx.service.configureNotificationCategories()

        let category = ctx.mockCenter.setCategories.first
        let actionIds = category?.actions.map(\.identifier) ?? []
        #expect(actionIds.contains(NotificationConstants.Action.complete))
        #expect(actionIds.contains(NotificationConstants.Action.snooze5Min))
        #expect(actionIds.contains(NotificationConstants.Action.snooze15Min))
        #expect(actionIds.contains(NotificationConstants.Action.snooze1Hour))
    }

    @Test("scheduled notification includes category identifier")
    @MainActor
    func scheduledNotificationIncludesCategory() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let task = ctx.createTask(stack: stack)
        let reminder = ctx.createTaskReminder(task: task)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        let request = ctx.mockCenter.addedRequests.first
        #expect(request?.content.categoryIdentifier == NotificationConstants.categoryIdentifier)
    }

    @Test("scheduled notification includes reminder userInfo")
    @MainActor
    func scheduledNotificationIncludesUserInfo() async throws {
        let ctx = try TestContext()
        let stack = ctx.createStack()
        let task = ctx.createTask(stack: stack)
        let reminder = ctx.createTaskReminder(task: task)
        try ctx.save()

        try await ctx.service.scheduleNotification(for: reminder)

        let request = ctx.mockCenter.addedRequests.first
        let userInfo = request?.content.userInfo
        #expect(userInfo?[NotificationConstants.UserInfoKey.reminderId] as? String == reminder.id)
        #expect(userInfo?[NotificationConstants.UserInfoKey.parentType] as? String == ParentType.task.rawValue)
        #expect(userInfo?[NotificationConstants.UserInfoKey.parentId] as? String == task.id)
    }
}
