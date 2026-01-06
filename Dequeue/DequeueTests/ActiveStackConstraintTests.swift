//
//  ActiveStackConstraintTests.swift
//  DequeueTests
//
//  Tests for the single-active-stack constraint (DEQ-23)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Active Stack Constraint Tests")
struct ActiveStackConstraintTests {
    // MARK: - Test Helpers

    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            configurations: config
        )
    }

    // MARK: - Stack Model Tests

    @Test("Stack initializes with isActive = false by default")
    func stackInitializesWithIsActiveFalse() {
        let stack = Stack(title: "Test Stack")
        #expect(stack.isActive == false)
    }

    @Test("Stack can be initialized with isActive = true")
    func stackInitializesWithIsActiveTrue() {
        let stack = Stack(title: "Test Stack", isActive: true)
        #expect(stack.isActive == true)
    }

    // MARK: - StackService.createStack Tests

    @Test("First non-draft stack becomes active automatically")
    @MainActor
    func firstStackBecomesActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try service.createStack(title: "First Stack")

        #expect(stack.isActive == true)
    }

    @Test("Draft stacks do not become active")
    @MainActor
    func draftStacksNotActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try service.createStack(title: "Draft Stack", isDraft: true)

        #expect(draft.isActive == false)
    }

    @Test("Second stack is not active when first exists")
    @MainActor
    func secondStackNotActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        #expect(first.isActive == true)
        #expect(second.isActive == false)
    }

    // MARK: - StackService.setAsActive Tests

    @Test("setAsActive activates target stack")
    @MainActor
    func setAsActiveActivatesTarget() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        #expect(first.isActive == true)
        #expect(second.isActive == false)

        try service.setAsActive(second)

        #expect(first.isActive == false)
        #expect(second.isActive == true)
    }

    @Test("setAsActive deactivates all other stacks")
    @MainActor
    func setAsActiveDeactivatesOthers() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")
        let third = try service.createStack(title: "Third Stack")

        // Manually set all to active to test deactivation
        first.isActive = true
        second.isActive = true
        third.isActive = true
        try context.save()

        try service.setAsActive(third)

        #expect(first.isActive == false)
        #expect(second.isActive == false)
        #expect(third.isActive == true)
    }

    @Test("Only one stack is active after multiple setAsActive calls")
    @MainActor
    func onlyOneActiveAfterMultipleCalls() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")
        let third = try service.createStack(title: "Third Stack")

        try service.setAsActive(second)
        try service.setAsActive(first)
        try service.setAsActive(third)
        try service.setAsActive(second)

        let activeCount = [first, second, third].filter { $0.isActive }.count
        #expect(activeCount == 1)
        #expect(second.isActive == true)
    }

    // MARK: - getCurrentActiveStack Tests

    @Test("getCurrentActiveStack returns the active stack")
    @MainActor
    func getCurrentActiveStackReturnsActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let first = try service.createStack(title: "First Stack")
        _ = try service.createStack(title: "Second Stack")

        let active = try service.getCurrentActiveStack()
        #expect(active?.id == first.id)
    }

    @Test("getCurrentActiveStack returns nil when no active stack")
    @MainActor
    func getCurrentActiveStackReturnsNilWhenNone() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Create only drafts
        _ = try service.createStack(title: "Draft 1", isDraft: true)
        _ = try service.createStack(title: "Draft 2", isDraft: true)

        let active = try service.getCurrentActiveStack()
        #expect(active == nil)
    }

    // MARK: - Migration Tests

    @Test("Migration activates first stack when none are active")
    @MainActor
    func migrationActivatesFirstStack() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Manually create stacks without isActive set (simulates pre-migration data)
        let stack1 = Stack(title: "Stack 1", sortOrder: 1, isActive: false)
        let stack2 = Stack(title: "Stack 2", sortOrder: 0, isActive: false)
        let stack3 = Stack(title: "Stack 3", sortOrder: 2, isActive: false)

        context.insert(stack1)
        context.insert(stack2)
        context.insert(stack3)
        try context.save()

        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")
        try service.migrateActiveStackState()

        // Stack with sortOrder 0 should become active
        #expect(stack2.isActive == true)
        #expect(stack1.isActive == false)
        #expect(stack3.isActive == false)
    }

    @Test("Migration keeps single active stack unchanged")
    @MainActor
    func migrationKeepsSingleActiveUnchanged() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1 = Stack(title: "Stack 1", sortOrder: 0, isActive: false)
        let stack2 = Stack(title: "Stack 2", sortOrder: 1, isActive: true)

        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")
        try service.migrateActiveStackState()

        #expect(stack1.isActive == false)
        #expect(stack2.isActive == true)
    }

    @Test("Migration resolves multiple active stacks")
    @MainActor
    func migrationResolvesMultipleActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1 = Stack(title: "Stack 1", sortOrder: 2, isActive: true)
        let stack2 = Stack(title: "Stack 2", sortOrder: 0, isActive: true)
        let stack3 = Stack(title: "Stack 3", sortOrder: 1, isActive: true)

        context.insert(stack1)
        context.insert(stack2)
        context.insert(stack3)
        try context.save()

        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")
        try service.migrateActiveStackState()

        // Only stack with lowest sortOrder should remain active
        let activeCount = [stack1, stack2, stack3].filter { $0.isActive }.count
        #expect(activeCount == 1)
        #expect(stack2.isActive == true)
    }

    // MARK: - Persistence Tests

    @Test("isActive state persists across fetch")
    @MainActor
    func isActiveStatePersists() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try service.createStack(title: "Test Stack")
        let stackId = stack.id

        #expect(stack.isActive == true)

        // Fetch the stack again
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let fetched = try context.fetch(descriptor).first

        #expect(fetched?.isActive == true)
    }

    // MARK: - Deactivation Event Tests (DEQ-24)

    @Test("setAsActive emits stack.deactivated event for previously active stack")
    @MainActor
    func setAsActiveEmitsDeactivatedEvent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        // Get event count before activation change
        let eventDescriptor = FetchDescriptor<Event>()
        let eventsBefore = try context.fetch(eventDescriptor)
        let countBefore = eventsBefore.count

        // Activate second stack (should deactivate first)
        try service.setAsActive(second)

        // Fetch events after
        let eventsAfter = try context.fetch(eventDescriptor)

        // Should have deactivated, activated, and reordered events
        #expect(eventsAfter.count > countBefore)

        // Find the deactivation event for the first stack
        let deactivationEvents = eventsAfter.filter { $0.eventType == .stackDeactivated }
        #expect(deactivationEvents.count >= 1)

        // Verify deactivation event is for the first stack
        let deactivationEvent = deactivationEvents.first { event in
            event.entityId == first.id
        }
        #expect(deactivationEvent != nil)
    }

    @Test("stack.deactivated event is recorded BEFORE stack.activated event")
    @MainActor
    func deactivatedEventBeforeActivatedEvent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        _ = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        // Activate second stack
        try service.setAsActive(second)

        // Fetch all events sorted by timestamp
        let sortedDescriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let events = try context.fetch(sortedDescriptor)

        // Find the deactivated and activated events for this activation
        let deactivatedEvent = events.first { $0.eventType == .stackDeactivated }
        let activatedEvents = events.filter { $0.eventType == .stackActivated }
        let lastActivatedEvent = activatedEvents.last { $0.entityId == second.id }

        #expect(deactivatedEvent != nil)
        #expect(lastActivatedEvent != nil)

        // Deactivation should happen before activation
        if let deactivated = deactivatedEvent, let activated = lastActivatedEvent {
            #expect(deactivated.timestamp <= activated.timestamp)
        }
    }

    @Test("No deactivation event when activating same stack")
    @MainActor
    func noDeactivationEventForSameStack() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let first = try service.createStack(title: "First Stack")
        _ = try service.createStack(title: "Second Stack")

        // Count deactivation events before
        let eventDescriptor = FetchDescriptor<Event>()
        let eventsBefore = try context.fetch(eventDescriptor)
        let deactivationCountBefore = eventsBefore.filter { $0.eventType == .stackDeactivated }.count

        // Activate the same stack that's already active
        try service.setAsActive(first)

        // Count deactivation events after
        let eventsAfter = try context.fetch(eventDescriptor)
        let deactivationCountAfter = eventsAfter.filter { $0.eventType == .stackDeactivated }.count

        // No new deactivation event should be recorded
        #expect(deactivationCountAfter == deactivationCountBefore)
    }

    @Test("Deactivation event captures stack state while still active")
    @MainActor
    func deactivationEventCapturesActiveState() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")
        let firstId = first.id

        // Activate second stack (deactivates first)
        try service.setAsActive(second)

        // Find deactivation event for first stack
        let eventDescriptor = FetchDescriptor<Event>()
        let events = try context.fetch(eventDescriptor)
        let deactivationEvent = events.first { event in
            event.eventType == .stackDeactivated && event.entityId == firstId
        }

        #expect(deactivationEvent != nil)

        // Decode the payload to verify state was captured while still active
        if let event = deactivationEvent {
            let payload = try event.decodePayload(StackStatusPayload.self)
            #expect(payload.stackId == firstId)
            // The fullState should have captured isActive = true before deactivation
            #expect(payload.fullState.isActive == true)
        }
    }

    // MARK: - markAsCompleted Deactivation Tests (DEQ-131)

    @Test("markAsCompleted deactivates active stack")
    @MainActor
    func markAsCompletedDeactivatesActiveStack() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try service.createStack(title: "Active Stack")
        #expect(stack.isActive == true)

        try service.markAsCompleted(stack)

        #expect(stack.isActive == false)
        #expect(stack.status == .completed)
    }

    @Test("markAsCompleted emits deactivation event for active stack")
    @MainActor
    func markAsCompletedEmitsDeactivationEvent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try service.createStack(title: "Active Stack")
        let stackId = stack.id

        // Count deactivation events before
        let eventDescriptor = FetchDescriptor<Event>()
        let eventsBefore = try context.fetch(eventDescriptor)
        let deactivationCountBefore = eventsBefore.filter { $0.eventType == .stackDeactivated }.count

        try service.markAsCompleted(stack)

        // Count deactivation events after
        let eventsAfter = try context.fetch(eventDescriptor)
        let deactivationCountAfter = eventsAfter.filter { $0.eventType == .stackDeactivated }.count

        // Should have one new deactivation event
        #expect(deactivationCountAfter == deactivationCountBefore + 1)

        // Verify deactivation event is for the completed stack
        let deactivationEvent = eventsAfter.first { event in
            event.eventType == .stackDeactivated && event.entityId == stackId
        }
        #expect(deactivationEvent != nil)
    }

    @Test("markAsCompleted does not emit deactivation event for inactive stack")
    @MainActor
    func markAsCompletedNoDeactivationForInactiveStack() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        _ = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        // Second stack is not active
        #expect(second.isActive == false)

        // Count deactivation events before
        let eventDescriptor = FetchDescriptor<Event>()
        let eventsBefore = try context.fetch(eventDescriptor)
        let deactivationCountBefore = eventsBefore.filter { $0.eventType == .stackDeactivated }.count

        try service.markAsCompleted(second)

        // Count deactivation events after
        let eventsAfter = try context.fetch(eventDescriptor)
        let deactivationCountAfter = eventsAfter.filter { $0.eventType == .stackDeactivated }.count

        // No new deactivation event for inactive stack
        #expect(deactivationCountAfter == deactivationCountBefore)
    }

    @Test("markAsCompleted with completeAllTasks completes pending tasks")
    @MainActor
    func markAsCompletedCompletesAllPendingTasks() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let taskService = TaskService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try stackService.createStack(title: "Stack with Tasks")
        let task1 = try taskService.createTask(title: "Task 1", stack: stack)
        let task2 = try taskService.createTask(title: "Task 2", stack: stack)
        let task3 = try taskService.createTask(title: "Task 3", stack: stack)

        // Mark one task as already completed
        try taskService.markAsCompleted(task2)

        #expect(task1.status == .pending)
        #expect(task2.status == .completed)
        #expect(task3.status == .pending)

        try stackService.markAsCompleted(stack, completeAllTasks: true)

        // All tasks should now be completed
        #expect(task1.status == .completed)
        #expect(task2.status == .completed)
        #expect(task3.status == .completed)
    }

    @Test("markAsCompleted without completeAllTasks leaves tasks unchanged")
    @MainActor
    func markAsCompletedLeavesTasksUnchanged() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let taskService = TaskService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try stackService.createStack(title: "Stack with Tasks")
        let task1 = try taskService.createTask(title: "Task 1", stack: stack)
        let task2 = try taskService.createTask(title: "Task 2", stack: stack)

        try stackService.markAsCompleted(stack, completeAllTasks: false)

        // Tasks should remain pending
        #expect(task1.status == .pending)
        #expect(task2.status == .pending)
        #expect(stack.status == .completed)
    }

    // MARK: - StackService.deactivateStack Tests (DEQ-148)

    @Test("deactivateStack sets isActive to false")
    @MainActor
    func deactivateStackSetsIsActiveFalse() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try service.createStack(title: "Active Stack")
        #expect(stack.isActive == true)

        try service.deactivateStack(stack)

        #expect(stack.isActive == false)
    }

    @Test("deactivateStack is idempotent - calling on non-active stack is safe")
    @MainActor
    func deactivateStackIsIdempotent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Create two stacks - first is active, second is not
        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        #expect(first.isActive == true)
        #expect(second.isActive == false)

        // Deactivating already non-active stack should be a no-op
        try service.deactivateStack(second)

        #expect(second.isActive == false)
        #expect(first.isActive == true) // First should remain active
    }

    @Test("After deactivation, getCurrentActiveStack returns nil")
    @MainActor
    func afterDeactivationNoActiveStack() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try service.createStack(title: "Only Stack")
        #expect(try service.getCurrentActiveStack() != nil)

        try service.deactivateStack(stack)

        #expect(try service.getCurrentActiveStack() == nil)
    }

    @Test("deactivateStack creates a stack.deactivated event")
    @MainActor
    func deactivateStackCreatesEvent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try service.createStack(title: "Stack to Deactivate")

        // Get event count before deactivation
        let eventsBefore = try context.fetch(FetchDescriptor<Event>())
        let beforeCount = eventsBefore.filter { $0.entityId == stack.id }.count

        try service.deactivateStack(stack)

        // Check for new event
        let eventsAfter = try context.fetch(FetchDescriptor<Event>())
        let stackEvents = eventsAfter.filter { $0.entityId == stack.id }
        let afterCount = stackEvents.count

        #expect(afterCount == beforeCount + 1)

        // Verify the event type
        let deactivatedEvent = stackEvents.first { $0.eventType == .stackDeactivated }
        #expect(deactivatedEvent != nil)
    }

    @Test("Can deactivate and then reactivate a stack")
    @MainActor
    func canDeactivateAndReactivate() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try service.createStack(title: "Toggle Stack")
        #expect(stack.isActive == true)

        try service.deactivateStack(stack)
        #expect(stack.isActive == false)

        try service.setAsActive(stack)
        #expect(stack.isActive == true)
    }

    @Test("Deactivating the only active stack leaves zero active stacks")
    @MainActor
    func deactivatingOnlyStackLeavesZeroActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Create multiple stacks - only first should be active
        let first = try service.createStack(title: "First")
        _ = try service.createStack(title: "Second")
        _ = try service.createStack(title: "Third")

        #expect(first.isActive == true)

        // Deactivate the only active stack
        try service.deactivateStack(first)

        // Should now have zero active stacks
        #expect(try service.getCurrentActiveStack() == nil)
        let allActiveStacks = try service.getAllStacksWithIsActiveTrue()
        #expect(allActiveStacks.isEmpty)
    }
}
