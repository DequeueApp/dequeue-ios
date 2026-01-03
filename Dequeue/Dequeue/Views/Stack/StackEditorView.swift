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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss

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
    @State var firstTaskTitle: String = ""
    @State var draftStack: Stack?
    @State var isCreatingDraft = false
    @State var showDiscardAlert = false

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

    // Initialization guard to prevent duplicate onAppear calls
    @State private var hasInitialized = false

    // Services (lazily initialized on first access, then cached)
    @State private var _stackService: StackService?
    @State private var _taskService: TaskService?
    @State private var _notificationService: NotificationService?
    @State private var _reminderActionHandler: ReminderActionHandler?

    // MARK: - Computed Properties

    /// Lazily initialized and cached stack service
    var stackService: StackService {
        if let service = _stackService { return service }
        let service = StackService(modelContext: modelContext)
        _stackService = service
        return service
    }

    /// Lazily initialized and cached task service
    var taskService: TaskService {
        if let service = _taskService { return service }
        let service = TaskService(modelContext: modelContext)
        _taskService = service
        return service
    }

    /// Lazily initialized and cached notification service
    var notificationService: NotificationService {
        if let service = _notificationService { return service }
        let service = NotificationService(modelContext: modelContext)
        _notificationService = service
        return service
    }

    /// Lazily initialized and cached reminder action handler
    var reminderActionHandler: ReminderActionHandler {
        if let handler = _reminderActionHandler { return handler }
        let handler = ReminderActionHandler(modelContext: modelContext, onError: handleError)
        _reminderActionHandler = handler
        return handler
    }

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
            .onAppear {
                initializeStateFromMode()
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(isCreateMode ? .inline : .large)
            #endif
            .toolbar { toolbarContent }
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
        }
    }

    /// Initialize state variables when view appears (services are lazily initialized)
    private func initializeStateFromMode() {
        // Guard against duplicate onAppear calls (SwiftUI can call onAppear multiple times)
        guard !hasInitialized else { return }
        hasInitialized = true

        if case .edit(let stack) = mode, stack.isDraft {
            // Editing an existing draft - initialize state from the stack
            title = stack.title
            stackDescription = stack.stackDescription ?? ""
            // Set draftStack so the view knows we have an existing draft
            draftStack = stack
        }
    }

    @ViewBuilder
    private var completeStackMessage: some View {
        if case .edit(let stack) = mode, !stack.pendingTasks.isEmpty {
            let taskCount = stack.pendingTasks.count
            Text("This stack has \(taskCount) pending task(s). Would you like to complete them as well?")
        } else {
            Text("Mark this stack as completed?")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                    Button("Complete") { showCompleteConfirmation = true }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Shared Sections

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
                if !isReadOnly && currentStack != nil {
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

    // MARK: - Error Handling

    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        ErrorReportingService.capture(error: error, context: ["view": "StackEditorView"])
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
