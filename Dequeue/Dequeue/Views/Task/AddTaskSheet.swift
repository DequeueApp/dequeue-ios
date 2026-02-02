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
    @Binding var startTime: Date?
    @Binding var dueTime: Date?
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

                Section("Dates") {
                    DatePicker("Start Date", selection: Binding(
                        get: { startTime ?? Date() },
                        set: { startTime = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if startTime != nil {
                            Button(role: .destructive) {
                                startTime = nil
                            } label: {
                                Label("Clear", systemImage: "xmark")
                            }
                        }
                    }

                    DatePicker("Due Date", selection: Binding(
                        get: { dueTime ?? Date() },
                        set: { dueTime = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if dueTime != nil {
                            Button(role: .destructive) {
                                dueTime = nil
                            } label: {
                                Label("Clear", systemImage: "xmark")
                            }
                        }
                    }
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
        #if os(iOS)
        .presentationDetents([.medium])
        #else
        .frame(minWidth: 400, minHeight: 200)
        #endif
    }
}

#Preview {
    AddTaskSheet(
        title: .constant(""),
        description: .constant(""),
        startTime: .constant(nil),
        dueTime: .constant(nil),
        onSave: {},
        onCancel: {}
    )
}
