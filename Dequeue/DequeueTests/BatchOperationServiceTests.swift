//
//  BatchOperationServiceTests.swift
//  DequeueTests
//
//  Tests for BatchOperationService — local batch operations on SwiftData tasks.
//

import Testing
import Foundation
import SwiftData
@testable import Dequeue

// MARK: - Test Helpers

private func makeBatchTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Arc.self,
        Tag.self,
        Attachment.self,
        Device.self,
        SyncConflict.self,
        configurations: config
    )
}

private func makeBatchTask(
    title: String,
    status: TaskStatus = .pending,
    priority: Int? = nil,
    tags: [String] = [],
    dueTime: Date? = nil,
    stack: Stack? = nil,
    in context: ModelContext
) throws -> QueueTask {
    let task = QueueTask(
        title: title,
        dueTime: dueTime,
        tags: tags,
        status: status,
        priority: priority,
        userId: "test-user",
        deviceId: "test-device",
        stack: stack
    )
    context.insert(task)
    try context.save()
    return task
}

// MARK: - BatchOperation Enum Tests

@Suite("BatchOperation Enum", .serialized)
struct BatchOpEnumTests {

    @Test("All operations have unique raw values")
    func uniqueRawValues() {
        let rawValues = BatchOperation.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("All operations have non-empty system images")
    func systemImages() {
        for operation in BatchOperation.allCases {
            #expect(!operation.systemImage.isEmpty, "Missing systemImage for \(operation.rawValue)")
        }
    }

    @Test("Destructive operations are correctly identified")
    func destructiveOperations() {
        #expect(BatchOperation.delete.isDestructive)
        #expect(BatchOperation.close.isDestructive)
        #expect(!BatchOperation.complete.isDestructive)
        #expect(!BatchOperation.reopen.isDestructive)
        #expect(!BatchOperation.move.isDestructive)
        #expect(!BatchOperation.setPriority.isDestructive)
        #expect(!BatchOperation.addTags.isDestructive)
        #expect(!BatchOperation.removeTags.isDestructive)
        #expect(!BatchOperation.setDueDate.isDestructive)
        #expect(!BatchOperation.clearDueDate.isDestructive)
    }

    @Test("Operation id matches raw value")
    func identifiable() {
        for operation in BatchOperation.allCases {
            #expect(operation.id == operation.rawValue)
        }
    }
}

// MARK: - BatchOperationResult Tests

@Suite("BatchOperationResult", .serialized)
struct BatchOpResultTests {

    @Test("Full success result")
    func fullSuccess() {
        let result = BatchOperationResult(
            operation: .complete,
            totalSelected: 3,
            successCount: 3,
            failureCount: 0,
            errors: []
        )
        #expect(result.isFullSuccess)
        #expect(result.summary == "Complete: 3 tasks updated")
    }

    @Test("Single task success uses singular noun")
    func singularNoun() {
        let result = BatchOperationResult(
            operation: .delete,
            totalSelected: 1,
            successCount: 1,
            failureCount: 0,
            errors: []
        )
        #expect(result.summary == "Delete: 1 task updated")
    }

    @Test("Partial failure result")
    func partialFailure() {
        let result = BatchOperationResult(
            operation: .setPriority,
            totalSelected: 5,
            successCount: 3,
            failureCount: 2,
            errors: ["Task A: error", "Task B: error"]
        )
        #expect(!result.isFullSuccess)
        #expect(result.summary == "Set Priority: 3 succeeded, 2 failed")
    }
}

// MARK: - Available Operations Tests

@Suite("BatchOperationService — Available Operations", .serialized)
@MainActor
struct BatchOpAvailableTests {

