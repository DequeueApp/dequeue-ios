//
//  ReminderActionHandler.swift
//  Dequeue
//
//  Shared handler for reminder snooze and delete actions (DEQ-18)
//

import SwiftUI
import SwiftData

/// Handles snooze and delete operations for reminders.
/// Shared between TaskDetailView and StackDetailView to avoid code duplication.
@MainActor
struct ReminderActionHandler {
    let modelContext: ModelContext
    let userId: String
    let deviceId: String
    let onError: (Error) -> Void
    var syncManager: SyncManager?

    private var reminderService: ReminderService {
        ReminderService(
            modelContext: modelContext,
            userId: userId,
            deviceId: deviceId
        )
    }

    private var notificationService: NotificationService {
        NotificationService(modelContext: modelContext)
    }

    /// Snoozes a reminder until the specified date.
    /// Cancels existing notification and schedules a new one.
    func snooze(_ reminder: Reminder, until date: Date) {
        do {
            // Cancel existing notification
            Task {
                await notificationService.cancelNotification(for: reminder)
            }

            // Snooze the reminder
            try reminderService.snoozeReminder(reminder, until: date)

            // Trigger immediate sync
            syncManager?.triggerImmediatePush()

            // Schedule new notification and update badge
            Task {
                try? await notificationService.scheduleNotification(for: reminder)
                await notificationService.updateAppBadge()
            }
        } catch {
            onError(error)
        }
    }

    /// Deletes a reminder and cancels its notification.
    func delete(_ reminder: Reminder) {
        do {
            // Cancel notification
            Task {
                await notificationService.cancelNotification(for: reminder)
            }

            try reminderService.deleteReminder(reminder)

            // Trigger immediate sync
            syncManager?.triggerImmediatePush()

            // Update app badge
            Task {
                await notificationService.updateAppBadge()
            }
        } catch {
            onError(error)
        }
    }

    /// Dismisses an overdue reminder, marking it as handled.
    /// This removes it from the active/overdue list without deleting it.
    func dismiss(_ reminder: Reminder) {
        do {
            // Cancel notification (if any)
            Task {
                await notificationService.cancelNotification(for: reminder)
            }

            try reminderService.dismissReminder(reminder)

            // Trigger immediate sync
            syncManager?.triggerImmediatePush()

            // Update app badge
            Task {
                await notificationService.updateAppBadge()
            }
        } catch {
            onError(error)
        }
    }
}
