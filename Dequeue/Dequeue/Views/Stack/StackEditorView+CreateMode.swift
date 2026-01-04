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
                    .onChange(of: title) { _, newValue in
                        handleTitleChange(newValue)
                    }
                TextField("Description (optional)", text: $stackDescription, axis: .vertical)
                    .lineLimit(3...6)
                    .onChange(of: stackDescription) { _, newValue in
                        handleDescriptionChange(newValue)
                    }
            }

            createModeTasksSection

            // Reminders section - only show when draft exists
            if draftStack != nil {
                remindersSection
            }
        }
    }

    // MARK: - Create Mode Tasks Section

    var createModeTasksSection: some View {
        Section {
            if pendingTasks.isEmpty {
                HStack {
                    Label("No Tasks", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
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
                .accessibilityIdentifier("addTaskButton")
            }
        }
    }

    func deleteCreateModeTasks(at offsets: IndexSet) {
        pendingTasks.remove(atOffsets: offsets)
    }

    // MARK: - Create Mode Actions

    func handleTitleChange(_ newTitle: String) {
        guard !isCreatingDraft else { return }

        if draftStack == nil && !newTitle.isEmpty {
            createDraft(title: newTitle)
        } else if let draft = draftStack {
            updateDraft(draft, title: newTitle, description: stackDescription)
        }
    }

    func handleDescriptionChange(_ newDescription: String) {
        guard let draft = draftStack else { return }
        updateDraft(draft, title: title, description: newDescription)
    }

    func createDraft(title: String) {
        isCreatingDraft = true

        do {
            let draft = try stackService.createStack(
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

        do {
            try stackService.updateDraft(
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
        if draftStack != nil {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }

    func discardDraftAndDismiss() {
        if let draft = draftStack {
            do {
                try stackService.discardDraft(draft)
                logger.info("Draft discarded: \(draft.id)")
                syncManager?.triggerImmediatePush()
            } catch {
                logger.error("Failed to discard draft: \(error.localizedDescription)")
            }
        }
        dismiss()
    }

    func publishAndCreate() {
        do {
            let stack: Stack

            if let existingDraft = draftStack {
                existingDraft.title = title
                existingDraft.stackDescription = stackDescription.isEmpty ? nil : stackDescription
                try stackService.publishDraft(existingDraft)
                stack = existingDraft
                logger.info("Draft published as stack: \(stack.id)")
            } else {
                stack = try stackService.createStack(
                    title: title,
                    description: stackDescription.isEmpty ? nil : stackDescription
                )
                logger.info("Stack created: \(stack.id)")
            }

            // Create all pending tasks
            for pendingTask in pendingTasks {
                let task = try taskService.createTask(
                    title: pendingTask.title,
                    description: pendingTask.description,
                    stack: stack
                )
                logger.info("Task created: \(task.id)")
            }

            syncManager?.triggerImmediatePush()
            dismiss()
        } catch {
            logger.error("Failed to create stack: \(error.localizedDescription)")
            errorMessage = "Failed to create stack: \(error.localizedDescription)"
            showError = true
        }
    }
}