    @Test("Empty selection returns no operations")
    func emptySelection() throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )
        let ops = service.availableOperations(for: [])
        #expect(ops.isEmpty)
    }

    @Test("Pending tasks show complete and close")
    func pendingTasks() throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Pending", status: .pending, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )
        let ops = service.availableOperations(for: [task])
        #expect(ops.contains(.complete))
        #expect(ops.contains(.close))
        #expect(!ops.contains(.reopen))
    }

    @Test("Completed tasks show reopen but not complete")
    func completedTasks() throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Done", status: .completed, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )
        let ops = service.availableOperations(for: [task])
        #expect(!ops.contains(.complete))
        #expect(ops.contains(.reopen))
    }

    @Test("Closed tasks hide close, show reopen")
    func closedTasks() throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Closed", status: .closed, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )
        let ops = service.availableOperations(for: [task])
        #expect(!ops.contains(.close))
        #expect(ops.contains(.reopen))
    }

    @Test("Tasks with due dates show clearDueDate")
    func withDueDates() throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Due", dueTime: Date(), in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )
        let ops = service.availableOperations(for: [task])
        #expect(ops.contains(.clearDueDate))
        #expect(ops.contains(.setDueDate))
    }

    @Test("Tasks without due dates hide clearDueDate")
    func withoutDueDates() throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "No Due", in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )
        let ops = service.availableOperations(for: [task])
        #expect(!ops.contains(.clearDueDate))
        #expect(ops.contains(.setDueDate))
    }

    @Test("Always-available operations present for any selection")
    func alwaysAvailable() throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Any", in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )
        let ops = service.availableOperations(for: [task])
        #expect(ops.contains(.move))
        #expect(ops.contains(.setPriority))
        #expect(ops.contains(.addTags))
        #expect(ops.contains(.removeTags))
        #expect(ops.contains(.delete))
    }

    @Test("Mixed selection shows all applicable operations")
    func mixedSelection() throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let pending = try makeBatchTask(title: "Pending", status: .pending, in: context)
        let completed = try makeBatchTask(title: "Done", status: .completed, dueTime: Date(), in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )
        let ops = service.availableOperations(for: [pending, completed])
        #expect(ops.contains(.complete))   // pending is completable
        #expect(ops.contains(.reopen))     // completed is reopenable
        #expect(ops.contains(.close))      // pending is closable
        #expect(ops.contains(.clearDueDate)) // completed has due date
    }
}

// MARK: - Batch Complete Tests

@Suite("BatchOperationService — Batch Complete", .serialized)
@MainActor
struct BatchOpCompleteTests {

    @Test("Complete pending tasks")
    func completePendingTasks() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let t1 = try makeBatchTask(title: "Task 1", status: .pending, in: context)
        let t2 = try makeBatchTask(title: "Task 2", status: .pending, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchComplete([t1, t2])

        #expect(result.successCount == 2)
        #expect(result.failureCount == 0)
        #expect(result.isFullSuccess)
        #expect(t1.status == .completed)
        #expect(t2.status == .completed)
    }

    @Test("Complete skips already completed tasks")
    func skipAlreadyCompleted() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let pending = try makeBatchTask(title: "Pending", status: .pending, in: context)
        let done = try makeBatchTask(title: "Done", status: .completed, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchComplete([pending, done])

        #expect(result.successCount == 1)
        #expect(result.failureCount == 1)
        #expect(result.errors.count == 1)
        #expect(pending.status == .completed)
        #expect(done.status == .completed) // unchanged
    }

    @Test("Complete blocked tasks succeeds")
    func completeBlockedTasks() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let blocked = try makeBatchTask(title: "Blocked", status: .blocked, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchComplete([blocked])

        #expect(result.successCount == 1)
        #expect(blocked.status == .completed)
    }

    @Test("Complete sets syncState to pending")
    func setsSyncState() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", status: .pending, in: context)
        task.syncState = .synced
        try context.save()
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        _ = try await service.batchComplete([task])

        #expect(task.syncState == .pending)
    }
}

// MARK: - Batch Close Tests

@Suite("BatchOperationService — Batch Close", .serialized)
@MainActor
struct BatchOpCloseTests {

    @Test("Close pending tasks")
    func closePendingTasks() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let t1 = try makeBatchTask(title: "Task 1", status: .pending, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchClose([t1])

        #expect(result.successCount == 1)
        #expect(result.isFullSuccess)
        #expect(t1.status == .closed)
    }

    @Test("Close skips already closed tasks")
    func skipAlreadyClosed() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let closed = try makeBatchTask(title: "Closed", status: .closed, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchClose([closed])

        #expect(result.successCount == 0)
        #expect(result.failureCount == 1)
    }
}

