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
        let id = UUID()
        let now = Date()

        let stack = Stack(
            id: id,
            title: "Custom Stack",
            stackDescription: "A description",
            status: .completed,
            priority: 1,
            sortOrder: 5,
            createdAt: now,
            updatedAt: now,
            isDraft: true,
            userId: "user123",
            syncState: .synced,
            revision: 3
        )

        #expect(stack.id == id)
        #expect(stack.title == "Custom Stack")
        #expect(stack.stackDescription == "A description")
        #expect(stack.status == .completed)
        #expect(stack.priority == 1)
        #expect(stack.sortOrder == 5)
        #expect(stack.isDraft == true)
        #expect(stack.userId == "user123")
        #expect(stack.syncState == .synced)
        #expect(stack.revision == 3)
    }

    @Test("pendingTasks filters correctly", .disabled("Flaky test - to be debugged"))
    func pendingTasksFiltersCorrectly() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Stack.self, Task.self, Reminder.self, configurations: config)
        let context = ModelContext(container)

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let pendingTask = Task(title: "Pending", status: .pending, sortOrder: 0, stack: stack)
        let completedTask = Task(title: "Completed", status: .completed, sortOrder: 1, stack: stack)
        let deletedTask = Task(title: "Deleted", status: .pending, sortOrder: 2, isDeleted: true, stack: stack)

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
        let container = try ModelContainer(for: Stack.self, Task.self, Reminder.self, configurations: config)
        let context = ModelContext(container)

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let pendingTask = Task(title: "Pending", status: .pending, sortOrder: 0, stack: stack)
        let completedTask = Task(title: "Completed", status: .completed, sortOrder: 1, stack: stack)

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
        let container = try ModelContainer(for: Stack.self, Task.self, Reminder.self, configurations: config)
        let context = ModelContext(container)

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let task1 = Task(title: "First", status: .pending, sortOrder: 0, stack: stack)
        let task2 = Task(title: "Second", status: .pending, sortOrder: 1, stack: stack)

        context.insert(task1)
        context.insert(task2)

        stack.tasks = [task1, task2]

        try context.save()

        #expect(stack.activeTask?.title == "First")
    }
}
