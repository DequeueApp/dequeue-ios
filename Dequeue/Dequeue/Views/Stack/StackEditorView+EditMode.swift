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
            activeStatusBanner
            descriptionSection
            editModeTagsSection
            arcSection
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

    // MARK: - Active Status Banner

    @ViewBuilder
    var activeStatusBanner: some View {
        if case .edit(let stack) = mode, !isReadOnly {
            Section {
                Button {
                    if stack.isActive {
                        deactivateStack()
                    } else {
                        setStackActive()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: stack.isActive ? "checkmark.circle.fill" : "star.fill")
                            .font(.title3)
                            .foregroundStyle(stack.isActive ? .green : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stack.isActive ? "Currently Active" : "Start Working")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(stack.isActive
                                 ? "Tap to deactivate this stack"
                                 : "Tap to set as your active stack")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(stack.isActive
                              ? Color.green.opacity(0.1)
                              : Color.orange.opacity(0.1))
                        .padding(.horizontal, -4)
                )
            }
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
        Task {
            do {
                try await service.addTag(tag, to: stack)
            } catch {
                handleError(error)
            }
        }
    }

    private func removeTagFromStack(_ tag: Tag, stack: Stack) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.removeTag(tag, from: stack)
            } catch {
                handleError(error)
            }
        }
    }

    private func createAndAddTag(name: String, stack: Stack) -> Tag? {
        Task { @MainActor in
            guard let service = tagService else {
                errorMessage = "Initializing... please try again."
                showError = true
                return
            }
            do {
                let tag = try await service.findOrCreateTag(name: name)
                addTagToStack(tag, stack: stack)
            } catch {
                handleError(error)
            }
        }
        return nil
    }

    // MARK: - Arc Section

    @ViewBuilder
    var arcSection: some View {
        if case .edit(let stack) = mode, !isReadOnly {
            Section("Arc") {
                Button {
                    showArcPicker = true
                } label: {
                    HStack {
                        if let arc = stack.arc {
                            HStack(spacing: 8) {
                                // Color indicator
                                Circle()
                                    .fill(arcColor(for: arc))
                                    .frame(width: 12, height: 12)

                                Text(arc.title)
                                    .foregroundStyle(.primary)
                            }
                        } else {
                            Text("None")
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showArcPicker) {
                ArcPickerSheet(stack: stack)
            }
        }
    }

    private func arcColor(for arc: Arc) -> Color {
        if let hex = arc.colorHex {
            return Color(hex: hex) ?? .indigo
        }
        return .indigo
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

        Task {
            do {
                try await service.setAsActive(stack)
                dismiss()
            } catch {
                handleError(error)
            }
        }
    }

    func deactivateStack() {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        Task {
            do {
                try await service.deactivateStack(stack)
                dismiss()
            } catch {
                handleError(error)
            }
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
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        Task {
            do {
                try await service.updateStack(stack, title: trimmedTitle, description: stack.stackDescription)
                editedTitle = ""
            } catch {
                handleError(error)
            }
        }
    }

    func saveDescription() {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        Task {
            do {
                try await service.updateStack(
                    stack,
                    title: stack.title,
                    description: editedDescription.isEmpty ? nil : editedDescription
                )
                isEditingDescription = false
            } catch {
                handleError(error)
            }
        }
    }

    func toggleTaskComplete(_ task: QueueTask) {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                if task.status != .completed {
                    try await service.markAsCompleted(task)
                }
            } catch {
                handleError(error)
            }
        }
    }

    func setTaskActive(_ task: QueueTask) {
        guard let service = taskService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.activateTask(task)
            } catch {
                handleError(error)
            }
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

        Task {
            do {
                try await service.updateSortOrders(tasks)
            } catch {
                handleError(error)
            }
        }
    }

    func completeStack(completeAllTasks: Bool) {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        Task {
            do {
                try await service.markAsCompleted(stack, completeAllTasks: completeAllTasks)
                dismiss()
            } catch {
                handleError(error)
            }
        }
    }

    func closeStack() {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        Task {
            do {
                try await service.closeStack(stack)
                dismiss()
            } catch {
                handleError(error)
            }
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

        Task {
            do {
                _ = try await service.createTask(
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
    }

    func cancelAddTask() {
        newTaskTitle = ""
        newTaskDescription = ""
        showAddTask = false
    }
}
