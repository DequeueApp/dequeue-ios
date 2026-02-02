//
//  StackDetailReadOnlyTests.swift
//  DequeueTests
//
//  Tests for read-only mode in StackDetailView (DEQ-8)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

/// Creates an in-memory model container for read-only tests
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

/// Tests if a stack passes the completed view filter (same logic as CompletedStacksView)
private func passesCompletedViewFilter(_ stack: Stack) -> Bool {
    !stack.isDeleted && (stack.status == .completed || stack.status == .closed)
}

@Suite("Stack Detail Read-Only Tests", .serialized)
@MainActor
struct StackDetailReadOnlyTests {
    // MARK: - Completed Stack Filter Tests

    @Test("completed status passes completed view filter")
    func completedStatusPassesFilter() {
        let stack = Stack(title: "Test", status: .completed)
        #expect(passesCompletedViewFilter(stack))
    }

    @Test("closed status passes completed view filter")
    func closedStatusPassesFilter() {
        let stack = Stack(title: "Test", status: .closed)
        #expect(passesCompletedViewFilter(stack))
    }

    @Test("active status fails completed view filter")
    func activeStatusFailsFilter() {
        let stack = Stack(title: "Test", status: .active)
        #expect(!passesCompletedViewFilter(stack))
    }

    @Test("archived status fails completed view filter")
    func archivedStatusFailsFilter() {
        let stack = Stack(title: "Test", status: .archived)
        #expect(!passesCompletedViewFilter(stack))
    }

    @Test("deleted completed stack fails completed view filter")
    func deletedCompletedStackFailsFilter() {
        let stack = Stack(title: "Test", status: .completed)
        stack.isDeleted = true
        #expect(!passesCompletedViewFilter(stack))
    }

    @Test("deleted closed stack fails completed view filter")
    func deletedClosedStackFailsFilter() {
        let stack = Stack(title: "Test", status: .closed)
        stack.isDeleted = true
        #expect(!passesCompletedViewFilter(stack))
    }

    // MARK: - Read-Only Stack Tests

    @Test("completed stack has correct status")
    func completedStackHasCorrectStatus() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack", status: .completed)
        context.insert(stack)
        try context.save()

        #expect(stack.status == .completed)
    }

    @Test("closed stack has correct status")
    func closedStackHasCorrectStatus() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack", status: .closed)
        context.insert(stack)
        try context.save()

        #expect(stack.status == .closed)
    }

    @Test("stack with tasks can be viewed read-only")
    func stackWithTasksCanBeViewedReadOnly() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack", status: .completed)
        context.insert(stack)

        let task1 = QueueTask(title: "Task 1", status: .pending, stack: stack)
        let task2 = QueueTask(title: "Task 2", status: .completed, stack: stack)
        context.insert(task1)
        context.insert(task2)
        stack.tasks.append(task1)
        stack.tasks.append(task2)
        try context.save()

        // Verify tasks are accessible on the stack
        #expect(stack.tasks.count == 2)
        #expect(stack.pendingTasks.count == 1)
        #expect(stack.completedTasks.count == 1)
    }

    @Test("stack description is accessible read-only")
    func stackDescriptionIsAccessibleReadOnly() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(
            title: "Test Stack",
            stackDescription: "Test description",
            status: .completed
        )
        context.insert(stack)
        try context.save()

        #expect(stack.stackDescription == "Test description")
    }
}
