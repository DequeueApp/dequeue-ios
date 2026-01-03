//
//  RemindersListView.swift
//  Dequeue
//
//  Shows all upcoming and overdue reminders (DEQ-22)
//

import SwiftUI
import SwiftData

struct RemindersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var reminders: [Reminder]
    @Query private var stacks: [Stack]
    @Query private var tasks: [QueueTask]

    init() {
        // Fetch active and snoozed reminders that aren't deleted
        _reminders = Query(
            filter: #Predicate<Reminder> { reminder in
                reminder.isDeleted == false
            },
            sort: \Reminder.remindAt
        )

        // Fetch all stacks and tasks for parent title lookup
        _stacks = Query(filter: #Predicate<Stack> { !$0.isDeleted })
        _tasks = Query(filter: #Predicate<QueueTask> { !$0.isDeleted })
    }

    @State private var showSnoozePicker = false
    @State private var selectedReminderForSnooze: Reminder?
    @State private var showDeleteConfirmation = false
    @State private var reminderToDelete: Reminder?
    @State private var showError = false
    @State private var errorMessage = ""

    private var reminderActionHandler: ReminderActionHandler {
        ReminderActionHandler(modelContext: modelContext, onError: showError)
    }

    // MARK: - Filtered Reminders

    private var activeReminders: [Reminder] {
        reminders.filter { $0.status == .active || $0.status == .snoozed }
    }

    private var overdueReminders: [Reminder] {
        return activeReminders
            .filter { $0.isPastDue && $0.status == .active }
            .sorted { $0.remindAt < $1.remindAt }
    }

    private var todayReminders: [Reminder] {
        let calendar = Calendar.current
        return activeReminders
            .filter { !$0.isPastDue && calendar.isDateInToday($0.remindAt) }
            .sorted { $0.remindAt < $1.remindAt }
    }

    private var upcomingReminders: [Reminder] {
        let calendar = Calendar.current
        return activeReminders
            .filter { !$0.isPastDue && !calendar.isDateInToday($0.remindAt) }
            .sorted { $0.remindAt < $1.remindAt }
    }

    private var snoozedReminders: [Reminder] {
        return activeReminders
            .filter { $0.status == .snoozed }
            .sorted { $0.remindAt < $1.remindAt }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if activeReminders.isEmpty {
                    emptyState
                } else {
                    remindersList
                }
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 300)
            #endif
            .navigationTitle("Reminders")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    // Dismisses alert automatically
                }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showSnoozePicker) {
                if let reminder = selectedReminderForSnooze {
                    SnoozePickerSheet(
                        isPresented: $showSnoozePicker,
                        reminder: reminder,
                        onSnooze: { snoozeUntil in
                            reminderActionHandler.snooze(reminder, until: snoozeUntil)
                            selectedReminderForSnooze = nil
                        }
                    )
                }
            }
            .confirmationDialog("Delete Reminder", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let reminder = reminderToDelete {
                        reminderActionHandler.delete(reminder)
                    }
                }
                Button("Cancel", role: .cancel) {
                    // Dismisses dialog automatically
                }
            } message: {
                Text("Are you sure you want to delete this reminder?")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Reminders",
            systemImage: "bell.slash",
            description: Text("You don't have any active reminders.\nAdd reminders from tasks or stacks.")
        )
    }

    // MARK: - Reminders List

    private var remindersList: some View {
        List {
            if !overdueReminders.isEmpty {
                overdueSection
            }

            if !todayReminders.isEmpty {
                todaySection
            }

            if !snoozedReminders.isEmpty {
                snoozedSection
            }

            if !upcomingReminders.isEmpty {
                upcomingSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private var overdueSection: some View {
        Section {
            ForEach(overdueReminders) { reminder in
                reminderRow(for: reminder)
            }
        } header: {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Overdue")
            }
        }
    }

    private var todaySection: some View {
        Section {
            ForEach(todayReminders) { reminder in
                reminderRow(for: reminder)
            }
        } header: {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                Text("Today")
            }
        }
    }

    private var snoozedSection: some View {
        Section {
            ForEach(snoozedReminders) { reminder in
                reminderRow(for: reminder)
            }
        } header: {
            HStack {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.purple)
                Text("Snoozed")
            }
        }
    }

    private var upcomingSection: some View {
        Section {
            ForEach(upcomingReminders) { reminder in
                reminderRow(for: reminder)
            }
        } header: {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                Text("Upcoming")
            }
        }
    }

    // MARK: - Reminder Row

    private func reminderRow(for reminder: Reminder) -> some View {
        ReminderRowView(
            reminder: reminder,
            parentTitle: parentTitle(for: reminder),
            onTap: nil,
            onSnooze: reminder.status != .snoozed ? {
                selectedReminderForSnooze = reminder
                showSnoozePicker = true
            } : nil,
            onDismiss: reminder.isPastDue ? {
                reminderActionHandler.dismiss(reminder)
            } : nil,
            onDelete: {
                reminderToDelete = reminder
                showDeleteConfirmation = true
            }
        )
    }

    // MARK: - Helpers

    private func parentTitle(for reminder: Reminder) -> String? {
        switch reminder.parentType {
        case .stack:
            return stacks.first { $0.id == reminder.parentId }?.title
        case .task:
            return tasks.first { $0.id == reminder.parentId }?.title
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        ErrorReportingService.capture(error: error, context: ["view": "RemindersListView"])
    }
}

// MARK: - Preview

#Preview("With Reminders") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )

    // Create test data
    let stack = Stack(title: "Project Planning", status: .active, sortOrder: 0)
    container.mainContext.insert(stack)

    let task = QueueTask(title: "Review PR", status: .pending, sortOrder: 0)
    task.stack = stack
    container.mainContext.insert(task)

    // Overdue reminder
    let overdueReminder = Reminder(
        parentId: task.id,
        parentType: .task,
        remindAt: Date().addingTimeInterval(-3_600)
    )
    container.mainContext.insert(overdueReminder)

    // Today reminder
    let todayReminder = Reminder(
        parentId: stack.id,
        parentType: .stack,
        remindAt: Date().addingTimeInterval(3_600)
    )
    container.mainContext.insert(todayReminder)

    // Snoozed reminder
    let snoozedReminder = Reminder(
        parentId: task.id,
        parentType: .task,
        status: .snoozed,
        snoozedFrom: Date().addingTimeInterval(-1_800),
        remindAt: Date().addingTimeInterval(1_800)
    )
    container.mainContext.insert(snoozedReminder)

    // Upcoming reminder
    let upcomingReminder = Reminder(
        parentId: stack.id,
        parentType: .stack,
        remindAt: Date().addingTimeInterval(86_400 * 2)
    )
    container.mainContext.insert(upcomingReminder)

    return RemindersListView()
        .modelContainer(container)
}

#Preview("Empty State") {
    RemindersListView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
