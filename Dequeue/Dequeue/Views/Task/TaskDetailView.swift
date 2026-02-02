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
    @State var previewCoordinator = AttachmentPreviewCoordinator()

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
        .attachmentPreview(coordinator: previewCoordinator)
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

        Task {
            do {
                try await service.updateTask(task, title: editedTitle, description: task.taskDescription)
                isEditingTitle = false
            } catch {
                showError(error)
            }
        }
    }

    private func saveDescription() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.updateTask(
                    task,
                    title: task.title,
                    description: editedDescription.isEmpty ? nil : editedDescription
                )
                isEditingDescription = false
            } catch {
                showError(error)
            }
        }
    }

    private func completeTask() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.markAsCompleted(task)
                HapticManager.shared.success()
            } catch {
                showError(error)
            }
        }
    }

    private func blockTask() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.markAsBlocked(task, reason: nil)
            } catch {
                showError(error)
            }
        }
    }

    private func unblockTask() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.unblock(task)
            } catch {
                showError(error)
            }
        }
    }

    private func setTaskActive() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.activateTask(task)
            } catch {
                showError(error)
            }
        }
    }

    private func closeTask() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.closeTask(task)
                dismiss()
            } catch {
                showError(error)
            }
        }
    }

    private func deleteTask() {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.deleteTask(task)
                dismiss()
            } catch {
                showError(error)
            }
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
    @AppStorage("developerModeEnabled") private var developerModeEnabled = false

    @State private var events: [Event] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var showLoadError = false
    @State private var selectedEventForDetail: Event?

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
                historyList
            }
        }
        .navigationTitle("Event History")
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
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

    private var historyList: some View {
        List {
            ForEach(events) { event in
                TaskHistoryRow(event: event)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard developerModeEnabled else { return }
                        selectedEventForDetail = event
                    }
            }
        }
        .sheet(item: $selectedEventForDetail) { event in
            EventDetailTableView(event: event)
        }
    }

    private func loadEvents() async {
        isLoading = true
        loadError = nil

        let service = EventService.readOnly(modelContext: modelContext)
        do {
            events = try service.fetchTaskHistoryWithRelated(for: task)
        } catch {
            loadError = error
            showLoadError = true
            events = []
            ErrorReportingService.capture(error: error, context: ["view": "TaskHistoryView"])
        }
        isLoading = false
    }
}

// MARK: - Task History Row

private struct TaskHistoryRow: View {
    let event: Event

    private var actionLabel: String {
        switch event.type {
        case "task.created": return "Task Created"
        case "task.updated": return "Task Updated"
        case "task.completed": return "Task Completed"
        case "task.activated": return "Task Activated"
        case "task.deleted": return "Task Deleted"
        case "task.reordered": return "Tasks Reordered"
        case "reminder.created": return "Reminder Set"
        case "reminder.updated": return "Reminder Updated"
        case "reminder.deleted": return "Reminder Removed"
        case "reminder.snoozed": return "Reminder Snoozed"
        case "attachment.added": return "Attachment Added"
        case "attachment.removed": return "Attachment Removed"
        default: return event.type
        }
    }

    private var actionIcon: String {
        switch event.type {
        case "task.created": return "plus.circle.fill"
        case "task.updated": return "pencil.circle.fill"
        case "task.completed": return "checkmark.circle.fill"
        case "task.activated": return "star.fill"
        case "task.deleted": return "trash.circle.fill"
        case "task.reordered": return "arrow.up.arrow.down"
        case "reminder.created": return "bell.fill"
        case "reminder.updated": return "bell.badge"
        case "reminder.deleted": return "bell.slash"
        case "reminder.snoozed": return "moon.zzz.fill"
        case "attachment.added": return "paperclip.circle.fill"
        case "attachment.removed": return "paperclip.badge.ellipsis"
        default: return "questionmark.circle.fill"
        }
    }

    private var actionColor: Color {
        switch event.type {
        case "task.created": return .green
        case "task.updated": return .blue
        case "task.completed": return .purple
        case "task.activated": return .cyan
        case "task.deleted": return .red
        case "task.reordered": return .secondary
        case "reminder.created": return .yellow
        case "reminder.updated": return .yellow
        case "reminder.deleted": return .red
        case "reminder.snoozed": return .indigo
        case "attachment.added": return .mint
        case "attachment.removed": return .red
        default: return .secondary
        }
    }

    private var eventDetails: (title: String?, subtitle: String?)? {
        if event.type.hasPrefix("task."),
           let payload = try? event.decodePayload(TaskEventPayload.self) {
            return (payload.title, payload.description)
        }
        if event.type.hasPrefix("reminder."),
           let payload = try? event.decodePayload(ReminderEventPayload.self) {
            let dateStr = payload.remindAt.formatted(date: .abbreviated, time: .shortened)
            return ("Reminder for \(dateStr)", nil)
        }
        if event.type.hasPrefix("attachment."),
           let payload = try? event.decodePayload(AttachmentEventPayload.self) {
            return (payload.filename, payload.mimeType)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: actionIcon)
                .font(.title2)
                .foregroundStyle(actionColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(actionLabel)
                        .font(.headline)
                    Spacer()
                    Text(event.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let details = eventDetails {
                    if let title = details.title {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let subtitle = details.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
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
