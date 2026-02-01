//
//  ArcEditorView.swift
//  Dequeue
//
//  View for creating and editing Arcs
//

import SwiftUI
import SwiftData
import os
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.dequeue", category: "ArcEditorView")

struct ArcEditorView: View {
    enum Mode: Equatable {
        case create
        case edit(Arc)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create):
                return true
            case let (.edit(arc1), .edit(arc2)):
                return arc1.id == arc2.id
            default:
                return false
            }
        }
    }

    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.syncManager) var syncManager
    @Environment(\.authService) var authService
    @Environment(\.attachmentUploadCoordinator) var attachmentUploadCoordinator

    @State var arcService: ArcService?
    @State var cachedDeviceId: String = ""

    // Reminder and attachment services
    @State var attachmentService: AttachmentService?
    @State var reminderActionHandler: ReminderActionHandler?
    @State var previewCoordinator = AttachmentPreviewCoordinator()
    private var notificationService: NotificationService {
        NotificationService(modelContext: modelContext)
    }

    let mode: Mode

    // Form fields
    @State var title: String = ""
    @State var arcDescription: String = ""
    @State var selectedColorHex: String = "5E5CE6" // Default indigo
    @State var startDate: Date?
    @State var dueDate: Date?
    @State var hasStartDate: Bool = false
    @State var hasDueDate: Bool = false

    // UI state
    @State var showError = false
    @State var errorMessage = ""
    @State var showDeleteConfirmation = false
    @State var showCompleteConfirmation = false
    @State var showStackPicker = false
    @FocusState private var isTitleFocused: Bool

    // Reminder state
    @State var showAddReminder = false
    @State var selectedReminderForEdit: Reminder?
    @State var showEditReminder = false
    @State var selectedReminderForSnooze: Reminder?
    @State var showSnoozePicker = false
    @State var reminderToDelete: Reminder?
    @State var showDeleteReminderConfirmation = false
    @State var showDueDateReminderPrompt = false

    // Attachment state
    @State var showAttachmentPicker = false
    @State var attachmentToDelete: Attachment?
    @State var showDeleteAttachmentConfirmation = false

    /// Preset colors for arc accent
    let colorPresets: [(name: String, hex: String)] = [
        ("Indigo", "5E5CE6"),
        ("Blue", "007AFF"),
        ("Cyan", "32ADE6"),
        ("Teal", "30B0C7"),
        ("Green", "34C759"),
        ("Yellow", "FFCC00"),
        ("Orange", "FF9500"),
        ("Red", "FF3B30"),
        ("Pink", "FF2D55"),
        ("Purple", "AF52DE")
    ]

    /// Whether the form is valid for saving
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The arc being edited (nil in create mode)
    var editingArc: Arc? {
        if case .edit(let arc) = mode {
            return arc
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Title & Description section
                Section {
                    TextField("Arc Title", text: $title)
                        .focused($isTitleFocused)
                        .accessibilityLabel("Arc title")

                    TextField("Description (optional)", text: $arcDescription, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Arc description")
                }

                // Color section
                Section("Accent Color") {
                    colorPicker
                }

                // Dates section
                Section("Dates") {
                    datesSection
                }

                // Stacks section (edit mode only)
                if let arc = editingArc {
                    stacksSection(for: arc)
                }

                // Reminders and Attachments sections (edit mode only)
                if editingArc != nil {
                    remindersSection
                    attachmentsSection
                }

                // Actions and Event history sections (edit mode only)
                if let arc = editingArc {
                    actionsSection(for: arc)
                    eventHistorySection(for: arc)
                }
            }
            .navigationTitle(mode == .create ? "New Arc" : "Edit Arc")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .create ? "Create" : "Save") {
                        saveArc()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { /* Dismiss handled by SwiftUI */ }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                "Complete Arc",
                isPresented: $showCompleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Complete Arc") {
                    completeArc()
                }
                Button("Cancel", role: .cancel) { /* Dismiss handled by SwiftUI */ }
            } message: {
                Text("Mark this arc as completed? You can reopen it later if needed.")
            }
            .confirmationDialog(
                "Delete Arc",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Arc", role: .destructive) {
                    deleteArc()
                }
                Button("Cancel", role: .cancel) { /* Dismiss handled by SwiftUI */ }
            } message: {
                Text("Delete this arc? Stacks within this arc will not be deleted.")
            }
            .task {
                await initializeServices()
                loadArcData()
            }
            .onAppear {
                if mode == .create {
                    isTitleFocused = true
                }
            }
            // Reminder sheets
            .sheet(isPresented: $showAddReminder) {
                if let arc = editingArc {
                    AddReminderSheet(parent: .arc(arc), notificationService: notificationService)
                }
            }
            .sheet(isPresented: $showEditReminder) {
                if let arc = editingArc, let reminder = selectedReminderForEdit {
                    AddReminderSheet(
                        parent: .arc(arc),
                        notificationService: notificationService,
                        existingReminder: reminder
                    )
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
            .confirmationDialog(
                "Delete Reminder",
                isPresented: $showDeleteReminderConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let reminder = reminderToDelete {
                        reminderActionHandler?.delete(reminder)
                    }
                }
                Button("Cancel", role: .cancel) { /* Dismiss handled by SwiftUI */ }
            } message: {
                Text("Are you sure you want to delete this reminder?")
            }
            // Attachment picker
            .fileImporter(
                isPresented: $showAttachmentPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    let accessedURLs = urls.compactMap { url -> URL? in
                        guard url.startAccessingSecurityScopedResource() else { return nil }
                        return url
                    }
                    handleFilesSelected(accessedURLs)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            .confirmationDialog(
                "Delete Attachment",
                isPresented: $showDeleteAttachmentConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let attachment = attachmentToDelete {
                        Task {
                            do {
                                try await attachmentService?.deleteAttachment(attachment)
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) { /* Dismiss handled by SwiftUI */ }
            } message: {
                Text("Are you sure you want to delete this attachment?")
            }
            .attachmentPreview(coordinator: previewCoordinator)
            // Due date reminder prompt
            .alert("Create Reminder?", isPresented: $showDueDateReminderPrompt) {
                Button("Yes, remind me") {
                    createDueDateReminder()
                }
                Button("No thanks", role: .cancel) { }
            } message: {
                Text("Would you like to create a reminder for this due date at 8:00 AM?")
            }
        }
    }

    /// Creates a reminder at 8 AM on the due date (called from edit flow)
    private func createDueDateReminder() {
        guard let arc = editingArc,
              let dueDate = dueDate,
              let reminderDate = dueDate.morningReminderTime() else { return }

        Task {
            do {
                try await createDueDateReminder(for: arc, at: reminderDate)
            } catch {
                errorMessage = "Failed to create reminder: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

// MARK: - Previews

#Preview("Create Mode") {
    ArcEditorView(mode: .create)
        .modelContainer(for: [Arc.self, Stack.self], inMemory: true)
}

#Preview("Edit Mode") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // Safe: In-memory container with known schema types cannot fail in preview context
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(for: Arc.self, Stack.self, configurations: config)
    let arc = Arc(title: "Test Arc", arcDescription: "Test description", colorHex: "FF6B6B")
    container.mainContext.insert(arc)

    return ArcEditorView(mode: .edit(arc))
        .modelContainer(container)
}
