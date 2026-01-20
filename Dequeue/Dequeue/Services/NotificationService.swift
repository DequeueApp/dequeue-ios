//
//  NotificationService.swift
//  Dequeue
//
//  Local notification scheduling and management (DEQ-12, DEQ-21)
//

import Foundation
import SwiftData
import UserNotifications
import Clerk

// MARK: - Notification Constants

/// Action and category identifiers for notification actions
/// Note: nonisolated(unsafe) is required for static properties used in nonisolated delegate methods.
/// These are String/TimeInterval constants (thread-safe, immutable), so unsafe is correct.
enum NotificationConstants {
    nonisolated(unsafe) static let categoryIdentifier = "REMINDER_CATEGORY"

    enum Action {
        nonisolated(unsafe) static let complete = "COMPLETE_ACTION"
        nonisolated(unsafe) static let snooze5Min = "SNOOZE_5_MIN_ACTION"
        nonisolated(unsafe) static let snooze15Min = "SNOOZE_15_MIN_ACTION"
        nonisolated(unsafe) static let snooze1Hour = "SNOOZE_1_HOUR_ACTION"
    }

    enum UserInfoKey {
        nonisolated(unsafe) static let reminderId = "reminderId"
        nonisolated(unsafe) static let parentType = "parentType"
        nonisolated(unsafe) static let parentId = "parentId"
    }

    /// Snooze durations in seconds
    enum SnoozeDuration {
        nonisolated(unsafe) static let fiveMinutes: TimeInterval = 5 * 60
        nonisolated(unsafe) static let fifteenMinutes: TimeInterval = 15 * 60
        nonisolated(unsafe) static let oneHour: TimeInterval = 60 * 60
    }
}

// MARK: - Notification Center Protocol

/// Protocol abstracting UNUserNotificationCenter for testability
/// Note: Does not conform to Sendable because UNUserNotificationCenter is not marked Sendable in SDK.
/// This is safe because all methods are called from MainActor context via NotificationService.
protocol NotificationCenterProtocol {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func getAuthorizationStatus() async -> UNAuthorizationStatus
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func updateBadgeCount(_ count: Int) async throws
}

/// Extension to make UNUserNotificationCenter conform to our protocol
extension UNUserNotificationCenter: NotificationCenterProtocol {
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    func updateBadgeCount(_ count: Int) async throws {
        try await setBadgeCount(count)
    }
}

// MARK: - Notification Service

@MainActor
final class NotificationService: NSObject {
    private let modelContext: ModelContext
    // UNUserNotificationCenter is thread-safe and can be accessed from any isolation domain
    nonisolated(unsafe) private let notificationCenter: NotificationCenterProtocol

    init(
        modelContext: ModelContext,
        notificationCenter: NotificationCenterProtocol = UNUserNotificationCenter.current()
    ) {
        self.modelContext = modelContext
        self.notificationCenter = notificationCenter
        super.init()
    }

    // MARK: - Permission

