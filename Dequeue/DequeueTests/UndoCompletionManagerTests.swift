//
//  UndoCompletionManagerTests.swift
//  DequeueTests
//
//  Tests for UndoCompletionManager - delayed stack completion with undo capability
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

/// Creates an in-memory model container for UndoCompletionManager tests
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

@Suite("UndoCompletionManager Tests", .serialized)
struct UndoCompletionManagerTests {
    // MARK: - Initial State Tests

    @Test("Manager initializes with no pending completion")
    func managerInitializesEmpty() {
        let manager = UndoCompletionManager()

        #expect(manager.hasPendingCompletion == false)
        #expect(manager.pendingStack == nil)
        #expect(manager.progress == 0.0)
    }

    // MARK: - Start Delayed Completion Tests

    @Test("startDelayedCompletion sets pending stack")
    @MainActor
    func startDelayedCompletionSetsPendingStack() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)

        #expect(manager.hasPendingCompletion == true)
        #expect(manager.pendingStack?.id == stack.id)
    }

    @Test("startDelayedCompletion resets progress to zero")
    @MainActor
    func startDelayedCompletionResetsProgress() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)

        #expect(manager.progress == 0.0)
    }

    @Test("Starting new completion cancels previous one")
    @MainActor
    func startingNewCompletionCancelsPrevious() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack1 = Stack(title: "First Stack", status: .active, sortOrder: 0)
        let stack2 = Stack(title: "Second Stack", status: .active, sortOrder: 1)
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        manager.startDelayedCompletion(for: stack1)
        #expect(manager.pendingStack?.id == stack1.id)

        manager.startDelayedCompletion(for: stack2)
        #expect(manager.pendingStack?.id == stack2.id)
        #expect(manager.hasPendingCompletion == true)
    }

    // MARK: - Undo Completion Tests

    @Test("undoCompletion clears pending stack")
    @MainActor
    func undoCompletionClearsPendingStack() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)
        #expect(manager.hasPendingCompletion == true)

        manager.undoCompletion()

        #expect(manager.hasPendingCompletion == false)
        #expect(manager.pendingStack == nil)
    }

    @Test("undoCompletion resets progress")
    @MainActor
    func undoCompletionResetsProgress() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)
        manager.undoCompletion()

        #expect(manager.progress == 0.0)
    }

    @Test("undoCompletion is safe to call with no pending completion")
    func undoCompletionSafeWhenNoPending() {
        let manager = UndoCompletionManager()

        // Should not crash or throw
        manager.undoCompletion()

        #expect(manager.hasPendingCompletion == false)
        #expect(manager.pendingStack == nil)
    }

    @Test("Stack remains active after undo")
    @MainActor
    func stackRemainsActiveAfterUndo() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)
        manager.undoCompletion()

        // Stack should still be active - not completed
        #expect(stack.status == .active)
    }

    // MARK: - Grace Period Completion Tests

    @Test("Stack is completed after grace period")
    @MainActor
    func stackCompletedAfterGracePeriod() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        #expect(stack.status == .active)

        manager.startDelayedCompletion(for: stack)

        // Wait for the grace period to elapse (plus a small buffer)
        try await Task.sleep(for: .seconds(UndoCompletionManager.gracePeriodDuration + 0.5))

        #expect(stack.status == .completed)
        #expect(manager.hasPendingCompletion == false)
    }

    @Test("Stack is NOT completed if undone before grace period")
    @MainActor
    func stackNotCompletedIfUndone() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)

        // Wait a bit but undo before grace period ends
        try await Task.sleep(for: .seconds(1.0))
        manager.undoCompletion()

        // Wait past when completion would have happened
        try await Task.sleep(for: .seconds(UndoCompletionManager.gracePeriodDuration))

        // Stack should still be active
        #expect(stack.status == .active)
    }

    // MARK: - Progress Tests

    @Test("Progress increases over time")
    @MainActor
    func progressIncreasesOverTime() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)

        let initialProgress = manager.progress

        // Wait a bit for progress to update
        try await Task.sleep(for: .seconds(1.0))

        let laterProgress = manager.progress

        #expect(laterProgress > initialProgress)
        #expect(laterProgress < 1.0) // Should not be complete yet

        // Clean up
        manager.undoCompletion()
    }

    @Test("Progress is approximately correct at midpoint")
    @MainActor
    func progressApproximatelyCorrectAtMidpoint() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)

        // Wait for half the grace period
        let halfDuration = UndoCompletionManager.gracePeriodDuration / 2.0
        try await Task.sleep(for: .seconds(halfDuration))

        // Progress should be approximately 0.5 (allow some tolerance for timing)
        #expect(manager.progress > 0.4)
        #expect(manager.progress < 0.6)

        // Clean up
        manager.undoCompletion()
    }

    // MARK: - Configuration Tests

    @Test("Manager works without syncManager")
    @MainActor
    func managerWorksWithoutSyncManager() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)

        // Wait for completion
        try await Task.sleep(for: .seconds(UndoCompletionManager.gracePeriodDuration + 0.5))

        // Should still complete successfully
        #expect(stack.status == .completed)
    }

    // MARK: - Edge Cases

    @Test("Multiple rapid start/undo cycles work correctly")
    @MainActor
    func multipleRapidStartUndoCycles() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        // Rapidly start and undo multiple times
        for _ in 1...5 {
            manager.startDelayedCompletion(for: stack)
            #expect(manager.hasPendingCompletion == true)

            manager.undoCompletion()
            #expect(manager.hasPendingCompletion == false)
        }

        // Stack should still be active
        #expect(stack.status == .active)
    }

    @Test("Grace period duration is 5 seconds")
    func gracePeriodDurationIsFiveSeconds() {
        #expect(UndoCompletionManager.gracePeriodDuration == 5.0)
    }
}

// MARK: - Stack Completion with Tasks Tests

@Suite("UndoCompletionManager Task Handling Tests", .serialized)
struct UndoCompletionManagerTaskTests {
    @Test("Completing stack also completes all pending tasks")
    @MainActor
    func completingStackCompletesAllTasks() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)

        // Add some pending tasks
        let task1 = QueueTask(title: "Task 1", status: .pending, sortOrder: 0, stack: stack)
        let task2 = QueueTask(title: "Task 2", status: .pending, sortOrder: 1, stack: stack)
        context.insert(task1)
        context.insert(task2)
        stack.tasks = [task1, task2]

        try context.save()

        #expect(stack.pendingTasks.count == 2)

        manager.startDelayedCompletion(for: stack)

        // Wait for completion
        try await Task.sleep(for: .seconds(UndoCompletionManager.gracePeriodDuration + 0.5))

        // All tasks should be completed
        #expect(task1.status == .completed)
        #expect(task2.status == .completed)
        #expect(stack.status == .completed)
    }

    @Test("Already completed tasks remain completed after stack completion")
    @MainActor
    func alreadyCompletedTasksRemainCompleted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil)

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)

        // Add a mix of pending and completed tasks
        let pendingTask = QueueTask(title: "Pending Task", status: .pending, sortOrder: 0, stack: stack)
        let completedTask = QueueTask(title: "Completed Task", status: .completed, sortOrder: 1, stack: stack)
        context.insert(pendingTask)
        context.insert(completedTask)
        stack.tasks = [pendingTask, completedTask]

        try context.save()

        manager.startDelayedCompletion(for: stack)

        // Wait for completion
        try await Task.sleep(for: .seconds(UndoCompletionManager.gracePeriodDuration + 0.5))

        // Both should be completed
        #expect(pendingTask.status == .completed)
        #expect(completedTask.status == .completed)
    }
}
