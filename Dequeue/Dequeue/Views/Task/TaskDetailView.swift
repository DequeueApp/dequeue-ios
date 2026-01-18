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
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService
    @Environment(\.attachmentUploadCoordinator) var attachmentUploadCoordinator

    @Bindable var task: QueueTask

    @State private var taskService: TaskService?
    @State private var notificationService: NotificationService?
    @State private var reminderActionHandler: ReminderActionHandler?
    @State var attachmentService: AttachmentService?
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var isEditingDescription = false
    @State private var editedDescription = ""
    @State private var showCloseConfirmation = false
    @State private var showDeleteConfirmation = false
    @State var showAttachmentPicker = false
    @State private var attachmentPickerError: AttachmentPickerError?
    @State var showError = false
    @State var errorMessage = ""
    @State private var showAddReminder = false
    @State private var showSnoozePicker = false
    @State private var selectedReminderForSnooze: Reminder?
    @State private var showEditReminder = false
    @State private var selectedReminderForEdit: Reminder?
    @State private var showDeleteReminderConfirmation = false
    @State private var reminderToDelete: Reminder?

    var body: some View {
        List {
            statusSection

            titleSection

            descriptionSection

            remindersSection

            attachmentsSection

            actionsSection

            detailsSection

            eventHistorySection
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
        .navigationTitle("Task Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard taskService == nil else { return }
            let deviceId = await DeviceService.shared.getDeviceId()
            let userId = authService.currentUserId ?? ""
            taskService = TaskService(
                modelContext: modelContext,
                userId: userId,
                deviceId: deviceId,
                syncManager: syncManager
            )
            notificationService = NotificationService(modelContext: modelContext)
            reminderActionHandler = ReminderActionHandler(
                modelContext: modelContext,
                userId: userId,
                deviceId: deviceId,
                onError: showError,
                syncManager: syncManager
            )
            attachmentService = AttachmentService(
                modelContext: modelContext,
                userId: userId,
                deviceId: deviceId,
                syncManager: syncManager
            )
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if task.status != .completed {
                    Button("Complete") {
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
        .sheet(isPresented: $showAddReminder) {
            if let service = notificationService {
                AddReminderSheet(parent: .task(task), notificationService: service)
            }
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
        .sheet(isPresented: $showEditReminder) {
            if let reminder = selectedReminderForEdit, let service = notificationService {
                AddReminderSheet(
                    parent: .task(task),
                    notificationService: service,
                    existingReminder: reminder
                )
            }
        }
        .confirmationDialog("Delete Reminder", isPresented: $showDeleteReminderConfirmation) {
            Button("Delete", role: .destructive) {
                if let reminder = reminderToDelete { reminderActionHandler?.delete(reminder) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this reminder?")
        }
        .attachmentPicker(
            isPresented: $showAttachmentPicker,
            onFilesSelected: handleFilesSelected,
            onError: { error in
                attachmentPickerError = error
                errorMessage = error.localizedDescription
                showError = true
            }
        )
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
                }
            } else {
                ForEach(task.activeReminders) { reminder in
                    ReminderRowView(
                        reminder: reminder,
                        onTap: {
                            selectedReminderForEdit = reminder
                            showEditReminder = true
                        },
                        onSnooze: {
                            selectedReminderForSnooze = reminder
                            showSnoozePicker = true
                        },
                        onDelete: {
                            reminderToDelete = reminder
                            showDeleteReminderConfirmation = true
                        }
                    )
                }
            }
        } header: {
            HStack {
                Text("Reminders")
                Spacer()
                Button {
                    showAddReminder = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .accessibilityIdentifier("addReminderButton")
            }
        }
    }

    private var actionsSection: some View {
        Section {
            if task.status == .pending && !isActiveTask {
                Button {
                    setTaskActive()
                } label: {
                    Label("Set as Active Task", systemImage: "star.fill")
                }
            }

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

    private var detailsSection: some View {
        Section {
            LabeledContent("Created", value: task.createdAt.smartFormatted())
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
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        do {
            try service.updateTask(task, title: editedTitle, description: task.taskDescription)
            isEditingTitle = false
        } catch {
            showError(error)
        }
    }

    private func saveDescription() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.updateTask(
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
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.markAsCompleted(task)
        } catch {
            showError(error)
        }
    }

    private func blockTask() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.markAsBlocked(task, reason: nil)
        } catch {
            showError(error)
        }
    }

    private func unblockTask() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.unblock(task)
        } catch {
            showError(error)
        }
    }

    private func setTaskActive() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.activateTask(task)
        } catch {
            showError(error)
        }
    }

    private func closeTask() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.closeTask(task)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func deleteTask() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.deleteTask(task)
            dismiss()
        } catch {
            showError(error)
        }
    }

    internal func showError(_ error: Error) {
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
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var showLoadError = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading history...")
            } else if events.isEmpty {
                ContentUnavailableView {
                    Label("No History", systemImage: "clock")
                } description: {
                    Text("No events recorded for this task")
                }
            } else {
                List {
                    ForEach(events) { event in
                        EventRowView(event: event)
                    }
                }
            }
        }
        .navigationTitle("Event History")
        #if os(macOS)
        // macOS sheets and navigation destinations need explicit frame sizing
        // to render correctly within NavigationStack contexts
        .frame(minWidth: 500, minHeight: 400)
        #endif
        // Use .task(id:) with updatedAt to:
        // 1. Load reliably on both iOS and macOS (onAppear is unreliable on macOS in sheets)
        // 2. Automatically refresh when the task is modified elsewhere
        .task(id: task.updatedAt) {
            await loadEvents()
        }
        .alert("Failed to Load History", isPresented: $showLoadError) {
            Button("Retry") {
                Task {
                    await loadEvents()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            if let error = loadError {
                Text(error.localizedDescription)
            }
        }
    }

    private func loadEvents() async {
        isLoading = true
        loadError = nil

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
            loadError = error
            showLoadError = true
            events = []
            ErrorReportingService.capture(error: error, context: ["view": "TaskHistoryView"])
        }
        isLoading = false
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
