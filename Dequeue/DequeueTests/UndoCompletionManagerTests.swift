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
@MainActor
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Device.self,
        configurations: config
    )
}

@Suite("UndoCompletionManager Tests", .serialized)
@MainActor
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
    func startDelayedCompletionSetsPendingStack() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)

        #expect(manager.hasPendingCompletion == true)
        #expect(manager.pendingStack?.id == stack.id)
    }

    @Test("startDelayedCompletion resets progress to zero")
    func startDelayedCompletionResetsProgress() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)

        #expect(manager.progress == 0.0)
    }

    @Test("Starting new completion supersedes and commits previous one")
    func startingNewCompletionSupersedesPrevious() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

        let stack1 = Stack(title: "First Stack", status: .active, sortOrder: 0)
        let stack2 = Stack(title: "Second Stack", status: .active, sortOrder: 1)
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        manager.startDelayedCompletion(for: stack1)
        #expect(manager.pendingStack?.id == stack1.id)

        // Tapping a second stack while the first is still pending must commit
        // the first (not silently drop it) and make the second the new pending.
        manager.startDelayedCompletion(for: stack2)
        #expect(manager.pendingStack?.id == stack2.id)
        #expect(manager.hasPendingCompletion == true)

        // First stack commit is dispatched on a Task; wait for it to land.
        try await waitUntil(timeout: 2.0) { stack1.status == .completed }
        #expect(stack1.status == .completed)
        #expect(stack2.status == .active) // still in grace period

        // Clean up the still-pending second stack.
        manager.undoCompletion()
    }

    @Test("Regression: rapidly completing 5 stacks commits all of them")
    func rapidCompletionsCommitAllStacks() async throws {
        // This is the exact bug Victor reported: tap Complete on several stacks
        // in quick succession (faster than the 5s grace period). Before the
        // supersede fix, only the LAST stack actually committed and the others
        // silently reverted. All 5 must end up completed.
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

        var stacks: [Stack] = []
        for index in 0..<5 {
            let stack = Stack(title: "Stack \(index)", status: .active, sortOrder: index)
            context.insert(stack)
            stacks.append(stack)
        }
        try context.save()

        // Rapid-fire complete each stack, faster than the grace period.
        for stack in stacks {
            manager.startDelayedCompletion(for: stack)
        }

        // The last stack is still pending; the first 4 must already be committed.
        try await waitUntil(timeout: 2.0) {
            stacks.dropLast().allSatisfy { $0.status == .completed }
        }
        for stack in stacks.dropLast() {
            #expect(stack.status == .completed, "\(stack.title) should be completed (was \(stack.status))")
        }
        #expect(stacks.last?.status == .active) // still in grace period

        // Let the grace period elapse so the last one commits too.
        try await Task.sleep(for: .seconds(UndoCompletionManager.gracePeriodDuration + 0.5))
        #expect(stacks.last?.status == .completed)
        #expect(manager.hasPendingCompletion == false)
    }

    @Test("Re-tapping the same pending stack resets its timer without double-commit")
    func reTappingSameStackResetsTimer() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)
        try await Task.sleep(for: .seconds(0.5))
        manager.startDelayedCompletion(for: stack) // same stack again

        #expect(manager.pendingStack?.id == stack.id)
        #expect(stack.status == .active) // must not have been committed early

        manager.undoCompletion()
        #expect(stack.status == .active)
    }

    // MARK: - Undo Completion Tests

    @Test("undoCompletion clears pending stack")
    func undoCompletionClearsPendingStack() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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
    func undoCompletionResetsProgress() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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
    func stackRemainsActiveAfterUndo() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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
    func stackCompletedAfterGracePeriod() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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
    func stackNotCompletedIfUndone() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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
    func progressIncreasesOverTime() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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
    func progressApproximatelyCorrectAtMidpoint() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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
    func managerWorksWithoutSyncManager() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

        let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()

        manager.startDelayedCompletion(for: stack)

        // Wait for completion (keep manager alive by referencing it)
        while manager.hasPendingCompletion {
            try await Task.sleep(for: .milliseconds(100))
        }

        // Should still complete successfully
        #expect(stack.status == .completed)
    }

    // MARK: - Edge Cases

    @Test("Multiple rapid start/undo cycles work correctly")
    func multipleRapidStartUndoCycles() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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

// MARK: - Helpers

/// Polls `condition` every 50ms up to `timeout`, returning when it first becomes
/// true. Used to wait for async commits dispatched by `UndoCompletionManager`
/// without baking the grace-period duration into every test.
@MainActor
private func waitUntil(
    timeout: TimeInterval,
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
}

// MARK: - Stack Completion with Tasks Tests

@Suite("UndoCompletionManager Task Handling Tests", .serialized)
@MainActor
struct UndoCompletionManagerTaskTests {
    @Test("Completing stack also completes all pending tasks")
    func completingStackCompletesAllTasks() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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

        // Wait for completion (keep manager alive by referencing it)
        while manager.hasPendingCompletion {
            try await Task.sleep(for: .milliseconds(100))
        }

        // All tasks should be completed
        #expect(task1.status == .completed)
        #expect(task2.status == .completed)
        #expect(stack.status == .completed)
    }

    @Test("Already completed tasks remain completed after stack completion")
    func alreadyCompletedTasksRemainCompleted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = UndoCompletionManager()
        manager.configure(modelContext: context, syncManager: nil, userId: "test-user", deviceId: "test-device")

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

        // Wait for completion (keep manager alive by referencing it)
        while manager.hasPendingCompletion {
            try await Task.sleep(for: .milliseconds(100))
        }

        // Both should be completed
        #expect(pendingTask.status == .completed)
        #expect(completedTask.status == .completed)
    }
}
