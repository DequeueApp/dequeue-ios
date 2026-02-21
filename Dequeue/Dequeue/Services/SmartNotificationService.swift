//
//  SmartNotificationService.swift
//  Dequeue
//
//  Automatic notification scheduling based on task due dates, overdue alerts,
//  and morning digest of today's tasks.
//

import Foundation
import SwiftData
import UserNotifications
import os

private let logger = Logger(subsystem: "com.dequeue", category: "SmartNotification")

// MARK: - Smart Notification Settings

/// User-configurable smart notification preferences
struct SmartNotificationSettings: Codable, Sendable {
    /// Whether to auto-schedule notifications for tasks with due dates
    var autoDueDateNotifications: Bool = true

    /// How far before the due date to notify (in minutes)
    var dueDateLeadTimeMinutes: Int = 30

    /// Whether to send a morning digest of today's tasks
    var morningDigestEnabled: Bool = true

    /// Hour for morning digest (0-23, default 8 AM)
    var morningDigestHour: Int = 8

    /// Minute for morning digest (0-59, default 0)
    var morningDigestMinute: Int = 0

    /// Whether to send overdue task alerts
    var overdueAlertsEnabled: Bool = true

    /// How often to remind about overdue tasks (in hours)
    var overdueAlertIntervalHours: Int = 4

    /// Whether to notify when tasks are about to become overdue (end of day)
    var endOfDayReminderEnabled: Bool = true

    /// Hour for end-of-day reminder (default 6 PM)
    var endOfDayReminderHour: Int = 18

    /// Maximum number of notifications per day
    var maxDailyNotifications: Int = 20

    static let `default` = SmartNotificationSettings()

    static let storageKey = "smartNotificationSettings"
}

// MARK: - Notification Identifiers

private enum SmartNotificationID {
    static let morningDigestPrefix = "smart-morning-digest-"
    static let dueDatePrefix = "smart-due-"
    static let overduePrefix = "smart-overdue-"
    static let endOfDayPrefix = "smart-eod-"

    static func dueDate(taskId: String) -> String {
        "\(dueDatePrefix)\(taskId)"
    }

    static func overdue(taskId: String) -> String {
        "\(overduePrefix)\(taskId)"
    }

    static func morningDigest(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(morningDigestPrefix)\(formatter.string(from: date))"
    }

    static func endOfDay(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(endOfDayPrefix)\(formatter.string(from: date))"
    }
}

// MARK: - Smart Notification Category

enum SmartNotificationCategory {
    static let dueDateCategory = "SMART_DUE_DATE_CATEGORY"
    static let digestCategory = "SMART_DIGEST_CATEGORY"
    static let overdueCategory = "SMART_OVERDUE_CATEGORY"

    enum Action {
        static let markComplete = "SMART_COMPLETE"
        static let snooze1Hour = "SMART_SNOOZE_1H"
        static let viewTask = "SMART_VIEW"
    }
}

// MARK: - Smart Notification Service

@MainActor
final class SmartNotificationService {
    private let modelContext: ModelContext
    nonisolated(unsafe) private let notificationCenter: NotificationCenterProtocol
    private let userDefaults: UserDefaults

    /// Current settings (cached in memory for fast reads)
    private(set) var settings: SmartNotificationSettings

    init(
        modelContext: ModelContext,
        notificationCenter: NotificationCenterProtocol = UNUserNotificationCenter.current(),
        userDefaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults

        // Load saved settings
        if let data = userDefaults.data(forKey: SmartNotificationSettings.storageKey),
           let saved = try? JSONDecoder().decode(SmartNotificationSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = .default
        }
    }

    // MARK: - Settings Management

    /// Updates and persists smart notification settings
    func updateSettings(_ newSettings: SmartNotificationSettings) {
        settings = newSettings
        if let data = try? JSONEncoder().encode(newSettings) {
            userDefaults.set(data, forKey: SmartNotificationSettings.storageKey)
        }
    }

    // MARK: - Configure Categories

