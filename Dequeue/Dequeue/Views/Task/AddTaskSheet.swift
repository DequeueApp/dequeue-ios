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
    @Binding var recurrenceRule: RecurrenceRule?
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var showRecurrencePicker = false

    init(
        title: Binding<String>,
        description: Binding<String>,
        startTime: Binding<Date?>,
        dueTime: Binding<Date?>,
        recurrenceRule: Binding<RecurrenceRule?> = .constant(nil),
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._title = title
        self._description = description
        self._startTime = startTime
        self._dueTime = dueTime
        self._recurrenceRule = recurrenceRule
        self.onSave = onSave
        self.onCancel = onCancel
    }

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
                    DatePicker(
                        "Start Date",
                        selection: Binding(
                            get: { startTime ?? Date() },
                            set: { startTime = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("taskStartDatePicker")
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if startTime != nil {
                            Button(role: .destructive) {
                                startTime = nil
                            } label: {
                                Label("Clear", systemImage: "xmark")
                            }
                        }
                    }

                    DatePicker(
                        "Due Date",
                        selection: Binding(
                            get: { dueTime ?? Date() },
                            set: { dueTime = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("taskDueDatePicker")
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

                Section("Repeat") {
                    Button {
                        showRecurrencePicker = true
                    } label: {
                        HStack {
                            Label("Repeat", systemImage: "repeat")
                            Spacer()
                            if let rule = recurrenceRule {
                                Text(rule.shortText)
                                    .foregroundStyle(.blue)
                            } else {
                                Text("Never")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("recurrenceButton")
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
                    .accessibilityIdentifier("addTaskCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave()
                    }
                    .disabled(title.isEmpty)
                    .accessibilityIdentifier("addTaskSaveButton")
                }
            }
            .sheet(isPresented: $showRecurrencePicker) {
                RecurrencePickerSheet(recurrenceRule: $recurrenceRule)
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
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
        recurrenceRule: .constant(nil),
        onSave: {},
        onCancel: {}
    )
}
