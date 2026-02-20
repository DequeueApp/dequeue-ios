//
//  TaskServiceTests.swift
//  DequeueTests
//
//  Tests for TaskService - task creation and management (DEQ-7)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container for TaskService tests
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Tag.self,
        Attachment.self,
        configurations: config
    )
}

/// Creates a TaskService with the given context
@MainActor
private func makeService(context: ModelContext) -> TaskService {
    TaskService(modelContext: context, userId: "test-user", deviceId: "test-device")
}

/// Creates a stack with optional tasks in the given context
@MainActor
private func makeStack(
    title: String = "Test Stack",
    in context: ModelContext,
    taskTitles: [String] = []
) -> Stack {
    let stack = Stack(title: title)
    context.insert(stack)
    for (index, taskTitle) in taskTitles.enumerated() {
        let task = QueueTask(title: taskTitle, status: .pending, sortOrder: index, stack: stack)
        context.insert(task)
        stack.tasks.append(task)
    }
    try? context.save()
    return stack
}

// MARK: - Create Task Tests

@Suite("TaskService - Create", .serialized)
@MainActor
struct TaskServiceCreateTests {
    @Test("createTask creates a new task with title")
    func createTaskWithTitle() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context)

        let service = makeService(context: context)
        let task = try await service.createTask(title: "New Task", stack: stack)

        #expect(task.title == "New Task")
        #expect(task.status == .pending)
        #expect(task.stack?.id == stack.id)
        #expect(stack.tasks.contains { $0.id == task.id })
    }

    @Test("createTask creates a task with description")
    func createTaskWithDescription() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context)

        let service = makeService(context: context)
        let task = try await service.createTask(
            title: "Task with Description",
            description: "This is a test description",
            stack: stack
        )

        #expect(task.title == "Task with Description")
        #expect(task.taskDescription == "This is a test description")
        #expect(task.status == .pending)
    }

    @Test("createTask assigns correct sort order")
    func createTaskAssignsSortOrder() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context)

        let service = makeService(context: context)
        let task1 = try await service.createTask(title: "First Task", stack: stack)
        let task2 = try await service.createTask(title: "Second Task", stack: stack)
        let task3 = try await service.createTask(title: "Third Task", stack: stack)

        #expect(task1.sortOrder == 0)
        #expect(task2.sortOrder == 1)
        #expect(task3.sortOrder == 2)
    }

    @Test("createTask allows custom sort order")
    func createTaskWithCustomSortOrder() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context)

        let service = makeService(context: context)
        let task = try await service.createTask(title: "Custom Order Task", stack: stack, sortOrder: 5)

        #expect(task.sortOrder == 5)
    }

    @Test("createTask sets sync state to pending")
    func createTaskSetsSyncState() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context)

        let service = makeService(context: context)
        let task = try await service.createTask(title: "New Task", stack: stack)

        #expect(task.syncState == .pending)
    }

    @Test("created task appears in stack's pendingTasks")
    func createdTaskAppearsInPendingTasks() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context)

        let service = makeService(context: context)
        _ = try await service.createTask(title: "New Task", stack: stack)

        #expect(stack.pendingTasks.count == 1)
        #expect(stack.pendingTasks.first?.title == "New Task")
    }

    @Test("createTask with dates")
    func createTaskWithDates() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context)

        let startTime = Date()
        let dueTime = Date().addingTimeInterval(86400) // +1 day

        let service = makeService(context: context)
        let task = try await service.createTask(
            title: "Dated Task",
            startTime: startTime,
            dueTime: dueTime,
            stack: stack
        )

        #expect(task.startTime != nil)
        #expect(task.dueTime != nil)
    }
}

// MARK: - Update Task Tests

@Suite("TaskService - Update", .serialized)
@MainActor
struct TaskServiceUpdateTests {
    @Test("updateTask changes title and description")
    func updateTaskTitleAndDescription() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Original Title"])
        let task = stack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.updateTask(task, title: "Updated Title", description: "New Description")

