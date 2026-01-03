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
                    .onSubmit {
                        // Save draft on submit (pressing Enter)
                        saveDraftIfNeeded()
                    }
                    .onChange(of: title) { _, newValue in
                        // Only create draft on first character, don't update on every keystroke
                        if draftStack == nil && !newValue.isEmpty && !isCreatingDraft {
                            createDraft(title: newValue)
                        }
                    }
                TextField("Description (optional)", text: $stackDescription, axis: .vertical)
                    .lineLimit(3...6)
                    .onSubmit {
                        // Save draft on submit
                        saveDraftIfNeeded()
                    }
            }

            Section("First Task") {
                TextField("Task title (optional)", text: $firstTaskTitle)
            }

            // Reminders section - only show when draft exists
            if draftStack != nil {
                remindersSection
            }

            // Event history section - show when draft exists (either new or editing existing)
            if currentStack != nil {
                draftEventHistorySection
            }
        }
        .onDisappear {
            // Save any pending changes when view disappears (blur equivalent)
            saveDraftIfNeeded()
        }
    }

    /// Event history section for drafts
    private var draftEventHistorySection: some View {
        Section {
            if let draft = currentStack {
                NavigationLink {
                    StackHistoryView(stack: draft)
                } label: {
                    Label("Event History", systemImage: "clock.arrow.circlepath")
                }
            }
        } footer: {
            Text("View the complete history of changes to this draft")
        }
    }

    /// Saves the draft if it exists and has changes
    func saveDraftIfNeeded() {
        // Use currentStack to handle both new drafts and editing existing drafts
        guard let draft = currentStack, draft.isDraft else { return }

        let currentTitle = title.isEmpty ? "Untitled" : title
        let currentDescription = stackDescription.isEmpty ? nil : stackDescription

        // Only save if there are actual changes
        if draft.title != currentTitle || draft.stackDescription != currentDescription {
            updateDraft(draft, title: currentTitle, description: stackDescription)
        }
    }

    // MARK: - Create Mode Actions

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
        } catch {
            logger.error("Failed to create draft: \(error.localizedDescription)")
            errorMessage = "Failed to save draft: \(error.localizedDescription)"
            showError = true
        }

        isCreatingDraft = false
    }

    func updateDraft(_ draft: Stack, title: String, description: String) {
        do {
            try stackService.updateDraft(
                draft,
                title: title.isEmpty ? "Untitled" : title,
                description: description.isEmpty ? nil : description
            )
            logger.debug("Auto-updated draft: \(draft.id)")
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

            // Add first task if provided
            if !firstTaskTitle.isEmpty {
                let task = try taskService.createTask(
                    title: firstTaskTitle,
                    stack: stack
                )
                logger.info("Task created: \(task.id)")
            }

            dismiss()
        } catch {
            logger.error("Failed to create stack: \(error.localizedDescription)")
            errorMessage = "Failed to create stack: \(error.localizedDescription)"
            showError = true
        }
    }
}
