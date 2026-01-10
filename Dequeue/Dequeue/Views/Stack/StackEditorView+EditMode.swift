//
//  StackEditorView+EditMode.swift
//  Dequeue
//
//  Edit mode content and actions for StackEditorView
//

import SwiftUI

// MARK: - Edit Mode Content

extension StackEditorView {
    var editModeContent: some View {
        List {
            descriptionSection
            pendingTasksSection

            if case .edit(let stack) = mode, !stack.completedTasks.isEmpty {
                completedTasksSection
            }

            remindersSection
            actionsSection
            detailsSection
            eventHistorySection
        }
    }

    // MARK: - Description Section

    var descriptionSection: some View {
        Section {
            descriptionContent
        } header: {
            Text("Description")
        }
    }

    @ViewBuilder
    var descriptionContent: some View {
        if case .edit(let stack) = mode {
            if isReadOnly {
                if let description = stack.stackDescription, !description.isEmpty {
                    Text(description).foregroundStyle(.primary)
                } else {
                    Text("No description").foregroundStyle(.secondary)
                }
            } else if isEditingDescription {
                descriptionEditingView
            } else {
                descriptionDisplayButton(for: stack)
            }
        }
    }

    var descriptionEditingView: some View {
        Group {
            TextField("Description", text: $editedDescription, axis: .vertical)
                .lineLimit(3...6)
                .onSubmit { saveDescription() }

            HStack {
                Button("Cancel") {
                    isEditingDescription = false
                    if case .edit(let stack) = mode {
                        editedDescription = stack.stackDescription ?? ""
                    }
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button("Save") { saveDescription() }
                    .fontWeight(.medium)
            }
        }
    }

    func descriptionDisplayButton(for stack: Stack) -> some View {
        Button {
            editedDescription = stack.stackDescription ?? ""
            isEditingDescription = true
        } label: {
            HStack {
                if let description = stack.stackDescription, !description.isEmpty {
                    Text(description).foregroundStyle(.primary)
                } else {
                    Text("Add description...").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tasks Section

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
    }

    @ViewBuilder
    func taskListContent(for stack: Stack) -> some View {
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

    // MARK: - Actions Section

    @ViewBuilder
    var actionsSection: some View {
        if !isReadOnly && !isCreateMode {
            Section {
                if case .edit(let stack) = mode {
                    if stack.isActive {
                        Button {
                            deactivateStack()
                        } label: {
                            Label("Deactivate Stack", systemImage: "star.slash")
                        }
                    } else {
                        Button {
                            setStackActive()
                        } label: {
                            Label("Set as Active Stack", systemImage: "star.fill")
                        }
                    }
                }

                Button(role: .destructive) {
                    showCloseConfirmation = true
                } label: {
                    Label("Close Without Completing", systemImage: "xmark.circle")
                }
            }
        }
    }

    func setStackActive() {
        guard case .edit(let stack) = mode else { return }

        do {
            try stackService.setAsActive(stack)
            dismiss()
        } catch {
            handleError(error)
        }
    }

    func deactivateStack() {
        guard case .edit(let stack) = mode else { return }

        do {
            try stackService.deactivateStack(stack)
            dismiss()
        } catch {
            handleError(error)
        }
    }

    @ViewBuilder
    var detailsSection: some View {
        if case .edit(let stack) = mode {
            Section {
                LabeledContent("Created", value: stack.createdAt.smartFormatted())
            }
        }
    }

    var eventHistorySection: some View {
        Section {
            if case .edit(let stack) = mode {
                NavigationLink {
                    StackHistoryView(stack: stack)
                } label: {
                    Label("Event History", systemImage: "clock.arrow.circlepath")
                }
            }
        } footer: {
            Text("View the complete history of changes to this stack")
        }
    }

    // MARK: - Edit Mode Actions

    func saveDescription() {
        guard case .edit(let stack) = mode else { return }

        do {
            try stackService.updateStack(
                stack,
                title: stack.title,
                description: editedDescription.isEmpty ? nil : editedDescription
            )
            isEditingDescription = false
        } catch {
            handleError(error)
        }
    }

    func toggleTaskComplete(_ task: QueueTask) {
        do {
            if task.status != .completed {
                try taskService.markAsCompleted(task)
            }
        } catch {
            handleError(error)
        }
    }

    func setTaskActive(_ task: QueueTask) {
        do {
            try taskService.activateTask(task)
        } catch {
            handleError(error)
        }
    }

    func moveTask(from source: IndexSet, to destination: Int) {
        guard case .edit(let stack) = mode else { return }

        var tasks = stack.pendingTasks
        tasks.move(fromOffsets: source, toOffset: destination)

        do {
            try taskService.updateSortOrders(tasks)
        } catch {
            handleError(error)
        }
    }

    func completeStack(completeAllTasks: Bool) {
        guard case .edit(let stack) = mode else { return }

        do {
            try stackService.markAsCompleted(stack, completeAllTasks: completeAllTasks)
            dismiss()
        } catch {
            handleError(error)
        }
    }

    func closeStack() {
        guard case .edit(let stack) = mode else { return }

        do {
            try stackService.closeStack(stack)
            dismiss()
        } catch {
            handleError(error)
        }
    }

    func addTask() {
        guard !newTaskTitle.isEmpty else { return }

        // In create mode (or draft mode), add to pending tasks array
        if isCreateMode {
            let pendingTask = StackEditorView.PendingTask(
                title: newTaskTitle,
                description: newTaskDescription.isEmpty ? nil : newTaskDescription
            )
            pendingTasks.append(pendingTask)
            newTaskTitle = ""
            newTaskDescription = ""
            showAddTask = false
            return
        }

        // In edit mode, create actual task
        guard let stack = currentStack else { return }

        do {
            _ = try taskService.createTask(
                title: newTaskTitle,
                description: newTaskDescription.isEmpty ? nil : newTaskDescription,
                stack: stack
            )
            newTaskTitle = ""
            newTaskDescription = ""
            showAddTask = false
        } catch {
            handleError(error)
        }
    }

    func cancelAddTask() {
        newTaskTitle = ""
        newTaskDescription = ""
        showAddTask = false
    }
}
