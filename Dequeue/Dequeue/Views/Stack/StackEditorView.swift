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
    @State var setAsActive: Bool = false
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
            mainContent
                .toolbar { toolbarContent }
                .task { await initializeServices() }
                .modifier(alertsModifier)
                .modifier(sheetsModifier)
                .modifier(lifecycleModifier)
        }
    }
}

// MARK: - Content & Service Initialization

extension StackEditorView {
    @ViewBuilder
    var mainContent: some View {
        Group {
            if isCreateMode { createModeContent } else { editModeContent }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
        .navigationTitle(displayedTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @MainActor
    func initializeServices() async {
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
}

// MARK: - Alert Modifiers

extension StackEditorView {
    var alertsModifier: some ViewModifier {
        StackEditorAlertsModifier(
            showError: $showError,
            errorMessage: errorMessage,
            showDiscardAlert: $showDiscardAlert,
            showSaveDraftPrompt: $showSaveDraftPrompt,
            showEditTitleAlert: $showEditTitleAlert,
            editedTitle: $editedTitle,
            showCompleteConfirmation: $showCompleteConfirmation,
            showCloseConfirmation: $showCloseConfirmation,
            showDeleteReminderConfirmation: $showDeleteReminderConfirmation,
            reminderToDelete: reminderToDelete,
            reminderActionHandler: reminderActionHandler,
            completeStackMessage: AnyView(completeStackMessage),
            onDismiss: { dismiss() },
            onDiscardDraft: discardDraftAndDismiss,
            onCreateDraft: createDraftAndDismiss,
            onSaveTitle: saveStackTitle,
            onCompleteStack: completeStack,
            onCloseStack: closeStack
        )
    }
}

private struct StackEditorAlertsModifier: ViewModifier {
    @Binding var showError: Bool
    let errorMessage: String
    @Binding var showDiscardAlert: Bool
    @Binding var showSaveDraftPrompt: Bool
    @Binding var showEditTitleAlert: Bool
    @Binding var editedTitle: String
    @Binding var showCompleteConfirmation: Bool
    @Binding var showCloseConfirmation: Bool
    @Binding var showDeleteReminderConfirmation: Bool
    let reminderToDelete: Reminder?
    let reminderActionHandler: ReminderActionHandler?
    let completeStackMessage: AnyView
    let onDismiss: () -> Void
    let onDiscardDraft: () -> Void
    let onCreateDraft: () -> Void
    let onSaveTitle: () -> Void
    let onCompleteStack: (Bool) -> Void
    let onCloseStack: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $showError) { Button("OK", role: .cancel) { } } message: {
                Text(errorMessage)
            }
            .alert("Discard Draft?", isPresented: $showDiscardAlert) {
                Button("Keep Draft") { onDismiss() }
                Button("Discard", role: .destructive) { onDiscardDraft() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Your draft has been auto-saved. Would you like to keep it or discard it?") }
            .alert("Save Draft?", isPresented: $showSaveDraftPrompt) {
                Button("Save Draft") { onCreateDraft() }
                Button("Discard", role: .destructive) { onDismiss() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("You have unsaved content. Would you like to save it as a draft?") }
            .alert("Edit Title", isPresented: $showEditTitleAlert) {
                TextField("Title", text: $editedTitle)
                Button("Save") { onSaveTitle() }
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { editedTitle = "" }
            } message: { Text("Enter a new title for this stack") }
            .confirmationDialog("Complete Stack", isPresented: $showCompleteConfirmation, titleVisibility: .visible) {
                Button("Complete All Tasks & Stack") { onCompleteStack(true) }
                Button("Complete Stack Only") { onCompleteStack(false) }
                Button("Cancel", role: .cancel) { }
            } message: { completeStackMessage }
            .confirmationDialog("Close Stack", isPresented: $showCloseConfirmation, titleVisibility: .visible) {
                Button("Close Without Completing", role: .destructive) { onCloseStack() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will close the stack without completing it. You can find it in completed stacks later.")
            }
            .confirmationDialog("Delete Reminder", isPresented: $showDeleteReminderConfirmation) {
                Button("Delete", role: .destructive) {
                    if let reminder = reminderToDelete { reminderActionHandler?.delete(reminder) }
                }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Are you sure you want to delete this reminder?") }
    }
}

// MARK: - Sheet Modifiers

extension StackEditorView {
    var sheetsModifier: some ViewModifier {
        StackEditorSheetsModifier(
            showAddTask: $showAddTask,
            newTaskTitle: $newTaskTitle,
            newTaskDescription: $newTaskDescription,
            showAddReminder: $showAddReminder,
            showArcSelection: $showArcSelection,
            showSnoozePicker: $showSnoozePicker,
            showEditReminder: $showEditReminder,
            showAttachmentPicker: $showAttachmentPicker,
            selectedArc: selectedArc,
            onArcSelected: { selectedArc = $0 },
            selectedReminderForSnooze: selectedReminderForSnooze,
            onSnoozeReminderCleared: { selectedReminderForSnooze = nil },
            selectedReminderForEdit: selectedReminderForEdit,
            currentStack: currentStack,
            notificationService: notificationService,
            reminderActionHandler: reminderActionHandler,
            previewCoordinator: previewCoordinator,
            onAddTask: addTask,
            onCancelAddTask: cancelAddTask,
            onFilesSelected: handleFilesSelected,
            onAttachmentError: { errorMessage = $0.localizedDescription; showError = true }
        )
    }
}

private struct StackEditorSheetsModifier: ViewModifier {
    @Binding var showAddTask: Bool
    @Binding var newTaskTitle: String
    @Binding var newTaskDescription: String
    @Binding var showAddReminder: Bool
    @Binding var showArcSelection: Bool
    @Binding var showSnoozePicker: Bool
    @Binding var showEditReminder: Bool
    @Binding var showAttachmentPicker: Bool
    let selectedArc: Arc?
    let onArcSelected: (Arc?) -> Void
    let selectedReminderForSnooze: Reminder?
    let onSnoozeReminderCleared: () -> Void
    let selectedReminderForEdit: Reminder?
    let currentStack: Stack?
    let notificationService: NotificationService?
    let reminderActionHandler: ReminderActionHandler?
    let previewCoordinator: AttachmentPreviewCoordinator
    let onAddTask: () -> Void
    let onCancelAddTask: () -> Void
    let onFilesSelected: ([URL]) -> Void
    let onAttachmentError: (AttachmentPickerError) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAddTask) {
                AddTaskSheet(
                    title: $newTaskTitle,
                    description: $newTaskDescription,
                    startTime: $newTaskStartTime,
                    dueTime: $newTaskDueTime,
                    onSave: onAddTask,
                    onCancel: onCancelAddTask
                )
            }
            .sheet(isPresented: $showAddReminder) {
                if let stack = currentStack, let service = notificationService {
                    AddReminderSheet(parent: .stack(stack), notificationService: service)
                }
            }
            .sheet(isPresented: $showArcSelection) {
                ArcSelectionSheet(currentArc: selectedArc) { onArcSelected($0) }
            }
            .sheet(isPresented: $showSnoozePicker) {
                if let reminder = selectedReminderForSnooze {
                    SnoozePickerSheet(isPresented: $showSnoozePicker, reminder: reminder) { snoozeUntil in
                        reminderActionHandler?.snooze(reminder, until: snoozeUntil)
                        onSnoozeReminderCleared()
                    }
                }
            }
            .sheet(isPresented: $showEditReminder) {
                if let reminder = selectedReminderForEdit, let stack = currentStack,
                   let service = notificationService {
                    AddReminderSheet(
                        parent: .stack(stack),
                        notificationService: service,
                        existingReminder: reminder
                    )
                }
            }
            .attachmentPicker(
                isPresented: $showAttachmentPicker,
                onFilesSelected: onFilesSelected,
                onError: onAttachmentError
            )
            .attachmentPreview(coordinator: previewCoordinator)
    }
}

// MARK: - Lifecycle Modifiers

extension StackEditorView {
    var lifecycleModifier: some ViewModifier {
        StackEditorLifecycleModifier(
            hasUnsavedContent: hasUnsavedContent,
            onBackground: saveOnBackground,
            onDisappear: { activeStatusTask?.cancel(); activeStatusTask = nil }
        )
    }
}

private struct StackEditorLifecycleModifier: ViewModifier {
    let hasUnsavedContent: Bool
    let onBackground: () -> Void
    let onDisappear: () -> Void

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(hasUnsavedContent)
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                onBackground()
            }
            #elseif os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                onBackground()
            }
            #endif
            .onDisappear { onDisappear() }
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
