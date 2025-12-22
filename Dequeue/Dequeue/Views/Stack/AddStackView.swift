//
//  AddStackView.swift
//  Dequeue
//
//  Create or edit a stack
//

import SwiftUI
import SwiftData

struct AddStackView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var firstTaskTitle: String = ""
    @State private var currentDraft: Stack?
    @State private var showDiscardAlert = false

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

    private var hasUnsavedChanges: Bool {
        // If we have content but no draft yet, or if draft exists with content
        hasContent && currentDraft == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stack") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
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
            .alert("Save Draft?", isPresented: $showDiscardAlert) {
                Button("Save Draft") {
                    saveDraftAndDismiss()
                }
                Button("Discard", role: .destructive) {
                    discardAndDismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Would you like to save this as a draft?")
            }
        }
    }

    private func handleCancel() {
        if hasContent {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }

    private func saveDraftAndDismiss() {
        if let draft = currentDraft {
            // Update existing draft
            draft.title = title.isEmpty ? "Untitled" : title
            draft.stackDescription = description.isEmpty ? nil : description
            draft.updatedAt = Date()
        } else {
            // Create new draft
            let draft = Stack(
                title: title.isEmpty ? "Untitled" : title,
                stackDescription: description.isEmpty ? nil : description,
                isDraft: true,
                syncState: .pending
            )
            modelContext.insert(draft)

            if !firstTaskTitle.isEmpty {
                let task = QueueTask(title: firstTaskTitle, stack: draft)
                modelContext.insert(task)
                draft.tasks.append(task)
            }
        }

        dismiss()
    }

    private func discardAndDismiss() {
        // If editing an existing draft, delete it
        if let draft = currentDraft, initialDraft != nil {
            draft.isDeleted = true
            draft.updatedAt = Date()
        }
        dismiss()
    }

    private func createStack() {
        let stack: Stack
        if let existingDraft = currentDraft {
            stack = existingDraft
            stack.isDraft = false
        } else {
            stack = Stack(title: title)
            modelContext.insert(stack)
        }

        stack.title = title
        stack.stackDescription = description.isEmpty ? nil : description
        stack.updatedAt = Date()
        stack.syncState = .pending

        if !firstTaskTitle.isEmpty {
            let task = QueueTask(title: firstTaskTitle, stack: stack)
            modelContext.insert(task)
            stack.tasks.append(task)
        }

        dismiss()
    }
}

#Preview {
    AddStackView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
