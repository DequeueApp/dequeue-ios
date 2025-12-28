//
//  StackDetailView.swift
//  Dequeue
//
//  View and manage a stack with its tasks
//

// swiftlint:disable file_length

import SwiftUI
import SwiftData

// swiftlint:disable:next type_body_length
struct StackDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var stack: Stack

    @State private var isEditingDescription = false
    @State private var editedDescription = ""
    @State private var showCompletedTasks = false
    @State private var showCloseConfirmation = false
    @State private var showCompleteConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var stackService: StackService {
        StackService(modelContext: modelContext)
    }

    private var taskService: TaskService {
        TaskService(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            List {
                descriptionSection

                pendingTasksSection

                if !stack.completedTasks.isEmpty {
                    completedTasksSection
                }

                actionsSection

                eventHistorySection
            }
            .navigationTitle(stack.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showCompleteConfirmation = true
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                "Complete Stack",
                isPresented: $showCompleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Complete All Tasks & Stack") {
                    completeStack(completeAllTasks: true)
                }
                Button("Complete Stack Only") {
                    completeStack(completeAllTasks: false)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if !stack.pendingTasks.isEmpty {
                    let taskCount = stack.pendingTasks.count
                    Text("This stack has \(taskCount) pending task(s). Would you like to complete them as well?")
                } else {
                    Text("Mark this stack as completed?")
                }
            }
            .confirmationDialog(
                "Close Stack",
                isPresented: $showCloseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Close Without Completing", role: .destructive) {
                    closeStack()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will close the stack without completing it. You can find it in completed stacks later.")
            }
        }
    }

    // MARK: - Sections

    private var descriptionSection: some View {
        Section {
            if isEditingDescription {
                TextField("Description", text: $editedDescription, axis: .vertical)
                    .lineLimit(3...6)
                    .onSubmit {
                        saveDescription()
                    }

                HStack {
                    Button("Cancel") {
                        isEditingDescription = false
                        editedDescription = stack.stackDescription ?? ""
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Save") {
                        saveDescription()
                    }
                    .fontWeight(.medium)
                }
            } else {
                Button {
                    editedDescription = stack.stackDescription ?? ""
                    isEditingDescription = true
                } label: {
                    HStack {
                        if let description = stack.stackDescription, !description.isEmpty {
                            Text(description)
                                .foregroundStyle(.primary)
                        } else {
                            Text("Add description...")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Description")
        }
    }

    private var pendingTasksSection: some View {
        Section {
            if stack.pendingTasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks", systemImage: "checkmark.circle")
                } description: {
                    Text("All tasks completed!")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(stack.pendingTasks) { task in
                    NavigationLink {
                        TaskDetailView(task: task)
                    } label: {
                        TaskRowView(
                            task: task,
                            isActive: task.id == stack.activeTask?.id,
                            onToggleComplete: { toggleTaskComplete(task) },
                            onSetActive: { setTaskActive(task) }
                        )
                    }
                    .buttonStyle(.plain)
                }
                .onMove(perform: moveTask)
            }
        } header: {
            HStack {
                Text("Tasks")
                Spacer()
                Text("\(stack.pendingTasks.count) pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var completedTasksSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showCompletedTasks) {
                ForEach(stack.completedTasks) { task in
                    NavigationLink {
                        TaskDetailView(task: task)
                    } label: {
                        CompletedTaskRowView(task: task)
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                HStack {
                    Text("Completed")
                    Spacer()
                    Text("\(stack.completedTasks.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                showCloseConfirmation = true
            } label: {
                Label("Close Without Completing", systemImage: "xmark.circle")
            }
        }
    }

    private var eventHistorySection: some View {
        Section {
            NavigationLink {
                StackHistoryView(stack: stack)
            } label: {
                Label("Event History", systemImage: "clock.arrow.circlepath")
            }
        } footer: {
            Text("View the complete history of changes to this stack")
        }
    }

    // MARK: - Actions

    private func saveDescription() {
        do {
            try stackService.updateStack(
                stack,
                title: stack.title,
                description: editedDescription.isEmpty ? nil : editedDescription
            )
            isEditingDescription = false
        } catch {
            showError(error)
        }
    }

    private func toggleTaskComplete(_ task: QueueTask) {
        do {
            if task.status == .completed {
                // swiftlint:disable:next todo
                // FIXME: Implement uncomplete if needed
            } else {
                try taskService.markAsCompleted(task)
            }
        } catch {
            showError(error)
        }
    }

    private func setTaskActive(_ task: QueueTask) {
        do {
            try taskService.activateTask(task)
        } catch {
            showError(error)
        }
    }

    private func moveTask(from source: IndexSet, to destination: Int) {
        var tasks = stack.pendingTasks
        tasks.move(fromOffsets: source, toOffset: destination)

        do {
            try taskService.updateSortOrders(tasks)
        } catch {
            showError(error)
        }
    }

    private func completeStack(completeAllTasks: Bool) {
        do {
            try stackService.markAsCompleted(stack, completeAllTasks: completeAllTasks)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func closeStack() {
        do {
            try stackService.closeStack(stack)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        ErrorReportingService.capture(error: error, context: ["view": "StackDetailView"])
    }
}

// MARK: - Task Row View

private struct TaskRowView: View {
    let task: QueueTask
    let isActive: Bool
    let onToggleComplete: () -> Void
    let onSetActive: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggleComplete()
            } label: {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(isActive ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(task.title)
                        .fontWeight(isActive ? .semibold : .regular)

                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                if let description = task.taskDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !isActive {
                Button {
                    onSetActive()
                } label: {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isActive ? Color.blue.opacity(0.08) : nil)
    }
}

// MARK: - Completed Task Row View

private struct CompletedTaskRowView: View {
    let task: QueueTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough()
                    .foregroundStyle(.secondary)

                Text(task.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )

    let stack = Stack(
        title: "Test Stack",
        stackDescription: "This is a test description",
        status: .active,
        sortOrder: 0
    )
    container.mainContext.insert(stack)

    let task1 = QueueTask(title: "First task", taskDescription: "Do this first", status: .pending, sortOrder: 0)
    task1.stack = stack
    container.mainContext.insert(task1)

    let task2 = QueueTask(title: "Second task", status: .pending, sortOrder: 1)
    task2.stack = stack
    container.mainContext.insert(task2)

    let task3 = QueueTask(title: "Completed task", status: .completed, sortOrder: 2)
    task3.stack = stack
    container.mainContext.insert(task3)

    return StackDetailView(stack: stack)
        .modelContainer(container)
}
