//
//  SmartNotificationServiceTests.swift
//  DequeueTests
//
//  Tests for SmartNotificationService — due date scheduling, morning digest,
//  overdue alerts, end-of-day reminders, and settings management.
//

import Testing
import Foundation
import UserNotifications
import SwiftData

@testable import Dequeue

// MARK: - Mock Notification Center

/// Mock notification center for testing notification scheduling
final class MockSmartNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    var scheduledRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []
    var allPendingRemoved = false
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var registeredCategories: Set<UNNotificationCategory> = []
    var badgeCount: Int = 0
    var shouldFailToAdd = false

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationStatus == .authorized
    }

    func add(_ request: UNNotificationRequest) async throws {
        if shouldFailToAdd {
            throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock failure"])
        }
        scheduledRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        scheduledRequests.removeAll { identifiers.contains($0.identifier) }
    }

    func removeAllPendingNotificationRequests() {
        allPendingRemoved = true
        scheduledRequests.removeAll()
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        scheduledRequests
    }

    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatus
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        registeredCategories = categories
    }

    func updateBadgeCount(_ count: Int) async throws {
        badgeCount = count
    }
}

// MARK: - Test Helpers

@MainActor
private func makeTestContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: QueueTask.self, Stack.self, Reminder.self, Arc.self,
        configurations: config
    )
    return container.mainContext
}

@MainActor
private func makeTask(
    title: String,
    dueTime: Date? = nil,
    status: TaskStatus = .pending,
    isDeleted: Bool = false,
    stack: Stack? = nil,
    priority: Int? = nil,
    in context: ModelContext
) -> QueueTask {
    let task = QueueTask(
        title: title,
        dueTime: dueTime,
        status: status,
        priority: priority,
        isDeleted: isDeleted,
        stack: stack
    )
    context.insert(task)
    try? context.save()
    return task
}

// MARK: - Settings Tests

@Suite("SmartNotificationSettings")
@MainActor
struct SmartNotificationSettingsTests {
    @Test("Default settings are sensible")
    func defaultSettings() {
        let settings = SmartNotificationSettings.default
        #expect(settings.autoDueDateNotifications == true)
        #expect(settings.dueDateLeadTimeMinutes == 30)
        #expect(settings.morningDigestEnabled == true)
        #expect(settings.morningDigestHour == 8)
        #expect(settings.overdueAlertsEnabled == true)
        #expect(settings.endOfDayReminderEnabled == true)
        #expect(settings.endOfDayReminderHour == 18)
        #expect(settings.maxDailyNotifications == 20)
    }

    @Test("Settings round-trip through JSON")
    func settingsRoundTrip() throws {
        var settings = SmartNotificationSettings.default
        settings.dueDateLeadTimeMinutes = 60
        settings.morningDigestHour = 7
        settings.overdueAlertIntervalHours = 2
        settings.maxDailyNotifications = 10

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SmartNotificationSettings.self, from: data)

        #expect(decoded.dueDateLeadTimeMinutes == 60)
        #expect(decoded.morningDigestHour == 7)
        #expect(decoded.overdueAlertIntervalHours == 2)
        #expect(decoded.maxDailyNotifications == 10)
    }
}

// MARK: - Service Initialization Tests

