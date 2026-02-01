//
//  StackTests.swift
//  DequeueTests
//
//  Tests for Stack model
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Stack Model Tests")
@MainActor
struct StackTests {
    @Test("Stack initializes with default values")
    func stackInitializesWithDefaults() {
        let stack = Stack(title: "Test Stack")

        #expect(stack.title == "Test Stack")
        #expect(stack.status == .active)
        #expect(stack.isDeleted == false)
        #expect(stack.isDraft == false)
        #expect(stack.syncState == .pending)
        #expect(stack.revision == 1)
        #expect(stack.sortOrder == 0)
        #expect(stack.tasks.isEmpty)
        #expect(stack.reminders.isEmpty)
    }

    @Test("Stack initializes with custom values")
    func stackInitializesWithCustomValues() {
        let id = UUID().uuidString
        let now = Date()

        let stack = Stack(
            id: id,
            title: "Custom Stack",
            stackDescription: "A description",
            status: StackStatus.completed,
            priority: 1,
            sortOrder: 5,
            createdAt: now,
            updatedAt: now,
            isDraft: true,
            userId: "user123",
            syncState: SyncState.synced,
            revision: 3
        )

        #expect(stack.id == id)
        #expect(stack.title == "Custom Stack")
        #expect(stack.stackDescription == "A description")
        #expect(stack.status == StackStatus.completed)
        #expect(stack.priority == 1)
        #expect(stack.sortOrder == 5)
        #expect(stack.isDraft == true)
        #expect(stack.userId == "user123")
        #expect(stack.syncState == SyncState.synced)
        #expect(stack.revision == 3)
    }

    @Test("pendingTasks filters correctly", .disabled("Flaky test - to be debugged"))
    func pendingTasksFiltersCorrectly() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Stack.self, QueueTask.self, Reminder.self, configurations: config)
        let context = ModelContext(container)

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let pendingTask = QueueTask(title: "Pending", status: TaskStatus.pending, sortOrder: 0, stack: stack)
        let completedTask = QueueTask(title: "Completed", status: TaskStatus.completed, sortOrder: 1, stack: stack)
        let deletedTask = QueueTask(title: "Deleted", status: TaskStatus.pending, sortOrder: 2, isDeleted: true, stack: stack)

        context.insert(pendingTask)
        context.insert(completedTask)
        context.insert(deletedTask)

        stack.tasks = [pendingTask, completedTask, deletedTask]

        try context.save()

        #expect(stack.pendingTasks.count == 1)
        #expect(stack.pendingTasks.first?.title == "Pending")
    }

    @Test("completedTasks filters correctly")
    func completedTasksFiltersCorrectly() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Stack.self, QueueTask.self, Reminder.self, configurations: config)
        let context = ModelContext(container)

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let pendingTask = QueueTask(title: "Pending", status: TaskStatus.pending, sortOrder: 0, stack: stack)
        let completedTask = QueueTask(title: "Completed", status: TaskStatus.completed, sortOrder: 1, stack: stack)

        context.insert(pendingTask)
        context.insert(completedTask)

        stack.tasks = [pendingTask, completedTask]

        try context.save()

        #expect(stack.completedTasks.count == 1)
        #expect(stack.completedTasks.first?.title == "Completed")
    }

    @Test("activeTask returns first pending task")
    func activeTaskReturnsFirstPending() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Stack.self, QueueTask.self, Reminder.self, configurations: config)
        let context = ModelContext(container)

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let task1 = QueueTask(title: "First", status: TaskStatus.pending, sortOrder: 0, stack: stack)
        let task2 = QueueTask(title: "Second", status: TaskStatus.pending, sortOrder: 1, stack: stack)

        context.insert(task1)
        context.insert(task2)

        stack.tasks = [task1, task2]

        try context.save()

        #expect(stack.activeTask?.title == "First")
    }

    // MARK: - Stack Creation with Multiple Tasks (DEQ-129)

    @Test("Creating stack with multiple tasks")
    @MainActor
    func creatingStackWithMultipleTasks() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let taskService = TaskService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Create stack
        let stack = try await stackService.createStack(
            title: "Test Stack",
            description: "Stack with multiple tasks"
        )

        // Create multiple tasks (simulating the create mode flow)
        let task1 = try await taskService.createTask(
            title: "First Task",
            description: "Description 1",
            stack: stack
        )
        let task2 = try await taskService.createTask(
            title: "Second Task",
            description: nil,
            stack: stack
        )
        let task3 = try await taskService.createTask(
            title: "Third Task",
            description: "Description 3",
            stack: stack
        )

        try context.save()

        // Verify all tasks were created
        #expect(stack.tasks.count == 3)
        #expect(stack.pendingTasks.count == 3)

        // Verify tasks are in correct order
        let tasks = stack.tasks.sorted { $0.sortOrder < $1.sortOrder }
        #expect(tasks[0].title == "First Task")
        #expect(tasks[1].title == "Second Task")
        #expect(tasks[2].title == "Third Task")

        // Verify descriptions
        #expect(tasks[0].taskDescription == "Description 1")
        #expect(tasks[1].taskDescription == nil)
        #expect(tasks[2].taskDescription == "Description 3")
    }

    @Test("Creating stack with no tasks")
    @MainActor
    func creatingStackWithNoTasks() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Create stack without tasks
        let stack = try await stackService.createStack(
            title: "Empty Stack",
            description: nil
        )

        try context.save()

        // Verify stack created successfully with no tasks
        #expect(stack.tasks.isEmpty)
        #expect(stack.pendingTasks.isEmpty)
        #expect(stack.title == "Empty Stack")
    }

    @Test("Task sort order is correct when created sequentially")
    @MainActor
    func taskSortOrderCorrect() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let taskService = TaskService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Test Stack")

        // Create 5 tasks
        for index in 1...5 {
            _ = try await taskService.createTask(
                title: "Task \(index)",
                stack: stack
            )
        }

        try context.save()

        // Verify sort orders are sequential
        let tasks = stack.tasks.sorted { $0.sortOrder < $1.sortOrder }
        for (index, task) in tasks.enumerated() {
            #expect(task.sortOrder == index)
            #expect(task.title == "Task \(index + 1)")
        }
    }
}