// MARK: - Batch Reopen Tests

@Suite("BatchOperationService — Batch Reopen", .serialized)
@MainActor
struct BatchOpReopenTests {

    @Test("Reopen completed tasks")
    func reopenCompleted() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Done", status: .completed, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchReopen([task])

        #expect(result.successCount == 1)
        #expect(task.status == .pending)
    }

    @Test("Reopen closed tasks")
    func reopenClosed() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Closed", status: .closed, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchReopen([task])

        #expect(result.successCount == 1)
        #expect(task.status == .pending)
    }

    @Test("Reopen clears blockedReason")
    func clearsBlockedReason() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Completed", status: .completed, in: context)
        task.blockedReason = "was blocked"
        try context.save()
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchReopen([task])

        #expect(result.successCount == 1)
        #expect(task.blockedReason == nil)
    }

    @Test("Reopen skips pending tasks")
    func skipPending() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Pending", status: .pending, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchReopen([task])

        #expect(result.successCount == 0)
        #expect(result.failureCount == 1)
    }
}

// MARK: - Batch Delete Tests

@Suite("BatchOperationService — Batch Delete", .serialized)
@MainActor
struct BatchOpDeleteTests {

    @Test("Delete marks tasks as deleted")
    func softDelete() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let t1 = try makeBatchTask(title: "Task 1", in: context)
        let t2 = try makeBatchTask(title: "Task 2", in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchDelete([t1, t2])

        #expect(result.successCount == 2)
        #expect(result.isFullSuccess)
        #expect(t1.isDeleted)
        #expect(t2.isDeleted)
    }

    @Test("Delete sets syncState to pending")
    func setsSyncState() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", in: context)
        task.syncState = .synced
        try context.save()
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        _ = try await service.batchDelete([task])

        #expect(task.syncState == .pending)
    }
}

// MARK: - Batch Move Tests

@Suite("BatchOperationService — Batch Move", .serialized)
@MainActor
struct BatchOpMoveTests {

    @Test("Move tasks to a different stack")
    func moveToStack() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let sourceStack = Stack(title: "Source")
        let targetStack = Stack(title: "Target")
        context.insert(sourceStack)
        context.insert(targetStack)
        try context.save()

        let task = try makeBatchTask(title: "Moveable", stack: sourceStack, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchMove([task], to: targetStack)

        #expect(result.successCount == 1)
        #expect(result.isFullSuccess)
        #expect(task.stack?.id == targetStack.id)
    }

    @Test("Move skips tasks already in target stack")
    func skipSameStack() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Stack A")
        context.insert(stack)
        try context.save()

        let task = try makeBatchTask(title: "Already Here", stack: stack, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchMove([task], to: stack)

        #expect(result.successCount == 0)
        #expect(result.failureCount == 1)
    }

    @Test("Move assigns sequential sort order")
    func sequentialSortOrder() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let target = Stack(title: "Target")
        context.insert(target)
        try context.save()

        let t1 = try makeBatchTask(title: "First", in: context)
        let t2 = try makeBatchTask(title: "Second", in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchMove([t1, t2], to: target)

        #expect(result.successCount == 2)
        // Sort order should be sequential starting from 0 (empty target stack)
        #expect(t1.sortOrder == 0)
        #expect(t2.sortOrder == 1)
    }
}

// MARK: - Batch Set Priority Tests

@Suite("BatchOperationService — Batch Set Priority", .serialized)
@MainActor
struct BatchOpSetPriorityTests {

    @Test("Set priority on multiple tasks")
    func setPriority() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let t1 = try makeBatchTask(title: "Task 1", priority: 1, in: context)
        let t2 = try makeBatchTask(title: "Task 2", priority: nil, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchSetPriority([t1, t2], priority: 3)

        #expect(result.successCount == 2)
        #expect(result.isFullSuccess)
        #expect(t1.priority == 3)
        #expect(t2.priority == 3)
    }

    @Test("Clear priority by setting nil")
    func clearPriority() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "High", priority: 3, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchSetPriority([task], priority: nil)

