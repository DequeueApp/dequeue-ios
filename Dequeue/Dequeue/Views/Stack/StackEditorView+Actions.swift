//
//  StackEditorView+Actions.swift
//  Dequeue
//
//  Action methods for StackEditorView (task and stack operations)
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "StackEditorView+Actions")

// MARK: - Stack Actions

extension StackEditorView {
    func setStackActive() {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        // Cancel any existing task to prevent overlapping operations
        activeStatusTask?.cancel()

        isTogglingActiveStatus = true
        activeStatusTask = Task {
            do {
                try await service.setAsActive(stack)
                // Check cancellation before updating UI state
                // If task was cancelled (e.g., view dismissed), skip state updates
                guard !Task.isCancelled else { return }
                // Ensure UI state updates happen on the main thread
                await MainActor.run {
                    isTogglingActiveStatus = false
                    // Dismiss to return to stack list - intentional UX decision
                    dismiss()
                }
            } catch {
                // Check cancellation before updating UI state
                // If task was cancelled (e.g., view dismissed), skip state updates
                guard !Task.isCancelled else { return }
                // Ensure UI state updates happen on the main thread
                await MainActor.run {
                    isTogglingActiveStatus = false
                    handleError(error)
                }
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

        // Cancel any existing task to prevent overlapping operations
        activeStatusTask?.cancel()

        isTogglingActiveStatus = true
        activeStatusTask = Task {
            do {
                try await service.deactivateStack(stack)
                // Check cancellation before updating UI state
                // If task was cancelled (e.g., view dismissed), skip state updates
                guard !Task.isCancelled else { return }
                // Ensure UI state updates happen on the main thread
                await MainActor.run {
                    isTogglingActiveStatus = false
                    // Dismiss to return to stack list - intentional UX decision
                    dismiss()
                }
            } catch {
                // Check cancellation before updating UI state
                // If task was cancelled (e.g., view dismissed), skip state updates
                guard !Task.isCancelled else { return }
                // Ensure UI state updates happen on the main thread
                await MainActor.run {
                    isTogglingActiveStatus = false
                    handleError(error)
                }
            }
        }
    }

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

    func deleteStack() {
        guard case .edit(let stack) = mode else { return }
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }

        Task {
            do {
                try await service.deleteStack(stack)
                dismiss()
            } catch {
                handleError(error)
            }
        }
    }
}

// MARK: - Task Actions

extension StackEditorView {
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

    func addTask() {
        guard !newTaskTitle.isEmpty else { return }

        // In create mode (or draft mode), add to pending tasks array
        if isCreateMode {
            let pendingTask = StackEditorView.PendingTask(
                title: newTaskTitle,
                description: newTaskDescription.isEmpty ? nil : newTaskDescription,
                startTime: newTaskStartTime,
                dueTime: newTaskDueTime,
                recurrenceRule: newTaskRecurrenceRule
            )
            pendingTasks.append(pendingTask)
            newTaskTitle = ""
            newTaskDescription = ""
            newTaskStartTime = nil
            newTaskDueTime = nil
            newTaskRecurrenceRule = nil
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

        let recurrenceRule = newTaskRecurrenceRule
        Task {
            do {
                let task = try await service.createTask(
                    title: newTaskTitle,
                    description: newTaskDescription.isEmpty ? nil : newTaskDescription,
                    startTime: newTaskStartTime,
                    dueTime: newTaskDueTime,
                    stack: stack
                )
                // Set recurrence rule if specified
                if let rule = recurrenceRule {
                    task.recurrenceRule = rule
                    task.updatedAt = Date()
                    task.syncState = .pending
                    try modelContext.save()
                }
                newTaskTitle = ""
                newTaskDescription = ""
                newTaskStartTime = nil
                newTaskDueTime = nil
                newTaskRecurrenceRule = nil
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
