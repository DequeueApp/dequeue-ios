//
//  AddTaskSheet.swift
//  Dequeue
//
//  Sheet for adding a new task to a stack
//

import SwiftUI

struct AddTaskSheet: View {
    @Binding var title: String
    @Binding var description: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $title)
                        .accessibilityIdentifier("taskTitleField")
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("taskDescriptionField")
                }
            }
            .navigationTitle("New Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave()
                    }
                    .disabled(title.isEmpty)
                    .accessibilityIdentifier("addTaskSaveButton")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    AddTaskSheet(
        title: .constant(""),
        description: .constant(""),
        onSave: {},
        onCancel: {}
    )
}
