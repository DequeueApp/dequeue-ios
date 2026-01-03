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
        configurations: config
    )
}

@Suite("TaskService Tests", .serialized)
struct TaskServiceTests {
    // MARK: - Create Task Tests (DEQ-7)

    @Test("createTask creates a new task with title")
    @MainActor
    func createTaskWithTitle() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let taskService = TaskService(modelContext: context)
        let task = try taskService.createTask(title: "New Task", stack: stack)

        #expect(task.title == "New Task")
        #expect(task.status == .pending)
        #expect(task.stack?.id == stack.id)
        #expect(stack.tasks.contains { $0.id == task.id })
    }

    @Test("createTask creates a task with description")
    @MainActor
    func createTaskWithDescription() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let taskService = TaskService(modelContext: context)
        let task = try taskService.createTask(
            title: "Task with Description",
            description: "This is a test description",
            stack: stack
        )

        #expect(task.title == "Task with Description")
        #expect(task.taskDescription == "This is a test description")
        #expect(task.status == .pending)
    }

    @Test("createTask assigns correct sort order")
    @MainActor
    func createTaskAssignsSortOrder() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let taskService = TaskService(modelContext: context)
        let task1 = try taskService.createTask(title: "First Task", stack: stack)
        let task2 = try taskService.createTask(title: "Second Task", stack: stack)
        let task3 = try taskService.createTask(title: "Third Task", stack: stack)

        #expect(task1.sortOrder == 0)
        #expect(task2.sortOrder == 1)
        #expect(task3.sortOrder == 2)
    }

    @Test("createTask allows custom sort order")
    @MainActor
    func createTaskWithCustomSortOrder() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let taskService = TaskService(modelContext: context)
        let task = try taskService.createTask(title: "Custom Order Task", stack: stack, sortOrder: 5)

        #expect(task.sortOrder == 5)
    }

    @Test("createTask sets sync state to pending")
    @MainActor
    func createTaskSetsSyncState() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let taskService = TaskService(modelContext: context)
        let task = try taskService.createTask(title: "New Task", stack: stack)

        #expect(task.syncState == .pending)
    }

    @Test("created task appears in stack's pendingTasks")
    @MainActor
    func createdTaskAppearsInPendingTasks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let taskService = TaskService(modelContext: context)
        _ = try taskService.createTask(title: "New Task", stack: stack)

        #expect(stack.pendingTasks.count == 1)
        #expect(stack.pendingTasks.first?.title == "New Task")
    }

    // MARK: - Mark Complete Tests

    @Test("markAsCompleted changes task status")
    @MainActor
    func markAsCompletedChangesStatus() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task", status: .pending, stack: stack)
        context.insert(task)
        stack.tasks.append(task)
        try context.save()

        let taskService = TaskService(modelContext: context)
        try taskService.markAsCompleted(task)

        #expect(task.status == .completed)
    }

    @Test("completed task moves from pendingTasks to completedTasks")
    @MainActor
    func completedTaskMovesToCompletedList() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task", status: .pending, stack: stack)
        context.insert(task)
        stack.tasks.append(task)
        try context.save()

        #expect(stack.pendingTasks.count == 1)
        #expect(stack.completedTasks.isEmpty)

        let taskService = TaskService(modelContext: context)
        try taskService.markAsCompleted(task)

        #expect(stack.pendingTasks.isEmpty)
        #expect(stack.completedTasks.count == 1)
    }
}
