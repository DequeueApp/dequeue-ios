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
            titleSection
            completionStatusBanner
            activeStatusBanner
            descriptionSection
            datesSection
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

    // MARK: - Inline Title Section

    @ViewBuilder
    var titleSection: some View {
        // Only show inline title for non-draft stacks in edit mode.
        // Draft stacks use createModeContent (routed via isCreateMode) which has its own title field.
        if case .edit(let stack) = mode, !stack.isDraft {
            Section {
                if isReadOnly {
                    Text(stack.title)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel(stack.title)
                } else {
                    TextField(
                        "Stack title",
                        text: Binding(
                            get: { isEditingTitle ? editedTitle : stack.title },
                            set: { editedTitle = $0 }
                        ),
                        axis: .vertical
                    )
                    .font(.largeTitle.bold())
                    .lineLimit(1...10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isEditingTitle ? Color(.systemFill) : Color.clear)
                            .padding(.horizontal, -8)
                    )
                    .focused($titleFocused)
                    .onChange(of: titleFocused) { _, focused in
                        if focused && !isEditingTitle {
                            editedTitle = stack.title
                            isEditingTitle = true
                        } else if !focused && isEditingTitle {
                            commitTitleEdit()
                        }
                    }
                    .accessibilityLabel("Stack title")
                    .accessibilityHint("Double tap to edit the title")
                    .accessibilityValue(isEditingTitle ? editedTitle : stack.title)
                }
            }
        }
    }

    /// Commit the in-progress title edit, saving if valid or reverting if empty.
    private func commitTitleEdit() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Revert — don't allow blank title
            isEditingTitle = false
            editedTitle = ""
            return
        }
        guard case .edit(let stack) = mode, trimmed != stack.title else {
            // Title unchanged — just exit editing
            isEditingTitle = false
            editedTitle = ""
            return
        }
        // Persist via the existing saveStackTitle path.
        // Keep isEditingTitle = true so the TextField continues showing editedTitle
        // until the model update lands; saveStackTitle() flips it on completion.
        editedTitle = trimmed
        saveStackTitle()
    }

    // MARK: - Completion Status Banner

    @ViewBuilder
    var completionStatusBanner: some View {
        if case .edit(let stack) = mode, stack.status != .active || stack.isDeleted {
            Section {
                StackCompletionStatusBanner(stack: stack)
            }
        }
    }

    // MARK: - Active Status Banner

    @ViewBuilder
    var activeStatusBanner: some View {
        if case .edit(let stack) = mode, !isReadOnly {
            Section {
                StackActiveStatusBanner(stack: stack, isLoading: isTogglingActiveStatus) {
                    if stack.isActive {
                        deactivateStack()
                    } else {
                        setStackActive()
                    }
                }
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

    // MARK: - Dates Section

    @ViewBuilder
    var datesSection: some View {
        if case .edit(let stack) = mode, !isReadOnly {
            Section("Dates") {
                OptionalDatePicker(
                    label: "Start Date",
                    icon: "calendar.badge.clock",
                    date: Binding(
                        get: { stack.startTime },
                        set: { newDate in
                            if let newDate {
                                updateStackStartDate(stack: stack, newDate: newDate)
                            } else {
                                clearStackStartDate(stack: stack)
                            }
                        }
                    )
                )

                OptionalDatePicker(
                    label: "Due Date",
                    icon: "calendar.badge.exclamationmark",
                    date: Binding(
                        get: { stack.dueTime },
                        set: { newDate in
                            if let newDate {
                                updateStackDueDate(stack: stack, newDate: newDate)
                            } else {
                                clearStackDueDate(stack: stack)
                            }
                        }
                    )
                )
            }
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

    // MARK: - Date Update Helpers

    private func updateStackStartDate(stack: Stack, newDate: Date) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.updateStackDates(stack, startTime: newDate, dueTime: stack.dueTime)
            } catch {
                handleError(error)
            }
        }
    }

    private func clearStackStartDate(stack: Stack) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.updateStackDates(stack, startTime: nil, dueTime: stack.dueTime)
            } catch {
                handleError(error)
            }
        }
    }

    private func updateStackDueDate(stack: Stack, newDate: Date) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.updateStackDates(stack, startTime: stack.startTime, dueTime: newDate)
            } catch {
                handleError(error)
            }
        }
    }

    private func clearStackDueDate(stack: Stack) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.updateStackDates(stack, startTime: stack.startTime, dueTime: nil)
            } catch {
                handleError(error)
            }
        }
    }
}
