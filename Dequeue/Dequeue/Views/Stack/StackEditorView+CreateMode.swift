//
//  StackEditorView+CreateMode.swift
//  Dequeue
//
//  Create mode content and actions for StackEditorView
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.dequeue", category: "StackEditorView")

// MARK: - Create Mode Content

extension StackEditorView {
    var createModeContent: some View {
        Form {
            Section("Stack") {
                TextField("Title", text: $title)
                    .focused($focusedField, equals: .title)
                TextField("Description (optional)", text: $stackDescription, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .description)
                    .onChange(of: stackDescription) { oldValue, newValue in
                        handleDescriptionChange(oldValue: oldValue, newValue: newValue)
                    }
            }
            .onChange(of: focusedField) { oldValue, newValue in
                handleFocusChange(from: oldValue, to: newValue)
            }

            createModeTagsSection

            createModeTasksSection

            remindersSection

            attachmentsSection
        }
    }

    // MARK: - Create Mode Tags Section

    var createModeTagsSection: some View {
        Section("Tags") {
            TagInputView(
                selectedTags: $selectedTags,
                allTags: allTags,
                onTagAdded: { _ in },
                onTagRemoved: { _ in },
                onNewTagCreated: { name in
                    guard let service = tagService else {
                        logger.error("TagService not initialized when creating tag '\(name)'")
                        return nil
                    }
                    do {
                        return try service.findOrCreateTag(name: name)
                    } catch {
                        logger.error("Failed to create tag '\(name)': \(error.localizedDescription)")
                        return nil
                    }
                }
            )
        }
    }

    // MARK: - Create Mode Tasks Section

