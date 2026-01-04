//
//  EventHistoryTests.swift
//  DequeueTests
//
//  Tests for Event History functionality to prevent regressions
//  Related: DEQ-117 (macOS Event History blank content fix)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container for Event History tests
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

@Suite("Event History Tests", .serialized)
struct EventHistoryTests {
    // MARK: - Stack History Tests

    @Test("fetchStackHistoryWithRelated returns stack events")
    @MainActor
    func fetchStackHistoryReturnsStackEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        // Record stack events
        let eventService = EventService(modelContext: context)
        try eventService.recordStackCreated(stack)
        try context.save()

        // Fetch history
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        #expect(events.count >= 1)
        #expect(events.contains { $0.type == "stack.created" })
    }

    @Test("fetchStackHistoryWithRelated includes task events")
    @MainActor
    func fetchStackHistoryIncludesTaskEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack with a task
        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(task)
        stack.tasks.append(task)
        try context.save()

        // Record events
        let eventService = EventService(modelContext: context)
        try eventService.recordStackCreated(stack)
        try eventService.recordTaskCreated(task)
        try context.save()

        // Fetch history
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        #expect(events.count >= 2)
        #expect(events.contains { $0.type == "stack.created" })
        #expect(events.contains { $0.type == "task.created" })
    }

    @Test("fetchStackHistoryWithRelated includes reminder events")
    @MainActor
    func fetchStackHistoryIncludesReminderEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack with a reminder
        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let reminder = Reminder(
            remindAt: Date().addingTimeInterval(3600),
            parentId: stack.id,
            parentType: .stack
        )
        context.insert(reminder)
        stack.reminders.append(reminder)
        try context.save()

        // Record events
        let eventService = EventService(modelContext: context)
        try eventService.recordStackCreated(stack)
        try eventService.recordReminderCreated(reminder)
        try context.save()

        // Fetch history
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        #expect(events.count >= 2)
        #expect(events.contains { $0.type == "stack.created" })
        #expect(events.contains { $0.type == "reminder.created" })
    }

    @Test("fetchHistory returns events for specific entity")
    @MainActor
    func fetchHistoryReturnsEventsForSpecificEntity() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create two stacks
        let stack1 = Stack(title: "Stack 1")
        let stack2 = Stack(title: "Stack 2")
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        // Record events for both
        let eventService = EventService(modelContext: context)
        try eventService.recordStackCreated(stack1)
        try eventService.recordStackCreated(stack2)
        try context.save()

        // Fetch history for stack1 only
        let events = try eventService.fetchHistory(for: stack1.id)

        #expect(events.count == 1)
        #expect(events.first?.entityId == stack1.id)
    }

    // MARK: - Task History Tests

    @Test("fetchHistory returns events for task")
    @MainActor
    func fetchHistoryReturnsTaskEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack with a task
        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(task)
        stack.tasks.append(task)
        try context.save()

        // Record task events
        let eventService = EventService(modelContext: context)
        try eventService.recordTaskCreated(task)
        try eventService.recordTaskUpdated(task)
        try context.save()

        // Fetch task history
        let events = try eventService.fetchHistory(for: task.id)

        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.entityId == task.id })
    }

    // MARK: - Event Loading Verification (regression prevention)

    @Test("events can be loaded immediately after creation")
    @MainActor
    func eventsCanBeLoadedImmediatelyAfterCreation() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        // Record an event
        let eventService = EventService(modelContext: context)
        try eventService.recordStackCreated(stack)
        try context.save()

        // Immediately fetch - this simulates the .task(id:) modifier behavior
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        // Events should be available immediately
        #expect(!events.isEmpty, "Events should be loadable immediately after creation")
    }

    @Test("empty stack returns empty history without error")
    @MainActor
    func emptyStackReturnsEmptyHistoryWithoutError() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack without recording any events
        let stack = Stack(title: "Empty Stack")
        context.insert(stack)
        try context.save()

        // Fetch history - should not throw
        let eventService = EventService(modelContext: context)
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        #expect(events.isEmpty)
    }

    @Test("history includes multiple event types")
    @MainActor
    func historyIncludesMultipleEventTypes() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        // Record various events
        let eventService = EventService(modelContext: context)
        try eventService.recordStackCreated(stack)
        try eventService.recordStackUpdated(stack)
        try eventService.recordStackActivated(stack)
        try context.save()

        // Fetch history
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)
        let eventTypes = Set(events.map { $0.type })

        #expect(eventTypes.contains("stack.created"))
        #expect(eventTypes.contains("stack.updated"))
        #expect(eventTypes.contains("stack.activated"))
    }
}
