//
//  TaskDetailView.swift
//  Dequeue
//
//  View and edit an individual task
//

// swiftlint:disable file_length

import SwiftUI
import SwiftData

// swiftlint:disable:next type_body_length
struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var task: QueueTask

    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var isEditingDescription = false
    @State private var editedDescription = ""
    @State private var showCloseConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var taskService: TaskService {
        TaskService(modelContext: modelContext)
    }

    var body: some View {
        List {
            statusSection

            titleSection

            descriptionSection

            remindersSection

            actionsSection

            eventHistorySection
        }
        .navigationTitle("Task Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if task.status != .completed {
                    Button("Done") {
                        completeTask()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "Close Task",
            isPresented: $showCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close Without Completing", role: .destructive) {
                closeTask()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will close the task without marking it as completed.")
        }
        .confirmationDialog(
            "Delete Task",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteTask()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                statusIcon
                    .font(.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.headline)

                    if let stack = task.stack {
                        Text("In: \(stack.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                statusBadge
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .blocked:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .closed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.gray)
        }
    }

    private var statusText: String {
        switch task.status {
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .blocked: return "Blocked"
        case .closed: return "Closed"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if task.status == .completed {
            Text("Completed")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        } else if task.status == .blocked {
            Text("Blocked")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        } else if isActiveTask {
            Text("Active")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        }
    }

    private var isActiveTask: Bool {
        task.stack?.activeTask?.id == task.id
    }

    private var titleSection: some View {
        Section {
            if isEditingTitle {
                TextField("Title", text: $editedTitle)
                    .onSubmit {
                        saveTitle()
                    }

                HStack {
                    Button("Cancel") {
                        isEditingTitle = false
                        editedTitle = task.title
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Save") {
                        saveTitle()
                    }
                    .fontWeight(.medium)
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button {
                    editedTitle = task.title
                    isEditingTitle = true
                } label: {
                    HStack {
                        Text(task.title)
                            .foregroundStyle(.primary)
                            .strikethrough(task.status == .completed)
                        Spacer()
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Title")
        }
    }

    private var descriptionSection: some View {
        Section {
            if isEditingDescription {
                TextField("Description", text: $editedDescription, axis: .vertical)
                    .lineLimit(3...6)

                HStack {
                    Button("Cancel") {
                        isEditingDescription = false
                        editedDescription = task.taskDescription ?? ""
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Save") {
                        saveDescription()
                    }
                    .fontWeight(.medium)
                }
            } else {
                Button {
                    editedDescription = task.taskDescription ?? ""
                    isEditingDescription = true
                } label: {
                    HStack {
                        if let description = task.taskDescription, !description.isEmpty {
                            Text(description)
                                .foregroundStyle(.primary)
                        } else {
                            Text("Add description...")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Description")
        }
    }

    private var remindersSection: some View {
        Section {
            if task.activeReminders.isEmpty {
                HStack {
                    Label("No reminders", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Spacer()
                    // swiftlint:disable:next todo
                    // FIXME: Add reminder button when ReminderService is implemented
                }
            } else {
                ForEach(task.activeReminders) { reminder in
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.orange)
                        Text(reminder.remindAt, style: .date)
                        Text(reminder.remindAt, style: .time)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Reminders")
        }
    }

    private var actionsSection: some View {
        Section {
            if task.status == .blocked {
                Button {
                    unblockTask()
                } label: {
                    Label("Unblock Task", systemImage: "play.circle")
                }
            } else if task.status == .pending {
                Button {
                    blockTask()
                } label: {
                    Label("Mark as Blocked", systemImage: "pause.circle")
                }
            }

            if task.status != .completed {
                Button(role: .destructive) {
                    showCloseConfirmation = true
                } label: {
                    Label("Close Without Completing", systemImage: "xmark.circle")
                }
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    private var eventHistorySection: some View {
        Section {
            NavigationLink {
                TaskHistoryView(task: task)
            } label: {
                Label("Event History", systemImage: "clock.arrow.circlepath")
            }
        } footer: {
            Text("View the complete history of changes to this task")
        }
    }

    // MARK: - Actions

    private func saveTitle() {
        guard !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            try taskService.updateTask(task, title: editedTitle, description: task.taskDescription)
            isEditingTitle = false
        } catch {
            showError(error)
        }
    }

    private func saveDescription() {
        do {
            try taskService.updateTask(
                task,
                title: task.title,
                description: editedDescription.isEmpty ? nil : editedDescription
            )
            isEditingDescription = false
        } catch {
            showError(error)
        }
    }

    private func completeTask() {
        do {
            try taskService.markAsCompleted(task)
        } catch {
            showError(error)
        }
    }

    private func blockTask() {
        do {
            try taskService.markAsBlocked(task, reason: nil)
        } catch {
            showError(error)
        }
    }

    private func unblockTask() {
        do {
            try taskService.unblock(task)
        } catch {
            showError(error)
        }
    }

    private func closeTask() {
        do {
            try taskService.closeTask(task)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func deleteTask() {
        do {
            try taskService.deleteTask(task)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        ErrorReportingService.capture(error: error, context: ["view": "TaskDetailView"])
    }
}

// MARK: - Task History View

struct TaskHistoryView: View {
    let task: QueueTask

    @Environment(\.modelContext) private var modelContext

    @State private var events: [Event] = []

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView {
                    Label("No History", systemImage: "clock")
                } description: {
                    Text("No events recorded for this task")
                }
            } else {
                ForEach(events) { event in
                    EventRowView(event: event)
                }
            }
        }
        .navigationTitle("Task History")
        .task {
            loadEvents()
        }
    }

    private func loadEvents() {
        let taskId = task.id
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate<Event> { event in
                event.entityId == taskId
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            events = try modelContext.fetch(descriptor)
        } catch {
            ErrorReportingService.capture(error: error, context: ["view": "TaskHistoryView"])
        }
    }
}

// MARK: - Event Row View

private struct EventRowView: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.type)
                    .font(.headline)
                    .foregroundStyle(colorForEventType)

                Spacer()

                if event.isSynced {
                    Image(systemName: "checkmark.icloud")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Text(event.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var colorForEventType: Color {
        if event.type.contains("created") {
            return .green
        } else if event.type.contains("completed") {
            return .blue
        } else if event.type.contains("deleted") || event.type.contains("closed") {
            return .red
        } else {
            return .primary
        }
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

    let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
    container.mainContext.insert(stack)

    let task = QueueTask(
        title: "Test Task",
        taskDescription: "This is a test task with a description",
        status: .pending,
        sortOrder: 0
    )
    task.stack = stack
    container.mainContext.insert(task)

    return NavigationStack {
        TaskDetailView(task: task)
    }
    .modelContainer(container)
}
