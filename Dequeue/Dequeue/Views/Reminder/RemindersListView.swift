//
//  RemindersListView.swift
//  Dequeue
//
//  Shows all upcoming and overdue reminders (DEQ-22)
//  Also shows items with start/due dates approaching
//

import SwiftUI
import SwiftData

/// Represents an item (Stack, Task, Arc) that has a scheduled date
struct DateScheduledItem: Identifiable {
    let id: String
    let title: String
    let date: Date
    let parentType: ParentType
    let isStartDate: Bool  // true = start date, false = due date
}

struct RemindersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService

    @Query private var reminders: [Reminder]
    @Query private var stacks: [Stack]
    @Query private var tasks: [QueueTask]
    @Query private var arcs: [Arc]

    @State private var reminderActionHandler: ReminderActionHandler?

    // Cached calendar instance for date comparisons
    private static let calendar = Calendar.current

    /// Callback when user wants to navigate to a Stack or Task
    /// Parameters: parentId, parentType
    var onGoToItem: ((String, ParentType) -> Void)?

    init(onGoToItem: ((String, ParentType) -> Void)? = nil) {
        self.onGoToItem = onGoToItem
        // Fetch active and snoozed reminders that aren't deleted
        _reminders = Query(
            filter: #Predicate<Reminder> { reminder in
                reminder.isDeleted == false
            },
            sort: \Reminder.remindAt
        )

        // Fetch all stacks, tasks, and arcs for parent title lookup
        _stacks = Query(filter: #Predicate<Stack> { !$0.isDeleted })
        _tasks = Query(filter: #Predicate<QueueTask> { !$0.isDeleted })
        _arcs = Query(filter: #Predicate<Arc> { !$0.isDeleted })
    }

    @State private var showSnoozePicker = false
    @State private var selectedReminderForSnooze: Reminder?
    @State private var showDeleteConfirmation = false
    @State private var reminderToDelete: Reminder?
    @State private var showError = false
    @State private var errorMessage = ""

    // MARK: - Filtered Reminders

    private var activeReminders: [Reminder] {
        return reminders.filter { $0.status == .active || $0.status == .snoozed }
    }

    private var overdueReminders: [Reminder] {
        return activeReminders
            .filter { $0.isPastDue && $0.status == .active }
            .sorted { $0.remindAt < $1.remindAt }
    }

    private var todayReminders: [Reminder] {
        return activeReminders
            .filter { !$0.isPastDue && Self.calendar.isDateInToday($0.remindAt) }
            .sorted { $0.remindAt < $1.remindAt }
    }

    private var upcomingReminders: [Reminder] {
        return activeReminders
            .filter { !$0.isPastDue && !Self.calendar.isDateInToday($0.remindAt) }
            .sorted { $0.remindAt < $1.remindAt }
    }

    private var snoozedReminders: [Reminder] {
        return activeReminders
            .filter { $0.status == .snoozed }
            .sorted { $0.remindAt < $1.remindAt }
    }

    /// Whether there are any items or reminders to show
    /// Note: startingSoonItems, dueSoonItems, overdueItems are defined in RemindersListView+DateItems.swift
    var hasAnyContent: Bool {
        !activeReminders.isEmpty ||
        !startingSoonItems.isEmpty ||
        !dueSoonItems.isEmpty ||
        !overdueItems.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if !hasAnyContent {
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
                            reminderActionHandler?.snooze(reminder, until: snoozeUntil)
                            selectedReminderForSnooze = nil
                        }
                    )
                }
            }
            .confirmationDialog("Delete Reminder", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let reminder = reminderToDelete {
                        reminderActionHandler?.delete(reminder)
                    }
                }
                Button("Cancel", role: .cancel) {
                    // Dismisses dialog automatically
                }
            } message: {
                Text("Are you sure you want to delete this reminder?")
            }
            .task {
                guard reminderActionHandler == nil else { return }
                let deviceId = await DeviceService.shared.getDeviceId()
                reminderActionHandler = ReminderActionHandler(
                    modelContext: modelContext,
                    userId: authService.currentUserId ?? "",
                    deviceId: deviceId,
                    onError: showError,
                    syncManager: syncManager
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing Scheduled",
            systemImage: "bell.slash",
            description: Text("No reminders or items with upcoming dates.\nAdd dates to your stacks, tasks, or arcs.")
        )
    }

    // MARK: - Reminders List

    private var remindersList: some View {
        List {
            // Overdue items section (items past their due date)
            if !overdueItems.isEmpty {
                overdueItemsSection
            }

            // Overdue reminders section
            if !overdueReminders.isEmpty {
                overdueSection
            }

            // Due soon section (items due in next 48 hours)
            if !dueSoonItems.isEmpty {
                dueSoonSection
            }

            // Starting soon section (items starting in next 24 hours)
            if !startingSoonItems.isEmpty {
                startingSoonSection
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

    // MARK: - Reminder Sections
    // Note: Date-based item sections (overdueItemsSection, dueSoonSection, startingSoonSection)
    // are defined in RemindersListView+DateItems.swift

    private var overdueSection: some View {
        Section {
            ForEach(overdueReminders) { reminder in
                reminderRow(for: reminder)
            }
        } header: {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Overdue Reminders")
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
            onGoToItem: onGoToItem != nil ? {
                // Dismiss sheet first, then navigate
                dismiss()
                // Small delay to ensure sheet dismisses before navigation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onGoToItem?(reminder.parentId, reminder.parentType)
                }
            } : nil,
            onSnooze: reminder.status != .snoozed ? {
                selectedReminderForSnooze = reminder
                showSnoozePicker = true
            } : nil,
            onDismiss: reminder.isPastDue ? {
                reminderActionHandler?.dismiss(reminder)
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
        case .arc:
            return arcs.first { $0.id == reminder.parentId }?.title
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