        #expect(task.title == "Updated Title")
        #expect(task.taskDescription == "New Description")
        #expect(task.syncState == .pending)
    }

    @Test("updateTask clears description when set to nil")
    func updateTaskClearsDescription() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context)

        let service = makeService(context: context)
        let task = try await service.createTask(title: "Test", description: "Initial desc", stack: stack)
        try await service.updateTask(task, title: "Test", description: nil)

        #expect(task.taskDescription == nil)
    }

    @Test("updateTaskDates changes start and due times")
    func updateTaskDates() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Test Task"])
        let task = stack.pendingTasks.first!

        let newStartTime = Date()
        let newDueTime = Date().addingTimeInterval(3600)

        let service = makeService(context: context)
        try await service.updateTaskDates(task, startTime: newStartTime, dueTime: newDueTime)

        #expect(task.startTime != nil)
        #expect(task.dueTime != nil)
        #expect(task.syncState == .pending)
    }

    @Test("updateTaskDates clears dates when set to nil")
    func updateTaskDatesClear() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context)

        let service = makeService(context: context)
        let task = try await service.createTask(
            title: "Dated Task",
            startTime: Date(),
            dueTime: Date().addingTimeInterval(86400),
            stack: stack
        )

        try await service.updateTaskDates(task, startTime: nil, dueTime: nil)

        #expect(task.startTime == nil)
        #expect(task.dueTime == nil)
    }
}

// MARK: - Status Change Tests

@Suite("TaskService - Status Changes", .serialized)
@MainActor
struct TaskServiceStatusTests {
    @Test("markAsCompleted changes task status")
    func markAsCompletedChangesStatus() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Test Task"])
        let task = stack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.markAsCompleted(task)

        #expect(task.status == .completed)
        #expect(task.syncState == .pending)
    }

    @Test("completed task moves from pendingTasks to completedTasks")
    func completedTaskMovesToCompletedList() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Test Task"])

        #expect(stack.pendingTasks.count == 1)
        #expect(stack.completedTasks.isEmpty)

        let service = makeService(context: context)
        try await service.markAsCompleted(stack.pendingTasks.first!)

        #expect(stack.pendingTasks.isEmpty)
        #expect(stack.completedTasks.count == 1)
    }

    @Test("markAsBlocked sets blocked status and reason")
    func markAsBlocked() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Test Task"])
        let task = stack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.markAsBlocked(task, reason: "Waiting for approval")

        #expect(task.status == .blocked)
        #expect(task.blockedReason == "Waiting for approval")
        #expect(task.syncState == .pending)
    }

    @Test("markAsBlocked with nil reason")
    func markAsBlockedNoReason() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Test Task"])
        let task = stack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.markAsBlocked(task, reason: nil)

        #expect(task.status == .blocked)
        #expect(task.blockedReason == nil)
    }

    @Test("unblock restores task to pending")
    func unblockRestoresPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Test Task"])
        let task = stack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.markAsBlocked(task, reason: "Blocked reason")
        #expect(task.status == .blocked)

        try await service.unblock(task)

        #expect(task.status == .pending)
        #expect(task.blockedReason == nil)
        #expect(task.syncState == .pending)
    }

    @Test("closeTask sets closed status")
    func closeTask() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Test Task"])
        let task = stack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.closeTask(task)

        #expect(task.status == .closed)
        #expect(task.syncState == .pending)
    }
}

// MARK: - Delete Tests

@Suite("TaskService - Delete", .serialized)
@MainActor
struct TaskServiceDeleteTests {
    @Test("deleteTask marks task as deleted")
    func deleteTaskMarksAsDeleted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Test Task"])
        let task = stack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.deleteTask(task)

        #expect(task.isDeleted == true)
        #expect(task.syncState == .pending)
    }

    @Test("deleted task no longer appears in pendingTasks")
    func deletedTaskDisappearsFromPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Task 1", "Task 2"])

        #expect(stack.pendingTasks.count == 2)

        let service = makeService(context: context)
        let taskToDelete = stack.pendingTasks.first!
        try await service.deleteTask(taskToDelete)

        #expect(stack.pendingTasks.count == 1)
    }
}

// MARK: - Reorder Tests