    /// Registers smart notification action categories
    func configureCategories() {
        let completeAction = UNNotificationAction(
            identifier: SmartNotificationCategory.Action.markComplete,
            title: "Mark Complete",
            options: [.authenticationRequired]
        )

        let snoozeAction = UNNotificationAction(
            identifier: SmartNotificationCategory.Action.snooze1Hour,
            title: "Snooze 1h",
            options: []
        )

        let dueDateCategory = UNNotificationCategory(
            identifier: SmartNotificationCategory.dueDateCategory,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        let digestCategory = UNNotificationCategory(
            identifier: SmartNotificationCategory.digestCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let overdueCategory = UNNotificationCategory(
            identifier: SmartNotificationCategory.overdueCategory,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([
            dueDateCategory, digestCategory, overdueCategory
        ])
    }

    // MARK: - Task Due Date Auto-Scheduling

    /// Called when a task's due date changes. Auto-schedules a notification.
    func handleTaskDueDateChanged(_ task: QueueTask) async {
        guard settings.autoDueDateNotifications else { return }

        // Cancel any existing due-date notification for this task
        let notifId = SmartNotificationID.dueDate(taskId: task.id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifId])

        // Don't schedule if task is completed/deleted or has no due date
        guard task.status != .completed,
              !task.isDeleted,
              let dueTime = task.dueTime else {
            return
        }

        // Calculate notification time (due date minus lead time)
        let leadTime = TimeInterval(settings.dueDateLeadTimeMinutes * 60)
        let notifyAt = dueTime.addingTimeInterval(-leadTime)

        // Don't schedule for past dates
        guard notifyAt > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Task Due Soon"
        content.body = formatDueDateBody(task: task, dueTime: dueTime)
        content.sound = .default
        content.categoryIdentifier = SmartNotificationCategory.dueDateCategory
        content.userInfo = [
            "type": "smart-due-date",
            "taskId": task.id
        ]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: notifyAt
            ),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notifId,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            logger.debug("Scheduled due-date notification for task '\(task.title)' at \(notifyAt)")
        } catch {
            logger.error("Failed to schedule due-date notification: \(error)")
        }
    }

    /// Called when a task is completed or deleted. Cancels its due-date notification.
    func cancelTaskNotification(_ taskId: String) {
        let ids = [
            SmartNotificationID.dueDate(taskId: taskId),
            SmartNotificationID.overdue(taskId: taskId)
        ]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Morning Digest

    /// Schedules the morning digest notification for tomorrow
    func scheduleMorningDigest() async {
        guard settings.morningDigestEnabled else { return }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let notifId = SmartNotificationID.morningDigest(date: tomorrow)

        // Cancel existing digest for tomorrow
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifId])

        // Count tasks due tomorrow
        let tasksDueTomorrow = fetchTasksDueOn(date: tomorrow)
        let overdueTasks = fetchOverdueTasks()

