//
//  NotificationService.swift
//  Dequeue
//
//  Local notification scheduling and management (DEQ-12)
//

import Foundation
import SwiftData
import UserNotifications

// MARK: - Notification Center Protocol

/// Protocol abstracting UNUserNotificationCenter for testability
protocol NotificationCenterProtocol: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func getAuthorizationStatus() async -> UNAuthorizationStatus
}

/// Extension to make UNUserNotificationCenter conform to our protocol
extension UNUserNotificationCenter: NotificationCenterProtocol {
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

// MARK: - Notification Service

@MainActor
final class NotificationService: NSObject {
    private let modelContext: ModelContext
    private let notificationCenter: NotificationCenterProtocol

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

    /// Checks if notifications are currently authorized
    /// - Returns: `true` if notifications can be scheduled
    func isAuthorized() async -> Bool {
        let status = await getAuthorizationStatus()
        return status == .authorized
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

        // Get parent title for notification content
        let parentTitle = try fetchParentTitle(for: reminder)
        content.title = parentTitle ?? "Reminder"
        content.body = formatReminderBody(for: reminder, parentTitle: parentTitle)

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

    // MARK: - Private Helpers

    private func fetchParentTitle(for reminder: Reminder) throws -> String? {
        switch reminder.parentType {
        case .task:
            return try fetchTaskTitle(id: reminder.parentId)
        case .stack:
            return try fetchStackTitle(id: reminder.parentId)
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
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let timeString = formatter.string(from: reminder.remindAt)
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
        // The notification identifier is the reminder ID
        // This can be used to navigate to the reminder/task/stack
        _ = response.notification.request.identifier
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