    /// Returns the current notification authorization status
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationCenter.getAuthorizationStatus()
    }

    /// Checks if notification permissions have been determined
    /// - Returns: `true` if user has already made a permission decision
    func hasPermissionBeenRequested() async -> Bool {
        let status = await getAuthorizationStatus()
        return status != .notDetermined
    }

    /// Requests notification authorization from the user
    /// - Returns: `true` if permission was granted, `false` otherwise
    func requestPermission() async -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            return false
        }
    }

    /// Requests notification authorization from the user with error propagation
    /// - Returns: `true` if permission was granted, `false` otherwise
    /// - Throws: Error if the authorization request fails
    func requestPermissionWithError() async throws -> Bool {
        try await notificationCenter.requestAuthorization(
            options: [.alert, .sound, .badge]
        )
    }

    /// Checks if notifications are currently authorized
    /// - Returns: `true` if notifications can be scheduled
    func isAuthorized() async -> Bool {
        let status = await getAuthorizationStatus()
        return status == .authorized
    }

    // MARK: - Categories

    /// Configures notification categories with action buttons
    /// Call this once during app startup
    func configureNotificationCategories() {
        let completeAction = UNNotificationAction(
            identifier: NotificationConstants.Action.complete,
            title: "Complete",
            options: [.authenticationRequired]
        )

        let snooze5MinAction = UNNotificationAction(
            identifier: NotificationConstants.Action.snooze5Min,
            title: "Snooze 5 min",
            options: []
        )

        let snooze15MinAction = UNNotificationAction(
            identifier: NotificationConstants.Action.snooze15Min,
            title: "Snooze 15 min",
            options: []
        )

        let snooze1HourAction = UNNotificationAction(
            identifier: NotificationConstants.Action.snooze1Hour,
            title: "Snooze 1 hour",
            options: []
        )

        let reminderCategory = UNNotificationCategory(
            identifier: NotificationConstants.categoryIdentifier,
            actions: [completeAction, snooze5MinAction, snooze15MinAction, snooze1HourAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([reminderCategory])
    }

    // MARK: - Schedule

    /// Schedules a local notification for the given reminder
    /// - Parameter reminder: The reminder to schedule a notification for
    func scheduleNotification(for reminder: Reminder) async throws {
        // Don't schedule for deleted or non-active reminders
        guard !reminder.isDeleted, reminder.status == .active else {
            return
        }

        // Don't schedule for past dates
        guard reminder.remindAt > Date() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = NotificationConstants.categoryIdentifier

        // Get parent title for notification content
        let parentTitle = try fetchParentTitle(for: reminder)
        content.title = parentTitle ?? "Reminder"
        content.body = formatReminderBody(for: reminder, parentTitle: parentTitle)

        // Store reminder info for action handling
        content.userInfo = [
            NotificationConstants.UserInfoKey.reminderId: reminder.id,
            NotificationConstants.UserInfoKey.parentType: reminder.parentType.rawValue,
            NotificationConstants.UserInfoKey.parentId: reminder.parentId
        ]

        // Create trigger based on reminder date
        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.remindAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        // Use reminder ID as notification identifier for easy cancellation
        let request = UNNotificationRequest(
            identifier: reminder.id,
            content: content,
            trigger: trigger
        )

        try await notificationCenter.add(request)
    }

    // MARK: - Cancel

    /// Cancels a pending notification for the given reminder
    /// - Parameter reminder: The reminder whose notification should be cancelled
    func cancelNotification(for reminder: Reminder) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminder.id])
    }

    /// Cancels notifications for multiple reminders
    /// - Parameter reminders: The reminders whose notifications should be cancelled
    func cancelNotifications(for reminders: [Reminder]) {
        let identifiers = reminders.map(\.id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - Reschedule All

    /// Reschedules all notifications to match current reminder state
    /// Call this on app launch or when reminders are synced
    func rescheduleAllNotifications() async {
        // Remove all existing notifications first
        notificationCenter.removeAllPendingNotificationRequests()

        // Fetch all active, upcoming reminders
        do {
            let reminders = try fetchActiveUpcomingReminders()
            for reminder in reminders {
                try? await scheduleNotification(for: reminder)
            }
        } catch {
            // Log error but don't throw - best effort reschedule
        }
    }

    // MARK: - App Badge

    /// Updates the app badge count to show the number of overdue reminders
    func updateAppBadge() async {
        do {
            let overdueCount = try fetchOverdueReminderCount()
            try await notificationCenter.updateBadgeCount(overdueCount)
        } catch {
            // Log error but don't throw - best effort badge update
            ErrorReportingService.capture(
                error: error,
                context: ["action": "update_app_badge"]
            )
        }
    }

    /// Clears the app badge
    func clearAppBadge() async {
        try? await notificationCenter.updateBadgeCount(0)
    }

    private func fetchOverdueReminderCount() throws -> Int {
        let now = Date()
        let predicate = #Predicate<Reminder> { reminder in
            reminder.isDeleted == false
        }
        let descriptor = FetchDescriptor<Reminder>(predicate: predicate)
        return try modelContext.fetch(descriptor)
            .filter { $0.status == .active && $0.remindAt <= now }
            .count
    }

    // MARK: - Private Helpers

    private func fetchParentTitle(for reminder: Reminder) throws -> String? {
        switch reminder.parentType {
        case .task:
            return try fetchTaskTitle(id: reminder.parentId)
        case .stack:
            return try fetchStackTitle(id: reminder.parentId)
        case .arc:
            return try fetchArcTitle(id: reminder.parentId)
        }
    }

    private func fetchTaskTitle(id: String) throws -> String? {
        let predicate = #Predicate<QueueTask> { task in
            task.id == id
        }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
        let tasks = try modelContext.fetch(descriptor)
        return tasks.first?.title
    }

    private func fetchStackTitle(id: String) throws -> String? {
        let predicate = #Predicate<Stack> { stack in
            stack.id == id
        }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let stacks = try modelContext.fetch(descriptor)
        return stacks.first?.title
    }

    private func fetchArcTitle(id: String) throws -> String? {
        let predicate = #Predicate<Arc> { arc in
            arc.id == id
        }
        let descriptor = FetchDescriptor<Arc>(predicate: predicate)
        let arcs = try modelContext.fetch(descriptor)
        return arcs.first?.title
    }

    private func fetchActiveUpcomingReminders() throws -> [Reminder] {
        let now = Date()
        let predicate = #Predicate<Reminder> { reminder in
            reminder.isDeleted == false
        }
        let descriptor = FetchDescriptor<Reminder>(predicate: predicate)
        return try modelContext.fetch(descriptor)
            .filter { $0.status == .active && $0.remindAt > now }
    }

    private func formatReminderBody(for reminder: Reminder, parentTitle: String?) -> String {
        let timeString = reminder.remindAt.formatted(date: .omitted, time: .shortened)
        let typeLabel = reminder.parentType == .task ? "Task" : "Stack"

        if let title = parentTitle {
            return "\(typeLabel): \(title) at \(timeString)"
        } else {
            return "Reminder at \(timeString)"
        }
    }
}

