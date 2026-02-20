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
            deviceId: deviceId,
            syncManager: syncManager
        )
    }

    private var notificationService: NotificationService {
        NotificationService(modelContext: modelContext)
    }

    /// Snoozes a reminder until the specified date.
    /// Cancels existing notification and schedules a new one.
    func snooze(_ reminder: Reminder, until date: Date) {
        Task {
            do {
                // Cancel existing notification
                notificationService.cancelNotification(for: reminder)

                // Snooze the reminder
                try await reminderService.snoozeReminder(reminder, until: date)

                // Schedule new notification and update badge
                try? await notificationService.scheduleNotification(for: reminder)
                await notificationService.updateAppBadge()
            } catch {
                onError(error)
            }
        }
    }

    /// Deletes a reminder and cancels its notification.
    func delete(_ reminder: Reminder) {
        Task {
            do {
                // Cancel notification
                notificationService.cancelNotification(for: reminder)

                try await reminderService.deleteReminder(reminder)

                // Update app badge
                await notificationService.updateAppBadge()
            } catch {
                onError(error)
            }
        }
    }

    /// Dismisses an overdue reminder, marking it as handled.
    /// This removes it from the active/overdue list without deleting it.
    func dismiss(_ reminder: Reminder) {
        Task {
            do {
                // Cancel notification (if any)
                notificationService.cancelNotification(for: reminder)

                try await reminderService.dismissReminder(reminder)

                // Update app badge
                await notificationService.updateAppBadge()
            } catch {
                onError(error)
            }
        }
    }
}