@Suite("SmartNotificationService Initialization")
@MainActor
struct ServiceInitTests {
    @Test("Loads default settings when none saved")
    @MainActor func defaultInit() throws {
        let context = try makeTestContext()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: MockSmartNotificationCenter(),
            userDefaults: defaults
        )
        #expect(service.settings.autoDueDateNotifications == true)
        #expect(service.settings.morningDigestEnabled == true)
    }

    @Test("Loads saved settings from UserDefaults")
    @MainActor func loadsSavedSettings() throws {
        let context = try makeTestContext()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!

        // Save custom settings
        var customSettings = SmartNotificationSettings.default
        customSettings.dueDateLeadTimeMinutes = 120
        customSettings.morningDigestEnabled = false
        let data = try JSONEncoder().encode(customSettings)
        defaults.set(data, forKey: SmartNotificationSettings.storageKey)

        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: MockSmartNotificationCenter(),
            userDefaults: defaults
        )
        #expect(service.settings.dueDateLeadTimeMinutes == 120)
        #expect(service.settings.morningDigestEnabled == false)
    }

    @Test("Update settings persists to UserDefaults")
    @MainActor func updateSettingsPersists() throws {
        let context = try makeTestContext()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: MockSmartNotificationCenter(),
            userDefaults: defaults
        )

        var newSettings = SmartNotificationSettings.default
        newSettings.maxDailyNotifications = 50
        service.updateSettings(newSettings)

        // Verify persisted
        let saved = defaults.data(forKey: SmartNotificationSettings.storageKey)!
        let decoded = try JSONDecoder().decode(SmartNotificationSettings.self, from: saved)
        #expect(decoded.maxDailyNotifications == 50)
    }
}

// MARK: - Due Date Notification Tests

@Suite("Due Date Notifications")
@MainActor
struct DueDateTests {
    @Test("Schedules notification for task with future due date")
    @MainActor func schedulesForFutureDue() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let task = makeTask(title: "Future Task", dueTime: futureDate, in: context)

        await service.handleTaskDueDateChanged(task)

        #expect(mock.scheduledRequests.count == 1)
        let req = mock.scheduledRequests[0]
        #expect(req.identifier == "smart-due-\(task.id)")
        #expect(req.content.title == "Task Due Soon")
        #expect(req.content.body.contains("Future Task"))
    }

    @Test("Does not schedule for past due date")
    @MainActor func skipsForPastDue() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let task = makeTask(title: "Past Task", dueTime: pastDate, in: context)

        await service.handleTaskDueDateChanged(task)

        #expect(mock.scheduledRequests.isEmpty)
    }

    @Test("Does not schedule for completed tasks")
    @MainActor func skipsForCompleted() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let futureDate = Date().addingTimeInterval(3600)
        let task = makeTask(title: "Done Task", dueTime: futureDate, status: .completed, in: context)

        await service.handleTaskDueDateChanged(task)

        #expect(mock.scheduledRequests.isEmpty)
    }

    @Test("Does not schedule for deleted tasks")
    @MainActor func skipsForDeleted() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let futureDate = Date().addingTimeInterval(3600)
        let task = makeTask(title: "Deleted Task", dueTime: futureDate, isDeleted: true, in: context)

        await service.handleTaskDueDateChanged(task)

        #expect(mock.scheduledRequests.isEmpty)
    }

    @Test("Does not schedule when auto-notifications disabled")
    @MainActor func respectsDisabledSetting() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: defaults
        )

        var settings = SmartNotificationSettings.default
        settings.autoDueDateNotifications = false
        service.updateSettings(settings)

        let futureDate = Date().addingTimeInterval(3600)
        let task = makeTask(title: "Task", dueTime: futureDate, in: context)

        await service.handleTaskDueDateChanged(task)

        #expect(mock.scheduledRequests.isEmpty)
    }

    @Test("Cancels existing notification before scheduling new one")
    @MainActor func cancelsBeforeRescheduling() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let futureDate = Date().addingTimeInterval(7200) // 2 hours from now
        let task = makeTask(title: "Task", dueTime: futureDate, in: context)

        await service.handleTaskDueDateChanged(task)
        await service.handleTaskDueDateChanged(task) // Reschedule

        // Should have cancelled the first and scheduled the second
        #expect(mock.removedIdentifiers.contains("smart-due-\(task.id)"))
    }

    @Test("Cancel task notification removes both due and overdue")
    @MainActor func cancelRemovesBoth() throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        service.cancelTaskNotification("task-123")

        #expect(mock.removedIdentifiers.contains("smart-due-task-123"))
        #expect(mock.removedIdentifiers.contains("smart-overdue-task-123"))
    }

    @Test("Includes stack title in notification body when available")
    @MainActor func includesStackTitle() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let stack = Stack(title: "My Stack")
        context.insert(stack)

        let futureDate = Date().addingTimeInterval(3600)
        let task = makeTask(title: "Task", dueTime: futureDate, stack: stack, in: context)

        await service.handleTaskDueDateChanged(task)

        #expect(mock.scheduledRequests.count == 1)
        #expect(mock.scheduledRequests[0].content.body.contains("My Stack"))
    }
}