        guard !tasksDueTomorrow.isEmpty || !overdueTasks.isEmpty else {
            logger.debug("No tasks for tomorrow's digest — skipping")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "☀️ Today's Tasks"
        content.body = formatMorningDigest(
            dueTasks: tasksDueTomorrow,
            overdueTasks: overdueTasks
        )
        content.sound = .default
        content.categoryIdentifier = SmartNotificationCategory.digestCategory
        content.userInfo = ["type": "smart-morning-digest"]

        var dateComponents = DateComponents()
        dateComponents.hour = settings.morningDigestHour
        dateComponents.minute = settings.morningDigestMinute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notifId,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            logger.debug("Scheduled morning digest for tomorrow")
        } catch {
            logger.error("Failed to schedule morning digest: \(error)")
        }
    }

    // MARK: - End-of-Day Reminder

    /// Schedules an end-of-day reminder for incomplete tasks
    func scheduleEndOfDayReminder() async {
        guard settings.endOfDayReminderEnabled else { return }

        let today = Date()
        let notifId = SmartNotificationID.endOfDay(date: today)

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifId])

        // Check if there are tasks due today that aren't completed
        let tasksDueToday = fetchTasksDueOn(date: today)
            .filter { $0.status != .completed }

        guard !tasksDueToday.isEmpty else { return }

        // Schedule for this evening
        var dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: today
        )
        dateComponents.hour = settings.endOfDayReminderHour
        dateComponents.minute = 0

        guard let eodDate = Calendar.current.date(from: dateComponents),
              eodDate > Date() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "🌙 End of Day Check"
        content.body = formatEndOfDayBody(tasks: tasksDueToday)
        content.sound = .default
        content.categoryIdentifier = SmartNotificationCategory.digestCategory
        content.userInfo = ["type": "smart-end-of-day"]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notifId,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            logger.debug("Scheduled end-of-day reminder with \(tasksDueToday.count) tasks")
        } catch {
            logger.error("Failed to schedule end-of-day reminder: \(error)")
        }
    }

    // MARK: - Overdue Alerts

    /// Schedules overdue alerts for tasks past their due date
    func scheduleOverdueAlerts() async {
        guard settings.overdueAlertsEnabled else { return }

        let overdueTasks = fetchOverdueTasks()
        guard !overdueTasks.isEmpty else { return }

        // Limit to max daily notifications
        let tasksToNotify = Array(overdueTasks.prefix(settings.maxDailyNotifications))

        for task in tasksToNotify {
            let notifId = SmartNotificationID.overdue(taskId: task.id)

            let content = UNMutableNotificationContent()
            content.title = "⚠️ Overdue Task"
            content.body = "\"\(task.title)\" was due \(formatRelativeTime(task.dueTime ?? Date()))"
            content.sound = .default
            content.categoryIdentifier = SmartNotificationCategory.overdueCategory
            content.userInfo = [
                "type": "smart-overdue",
                "taskId": task.id
            ]

            // Schedule for now + small delay
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 1,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: notifId,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
            } catch {
                logger.error("Failed to schedule overdue alert for '\(task.title)': \(error)")
            }
        }

        if !tasksToNotify.isEmpty {
            logger.debug("Scheduled \(tasksToNotify.count) overdue alerts")
        }
    }

    // MARK: - Full Refresh

    /// Refreshes all smart notifications (call on app launch, after sync, etc.)
    func refreshAllNotifications() async {
        // Remove all smart notifications
        let pending = await notificationCenter.pendingNotificationRequests()
        let smartIds = pending
            .filter { request in
                request.identifier.hasPrefix(SmartNotificationID.dueDatePrefix) ||
                request.identifier.hasPrefix(SmartNotificationID.overduePrefix) ||
                request.identifier.hasPrefix(SmartNotificationID.morningDigestPrefix) ||
                request.identifier.hasPrefix(SmartNotificationID.endOfDayPrefix)
            }
            .map(\.identifier)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: smartIds)

        // Re-schedule all due date notifications
        let upcomingTasks = fetchTasksWithUpcomingDueDates()
        let limit = settings.maxDailyNotifications
        for task in upcomingTasks.prefix(limit) {
            await handleTaskDueDateChanged(task)
        }

        // Schedule digest and EOD
        await scheduleMorningDigest()
        await scheduleEndOfDayReminder()

        logger.info("Refreshed smart notifications: \(upcomingTasks.count) due-date tasks")
    }

    // MARK: - Query Helpers

    /// Fetches tasks due on a specific date (any time that day)
    func fetchTasksDueOn(date: Date) -> [QueueTask] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let predicate = #Predicate<QueueTask> { task in
            task.isDeleted == false &&
            task.dueTime != nil
        }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)

        do {
            return try modelContext.fetch(descriptor)
                .filter { task in
                    guard let due = task.dueTime else { return false }
                    return due >= startOfDay && due < endOfDay
                }
        } catch {
            logger.error("Failed to fetch tasks due on \(date): \(error)")
            return []
        }
    }

    /// Fetches tasks that are overdue (due date in the past, not completed)
    func fetchOverdueTasks() -> [QueueTask] {
        let now = Date()
        let predicate = #Predicate<QueueTask> { task in
            task.isDeleted == false &&
            task.dueTime != nil
        }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)

        do {
            return try modelContext.fetch(descriptor)
                .filter { task in
                    guard let due = task.dueTime else { return false }
                    return due < now && task.status != .completed
                }
                .sorted { ($0.dueTime ?? .distantPast) < ($1.dueTime ?? .distantPast) }
        } catch {
            logger.error("Failed to fetch overdue tasks: \(error)")
            return []
        }
    }

    /// Fetches tasks with due dates in the next 7 days
    func fetchTasksWithUpcomingDueDates() -> [QueueTask] {
        let now = Date()
        guard let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now) else {
            return []
        }

        let predicate = #Predicate<QueueTask> { task in
            task.isDeleted == false &&
            task.dueTime != nil
        }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)

        do {
            return try modelContext.fetch(descriptor)
                .filter { task in
                    guard let due = task.dueTime else { return false }
                    return due > now && due <= weekFromNow && task.status != .completed
                }
                .sorted { ($0.dueTime ?? .distantFuture) < ($1.dueTime ?? .distantFuture) }
        } catch {
            logger.error("Failed to fetch upcoming tasks: \(error)")
            return []
        }
    }

    // MARK: - Formatting

    private func formatDueDateBody(task: QueueTask, dueTime: Date) -> String {
        let timeStr = dueTime.formatted(date: .omitted, time: .shortened)
        if let stackTitle = task.stack?.title {
            return "\"\(task.title)\" in \(stackTitle) — due at \(timeStr)"
        }
        return "\"\(task.title)\" — due at \(timeStr)"
    }

    private func formatMorningDigest(dueTasks: [QueueTask], overdueTasks: [QueueTask]) -> String {
        var parts: [String] = []

        if !dueTasks.isEmpty {
            parts.append("\(dueTasks.count) task\(dueTasks.count == 1 ? "" : "s") due today")
            let titles = dueTasks.prefix(3).map { "• \($0.title)" }
            parts.append(contentsOf: titles)
            if dueTasks.count > 3 {
                parts.append("  + \(dueTasks.count - 3) more")
            }
        }

        if !overdueTasks.isEmpty {
            parts.append("⚠️ \(overdueTasks.count) overdue task\(overdueTasks.count == 1 ? "" : "s")")
        }

        return parts.joined(separator: "\n")
    }

    private func formatEndOfDayBody(tasks: [QueueTask]) -> String {
        let count = tasks.count
        let titles = tasks.prefix(3).map { "• \($0.title)" }.joined(separator: "\n")
        var body = "You have \(count) task\(count == 1 ? "" : "s") still due today:\n\(titles)"
        if count > 3 {
            body += "\n+ \(count - 3) more"
        }
        return body
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