// MARK: - Notification Delegate Support

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Called when a notification is about to be presented while the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        return [.banner, .sound, .badge]
    }

    /// Called when the user interacts with a notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        // Handle custom actions
        switch actionIdentifier {
        case NotificationConstants.Action.complete:
            await handleCompleteAction(userInfo: userInfo)
        case NotificationConstants.Action.snooze5Min:
            await handleSnoozeAction(userInfo: userInfo, duration: NotificationConstants.SnoozeDuration.fiveMinutes)
        case NotificationConstants.Action.snooze15Min:
            await handleSnoozeAction(userInfo: userInfo, duration: NotificationConstants.SnoozeDuration.fifteenMinutes)
        case NotificationConstants.Action.snooze1Hour:
            await handleSnoozeAction(userInfo: userInfo, duration: NotificationConstants.SnoozeDuration.oneHour)
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification - can be used for navigation
            break
        case UNNotificationDismissActionIdentifier:
            // User dismissed the notification
            break
        default:
            break
        }
    }

    /// Handles the "Complete" action from a notification
    nonisolated private func handleCompleteAction(userInfo: [AnyHashable: Any]) async {
        guard let parentType = userInfo[NotificationConstants.UserInfoKey.parentType] as? String,
              let parentId = userInfo[NotificationConstants.UserInfoKey.parentId] as? String,
              parentType == ParentType.task.rawValue else {
            // Can only complete tasks, not stacks
            return
        }

        // Fetch userId and deviceId for event tracking
        let userId = await MainActor.run { Clerk.shared.user?.id ?? "" }
        let deviceId = await DeviceService.shared.getDeviceId()

        await MainActor.run {
            do {
                let taskService = TaskService(
                    modelContext: modelContext,
                    userId: userId,
                    deviceId: deviceId
                )
                if let task = try fetchTask(id: parentId) {
                    try taskService.markAsCompleted(task)
                }
            } catch {
                ErrorReportingService.capture(
                    error: error,
                    context: ["action": "notification_complete_task"]
                )
            }
        }
    }

    /// Handles the "Snooze" action from a notification
    /// - Parameters:
    ///   - userInfo: The notification's user info dictionary
    ///   - duration: The snooze duration in seconds
    nonisolated private func handleSnoozeAction(userInfo: [AnyHashable: Any], duration: TimeInterval) async {
        guard let reminderId = userInfo[NotificationConstants.UserInfoKey.reminderId] as? String else {
            return
        }

        // Fetch userId and deviceId for event tracking
        let userId = await MainActor.run { Clerk.shared.user?.id ?? "" }
        let deviceId = await DeviceService.shared.getDeviceId()

        await MainActor.run {
            do {
                let reminderService = ReminderService(
                    modelContext: modelContext,
                    userId: userId,
                    deviceId: deviceId
                )
                if let reminder = try fetchReminder(id: reminderId) {
                    let snoozeUntil = Date().addingTimeInterval(duration)
                    try reminderService.snoozeReminder(reminder, until: snoozeUntil)
                    // Reschedule notification for snoozed time
                    Task {
                        try? await scheduleNotification(for: reminder)
                    }
                }
            } catch {
                ErrorReportingService.capture(
                    error: error,
                    context: ["action": "notification_snooze_reminder", "duration": "\(duration)"]
                )
            }
        }
    }

    /// Fetches a task by ID
    private func fetchTask(id: String) throws -> QueueTask? {
        let predicate = #Predicate<QueueTask> { task in
            task.id == id
        }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    /// Fetches a reminder by ID
    private func fetchReminder(id: String) throws -> Reminder? {
        let predicate = #Predicate<Reminder> { reminder in
            reminder.id == id
        }
        let descriptor = FetchDescriptor<Reminder>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - Notification Errors

enum NotificationError: LocalizedError {
    case permissionDenied
    case schedulingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission was denied. Enable notifications in Settings."
        case .schedulingFailed(let error):
            return "Failed to schedule notification: \(error.localizedDescription)"
        }
    }
}
