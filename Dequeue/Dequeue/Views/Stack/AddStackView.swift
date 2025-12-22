//
//  AddStackView.swift
//  Dequeue
//
//  Create or edit a stack with auto-save draft behavior
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "AddStackView")

struct AddStackView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var firstTaskTitle: String = ""
    @State private var currentDraft: Stack?
    @State private var showDiscardAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var isCreatingDraft = false

    let initialDraft: Stack?

    init(draft: Stack? = nil) {
        self.initialDraft = draft
        if let draft {
            _title = State(initialValue: draft.title)
            _description = State(initialValue: draft.stackDescription ?? "")
            _currentDraft = State(initialValue: draft)
        }
    }

    private var hasContent: Bool {
        !title.isEmpty || !description.isEmpty || !firstTaskTitle.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stack") {
                    TextField("Title", text: $title)
                        .onChange(of: title) { _, newValue in
                            handleTitleChange(newValue)
                        }
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: description) { _, newValue in
                            handleDescriptionChange(newValue)
                        }
                }

                Section("First Task") {
                    TextField("Task title", text: $firstTaskTitle)
                }
            }
            .navigationTitle(currentDraft != nil ? "Edit Draft" : "New Stack")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        handleCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createStack()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .alert("Discard Draft?", isPresented: $showDiscardAlert) {
                Button("Keep Draft") {
                    // Draft is already auto-saved, just dismiss
                    dismiss()
                }
                Button("Discard", role: .destructive) {
                    discardAndDismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your draft has been auto-saved. Would you like to keep it or discard it?")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Auto-Save Draft Behavior

    private func handleTitleChange(_ newTitle: String) {
        guard !isCreatingDraft else { return }

        if currentDraft == nil && !newTitle.isEmpty {
            // Create a new draft when user first enters a title
            createDraftAsync(title: newTitle)
        } else if let draft = currentDraft {
            // Update existing draft
            updateDraftAsync(draft, title: newTitle, description: description)
        }
    }

    private func handleDescriptionChange(_ newDescription: String) {
        guard let draft = currentDraft else { return }
        updateDraftAsync(draft, title: title, description: newDescription)
    }

    private func createDraftAsync(title: String) {
        isCreatingDraft = true
        let stackService = StackService(modelContext: modelContext)

        do {
            let draft = try stackService.createStack(
                title: title,
                description: description.isEmpty ? nil : description,
                isDraft: true
            )
            currentDraft = draft
            logger.info("Auto-created draft: \(draft.id)")
        } catch {
            logger.error("Failed to create draft: \(error.localizedDescription)")
            errorMessage = "Failed to save draft: \(error.localizedDescription)"
            showErrorAlert = true
        }

        isCreatingDraft = false
    }

    private func updateDraftAsync(_ draft: Stack, title: String, description: String) {
        let stackService = StackService(modelContext: modelContext)

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

    // MARK: - Actions

    private func handleCancel() {
        if currentDraft != nil {
            // Draft exists (either new or editing) - ask what to do
            showDiscardAlert = true
        } else {
            // No content entered, just dismiss
            dismiss()
        }
    }

    private func discardAndDismiss() {
        if let draft = currentDraft {
            let stackService = StackService(modelContext: modelContext)
            do {
                try stackService.discardDraft(draft)
                logger.info("Draft discarded: \(draft.id)")
            } catch {
                logger.error("Failed to discard draft: \(error.localizedDescription)")
            }
        }
        dismiss()
    }

    private func createStack() {
        let stackService = StackService(modelContext: modelContext)
        let taskService = TaskService(modelContext: modelContext)

        do {
            let stack: Stack

            if let existingDraft = currentDraft {
                // Publishing a draft - update it and publish
                existingDraft.title = title
                existingDraft.stackDescription = description.isEmpty ? nil : description
                try stackService.publishDraft(existingDraft)
                stack = existingDraft
                logger.info("Draft published as stack: \(stack.id)")
            } else {
                // Create new stack directly (no draft was created yet)
                stack = try stackService.createStack(
                    title: title,
                    description: description.isEmpty ? nil : description
                )
                logger.info("Stack created: \(stack.id)")
            }

            // Add first task if provided (records task.created event)
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
            showErrorAlert = true
        }
    }
}

#Preview {
    AddStackView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
