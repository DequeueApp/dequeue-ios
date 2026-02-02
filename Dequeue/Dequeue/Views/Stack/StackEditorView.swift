//
//  StackEditorView.swift
//  Dequeue
//
//  Unified view for creating and editing stacks (DEQ-99)
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "StackEditorView")

struct StackEditorView: View {
    enum Mode: Equatable {
        case create
        case edit(Stack)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create):
                return true
            case let (.edit(stack1), .edit(stack2)):
                return stack1.id == stack2.id
            default:
                return false
            }
        }
    }

    /// Fields that can receive focus in create mode.
    /// Used with @FocusState to detect blur events and trigger auto-save.
    enum EditorField: Hashable {
        /// The stack title text field
        case title
        /// The stack description text field
        case description
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.syncManager) var syncManager
    @Environment(\.authService) var authService
    @Environment(\.undoCompletionManager) var undoCompletionManager
    @Environment(\.attachmentUploadCoordinator) var attachmentUploadCoordinator
    @State var stackService: StackService?
    @State var taskService: TaskService?
    @State var arcService: ArcService?
    @State var notificationService: NotificationService?
    @State var reminderActionHandler: ReminderActionHandler?
    @State var tagService: TagService?
    @State var attachmentService: AttachmentService?

    /// All available tags for autocomplete suggestions
    @Query(filter: #Predicate<Tag> { !$0.isDeleted }, sort: \.name)
    var allTags: [Tag]

    let mode: Mode
    let isReadOnly: Bool

    init(mode: Mode, isReadOnly: Bool = false) {
        self.mode = mode
        self.isReadOnly = isReadOnly
    }

    // MARK: - State (internal for extensions)

    // Create mode state
    @State var title: String = ""
    @State var stackDescription: String = ""
    @State var selectedStartDate: Date?
    @State var selectedDueDate: Date?
    @State var pendingTasks: [PendingTask] = []
    @State var selectedTags: [Tag] = []
    @State var selectedArc: Arc?
    @State var draftStack: Stack?
    @State var isCreatingDraft = false
    @State var showDiscardAlert = false
    @State var showSaveDraftPrompt = false
    @State var showArcSelection = false
    @FocusState var focusedField: EditorField?

    // Pending task model for create mode
    // NOTE: Pending tasks are stored in @State and are NOT persisted to draft Stack.
    // If the app crashes or is backgrounded during creation, pending tasks will be lost
    // even though the draft Stack itself is auto-saved. This is acceptable for v1 since
    // Stack creation is typically a quick flow. Future improvement: persist to draft Stack.
    struct PendingTask: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var description: String?
        var startTime: Date?
        var dueTime: Date?
    }

    // Edit mode state
    @State var showEditTitleAlert = false
    @State var editedTitle = ""
    @State var isEditingDescription = false
    @State var editedDescription = ""
    @State var showCompletedTasks = false
    @State var showCompleteConfirmation = false
    @State var showCloseConfirmation = false
    @State var isTogglingActiveStatus = false
    // Task tracking for async operations that dismiss the view
    // Prevents race conditions when view is dismissed before task completes
    @State var activeStatusTask: Task<Void, Never>?

    // Shared state
    @State var showError = false
    @State var errorMessage = ""
    @State var showAttachmentPicker = false
    @State private var attachmentPickerError: AttachmentPickerError?
    @State var showAddTask = false
    @State var newTaskTitle = ""
    @State var newTaskDescription = ""
    @State var newTaskStartTime: Date?
    @State var newTaskDueTime: Date?
    @State var showAddReminder = false
    @State var showSnoozePicker = false
    @State var selectedReminderForSnooze: Reminder?
    @State var showEditReminder = false
    @State var selectedReminderForEdit: Reminder?
    @State var showDeleteReminderConfirmation = false
    @State var reminderToDelete: Reminder?
    @State var previewCoordinator = AttachmentPreviewCoordinator()
    @State var showArcPicker = false

    // MARK: - Computed Properties

    /// True if we're creating a new stack OR editing a draft (both use the simple form UI)
    var isCreateMode: Bool {
        switch mode {
        case .create:
            return true
        case .edit(let stack):
            // Drafts use the create-mode UI so users can continue editing and publish
            return stack.isDraft
        }
    }

    /// The current stack being worked on (draft for create, existing for edit)
    var currentStack: Stack? {
        switch mode {
        case .create:
            return draftStack
        case .edit(let stack):
            return stack
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isCreateMode {
                    createModeContent
                } else {
                    editModeContent
                }
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
            .navigationTitle(displayedTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .task {
                guard stackService == nil else { return }
                let deviceId = await DeviceService.shared.getDeviceId()
                let userId = authService.currentUserId ?? ""
                stackService = StackService(
                    modelContext: modelContext,
                    userId: userId,
                    deviceId: deviceId,
                    syncManager: syncManager
                )
                taskService = TaskService(
                    modelContext: modelContext,
                    userId: userId,
                    deviceId: deviceId,
                    syncManager: syncManager
                )
                arcService = ArcService(
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
                    onError: handleError,
                    syncManager: syncManager
                )
                tagService = TagService(
                    modelContext: modelContext,
                    userId: userId,
                    deviceId: deviceId,
                    syncManager: syncManager
                )
                attachmentService = AttachmentService(
                    modelContext: modelContext,
                    userId: userId,
                    deviceId: deviceId,
                    syncManager: syncManager
                )
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            // Sheets and dialogs
            .alert("Discard Draft?", isPresented: $showDiscardAlert) {
                Button("Keep Draft") { dismiss() }
                Button("Discard", role: .destructive) { discardDraftAndDismiss() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your draft has been auto-saved. Would you like to keep it or discard it?")
            }
            .alert("Save Draft?", isPresented: $showSaveDraftPrompt) {
                Button("Save Draft") {
                    createDraftAndDismiss()
                }
                Button("Discard", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have unsaved content. Would you like to save it as a draft?")
            }
            .alert("Edit Title", isPresented: $showEditTitleAlert) {
                TextField("Title", text: $editedTitle)
                Button("Save") {
                    saveStackTitle()
                }
                .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {
                    editedTitle = ""
                }
            } message: {
                Text("Enter a new title for this stack")
            }
            .confirmationDialog("Complete Stack", isPresented: $showCompleteConfirmation, titleVisibility: .visible) {
                Button("Complete All Tasks & Stack") { completeStack(completeAllTasks: true) }
                Button("Complete Stack Only") { completeStack(completeAllTasks: false) }
                Button("Cancel", role: .cancel) { }
            } message: {
                completeStackMessage
            }
            .confirmationDialog("Close Stack", isPresented: $showCloseConfirmation, titleVisibility: .visible) {
                Button("Close Without Completing", role: .destructive) { closeStack() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will close the stack without completing it. You can find it in completed stacks later.")
            }
            .sheet(isPresented: $showAddTask) {
                AddTaskSheet(
                    title: $newTaskTitle,
                    description: $newTaskDescription,
                    startTime: $newTaskStartTime,
                    dueTime: $newTaskDueTime,
                    onSave: addTask,
                    onCancel: cancelAddTask
                )
            }
            .sheet(isPresented: $showAddReminder) {
                if let stack = currentStack, let service = notificationService {
                    AddReminderSheet(parent: .stack(stack), notificationService: service)
                }
            }
            .sheet(isPresented: $showArcSelection) {
                ArcSelectionSheet(currentArc: selectedArc) { arc in
                    selectedArc = arc
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
                if let reminder = selectedReminderForEdit,
                   let stack = currentStack,
                   let service = notificationService {
                    AddReminderSheet(
                        parent: .stack(stack),
                        notificationService: service,
                        existingReminder: reminder
                    )
                }
            }
            .confirmationDialog("Delete Reminder", isPresented: $showDeleteReminderConfirmation) {
                Button("Delete", role: .destructive) {
                    if let reminder = reminderToDelete {
                        reminderActionHandler?.delete(reminder)
                    }
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
            // Prevent swipe-to-dismiss when there's unsaved content
            .interactiveDismissDisabled(hasUnsavedContent)
            #if os(iOS)
            // Save pending changes when app enters background
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                saveOnBackground()
            }
            #elseif os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                saveOnBackground()
            }
            #endif
            // Cancel any pending async operations when view disappears
            // This prevents race conditions where tasks complete after view is gone
            .onDisappear {
                activeStatusTask?.cancel()
                activeStatusTask = nil
            }
        }
    }
}

// MARK: - Helper Computed Properties

private extension StackEditorView {
    var navigationTitle: String {
        switch mode {
        case .create:
            return draftStack != nil ? "Edit Draft" : "New Stack"
        case .edit(let stack):
            return stack.title
        }
    }

    /// Whether to show a custom title view with edit button (for edit mode, non-read-only)
    var showsCustomTitle: Bool {
        !isCreateMode && !isReadOnly
    }

    /// The title to display in the navigation bar (empty when using custom editable title)
    var displayedTitle: String {
        showsCustomTitle ? "" : navigationTitle
    }

    /// Whether there's unsaved content that should prevent accidental dismissal
    var hasUnsavedContent: Bool {
        isCreateMode && (!title.isEmpty || !stackDescription.isEmpty || draftStack != nil)
    }
}

// MARK: - Toolbar & Shared Sections

extension StackEditorView {
    @ViewBuilder
    var completeStackMessage: some View {
        if case .edit(let stack) = mode, !stack.pendingTasks.isEmpty {
            let taskCount = stack.pendingTasks.count
            Text("This stack has \(taskCount) pending task(s). Would you like to complete them as well?")
        } else {
            Text("Mark this stack as completed?")
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if isCreateMode {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { handleCreateCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { publishAndCreate() }
                    .disabled(title.isEmpty)
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            // Custom title with inline edit button for editable stacks
            if showsCustomTitle {
                ToolbarItem(placement: .principal) {
                    editableTitleView
                }
            }
            if !isReadOnly {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") { handleCompleteButtonTapped() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// Custom title view with inline pencil button for editing
    @ViewBuilder
    private var editableTitleView: some View {
        if case .edit(let stack) = mode {
            Button {
                editedTitle = stack.title
                showEditTitleAlert = true
            } label: {
                HStack(spacing: 4) {
                    Text(stack.title)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit title: \(stack.title)")
            .accessibilityHint("Double tap to edit the stack title")
        }
    }

    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        ErrorReportingService.capture(error: error, context: ["view": "StackEditorView"])
    }

    // MARK: - Completion Handling

    /// Handles the Complete button tap with conditional behavior based on pending tasks.
    /// - If stack has pending tasks: show confirmation dialog (choose to complete tasks or not)
    /// - If stack has no pending tasks: immediately dismiss and start delayed completion with undo
    func handleCompleteButtonTapped() {
        guard case .edit(let stack) = mode else { return }

        if stack.pendingTasks.isEmpty {
            // No pending tasks - use delayed completion with undo banner
            if let manager = undoCompletionManager {
                manager.startDelayedCompletion(for: stack)
            } else {
                // Fallback: complete immediately if manager not available
                completeStack(completeAllTasks: true)
                return
            }
            dismiss()
        } else {
            // Has pending tasks - show confirmation dialog
            showCompleteConfirmation = true
        }
    }
}

// MARK: - Preview

#Preview("Create Mode") {
    StackEditorView(mode: .create)
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self, Attachment.self], inMemory: true)
}

#Preview("Edit Mode") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(for: Stack.self, Attachment.self, configurations: config)
    let stack = Stack(title: "Test Stack", stackDescription: "Test description", status: .active, sortOrder: 0)
    container.mainContext.insert(stack)
    return StackEditorView(mode: .edit(stack)).modelContainer(container)
}