@Suite("TaskService - Reorder", .serialized)
@MainActor
struct TaskServiceReorderTests {
    @Test("updateSortOrders reorders tasks")
    func reorderTasks() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["A", "B", "C"])

        let tasks = stack.pendingTasks
        let taskA = tasks.first { $0.title == "A" }!
        let taskB = tasks.first { $0.title == "B" }!
        let taskC = tasks.first { $0.title == "C" }!

        // Reverse order: C, B, A
        let service = makeService(context: context)
        try await service.updateSortOrders([taskC, taskB, taskA])

        #expect(taskC.sortOrder == 0)
        #expect(taskB.sortOrder == 1)
        #expect(taskA.sortOrder == 2)
    }

    @Test("updateSortOrders sets sync state to pending")
    func reorderSetsSyncState() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["A", "B"])

        let tasks = stack.pendingTasks

        let service = makeService(context: context)
        try await service.updateSortOrders(tasks.reversed())

        for task in tasks {
            #expect(task.syncState == .pending)
        }
    }
}

// MARK: - Move Tests

@Suite("TaskService - Move", .serialized)
@MainActor
struct TaskServiceMoveTests {
    @Test("moveTask moves task to target stack")
    func moveTaskToTargetStack() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let sourceStack = makeStack(title: "Source", in: context, taskTitles: ["Task to Move"])
        let targetStack = makeStack(title: "Target", in: context)

        let task = sourceStack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.moveTask(task, to: targetStack)

        #expect(task.stack?.id == targetStack.id)
        #expect(task.syncState == .pending)
    }

    @Test("moveTask removes task from source stack")
    func moveTaskRemovesFromSource() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let sourceStack = makeStack(title: "Source", in: context, taskTitles: ["Task 1", "Task 2"])
        let targetStack = makeStack(title: "Target", in: context)

        let taskToMove = sourceStack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.moveTask(taskToMove, to: targetStack)

        #expect(sourceStack.pendingTasks.count == 1)
    }

    @Test("moveTask assigns sort order in target stack")
    func moveTaskAssignsSortOrder() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let sourceStack = makeStack(title: "Source", in: context, taskTitles: ["Mover"])
        let targetStack = makeStack(title: "Target", in: context, taskTitles: ["Existing 1", "Existing 2"])

        let task = sourceStack.pendingTasks.first!

        let service = makeService(context: context)
        try await service.moveTask(task, to: targetStack)

        // Should get sort order at end of target stack's tasks
        #expect(task.sortOrder >= 0)
        #expect(task.stack?.id == targetStack.id)
    }

    @Test("moveTask updates timestamp")
    func moveTaskUpdatesTimestamp() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let sourceStack = makeStack(title: "Source", in: context, taskTitles: ["Task"])
        let targetStack = makeStack(title: "Target", in: context)

        let task = sourceStack.pendingTasks.first!
        let originalUpdate = task.updatedAt

        // Small delay to ensure different timestamp
        try await Task.sleep(for: .milliseconds(10))

        let service = makeService(context: context)
        try await service.moveTask(task, to: targetStack)

        #expect(task.updatedAt > originalUpdate)
    }
}

// MARK: - Activate Tests

@Suite("TaskService - Activate", .serialized)
@MainActor
struct TaskServiceActivateTests {
    @Test("activateTask sets task as active")
    func activateTask() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Task 1", "Task 2", "Task 3"])

        let taskToActivate = stack.pendingTasks.first { $0.title == "Task 2" }!

        let service = makeService(context: context)
        try await service.activateTask(taskToActivate)

        #expect(stack.activeTaskId == taskToActivate.id)
        #expect(taskToActivate.lastActiveTime != nil)
    }

    @Test("activateTask moves task to top of sort order")
    func activateTaskMovesToTop() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["First", "Second", "Third"])

        let taskToActivate = stack.pendingTasks.first { $0.title == "Third" }!

        let service = makeService(context: context)
        try await service.activateTask(taskToActivate)

        #expect(taskToActivate.sortOrder == 0)
    }

    @Test("activateTask updates stack's activeTaskId")
    func activateTaskUpdatesStackActiveId() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = makeStack(in: context, taskTitles: ["Task A", "Task B"])

        let taskA = stack.pendingTasks.first { $0.title == "Task A" }!
        let taskB = stack.pendingTasks.first { $0.title == "Task B" }!

        let service = makeService(context: context)

        // Activate A
        try await service.activateTask(taskA)
        #expect(stack.activeTaskId == taskA.id)

        // Activate B
        try await service.activateTask(taskB)
        #expect(stack.activeTaskId == taskB.id)
    }
}
