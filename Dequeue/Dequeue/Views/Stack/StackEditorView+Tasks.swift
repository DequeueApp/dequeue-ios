//
//  StackEditorView+Tasks.swift
//  Dequeue
//
//  Tasks section for StackEditorView (edit mode)
//

import SwiftUI
import SwiftData

// MARK: - Tasks Section

extension StackEditorView {
    var pendingTasksSection: some View {
        Section {
            if case .edit(let stack) = mode {
                if stack.pendingTasks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "checkmark.circle")
                    } description: {
                        Text("All tasks completed!")
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("No pending tasks. All tasks completed!")
                } else {
                    taskListContent(for: stack)
                }
            }
        } header: {
            HStack {
                Text("Tasks")
                Spacer()
                if case .edit(let stack) = mode {
                    Text("\(stack.pendingTasks.count) pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !isReadOnly {
                    if case .edit(let stack) = mode, !stack.pendingTasks.isEmpty {
                        Button {
                            withAnimation {
                                isSelectingTasks.toggle()
                                if !isSelectingTasks {
                                    selectedTaskIds.removeAll()
                                }
                            }
                        } label: {
                            Text(isSelectingTasks ? "Done" : "Select")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("selectTasksButton")
                    }
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
    }

    @ViewBuilder
    func taskListContent(for stack: Stack) -> some View {
        if isSelectingTasks {
            // Multi-select mode
            ForEach(stack.pendingTasks) { task in
                selectableTaskRow(task: task, stack: stack)
            }

            // Batch action toolbar
            if !selectedTaskIds.isEmpty {
                batchActionBar
            }
        } else {
            // Normal mode
            let taskList = ForEach(stack.pendingTasks) { task in
                NavigationLink {
                    TaskDetailView(task: task)
                } label: {
                    TaskRowView(
                        task: task,
                        isActive: task.id == stack.activeTask?.id,
                        onToggleComplete: isReadOnly ? nil : { toggleTaskComplete(task) },
                        onSetActive: isReadOnly ? nil : { setTaskActive(task) }
                    )
                }
                .buttonStyle(.plain)
            }

            if isReadOnly {
                taskList
            } else {
                taskList.onMove(perform: moveTask)
            }
        }
    }

    var completedTasksSection: some View {
        Section {
            if case .edit(let stack) = mode {
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
    }

    // MARK: - Selectable Task Row

    private func selectableTaskRow(task: QueueTask, stack: Stack) -> some View {
        let isSelected = selectedTaskIds.contains(task.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedTaskIds.remove(task.id)
                } else {
                    selectedTaskIds.insert(task.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Selection checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)

                // Task info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(task.title)
                            .fontWeight(task.id == stack.activeTask?.id ? .semibold : .regular)
                        if task.id == stack.activeTask?.id {
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
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.blue.opacity(0.06) : nil)
        .accessibilityLabel("\(task.title)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Batch Action Bar

    var batchActionBar: some View {
        VStack(spacing: 8) {
            Divider()

            if batchOperationInProgress {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let result = batchOperationResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(result)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { batchOperationResult = nil }
                    }
                }
            } else {
                HStack(spacing: 16) {
                    Text("\(selectedTaskIds.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Select All / Deselect All
                    if case .edit(let stack) = mode {
                        let allSelected = selectedTaskIds.count == stack.pendingTasks.count
                        Button {
                            withAnimation {
                                if allSelected {
                                    selectedTaskIds.removeAll()
                                } else {
                                    selectedTaskIds = Set(stack.pendingTasks.map(\.id))
                                }
                            }
                        } label: {
                            Text(allSelected ? "Deselect All" : "Select All")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack(spacing: 12) {
                    // Complete
                    Button {
                        batchCompleteSelected()
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .accessibilityIdentifier("batchCompleteButton")

                    // Move
                    Button {
                        showBatchMoveSheet = true
                    } label: {
                        Label("Move", systemImage: "arrow.right.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .accessibilityIdentifier("batchMoveButton")

                    // Delete
                    Button {
                        showBatchDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityIdentifier("batchDeleteButton")
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .confirmationDialog(
            "Delete \(selectedTaskIds.count) Tasks",
            isPresented: $showBatchDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedTaskIds.count) Tasks", role: .destructive) {
                batchDeleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(selectedTaskIds.count) tasks? This cannot be undone.")
        }
        .sheet(isPresented: $showBatchMoveSheet) {
            BatchMoveStackPicker(
                selectedTaskIds: selectedTaskIds,
                currentStackId: {
                    if case .edit(let stack) = mode { return stack.id }
                    return nil
                }(),
                onMove: { targetStack in
                    batchMoveSelected(to: targetStack)
                }
            )
        }
    }

    // MARK: - Batch Operations (Local)

    /// Batch complete selected tasks using local TaskService.
    /// Falls back to individual operations for immediate local consistency.
    func batchCompleteSelected() {
        guard case .edit = mode, let taskService else { return }

        batchOperationInProgress = true
        let taskIds = selectedTaskIds

        Task {
            var completed = 0
            if case .edit(let stack) = mode {
                for task in stack.pendingTasks where taskIds.contains(task.id) {
                    do {
                        try await taskService.markAsCompleted(task)
                        completed += 1
                    } catch {
                        handleError(error)
                    }
                }
            }

            withAnimation {
                batchOperationInProgress = false
                batchOperationResult = "Completed \(completed) task\(completed == 1 ? "" : "s")"
                selectedTaskIds.removeAll()
            }

            // Exit selection mode after a short delay
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                isSelectingTasks = false
                batchOperationResult = nil
            }
        }
    }

    /// Batch delete selected tasks using local TaskService.
    func batchDeleteSelected() {
        guard case .edit = mode, let taskService else { return }

        batchOperationInProgress = true
        let taskIds = selectedTaskIds

        Task {
            var deleted = 0
            if case .edit(let stack) = mode {
                for task in stack.pendingTasks where taskIds.contains(task.id) {
                    do {
                        try await taskService.deleteTask(task)
                        deleted += 1
                    } catch {
                        handleError(error)
                    }
                }
            }

            withAnimation {
                batchOperationInProgress = false
                batchOperationResult = "Deleted \(deleted) task\(deleted == 1 ? "" : "s")"
                selectedTaskIds.removeAll()
            }

            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                isSelectingTasks = false
                batchOperationResult = nil
            }
        }
    }

    /// Batch move selected tasks to another stack.
    func batchMoveSelected(to targetStack: Stack) {
        guard case .edit(let currentStack) = mode, let taskService else { return }

        batchOperationInProgress = true
        let taskIds = selectedTaskIds

        Task {
            var moved = 0
            let tasksToMove = currentStack.pendingTasks.filter { taskIds.contains($0.id) }

            for task in tasksToMove {
                do {
                    try await taskService.moveTask(task, to: targetStack)
                    moved += 1
                } catch {
                    handleError(error)
                }
            }

            withAnimation {
                batchOperationInProgress = false
                batchOperationResult = "Moved \(moved) task\(moved == 1 ? "" : "s") to \(targetStack.title)"
                selectedTaskIds.removeAll()
            }

            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                isSelectingTasks = false
                batchOperationResult = nil
            }
        }
    }
}

// MARK: - Batch Move Stack Picker

/// Sheet for selecting a target stack when batch moving tasks
struct BatchMoveStackPicker: View {
    let selectedTaskIds: Set<String>
    let currentStackId: String?
    let onMove: (Stack) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var availableStacks: [Stack] = []

    var body: some View {
        NavigationStack {
            List {
                if availableStacks.isEmpty {
                    ContentUnavailableView {
                        Label("No Other Stacks", systemImage: "square.stack.3d.up.slash")
                    } description: {
                        Text("Create another stack to move tasks to.")
                    }
                } else {
                    Section {
                        ForEach(availableStacks) { stack in
                            Button {
                                onMove(stack)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stack.title)
                                            .font(.body)
                                            .foregroundStyle(.primary)

                                        Text("\(stack.pendingTasks.count) tasks")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: {
                        Text("Move \(selectedTaskIds.count) task\(selectedTaskIds.count == 1 ? "" : "s") to:")
                    }
                }
            }
            .navigationTitle("Move Tasks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                loadStacks()
            }
        }
    }

    private func loadStacks() {
        let predicate = #Predicate<Stack> { stack in
            !stack.isDeleted
        }
        var descriptor = FetchDescriptor<Stack>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50

        if let stacks = try? modelContext.fetch(descriptor) {
            availableStacks = stacks.filter { stack in
                stack.id != currentStackId &&
                stack.status != .completed &&
                stack.status != .closed
            }
        }
    }
}
