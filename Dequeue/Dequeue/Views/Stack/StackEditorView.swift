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
    @State private var cachedDeviceId: String = ""

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
    @State var pendingTasks: [PendingTask] = []
    @State var selectedTags: [Tag] = []
    @State var draftStack: Stack?
    @State var isCreatingDraft = false
    @State var showDiscardAlert = false
    @State var showSaveDraftPrompt = false
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
    }

    // Edit mode state
    @State var isEditingDescription = false
    @State var editedDescription = ""
    @State var showCompletedTasks = false
    @State var showCompleteConfirmation = false
    @State var showCloseConfirmation = false

    // Shared state
    @State var showError = false
    @State var errorMessage = ""
    @State var showAddTask = false
    @State var newTaskTitle = ""
    @State var newTaskDescription = ""
    @State var showAddReminder = false
    @State var showSnoozePicker = false
    @State var selectedReminderForSnooze: Reminder?
    @State var showEditReminder = false
    @State var selectedReminderForEdit: Reminder?
    @State var showDeleteReminderConfirmation = false
    @State var reminderToDelete: Reminder?

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

    private var navigationTitle: String {
        switch mode {
        case .create:
            return draftStack != nil ? "Edit Draft" : "New Stack"
        case .edit(let stack):
            return stack.title
        }
    }

    /// Whether there's unsaved content that should prevent accidental dismissal
    private var hasUnsavedContent: Bool {
        isCreateMode && (!title.isEmpty || !stackDescription.isEmpty || draftStack != nil)
    }

    // MARK: - Services

    var stackService: StackService {
        StackService(
            modelContext: modelContext,
            userId: authService.currentUserId ?? "",
            deviceId: cachedDeviceId,
            syncManager: syncManager
        )
    }

    var taskService: TaskService {
        TaskService(
            modelContext: modelContext,
            userId: authService.currentUserId ?? "",
            deviceId: cachedDeviceId,
            syncManager: syncManager
        )
    }

    var notificationService: NotificationService {
        NotificationService(modelContext: modelContext)
    }

    var reminderActionHandler: ReminderActionHandler {
        ReminderActionHandler(
            modelContext: modelContext,
            userId: authService.currentUserId ?? "",
            deviceId: cachedDeviceId,
            onError: handleError,
            syncManager: syncManager
        )
    }

    var tagService: TagService {
        TagService(
            modelContext: modelContext,
            userId: authService.currentUserId ?? "",
            deviceId: cachedDeviceId,
            syncManager: syncManager
        )
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
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(isCreateMode ? .inline : .large)
            #endif
            .toolbar { toolbarContent }
            .task {
                if cachedDeviceId.isEmpty {
                    cachedDeviceId = await DeviceService.shared.getDeviceId()
                }
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
                    onSave: addTask,
                    onCancel: cancelAddTask
                )
            }
            .sheet(isPresented: $showAddReminder) {
                if let stack = currentStack {
                    AddReminderSheet(parent: .stack(stack), notificationService: notificationService)
                }
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
            .sheet(isPresented: $showEditReminder) {
                if let reminder = selectedReminderForEdit, let stack = currentStack {
                    AddReminderSheet(
                        parent: .stack(stack),
                        notificationService: notificationService,
                        existingReminder: reminder
                    )
                }
            }
            .confirmationDialog("Delete Reminder", isPresented: $showDeleteReminderConfirmation) {
                Button("Delete", role: .destructive) {
                    if let reminder = reminderToDelete {
                        reminderActionHandler.delete(reminder)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this reminder?")
            }
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
        }
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
            if !isReadOnly {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") { handleCompleteButtonTapped() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    var remindersSection: some View {
        Section {
            if let stack = currentStack, !stack.activeReminders.isEmpty {
                remindersList
            } else {
                HStack {
                    Label("No reminders", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        } header: {
            HStack {
                Text("Reminders")
                Spacer()
                // Show add button when: not read-only AND (stack exists OR in create mode)
                if !isReadOnly && (currentStack != nil || mode == .create) {
                    Button {
                        handleAddReminderTap()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("addStackReminderButton")
                }
            }
        }
    }

    /// Handles the add reminder button tap.
    /// In create mode without a draft, auto-creates a draft first so reminders can be attached.
    func handleAddReminderTap() {
        // If we already have a stack, just show the sheet
        if currentStack != nil {
            showAddReminder = true
            return
        }

        // In create mode without a draft, create the draft first
        if case .create = mode {
            // Use the current title or "Untitled" as fallback
            let draftTitle = title.isEmpty ? "Untitled" : title
            createDraft(title: draftTitle)

            // Show the sheet - draftStack is now set
            if draftStack != nil {
                showAddReminder = true
            }
        }
    }

    @ViewBuilder
    var remindersList: some View {
        if let stack = currentStack {
            ForEach(stack.activeReminders) { reminder in
                ReminderRowView(
                    reminder: reminder,
                    onTap: isReadOnly ? nil : {
                        selectedReminderForEdit = reminder
                        showEditReminder = true
                    },
                    onSnooze: isReadOnly ? nil : {
                        selectedReminderForSnooze = reminder
                        showSnoozePicker = true
                    },
                    onDismiss: (isReadOnly || !reminder.isPastDue) ? nil : {
                        reminderActionHandler.dismiss(reminder)
                    },
                    onDelete: isReadOnly ? nil : {
                        reminderToDelete = reminder
                        showDeleteReminderConfirmation = true
                    }
                )
            }
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
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}

#Preview("Edit Mode") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(for: Stack.self, configurations: config)
    let stack = Stack(title: "Test Stack", stackDescription: "Test description", status: .active, sortOrder: 0)
    container.mainContext.insert(stack)
    return StackEditorView(mode: .edit(stack)).modelContainer(container)
}