    var createModeTasksSection: some View {
        Section {
            if pendingTasks.isEmpty {
                HStack {
                    Label("No Tasks", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("No tasks added yet")
                    Spacer()
                }
            } else {
                ForEach(pendingTasks) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                            if let description = task.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .onDelete(perform: deleteCreateModeTasks)
            }
        } header: {
            HStack {
                Text("Tasks")
                Spacer()
                Text("\(pendingTasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showAddTask = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("addTaskButton")
            }
        }
    }

    func deleteCreateModeTasks(at offsets: IndexSet) {
        pendingTasks.remove(atOffsets: offsets)
    }

    // MARK: - Create Mode Actions

    /// Handles focus changes between fields to trigger saves at appropriate times.
    /// - Title blur: Creates draft if title has content, or updates draft if changed
    /// - Description blur: Saves any pending description changes
    func handleFocusChange(from oldField: EditorField?, to newField: EditorField?) {
        // Title field lost focus
        if oldField == .title {
            handleTitleBlur()
        }

        // Description field lost focus
        if oldField == .description {
            handleDescriptionBlur()
        }
    }

    /// Called when the title field loses focus.
    /// Creates a draft if this is the first time content was entered,
    /// or updates the draft if the title changed.
    func handleTitleBlur() {
        guard isCreateMode else { return }
        guard !isCreatingDraft else { return }
        guard !title.isEmpty else { return }

        if draftStack == nil {
            // First time user entered a title and left the field - create draft
            createDraft(title: title)
        } else if let draft = draftStack, draft.title != title {
            // Title changed - update draft
            updateDraft(draft, title: title, description: stackDescription)
        }
    }

    /// Called when the description field loses focus.
    /// Saves any pending description changes that weren't saved by word completion.
    func handleDescriptionBlur() {
        guard isCreateMode else { return }
        guard let draft = draftStack else { return }
        guard draft.stackDescription != stackDescription else { return }
        updateDraft(draft, title: title, description: stackDescription)
    }

    /// Handles description text changes to detect word completion.
    /// Fires a save event when a space or newline is added, providing crash recovery
    /// without the overhead of per-keystroke events.
    func handleDescriptionChange(oldValue: String, newValue: String) {
        guard let draft = draftStack else { return }

        // Detect word completion: new text ends with word boundary when old didn't.
        // This handles both typing and pasting text ending with space/newline.
        // The blur handler catches any remaining unsaved content.
        let newEndsWithWordBoundary = newValue.last == " " || newValue.last == "\n"
        let oldEndsWithWordBoundary = oldValue.last == " " || oldValue.last == "\n"

        if newEndsWithWordBoundary && !oldEndsWithWordBoundary {
            updateDraft(draft, title: title, description: newValue)
        }
    }

    func createDraft(title: String) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        isCreatingDraft = true

        do {
            let draft = try service.createStack(
                title: title,
                description: stackDescription.isEmpty ? nil : stackDescription,
                isDraft: true
            )
            draftStack = draft
            logger.info("Auto-created draft: \(draft.id)")
            syncManager?.triggerImmediatePush()
        } catch {
            logger.error("Failed to create draft: \(error.localizedDescription)")
            errorMessage = "Failed to save draft: \(error.localizedDescription)"
            showError = true
        }

        isCreatingDraft = false
    }

    func updateDraft(_ draft: Stack, title: String, description: String) {
        // Check if draft was published elsewhere before attempting update
        guard draft.isDraft else {
            logger.warning("Attempted to update non-draft stack - draft may have been published")
            draftStack = nil
            errorMessage = "This draft has been published. Changes were not saved."
            showError = true
            return
        }
        guard let service = stackService else {
            logger.error("StackService not initialized when updating draft")
            return
        }

        do {
            try service.updateDraft(
                draft,
                title: title.isEmpty ? "Untitled" : title,
                description: description.isEmpty ? nil : description
            )
            logger.debug("Auto-updated draft: \(draft.id)")
            syncManager?.triggerImmediatePush()
        } catch {
            logger.error("Failed to update draft: \(error.localizedDescription)")
        }
    }

    func handleCreateCancel() {
        // Case 1: Draft exists - show discard dialog
        if draftStack != nil {
            showDiscardAlert = true
            return
        }

        // Case 2: No draft but has content - prompt to save draft
        if !title.isEmpty || !stackDescription.isEmpty {
            showSaveDraftPrompt = true
            return
        }

        // Case 3: No content at all - just dismiss
        dismiss()
    }

    func discardDraftAndDismiss() {
        if let draft = draftStack, let service = stackService {
            do {
                try service.discardDraft(draft)
                logger.info("Draft discarded: \(draft.id)")
                syncManager?.triggerImmediatePush()
            } catch {
                logger.error("Failed to discard draft: \(error.localizedDescription)")
            }
        }
        dismiss()
    }

    func publishAndCreate() {
        guard let stackSvc = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        do {
            let stack = try createOrPublishStack(using: stackSvc)
            associateTagsWithStack(stack)

            let failedTasks = createPendingTasks(for: stack)
            if !failedTasks.isEmpty {
                showTaskCreationError(failedTasks: failedTasks)
                return
            }

            syncManager?.triggerImmediatePush()
            dismiss()
        } catch {
            logger.error("Failed to create stack: \(error.localizedDescription)")
            errorMessage = "Failed to create stack: \(error.localizedDescription)"
            showError = true
        }
    }

    private func createOrPublishStack(using stackSvc: StackService) throws -> Stack {
        if let existingDraft = draftStack {
            existingDraft.title = title
            existingDraft.stackDescription = stackDescription.isEmpty ? nil : stackDescription
            try stackSvc.publishDraft(existingDraft)
            logger.info("Draft published as stack: \(existingDraft.id)")
            return existingDraft
        } else {
            let stack = try stackSvc.createStack(
                title: title,
                description: stackDescription.isEmpty ? nil : stackDescription
            )
            logger.info("Stack created: \(stack.id)")
            return stack
        }
    }

    private func associateTagsWithStack(_ stack: Stack) {
        for tag in selectedTags where !stack.tagObjects.contains(where: { $0.id == tag.id }) {
            stack.tagObjects.append(tag)
            logger.info("Tag '\(tag.name)' associated with stack: \(stack.id)")
        }
    }

    private func createPendingTasks(for stack: Stack) -> [String] {
        guard let taskSvc = taskService else { return [] }
        var failedTasks: [String] = []
        for pendingTask in pendingTasks {
            do {
                let task = try taskSvc.createTask(
                    title: pendingTask.title,
                    description: pendingTask.description,
                    stack: stack
                )
                logger.info("Task created: \(task.id)")
            } catch {
                logger.error("Failed to create task '\(pendingTask.title)': \(error.localizedDescription)")
                failedTasks.append(pendingTask.title)
            }
        }
        return failedTasks
    }

    private func showTaskCreationError(failedTasks: [String]) {
        logger.warning("Stack created but \(failedTasks.count) task(s) failed to create")
        let taskList = failedTasks.prefix(3).joined(separator: ", ")
        let suffix = failedTasks.count > 3 ? " and \(failedTasks.count - 3) more" : ""
        errorMessage = "Stack created but \(failedTasks.count) task(s) failed: \(taskList)\(suffix)"
        showError = true
    }

    // MARK: - Background Save

    /// Saves any pending changes when the app enters background.
    /// This ensures content is preserved if the user switches apps or phone dies.
    func saveOnBackground() {
        guard isCreateMode else { return }
        guard !isCreatingDraft else { return }
        guard let service = stackService else {
            logger.warning("Background save skipped: StackService not initialized")
            return
        }

        if draftStack == nil && !title.isEmpty {
            // Create draft with current content
            do {
                let draft = try service.createStack(
                    title: title,
                    description: stackDescription.isEmpty ? nil : stackDescription,
                    isDraft: true
                )
                draftStack = draft
                logger.info("Background save: created draft \(draft.id)")
                syncManager?.triggerImmediatePush()
            } catch {
                logger.error("Background save failed to create draft: \(error.localizedDescription)")
            }
        } else if let draft = draftStack {
            // Update draft if there are pending changes
            let titleChanged = draft.title != title
            let descriptionChanged = draft.stackDescription != stackDescription
            if titleChanged || descriptionChanged {
                do {
                    try service.updateDraft(
                        draft,
                        title: title.isEmpty ? "Untitled" : title,
                        description: stackDescription.isEmpty ? nil : stackDescription
                    )
                    logger.info("Background save: updated draft \(draft.id)")
                    syncManager?.triggerImmediatePush()
                } catch {
                    logger.error("Background save failed to update draft: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Creates a draft from unsaved content and dismisses the sheet.
    /// Called when user chooses "Save Draft" from the save draft prompt.
    func createDraftAndDismiss() {
        // Only create draft if we don't have one and there's content to save
        if draftStack == nil && !title.isEmpty {
            createDraft(title: title)
        }
        dismiss()
    }
}
