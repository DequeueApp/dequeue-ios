//
//  ReminderRowView.swift
//  Dequeue
//
//  Reusable row component for displaying reminders in lists (DEQ-17)
//

import SwiftUI
import SwiftData

struct ReminderRowView: View {
    let reminder: Reminder
    var parentTitle: String?
    var onTap: (() -> Void)?
    var onGoToItem: (() -> Void)?
    var onSnooze: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            // Dismiss action for overdue reminders
            if let onDismiss, reminder.isPastDue {
                Button {
                    onDismiss()
                } label: {
                    Label("Dismiss", systemImage: "checkmark.circle")
                }
                .tint(.green)
            }
            // Snooze also available on trailing for discoverability
            if let onSnooze, reminder.status != .snoozed {
                Button {
                    onSnooze()
                } label: {
                    Label("Snooze", systemImage: "clock")
                }
                .tint(.orange)
            }
            // Go to parent item (Stack or Task)
            if let onGoToItem {
                Button {
                    onGoToItem()
                } label: {
                    Label(
                        reminder.parentType == .task ? "Go to Task" : "Go to Stack",
                        systemImage: reminder.parentType == .task ? "doc.text" : "square.stack.3d.up"
                    )
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let onSnooze, reminder.status != .snoozed {
                Button {
                    onSnooze()
                } label: {
                    Label("Snooze", systemImage: "clock.badge.questionmark")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            // Go to parent item - primary action
            if let onGoToItem {
                Button {
                    onGoToItem()
                } label: {
                    Label(
                        reminder.parentType == .task ? "Go to Task" : "Go to Stack",
                        systemImage: reminder.parentType == .task ? "doc.text" : "square.stack.3d.up"
                    )
                }
            }
            if let onSnooze, reminder.status != .snoozed {
                Button {
                    onSnooze()
                } label: {
                    Label("Snooze", systemImage: "clock")
                }
            }
            if let onDismiss, reminder.isPastDue {
                Button {
                    onDismiss()
                } label: {
                    Label("Dismiss", systemImage: "checkmark.circle")
                }
            }
            if let onTap {
                Button {
                    onTap()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if let onDelete {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Row Content

    private var rowContent: some View {
        HStack(spacing: 12) {
            reminderIcon
            reminderInfo
            Spacer()
            statusBadge
        }
        .padding(.vertical, 4)
    }

    private var reminderIcon: some View {
        Image(systemName: iconName)
            .font(.title2)
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        switch reminder.status {
        case .snoozed:
            return "bell.badge.clock"
        case .fired:
            return "bell.badge.checkmark"
        case .active:
            return reminder.isPastDue ? "bell.badge.exclamationmark" : "bell.fill"
        }
    }

    private var iconColor: Color {
        switch reminder.status {
        case .snoozed:
            return .purple
        case .fired:
            return .gray
        case .active:
            return reminder.isPastDue ? .red : .orange
        }
    }

    // MARK: - Reminder Info

    private var reminderInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            timeDisplay
            if let parentTitle, !parentTitle.isEmpty {
                parentDisplay(title: parentTitle)
            }
        }
    }

    private var timeDisplay: some View {
        HStack(spacing: 4) {
            Text(formattedDate)
                .fontWeight(reminder.isPastDue ? .semibold : .regular)
                .foregroundStyle(reminder.isPastDue ? .red : .primary)

            Text(formattedTime)
                .foregroundStyle(reminder.isPastDue ? .red.opacity(0.8) : .secondary)
        }
    }

    private func parentDisplay(title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: reminder.parentType == .task ? "doc.text" : "square.stack.3d.up")
                .font(.caption2)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        if reminder.status == .snoozed {
            StatusBadge(text: "Snoozed", color: .purple)
        } else if reminder.isPastDue {
            StatusBadge(text: "Overdue", color: .red)
        }
    }

    // MARK: - Formatting

    private var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(reminder.remindAt) {
            return "Today"
        } else if calendar.isDateInTomorrow(reminder.remindAt) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(reminder.remindAt) {
            return "Yesterday"
        } else {
            return reminder.remindAt.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private var formattedTime: String {
        reminder.remindAt.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts: [String] = []

        // Status
        if reminder.status == .snoozed {
            parts.append("Snoozed reminder")
        } else if reminder.isPastDue {
            parts.append("Overdue reminder")
        } else {
            parts.append("Reminder")
        }

        // Time
        parts.append("scheduled for \(formattedDate) at \(formattedTime)")

        // Parent
        if let parentTitle, !parentTitle.isEmpty {
            let typeLabel = reminder.parentType == .task ? "task" : "stack"
            parts.append("for \(typeLabel) \(parentTitle)")
        }

        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        var hints: [String] = []

        if onTap != nil {
            hints.append("Double tap to edit")
        }
        if onGoToItem != nil {
            let itemType = reminder.parentType == .task ? "task" : "stack"
            hints.append("Swipe left to go to \(itemType)")
        }
        if onSnooze != nil && reminder.status != .snoozed {
            hints.append("Swipe right to snooze")
        }
        if onDismiss != nil && reminder.isPastDue {
            hints.append("Swipe left to dismiss")
        }
        if onDelete != nil {
            hints.append("Swipe left to delete")
        }

        return hints.joined(separator: ". ")
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("Active Reminder") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )

    let reminder = Reminder(
        parentId: "test-stack",
        parentType: .stack,
        remindAt: Date().addingTimeInterval(3_600)
    )
    container.mainContext.insert(reminder)

    return List {
        ReminderRowView(
            reminder: reminder,
            parentTitle: "My Important Stack",
            onTap: {},
            onSnooze: {},
            onDelete: {}
        )
    }
    .modelContainer(container)
}

#Preview("Overdue Reminder") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )

    let reminder = Reminder(
        parentId: "test-task",
        parentType: .task,
        remindAt: Date().addingTimeInterval(-3_600)
    )
    container.mainContext.insert(reminder)

    return List {
        ReminderRowView(
            reminder: reminder,
            parentTitle: "Review pull request",
            onTap: {},
            onSnooze: {},
            onDelete: {}
        )
    }
    .modelContainer(container)
}

#Preview("Snoozed Reminder") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )

    let reminder = Reminder(
        parentId: "test-task",
        parentType: .task,
        status: .snoozed,
        snoozedFrom: Date().addingTimeInterval(-1_800),
        remindAt: Date().addingTimeInterval(1_800)
    )
    container.mainContext.insert(reminder)

    return List {
        ReminderRowView(
            reminder: reminder,
            parentTitle: "Follow up on email",
            onTap: {},
            onDelete: {}
        )
    }
    .modelContainer(container)
}

#Preview("Multiple Reminders") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )

    let upcomingReminder = Reminder(
        parentId: "stack-1",
        parentType: .stack,
        remindAt: Date().addingTimeInterval(7_200)
    )
    container.mainContext.insert(upcomingReminder)

    let overdueReminder = Reminder(
        parentId: "task-1",
        parentType: .task,
        remindAt: Date().addingTimeInterval(-3_600)
    )
    container.mainContext.insert(overdueReminder)

    let snoozedReminder = Reminder(
        parentId: "task-2",
        parentType: .task,
        status: .snoozed,
        remindAt: Date().addingTimeInterval(1_800)
    )
    container.mainContext.insert(snoozedReminder)

    return List {
        Section("Upcoming") {
            ReminderRowView(
                reminder: upcomingReminder,
                parentTitle: "Project Planning",
                onTap: {},
                onSnooze: {},
                onDelete: {}
            )
        }

        Section("Overdue") {
            ReminderRowView(
                reminder: overdueReminder,
                parentTitle: "Submit report",
                onTap: {},
                onSnooze: {},
                onDelete: {}
            )
        }

        Section("Snoozed") {
            ReminderRowView(
                reminder: snoozedReminder,
                parentTitle: "Call client",
                onTap: {},
                onDelete: {}
            )
        }
    }
    .modelContainer(container)
}