        #expect(result.successCount == 1)
        #expect(task.priority == nil)
    }
}

// MARK: - Batch Tag Tests

@Suite("BatchOperationService — Batch Tags", .serialized)
@MainActor
struct BatchOpTagTests {

    @Test("Add tags to tasks")
    func addTags() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", tags: ["existing"], in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchAddTags([task], tags: ["new", "another"])

        #expect(result.successCount == 1)
        #expect(result.isFullSuccess)
        #expect(task.tags.contains("existing"))
        #expect(task.tags.contains("new"))
        #expect(task.tags.contains("another"))
    }

    @Test("Add tags skips tasks that already have all tags")
    func skipDuplicateTags() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", tags: ["work"], in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchAddTags([task], tags: ["work"])

        #expect(result.successCount == 0)
        #expect(result.failureCount == 1)
    }

    @Test("Added tags are sorted")
    func tagsSorted() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", tags: ["zebra"], in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchAddTags([task], tags: ["apple", "mango"])

        #expect(result.successCount == 1)
        #expect(task.tags == ["apple", "mango", "zebra"])
    }

    @Test("Remove tags from tasks")
    func removeTags() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", tags: ["work", "urgent", "review"], in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchRemoveTags([task], tags: ["urgent", "review"])

        #expect(result.successCount == 1)
        #expect(result.isFullSuccess)
        #expect(task.tags == ["work"])
    }

    @Test("Remove tags skips tasks without matching tags")
    func skipNoMatchingTags() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", tags: ["work"], in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchRemoveTags([task], tags: ["nonexistent"])

        #expect(result.successCount == 0)
        #expect(result.failureCount == 1)
    }
}

// MARK: - Batch Due Date Tests

@Suite("BatchOperationService — Batch Due Date", .serialized)
@MainActor
struct BatchOpDueDateTests {

    @Test("Set due date on tasks")
    func setDueDate() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", in: context)
        let dueDate = Date().addingTimeInterval(86400) // tomorrow
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchSetDueDate([task], dueDate: dueDate)

        #expect(result.successCount == 1)
        #expect(result.isFullSuccess)
        #expect(task.dueTime == dueDate)
    }

    @Test("Set due date overwrites existing due date")
    func overwriteDueDate() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let oldDate = Date()
        let newDate = Date().addingTimeInterval(86400)
        let task = try makeBatchTask(title: "Task", dueTime: oldDate, in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchSetDueDate([task], dueDate: newDate)

        #expect(result.successCount == 1)
        #expect(task.dueTime == newDate)
    }

    @Test("Clear due date from tasks")
    func clearDueDate() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", dueTime: Date(), in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchClearDueDate([task])

        #expect(result.successCount == 1)
        #expect(result.isFullSuccess)
        #expect(task.dueTime == nil)
    }

    @Test("Clear due date skips tasks without due dates")
    func skipNoDueDate() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchClearDueDate([task])

        #expect(result.successCount == 0)
        #expect(result.failureCount == 1)
    }
}

// MARK: - Edge Cases

@Suite("BatchOperationService — Edge Cases", .serialized)
@MainActor
struct BatchOpEdgeCaseTests {

    @Test("Empty task array returns zero-count result")
    func emptyArray() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let result = try await service.batchComplete([])

        #expect(result.successCount == 0)
        #expect(result.totalSelected == 0)
        #expect(result.isFullSuccess)
    }

    @Test("Operations update updatedAt timestamp")
    func updatesTimestamp() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", in: context)
        let originalDate = task.updatedAt
        // Small delay to ensure different timestamp
        try await Task.sleep(for: .milliseconds(10))
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        _ = try await service.batchSetPriority([task], priority: 3)

        #expect(task.updatedAt > originalDate)
    }

    @Test("Batch result reports correct operation type")
    func correctOperationType() async throws {
        let container = try makeBatchTestContainer()
        let context = container.mainContext
        let task = try makeBatchTask(title: "Task", in: context)
        let service = BatchOperationService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let deleteResult = try await service.batchDelete([task])
        #expect(deleteResult.operation == .delete)
    }
}
