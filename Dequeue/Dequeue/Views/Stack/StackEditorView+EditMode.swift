//
//  StackEditorView+EditMode.swift
//  Dequeue
//
//  Edit mode content and actions for StackEditorView
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.dequeue", category: "StackEditorView+EditMode")

// MARK: - Edit Mode Content

extension StackEditorView {
    var editModeContent: some View {
        List {
            descriptionSection
            editModeTagsSection
            pendingTasksSection

            if case .edit(let stack) = mode, !stack.completedTasks.isEmpty {
                completedTasksSection
            }

            remindersSection
            attachmentsSection
            actionsSection
            detailsSection
            eventHistorySection
        }
    }

    // MARK: - Tags Section

    @ViewBuilder
    var editModeTagsSection: some View {
        if case .edit(let stack) = mode {
            Section("Tags") {
                TagInputView(
                    selectedTags: Binding(
                        get: { stack.tagObjects.filter { !$0.isDeleted } },
                        set: { _ in }
                    ),
                    allTags: allTags,
                    onTagAdded: { tag in
                        addTagToStack(tag, stack: stack)
                    },
                    onTagRemoved: { tag in
                        removeTagFromStack(tag, stack: stack)
                    },
                    onNewTagCreated: { name in
                        createAndAddTag(name: name, stack: stack)
                    }
                )
            }
        }
    }

    private func addTagToStack(_ tag: Tag, stack: Stack) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.addTag(tag, to: stack)
        } catch {
            handleError(error)
        }
    }

    private func removeTagFromStack(_ tag: Tag, stack: Stack) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.removeTag(tag, from: stack)
        } catch {
            handleError(error)
        }
    }

    private func createAndAddTag(name: String, stack: Stack) -> Tag? {
        guard let service = tagService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return nil
        }
        do {
            let tag = try service.findOrCreateTag(name: name)
            addTagToStack(tag, stack: stack)
            return tag
        } catch {
            handleError(error)
            return nil
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
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        do {
            try service.setAsActive(stack)
            dismiss()
        } catch {
            handleError(error)
        }
    }

    func deactivateStack() {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        do {
            try service.deactivateStack(stack)
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

    func saveStackTitle() {
        logger.info("saveStackTitle: editedTitle='\(self.editedTitle)'")
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("saveStackTitle: trimmedTitle='\(trimmedTitle)'")
        guard !trimmedTitle.isEmpty else {
            logger.warning("saveStackTitle: trimmedTitle is empty, returning")
            return
        }
        guard case .edit(let stack) = mode else {
            logger.warning("saveStackTitle: not in edit mode, returning")
            return
        }
        logger.info("saveStackTitle: current stack.title='\(stack.title)'")
        guard let service = stackService else {
            logger.error("saveStackTitle: stackService is nil")
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        do {
            logger.info("saveStackTitle: calling updateStack with title='\(trimmedTitle)'")
            try service.updateStack(
                stack,
                title: trimmedTitle,
                description: stack.stackDescription
            )
            logger.info("saveStackTitle: after updateStack, stack.title='\(stack.title)'")
            editedTitle = ""
        } catch {
            logger.error("saveStackTitle: error - \(error.localizedDescription)")
            handleError(error)
        }
    }

    func saveDescription() {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        do {
            try service.updateStack(
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
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            if task.status != .completed {
                try service.markAsCompleted(task)
            }
        } catch {
            handleError(error)
        }
    }

    func setTaskActive(_ task: QueueTask) {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        do {
            try service.activateTask(task)
        } catch {
            handleError(error)
        }
    }

    func moveTask(from source: IndexSet, to destination: Int) {
        guard case .edit(let stack) = mode else { return }
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        var tasks = stack.pendingTasks
        tasks.move(fromOffsets: source, toOffset: destination)

        do {
            try service.updateSortOrders(tasks)
        } catch {
            handleError(error)
        }
    }

    func completeStack(completeAllTasks: Bool) {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        do {
            try service.markAsCompleted(stack, completeAllTasks: completeAllTasks)
            dismiss()
        } catch {
            handleError(error)
        }
    }

    func closeStack() {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        do {
            try service.closeStack(stack)
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
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        do {
            _ = try service.createTask(
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
