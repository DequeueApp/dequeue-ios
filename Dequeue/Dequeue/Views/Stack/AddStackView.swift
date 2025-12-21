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

    let draft: Stack?

    init(draft: Stack? = nil) {
        self.draft = draft
        if let draft {
            _title = State(initialValue: draft.title)
            _description = State(initialValue: draft.stackDescription ?? "")
        }
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
            .navigationTitle(draft != nil ? "Edit Draft" : "New Stack")
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
                    Button("Create") {
                        createStack()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .onChange(of: title) { _, _ in
                saveDraft()
            }
            .onChange(of: description) { _, _ in
                saveDraft()
            }
        }
    }

    private func saveDraft() {
        guard draft == nil else { return }
        // Auto-save as draft functionality would go here
    }

    private func createStack() {
        let stack: Stack
        if let existingDraft = draft {
            stack = existingDraft
            stack.isDraft = false
        } else {
            stack = Stack(title: title)
        }

        stack.title = title
        stack.stackDescription = description.isEmpty ? nil : description
        stack.updatedAt = Date()
        stack.syncState = .pending

        if draft == nil {
            modelContext.insert(stack)
        }

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
