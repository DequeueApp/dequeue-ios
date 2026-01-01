//
//  StackDetailView.swift
//  Dequeue
//
//  View and manage a stack with its tasks
//

import SwiftUI
import SwiftData

// swiftlint:disable:next type_body_length
struct StackDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var stack: Stack
    let isReadOnly: Bool

    init(stack: Stack, isReadOnly: Bool = false) {
        self.stack = stack
        self.isReadOnly = isReadOnly
    }

    @State private var isEditingDescription = false
    @State private var editedDescription = ""
    @State private var showCompletedTasks = false
    @State private var showCloseConfirmation = false
    @State private var showCompleteConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showAddTask = false
    @State private var newTaskTitle = ""
    @State private var newTaskDescription = ""
    @State private var showAddReminder = false
    @State private var showSnoozePicker = false
    @State private var selectedReminderForSnooze: Reminder?

    private var stackService: StackService {
        StackService(modelContext: modelContext)
    }

    private var taskService: TaskService {
        TaskService(modelContext: modelContext)
    }

    private var notificationService: NotificationService {
        NotificationService(modelContext: modelContext)
    }

    private var reminderActionHandler: ReminderActionHandler {
        ReminderActionHandler(modelContext: modelContext, onError: showError)
    }

    var body: some View {
        NavigationStack {
            List {
                descriptionSection

                pendingTasksSection

                if !stack.completedTasks.isEmpty {
                    completedTasksSection
                }

                remindersSection

                actionsSection

                eventHistorySection
            }
            .navigationTitle(stack.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showCompleteConfirmation = true
                        }
                        .fontWeight(.semibold)
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                "Complete Stack",
                isPresented: $showCompleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Complete All Tasks & Stack") {
                    completeStack(completeAllTasks: true)
                }
                Button("Complete Stack Only") {
                    completeStack(completeAllTasks: false)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if !stack.pendingTasks.isEmpty {
                    let taskCount = stack.pendingTasks.count
                    Text("This stack has \(taskCount) pending task(s). Would you like to complete them as well?")
                } else {
                    Text("Mark this stack as completed?")
                }
            }
            .confirmationDialog(
                "Close Stack",
                isPresented: $showCloseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Close Without Completing", role: .destructive) {
                    closeStack()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will close the stack without completing it. You can find it in completed stacks later.")
            }
            .sheet(isPresented: $showAddTask) {
                AddTaskSheet(
                    title: $newTaskTitle,
                    description: $newTaskDescription,
                    onSave: addTask,
                    onCancel: cancelAddTask
                )
            }
            .sheet(isPresented: $showAddReminder) {
                AddReminderSheet(parent: .stack(stack), notificationService: notificationService)
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
        }
    }

    // MARK: - Sections

    private var descriptionSection: some View {
        Section {
            descriptionContent
        } header: {
            Text("Description")
        }
    }

    @ViewBuilder
    private var descriptionContent: some View {
        if isReadOnly {
            if let description = stack.stackDescription, !description.isEmpty {
                Text(description).foregroundStyle(.primary)
            } else {
                Text("No description").foregroundStyle(.secondary)
            }
        } else if isEditingDescription {
            descriptionEditingView
        } else {
            descriptionDisplayButton
        }
    }

    private var descriptionEditingView: some View {
        Group {
            TextField("Description", text: $editedDescription, axis: .vertical)
                .lineLimit(3...6)
                .onSubmit { saveDescription() }

            HStack {
                Button("Cancel") {
                    isEditingDescription = false
                    editedDescription = stack.stackDescription ?? ""
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button("Save") { saveDescription() }
                    .fontWeight(.medium)
            }
        }
    }

    private var descriptionDisplayButton: some View {
        Button {
            editedDescription = stack.stackDescription ?? ""
            isEditingDescription = true
        } label: {
            HStack {
                if let description = stack.stackDescription, !description.isEmpty {
                    Text(description).foregroundStyle(.primary)
                } else {
                    Text("Add description...").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
        }
    }

    private var pendingTasksSection: some View {
        Section {
            if stack.pendingTasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks", systemImage: "checkmark.circle")
                } description: {
                    Text("All tasks completed!")
                }
                .listRowBackground(Color.clear)
            } else {
                taskListContent
            }
        } header: {
            HStack {
                Text("Tasks")
                Spacer()
                Text("\(stack.pendingTasks.count) pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !isReadOnly {
                    Button {
                        showAddTask = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .accessibilityIdentifier("addTaskButton")
                }
            }
        }
    }

    @ViewBuilder
    private var taskListContent: some View {
        let taskList = ForEach(stack.pendingTasks) { task in
            NavigationLink {
                TaskDetailView(task: task)
            } label: {
                taskRowContent(for: task)
            }
            .buttonStyle(.plain)
        }

        if isReadOnly {
            taskList
        } else {
            taskList.onMove(perform: moveTask)
        }
    }

    private var completedTasksSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showCompletedTasks) {
                ForEach(stack.completedTasks) { task in
                    NavigationLink {
                        TaskDetailView(task: task)
                    } label: {
                        CompletedTaskRowView(task: task)
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                HStack {
                    Text("Completed")
                    Spacer()
                    Text("\(stack.completedTasks.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var remindersSection: some View {
        Section {
            if stack.activeReminders.isEmpty {
                HStack {
                    Label("No reminders", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                remindersList
            }
        } header: {
            HStack {
                Text("Reminders")
                Spacer()
                if !isReadOnly {
                    Button {
                        showAddReminder = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .accessibilityIdentifier("addStackReminderButton")
                }
            }
        }
    }

    @ViewBuilder
    private var remindersList: some View {
        ForEach(stack.activeReminders) { reminder in
            ReminderRowView(
                reminder: reminder,
                onTap: isReadOnly ? nil : {
                    // TODO: DEQ-19 - Edit reminder
                },
                onSnooze: isReadOnly ? nil : {
                    selectedReminderForSnooze = reminder
                    showSnoozePicker = true
                },
                onDelete: isReadOnly ? nil : {
                    reminderActionHandler.delete(reminder)
                }
            )
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if !isReadOnly {
            Section {
                Button(role: .destructive) {
                    showCloseConfirmation = true
                } label: {
                    Label("Close Without Completing", systemImage: "xmark.circle")
                }
            }
        }
    }

    private var eventHistorySection: some View {
        Section {
            NavigationLink {
                StackHistoryView(stack: stack)
            } label: {
                Label("Event History", systemImage: "clock.arrow.circlepath")
            }
        } footer: {
            Text("View the complete history of changes to this stack")
        }
    }

    // MARK: - Helpers

    private func taskRowContent(for task: QueueTask) -> some View {
        TaskRowView(
            task: task,
            isActive: task.id == stack.activeTask?.id,
            onToggleComplete: isReadOnly ? nil : { toggleTaskComplete(task) },
            onSetActive: isReadOnly ? nil : { setTaskActive(task) }
        )
    }

    // MARK: - Actions

    private func saveDescription() {
        do {
            try stackService.updateStack(
                stack,
                title: stack.title,
                description: editedDescription.isEmpty ? nil : editedDescription
            )
            isEditingDescription = false
        } catch {
            showError(error)
        }
    }

    private func toggleTaskComplete(_ task: QueueTask) {
        do {
            if task.status == .completed {
                // swiftlint:disable:next todo
                // FIXME: Implement uncomplete if needed
            } else {
                try taskService.markAsCompleted(task)
            }
        } catch {
            showError(error)
        }
    }

    private func setTaskActive(_ task: QueueTask) {
        do {
            try taskService.activateTask(task)
        } catch {
            showError(error)
        }
    }

    private func moveTask(from source: IndexSet, to destination: Int) {
        var tasks = stack.pendingTasks
        tasks.move(fromOffsets: source, toOffset: destination)

        do {
            try taskService.updateSortOrders(tasks)
        } catch {
            showError(error)
        }
    }

    private func completeStack(completeAllTasks: Bool) {
        do {
            try stackService.markAsCompleted(stack, completeAllTasks: completeAllTasks)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func closeStack() {
        do {
            try stackService.closeStack(stack)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func addTask() {
        guard !newTaskTitle.isEmpty else { return }

        do {
            _ = try taskService.createTask(
                title: newTaskTitle,
                description: newTaskDescription.isEmpty ? nil : newTaskDescription,
                stack: stack
            )
            newTaskTitle = ""
            newTaskDescription = ""
            showAddTask = false
        } catch {
            showError(error)
        }
    }

    private func cancelAddTask() {
        newTaskTitle = ""
        newTaskDescription = ""
        showAddTask = false
    }

    private func deleteReminders(at offsets: IndexSet) {
        let remindersToDelete = offsets.map { stack.activeReminders[$0] }
        for reminder in remindersToDelete {
            reminderActionHandler.delete(reminder)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        ErrorReportingService.capture(error: error, context: ["view": "StackDetailView"])
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )

    let stack = Stack(
        title: "Test Stack",
        stackDescription: "This is a test description",
        status: .active,
        sortOrder: 0
    )
    container.mainContext.insert(stack)

    let task1 = QueueTask(title: "First task", taskDescription: "Do this first", status: .pending, sortOrder: 0)
    task1.stack = stack
    container.mainContext.insert(task1)

    let task2 = QueueTask(title: "Second task", status: .pending, sortOrder: 1)
    task2.stack = stack
    container.mainContext.insert(task2)

    let task3 = QueueTask(title: "Completed task", status: .completed, sortOrder: 2)
    task3.stack = stack
    container.mainContext.insert(task3)

    return StackDetailView(stack: stack)
        .modelContainer(container)
}