// MARK: - Morning Digest Tests

@Suite("Morning Digest")
@MainActor
struct MorningDigestTests {
    @Test("Schedules morning digest when tasks exist")
    @MainActor func schedulesWithTasks() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        // Create tasks due tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let tomorrowNoon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow)!
        _ = makeTask(title: "Task 1", dueTime: tomorrowNoon, in: context)
        _ = makeTask(title: "Task 2", dueTime: tomorrowNoon, in: context)

        await service.scheduleMorningDigest()

        let digestRequests = mock.scheduledRequests.filter {
            $0.identifier.hasPrefix("smart-morning-digest-")
        }
        #expect(digestRequests.count == 1)
        #expect(digestRequests[0].content.title == "☀️ Today's Tasks")
        #expect(digestRequests[0].content.body.contains("2 tasks due today"))
    }

    @Test("Skips digest when no tasks")
    @MainActor func skipsWhenEmpty() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        await service.scheduleMorningDigest()

        let digestRequests = mock.scheduledRequests.filter {
            $0.identifier.hasPrefix("smart-morning-digest-")
        }
        #expect(digestRequests.isEmpty)
    }

    @Test("Respects disabled setting")
    @MainActor func respectsDisabled() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: defaults
        )

        var settings = SmartNotificationSettings.default
        settings.morningDigestEnabled = false
        service.updateSettings(settings)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        _ = makeTask(title: "Task", dueTime: tomorrow, in: context)

        await service.scheduleMorningDigest()

        #expect(mock.scheduledRequests.isEmpty)
    }
}

// MARK: - Overdue Alert Tests

@Suite("Overdue Alerts")
@MainActor
struct OverdueAlertTests {
    @Test("Schedules alerts for overdue tasks")
    @MainActor func schedulesForOverdue() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let pastDate = Date().addingTimeInterval(-7200) // 2 hours ago
        _ = makeTask(title: "Overdue Task", dueTime: pastDate, in: context)

        await service.scheduleOverdueAlerts()

        let overdueRequests = mock.scheduledRequests.filter {
            $0.identifier.hasPrefix("smart-overdue-")
        }
        #expect(overdueRequests.count == 1)
        #expect(overdueRequests[0].content.title == "⚠️ Overdue Task")
    }

    @Test("Skips completed tasks for overdue alerts")
    @MainActor func skipsCompleted() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let pastDate = Date().addingTimeInterval(-7200)
        _ = makeTask(title: "Done Task", dueTime: pastDate, status: .completed, in: context)

        await service.scheduleOverdueAlerts()

        #expect(mock.scheduledRequests.isEmpty)
    }

    @Test("Respects max daily notification limit")
    @MainActor func respectsMaxLimit() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: defaults
        )

        var settings = SmartNotificationSettings.default
        settings.maxDailyNotifications = 3
        service.updateSettings(settings)

        let pastDate = Date().addingTimeInterval(-3600)
        for i in 1...10 {
            _ = makeTask(title: "Overdue \(i)", dueTime: pastDate, in: context)
        }

        await service.scheduleOverdueAlerts()

        #expect(mock.scheduledRequests.count == 3) // Limited to max
    }

    @Test("Respects disabled setting")
    @MainActor func respectsDisabled() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: defaults
        )

        var settings = SmartNotificationSettings.default
        settings.overdueAlertsEnabled = false
        service.updateSettings(settings)

        let pastDate = Date().addingTimeInterval(-3600)
        _ = makeTask(title: "Overdue", dueTime: pastDate, in: context)

        await service.scheduleOverdueAlerts()

        #expect(mock.scheduledRequests.isEmpty)
    }
}

