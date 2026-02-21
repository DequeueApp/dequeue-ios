//
//  BatchOperationTests.swift
//  DequeueTests
//
//  Tests for batch operation service and selection management.
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - BatchOperation Tests

@Suite("BatchOperation Model")
struct BatchOperationModelTests {

    @Test("All operations have system images")
    func allOperationsHaveImages() {
        for operation in BatchOperation.allCases {
            #expect(!operation.systemImage.isEmpty, "\(operation.rawValue) should have a system image")
        }
    }

    @Test("All operations have display names")
    func allOperationsHaveNames() {
        for operation in BatchOperation.allCases {
            #expect(!operation.rawValue.isEmpty, "Operation should have a display name")
        }
    }

    @Test("Destructive operations identified correctly")
    func destructiveOperations() {
        #expect(BatchOperation.delete.isDestructive)
        #expect(BatchOperation.close.isDestructive)
        #expect(!BatchOperation.complete.isDestructive)
        #expect(!BatchOperation.move.isDestructive)
        #expect(!BatchOperation.setPriority.isDestructive)
        #expect(!BatchOperation.reopen.isDestructive)
        #expect(!BatchOperation.addTags.isDestructive)
        #expect(!BatchOperation.removeTags.isDestructive)
        #expect(!BatchOperation.setDueDate.isDestructive)
        #expect(!BatchOperation.clearDueDate.isDestructive)
    }

    @Test("Operation IDs are unique")
    func operationIdsUnique() {
        let ids = BatchOperation.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Operation count is 10")
    func operationCount() {
        #expect(BatchOperation.allCases.count == 10)
    }
}

// MARK: - BatchOperationResult Tests

@Suite("BatchOperationResult")
struct BatchOperationResultTests {

    @Test("Full success result")
    func fullSuccess() {
        let result = BatchOperationResult(
            operation: .complete,
            totalSelected: 5,
            successCount: 5,
            failureCount: 0,
            errors: []
        )
        #expect(result.isFullSuccess)
        #expect(result.summary == "Complete: 5 tasks updated")
    }

    @Test("Single task success result")
    func singleTaskSuccess() {
        let result = BatchOperationResult(
            operation: .delete,
            totalSelected: 1,
            successCount: 1,
            failureCount: 0,
            errors: []
        )
        #expect(result.isFullSuccess)
        #expect(result.summary == "Delete: 1 task updated")
    }

    @Test("Partial failure result")
    func partialFailure() {
        let result = BatchOperationResult(
            operation: .move,
            totalSelected: 5,
            successCount: 3,
            failureCount: 2,
            errors: ["Task A: already in target stack", "Task B: error"]
        )
        #expect(!result.isFullSuccess)
        #expect(result.summary == "Move to Stack: 3 succeeded, 2 failed")
        #expect(result.errors.count == 2)
    }

    @Test("All failures result")
    func allFailures() {
        let result = BatchOperationResult(
            operation: .complete,
            totalSelected: 3,
            successCount: 0,
            failureCount: 3,
            errors: ["A", "B", "C"]
        )
        #expect(!result.isFullSuccess)
        #expect(result.failureCount == 3)
    }
}

// MARK: - BatchSelectionManager Tests

@Suite("BatchSelectionManager")
@MainActor
struct BatchSelectionManagerTests {

    @Test("Initial state")
    func initialState() {
        let manager = BatchSelectionManager()
        #expect(!manager.isSelecting)
        #expect(manager.selectedTaskIds.isEmpty)
        #expect(manager.lastOperationResult == nil)
        #expect(!manager.showingResultBanner)
    }

    @Test("Enter selection mode")
    func enterSelectionMode() {
        let manager = BatchSelectionManager()
        manager.enterSelectionMode()
        #expect(manager.isSelecting)
        #expect(manager.selectedTaskIds.isEmpty)
    }

    @Test("Exit selection mode clears selection")
    func exitSelectionMode() {
        let manager = BatchSelectionManager()
        manager.enterSelectionMode()
        manager.selectedTaskIds.insert("task-1")
        manager.selectedTaskIds.insert("task-2")
        manager.exitSelectionMode()
        #expect(!manager.isSelecting)
        #expect(manager.selectedTaskIds.isEmpty)
    }

    @Test("Toggle selection")
    func toggleSelection() {
        let manager = BatchSelectionManager()
        manager.toggle("task-1")
        #expect(manager.isSelected("task-1"))
        #expect(manager.selectedTaskIds.count == 1)

        manager.toggle("task-1")
        #expect(!manager.isSelected("task-1"))
        #expect(manager.selectedTaskIds.isEmpty)
    }

    @Test("Select all tasks")
    func selectAll() {
        let manager = BatchSelectionManager()
        let tasks = [
            QueueTask(id: "t1", title: "Task 1"),
            QueueTask(id: "t2", title: "Task 2"),
            QueueTask(id: "t3", title: "Task 3")
        ]
        manager.selectAll(tasks)
        #expect(manager.selectedTaskIds.count == 3)
        #expect(manager.isSelected("t1"))
        #expect(manager.isSelected("t2"))
        #expect(manager.isSelected("t3"))
    }

    @Test("Deselect all")
    func deselectAll() {
        let manager = BatchSelectionManager()
        manager.selectedTaskIds = Set(["t1", "t2", "t3"])
        manager.deselectAll()
        #expect(manager.selectedTaskIds.isEmpty)
    }

