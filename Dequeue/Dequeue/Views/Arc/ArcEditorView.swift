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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService
    @Environment(\.attachmentUploadCoordinator) var attachmentUploadCoordinator

    @State private var arcService: ArcService?
    @State private var cachedDeviceId: String = ""

    // Reminder and attachment services
    @State var attachmentService: AttachmentService?
    @State var reminderActionHandler: ReminderActionHandler?
    @State var previewCoordinator = AttachmentPreviewCoordinator()
    private var notificationService: NotificationService {
        NotificationService(modelContext: modelContext)
    }

    let mode: Mode

    // Form fields
    @State private var title: String = ""
    @State private var arcDescription: String = ""
    @State private var selectedColorHex: String = "5E5CE6" // Default indigo

    // UI state
    @State var showError = false
    @State var errorMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var showCompleteConfirmation = false
    @State private var showStackPicker = false
    @FocusState private var isTitleFocused: Bool

    // Reminder state
    @State var showAddReminder = false
    @State var selectedReminderForEdit: Reminder?
    @State var showEditReminder = false
    @State var selectedReminderForSnooze: Reminder?
    @State var showSnoozePicker = false
    @State var reminderToDelete: Reminder?
    @State var showDeleteReminderConfirmation = false

    // Attachment state
    @State var showAttachmentPicker = false
    @State var attachmentToDelete: Attachment?
    @State var showDeleteAttachmentConfirmation = false

    /// Preset colors for arc accent
    private let colorPresets: [(name: String, hex: String)] = [
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

                // Stacks section (edit mode only)
                if let arc = editingArc {
                    stacksSection(for: arc)
                }

                // Reminders section (edit mode only)
                if editingArc != nil {
                    remindersSection
                }

                // Attachments section (edit mode only)
                if editingArc != nil {
                    attachmentsSection
                }

                // Actions section (edit mode only)
                if let arc = editingArc {
                    actionsSection(for: arc)
                }

                // Event history section (edit mode only)
                if let arc = editingArc {
                    eventHistorySection(for: arc)
                }
            }
            .navigationTitle(mode == .create ? "New Arc" : "Edit Arc")
            .navigationBarTitleDisplayMode(.inline)
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
                Button("OK", role: .cancel) {}
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
                Button("Cancel", role: .cancel) {}
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
                Button("Cancel", role: .cancel) {}
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
                Button("Cancel", role: .cancel) {}
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
                        do {
                            try attachmentService?.deleteAttachment(attachment)
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this attachment?")
            }
            .attachmentPreview(coordinator: previewCoordinator)
        }
    }

    // MARK: - Subviews

    private var colorPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
            ForEach(colorPresets, id: \.hex) { preset in
                Button {
                    selectedColorHex = preset.hex
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex) ?? .indigo)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if selectedColorHex == preset.hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(selectedColorHex == preset.hex ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func stacksSection(for arc: Arc) -> some View {
        Section {
            if arc.sortedStacks.isEmpty {
                Text("No stacks assigned")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(arc.sortedStacks) { stack in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(stack.title)
                                .font(.body)
                            if stack.status == .completed {
                                Text("Completed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if stack.status == .completed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            // Remove from arc button
                            Button {
                                removeStack(stack, from: arc)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Add stack button
            Button {
                showStackPicker = true
            } label: {
                Label("Add Stack", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Stacks")
                Spacer()
                Text("\(arc.completedStackCount)/\(arc.totalStackCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showStackPicker) {
            StackPickerForArcSheet(arc: arc)
        }
    }

    private func removeStack(_ stack: Stack, from arc: Arc) {
        do {
            try arcService?.removeStack(stack, from: arc)
            logger.info("Removed stack \(stack.id) from arc \(arc.id)")
        } catch {
            handleError(error, action: "remove_stack")
        }
    }

    @ViewBuilder
    private func actionsSection(for arc: Arc) -> some View {
        Section {
            // Status actions
            switch arc.status {
            case .active:
                Button {
                    pauseArc()
                } label: {
                    Label("Pause Arc", systemImage: "pause.circle")
                }

                Button {
                    showCompleteConfirmation = true
                } label: {
                    Label("Complete Arc", systemImage: "checkmark.circle")
                }
                .foregroundStyle(.green)

            case .paused:
                Button {
                    resumeArc()
                } label: {
                    Label("Resume Arc", systemImage: "play.circle")
                }
                .foregroundStyle(.blue)

                Button {
                    showCompleteConfirmation = true
                } label: {
                    Label("Complete Arc", systemImage: "checkmark.circle")
                }
                .foregroundStyle(.green)

            case .completed:
                Button {
                    reopenArc()
                } label: {
                    Label("Reopen Arc", systemImage: "arrow.uturn.backward.circle")
                }
                .foregroundStyle(.blue)

            case .archived:
                Button {
                    unarchiveArc()
                } label: {
                    Label("Unarchive Arc", systemImage: "tray.and.arrow.up")
                }
                .foregroundStyle(.blue)
            }

            // Delete action
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Arc", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func eventHistorySection(for arc: Arc) -> some View {
        Section {
            NavigationLink {
                ArcHistoryView(arc: arc)
            } label: {
                Label("Event History", systemImage: "clock.arrow.circlepath")
            }
        } footer: {
            Text("View the complete history of changes to this arc")
        }
    }

    // MARK: - Initialization

    private func initializeServices() async {
        if cachedDeviceId.isEmpty {
            cachedDeviceId = await DeviceService.shared.getDeviceId()
        }

        let userId = authService.currentUserId ?? ""

        if arcService == nil {
            arcService = ArcService(
                modelContext: modelContext,
                userId: userId,
                deviceId: cachedDeviceId,
                syncManager: syncManager
            )
        }

        if attachmentService == nil {
            attachmentService = AttachmentService(
                modelContext: modelContext,
                userId: userId,
                deviceId: cachedDeviceId,
                syncManager: syncManager
            )
        }

        if reminderActionHandler == nil {
            reminderActionHandler = ReminderActionHandler(
                modelContext: modelContext,
                userId: userId,
                deviceId: cachedDeviceId,
                onError: { [self] error in
                    errorMessage = error.localizedDescription
                    showError = true
                },
                syncManager: syncManager
            )
        }
    }

    private func loadArcData() {
        if let arc = editingArc {
            title = arc.title
            arcDescription = arc.arcDescription ?? ""
            selectedColorHex = arc.colorHex ?? "5E5CE6"
        }
    }

    // MARK: - Actions

    private func saveArc() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        do {
            if let arc = editingArc {
                // Update existing arc
                try arcService?.updateArc(
                    arc,
                    title: trimmedTitle,
                    description: arcDescription.isEmpty ? nil : arcDescription,
                    colorHex: selectedColorHex
                )
                logger.info("Updated arc: \(arc.id)")
            } else {
                // Create new arc
                let arc = try arcService?.createArc(
                    title: trimmedTitle,
                    description: arcDescription.isEmpty ? nil : arcDescription,
                    colorHex: selectedColorHex
                )
                logger.info("Created arc: \(arc?.id ?? "unknown")")
            }
            dismiss()
        } catch ArcServiceError.maxActiveArcsExceeded(let limit) {
            errorMessage = "You can have up to \(limit) active arcs. Complete or pause an existing arc first."
            showError = true
        } catch {
            logger.error("Failed to save arc: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
            ErrorReportingService.capture(error: error, context: ["action": "save_arc"])
        }
    }

    private func pauseArc() {
        guard let arc = editingArc else { return }
        do {
            try arcService?.pause(arc)
            logger.info("Paused arc: \(arc.id)")
        } catch {
            handleError(error, action: "pause_arc")
        }
    }

    private func resumeArc() {
        guard let arc = editingArc else { return }
        do {
            try arcService?.resume(arc)
            logger.info("Resumed arc: \(arc.id)")
        } catch {
            handleError(error, action: "resume_arc")
        }
    }

    private func completeArc() {
        guard let arc = editingArc else { return }
        do {
            try arcService?.markAsCompleted(arc)
            logger.info("Completed arc: \(arc.id)")
            dismiss()
        } catch {
            handleError(error, action: "complete_arc")
        }
    }

    private func reopenArc() {
        guard let arc = editingArc else { return }
        do {
            try arcService?.resume(arc)
            logger.info("Reopened arc: \(arc.id)")
        } catch {
            handleError(error, action: "reopen_arc")
        }
    }

    private func unarchiveArc() {
        guard let arc = editingArc else { return }
        do {
            try arcService?.resume(arc)
            logger.info("Unarchived arc: \(arc.id)")
        } catch {
            handleError(error, action: "unarchive_arc")
        }
    }

    private func deleteArc() {
        guard let arc = editingArc else { return }
        do {
            try arcService?.deleteArc(arc)
            logger.info("Deleted arc: \(arc.id)")
            dismiss()
        } catch {
            handleError(error, action: "delete_arc")
        }
    }

    private func handleError(_ error: Error, action: String) {
        logger.error("Failed to \(action): \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        showError = true
        ErrorReportingService.capture(error: error, context: ["action": action])
    }
}

// MARK: - Previews

#Preview("Create Mode") {
    ArcEditorView(mode: .create)
        .modelContainer(for: [Arc.self, Stack.self], inMemory: true)
}

#Preview("Edit Mode") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(for: Arc.self, Stack.self, configurations: config)
    let arc = Arc(title: "Test Arc", arcDescription: "Test description", colorHex: "FF6B6B")
    container.mainContext.insert(arc)

    return ArcEditorView(mode: .edit(arc))
        .modelContainer(container)
}