// MARK: - Query Helper Tests

@Suite("Query Helpers")
@MainActor
struct QueryHelperTests {
    @Test("Fetches tasks due on a specific date")
    @MainActor func fetchTasksDueOn() throws {
        let context = try makeTestContext()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: MockSmartNotificationCenter(),
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let today = Date()
        let todayNoon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: todayNoon)!

        _ = makeTask(title: "Today Task", dueTime: todayNoon, in: context)
        _ = makeTask(title: "Tomorrow Task", dueTime: tomorrow, in: context)
        _ = makeTask(title: "No Due", in: context)

        let todayTasks = service.fetchTasksDueOn(date: today)
        #expect(todayTasks.count == 1)
        #expect(todayTasks[0].title == "Today Task")
    }

    @Test("Fetches overdue tasks")
    @MainActor func fetchOverdue() throws {
        let context = try makeTestContext()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: MockSmartNotificationCenter(),
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let pastDate = Date().addingTimeInterval(-86400) // Yesterday
        let futureDate = Date().addingTimeInterval(86400) // Tomorrow

        _ = makeTask(title: "Overdue", dueTime: pastDate, in: context)
        _ = makeTask(title: "Future", dueTime: futureDate, in: context)
        _ = makeTask(title: "Done Past", dueTime: pastDate, status: .completed, in: context)

        let overdue = service.fetchOverdueTasks()
        #expect(overdue.count == 1)
        #expect(overdue[0].title == "Overdue")
    }

    @Test("Fetches upcoming tasks within 7 days")
    @MainActor func fetchUpcoming() throws {
        let context = try makeTestContext()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: MockSmartNotificationCenter(),
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        let twoDays = Date().addingTimeInterval(2 * 86400)
        let tenDays = Date().addingTimeInterval(10 * 86400)
        let pastDate = Date().addingTimeInterval(-86400)

        _ = makeTask(title: "Upcoming", dueTime: twoDays, in: context)
        _ = makeTask(title: "Far Out", dueTime: tenDays, in: context)
        _ = makeTask(title: "Past", dueTime: pastDate, in: context)

        let upcoming = service.fetchTasksWithUpcomingDueDates()
        #expect(upcoming.count == 1)
        #expect(upcoming[0].title == "Upcoming")
    }
}

// MARK: - Full Refresh Tests

@Suite("Full Notification Refresh")
@MainActor
struct FullRefreshTests {
    @Test("Refresh cleans and re-schedules all")
    @MainActor func refreshAll() async throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        // Create a task due in 2 hours
        let futureDate = Date().addingTimeInterval(7200)
        _ = makeTask(title: "Soon Task", dueTime: futureDate, in: context)

        // Pre-populate with stale notifications
        let staleRequest = UNNotificationRequest(
            identifier: "smart-due-old-task",
            content: UNMutableNotificationContent(),
            trigger: nil
        )
        mock.scheduledRequests.append(staleRequest)

        await service.refreshAllNotifications()

        // Stale notification should be removed
        #expect(mock.removedIdentifiers.contains("smart-due-old-task"))

        // New notification should be scheduled for the task
        let dueRequests = mock.scheduledRequests.filter {
            $0.identifier.hasPrefix("smart-due-")
        }
        #expect(dueRequests.count >= 1)
    }
}

// MARK: - Category Configuration Tests

@Suite("Notification Categories")
@MainActor
struct CategoryTests {
    @Test("Configures all expected categories")
    @MainActor func configuresCategories() throws {
        let context = try makeTestContext()
        let mock = MockSmartNotificationCenter()
        let service = SmartNotificationService(
            modelContext: context,
            notificationCenter: mock,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        service.configureCategories()

        #expect(mock.registeredCategories.count == 3)
        let ids = Set(mock.registeredCategories.map(\.identifier))
        #expect(ids.contains(SmartNotificationCategory.dueDateCategory))
        #expect(ids.contains(SmartNotificationCategory.digestCategory))
        #expect(ids.contains(SmartNotificationCategory.overdueCategory))
    }
}