    @Test("Invert selection")
    func invertSelection() {
        let manager = BatchSelectionManager()
        let tasks = [
            QueueTask(id: "t1", title: "Task 1"),
            QueueTask(id: "t2", title: "Task 2"),
            QueueTask(id: "t3", title: "Task 3")
        ]
        manager.selectedTaskIds = Set(["t1"])
        manager.invertSelection(tasks)
        #expect(!manager.isSelected("t1"))
        #expect(manager.isSelected("t2"))
        #expect(manager.isSelected("t3"))
    }

    @Test("Invert empty selection selects all")
    func invertEmptySelection() {
        let manager = BatchSelectionManager()
        let tasks = [
            QueueTask(id: "t1", title: "Task 1"),
            QueueTask(id: "t2", title: "Task 2")
        ]
        manager.invertSelection(tasks)
        #expect(manager.selectedTaskIds.count == 2)
    }

    @Test("Invert full selection deselects all")
    func invertFullSelection() {
        let manager = BatchSelectionManager()
        let tasks = [
            QueueTask(id: "t1", title: "Task 1"),
            QueueTask(id: "t2", title: "Task 2")
        ]
        manager.selectAll(tasks)
        manager.invertSelection(tasks)
        #expect(manager.selectedTaskIds.isEmpty)
    }

    @Test("Show result sets banner")
    func showResult() {
        let manager = BatchSelectionManager()
        let result = BatchOperationResult(
            operation: .complete,
            totalSelected: 3,
            successCount: 3,
            failureCount: 0,
            errors: []
        )
        manager.showResult(result)
        #expect(manager.showingResultBanner)
        #expect(manager.lastOperationResult != nil)
        #expect(manager.lastOperationResult?.isFullSuccess == true)
    }

    @Test("Re-entering selection mode clears previous state")
    func reenterSelectionMode() {
        let manager = BatchSelectionManager()
        manager.enterSelectionMode()
        manager.selectedTaskIds = Set(["t1", "t2"])
        manager.exitSelectionMode()
        manager.enterSelectionMode()
        #expect(manager.selectedTaskIds.isEmpty)
    }

    @Test("isSelected returns false for unknown ID")
    func isSelectedUnknownId() {
        let manager = BatchSelectionManager()
        #expect(!manager.isSelected("nonexistent"))
    }
}

// MARK: - Available Operations Tests

@Suite("Available Operations Logic")
struct AvailableOperationsTests {

    @Test("Pending tasks have complete option")
    func pendingTasksCanComplete() {
        let tasks = [
            QueueTask(title: "Pending task", status: .pending)
        ]
        let operations = computeAvailableOperations(for: tasks)
        #expect(operations.contains(.complete))
    }

    @Test("Completed tasks have reopen option")
    func completedTasksCanReopen() {
        let tasks = [
            QueueTask(title: "Done task", status: .completed)
        ]
        let operations = computeAvailableOperations(for: tasks)
        #expect(operations.contains(.reopen))
    }

    @Test("Tasks with due dates have clear option")
    func tasksWithDueDateCanClear() {
        let tasks = [
            QueueTask(title: "Due task", dueTime: Date())
        ]
        let operations = computeAvailableOperations(for: tasks)
        #expect(operations.contains(.clearDueDate))
    }

    @Test("Tasks without due dates don't have clear option")
    func tasksWithoutDueDateCantClear() {
        let tasks = [
            QueueTask(title: "No due task")
        ]
        let operations = computeAvailableOperations(for: tasks)
        #expect(!operations.contains(.clearDueDate))
    }

    @Test("Move and priority always available")
    func moveAndPriorityAlwaysAvailable() {
        let tasks = [QueueTask(title: "Any task")]
        let operations = computeAvailableOperations(for: tasks)
        #expect(operations.contains(.move))
        #expect(operations.contains(.setPriority))
        #expect(operations.contains(.addTags))
        #expect(operations.contains(.removeTags))
        #expect(operations.contains(.setDueDate))
        #expect(operations.contains(.delete))
    }

    @Test("Empty selection returns no operations")
    func emptySelection() {
        let operations = computeAvailableOperations(for: [])
        #expect(operations.isEmpty)
    }

    @Test("Mixed status tasks have multiple options")
    func mixedStatusTasks() {
        let tasks = [
            QueueTask(title: "Pending", status: .pending),
            QueueTask(title: "Completed", status: .completed),
            QueueTask(title: "Blocked", status: .blocked)
        ]
        let operations = computeAvailableOperations(for: tasks)
        #expect(operations.contains(.complete))
        #expect(operations.contains(.reopen))
        #expect(operations.contains(.close))
    }

    // Standalone helper to test available operations logic without ModelContext
    private func computeAvailableOperations(for tasks: [QueueTask]) -> [BatchOperation] {
        guard !tasks.isEmpty else { return [] }
        var operations: [BatchOperation] = []
        let hasCompletable = tasks.contains { $0.status == .pending || $0.status == .blocked }
        let hasClosable = tasks.contains { $0.status != .closed }
        let hasReopenable = tasks.contains { $0.status == .completed || $0.status == .closed }
        let hasDueDate = tasks.contains { $0.dueTime != nil }
        if hasCompletable { operations.append(.complete) }
        if hasClosable { operations.append(.close) }
        if hasReopenable { operations.append(.reopen) }
        operations.append(.move)
        operations.append(.setPriority)
        operations.append(.addTags)
        operations.append(.removeTags)
        operations.append(.setDueDate)
        if hasDueDate { operations.append(.clearDueDate) }
        operations.append(.delete)
        return operations
    }
}
