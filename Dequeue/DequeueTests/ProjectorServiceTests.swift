//
//  ProjectorServiceTests.swift
//  DequeueTests
//
//  Tests for ProjectorService event projection, specifically isActive restoration (DEQ-136)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ProjectorService Tests")
@MainActor
struct ProjectorServiceTests {

    // MARK: - Test Helpers

    /// Helper to apply multiple events in sequence
    private func applyEvents(_ events: [Event], context: ModelContext) throws {
        for event in events {
            try ProjectorService.apply(event: event, context: context)
        }
    }

    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self, SyncConflict.self,
            configurations: config
        )
    }

    /// Creates a stack event payload that can be decoded by StackEventPayload
    private func createStackPayload(
        id: String,
        title: String,
        isActive: Bool,
        status: StackStatus = .active
    ) throws -> Data {
        // Create a dictionary that matches StackEventPayload structure
        let payload: [String: Any] = [
            "id": id,
            "title": title,
            "description": NSNull(),
            "status": status.rawValue,
            "priority": NSNull(),
            "sortOrder": 0,
            "isDraft": false,
            "isActive": isActive,
            "activeTaskId": NSNull(),
            "deleted": false
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Creates an entity status payload for activated/deactivated events
    private func createEntityStatusPayload(id: String, status: String = "active") throws -> Data {
        let payload: [String: String] = [
            "id": id,
            "status": status
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - updateStack isActive Restoration Tests (DEQ-136)

    @Test("updateStack restores isActive from payload")
    func updateStackRestoresIsActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with isActive = false
        let stack = Stack(title: "Test Stack", isActive: false)
        context.insert(stack)
        try context.save()

        #expect(stack.isActive == false)

        // Create a stack.updated event with isActive = true
        let payload = try createStackPayload(id: stack.id, title: "Updated Title", isActive: true)
        let event = Event(eventType: .stackUpdated, payload: payload, entityId: stack.id)
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify isActive was restored
        #expect(stack.isActive == true)
        #expect(stack.title == "Updated Title")
    }

    @Test("applyStackCreated sets isActive from payload")
    func applyStackCreatedSetsIsActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()

        // Create a stack.created event with isActive = true
        let payload = try createStackPayload(id: stackId, title: "New Active Stack", isActive: true)
        let event = Event(eventType: .stackCreated, payload: payload, entityId: stackId)
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify the stack was created with isActive = true
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let stacks = try context.fetch(descriptor)

        #expect(stacks.count == 1)
        #expect(stacks.first?.isActive == true)
    }

    @Test("applyStackCreated sets isActive to false when payload says so")
    func applyStackCreatedSetsIsActiveFalse() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()

        // Create a stack.created event with isActive = false
        let payload = try createStackPayload(id: stackId, title: "New Inactive Stack", isActive: false)
        let event = Event(eventType: .stackCreated, payload: payload, entityId: stackId)
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify the stack was created with isActive = false
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let stacks = try context.fetch(descriptor)

        #expect(stacks.count == 1)
        #expect(stacks.first?.isActive == false)
    }

    // MARK: - applyStackActivated Tests (DEQ-136)

    @Test("applyStackActivated sets isActive to true")
    func applyStackActivatedSetsIsActiveTrue() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with isActive = false
        let stack = Stack(title: "Test Stack", isActive: false)
        context.insert(stack)
        try context.save()

        #expect(stack.isActive == false)

        // Create a stack.activated event
        let payloadData = try createEntityStatusPayload(id: stack.id, status: "active")
        let event = Event(eventType: .stackActivated, payload: payloadData, entityId: stack.id)
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify isActive was set to true (not status changed)
        #expect(stack.isActive == true)
    }

    @Test("applyStackActivated does not change workflow status")
    func applyStackActivatedDoesNotChangeStatus() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with specific workflow status
        let stack = Stack(title: "Test Stack", status: .completed, isActive: false)
        context.insert(stack)
        try context.save()

        let originalStatus = stack.status
        #expect(originalStatus == .completed)

        // Create a stack.activated event
        let payloadData = try createEntityStatusPayload(id: stack.id, status: "active")
        let event = Event(eventType: .stackActivated, payload: payloadData, entityId: stack.id)
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify workflow status was NOT changed
        #expect(stack.status == .completed)
        // But isActive should be true
        #expect(stack.isActive == true)
    }

    // MARK: - applyStackDeactivated Tests (DEQ-136)

    @Test("applyStackDeactivated sets isActive to false")
    func applyStackDeactivatedSetsIsActiveFalse() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with isActive = true
        let stack = Stack(title: "Test Stack", isActive: true)
        context.insert(stack)
        try context.save()

        #expect(stack.isActive == true)

        // Create a stack.deactivated event
        let payloadData = try createEntityStatusPayload(id: stack.id, status: "archived")
        let event = Event(eventType: .stackDeactivated, payload: payloadData, entityId: stack.id)
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify isActive was set to false (not status changed)
        #expect(stack.isActive == false)
    }

    @Test("applyStackDeactivated does not change workflow status")
    func applyStackDeactivatedDoesNotChangeStatus() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with specific workflow status
        let stack = Stack(title: "Test Stack", status: .active, isActive: true)
        context.insert(stack)
        try context.save()

        let originalStatus = stack.status
        #expect(originalStatus == .active)

        // Create a stack.deactivated event
        let payloadData = try createEntityStatusPayload(id: stack.id, status: "archived")
        let event = Event(eventType: .stackDeactivated, payload: payloadData, entityId: stack.id)
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify workflow status was NOT changed
        #expect(stack.status == .active)
        // But isActive should be false
        #expect(stack.isActive == false)
    }

    // MARK: - Single Active Stack Constraint Tests (DEQ-136)

    @Test("Only one stack is active after rehydrating multiple events")
    func singleActiveAfterRehydration() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1Id = CUID.generate()
        let stack2Id = CUID.generate()
        let stack3Id = CUID.generate()

        // Create three stacks via events
        let payload1 = try createStackPayload(id: stack1Id, title: "Stack 1", isActive: false)
        let payload2 = try createStackPayload(id: stack2Id, title: "Stack 2", isActive: false)
        let payload3 = try createStackPayload(id: stack3Id, title: "Stack 3", isActive: true)

        let event1 = Event(eventType: .stackCreated, payload: payload1, entityId: stack1Id)
        let event2 = Event(eventType: .stackCreated, payload: payload2, entityId: stack2Id)
        let event3 = Event(eventType: .stackCreated, payload: payload3, entityId: stack3Id)

        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        // Apply events in order
        try applyEvents([event1, event2, event3], context: context)

        // Verify only stack3 is active
        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)

        let activeStacks = stacks.filter { $0.isActive }
        #expect(activeStacks.count == 1)
        #expect(activeStacks.first?.id == stack3Id)
    }

    @Test("Activation and deactivation events maintain single active constraint")
    func activationDeactivationMaintainsConstraint() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1Id = CUID.generate()
        let stack2Id = CUID.generate()

        // Create two stacks with stack1 active
        let payload1 = try createStackPayload(id: stack1Id, title: "Stack 1", isActive: true)
        let payload2 = try createStackPayload(id: stack2Id, title: "Stack 2", isActive: false)

        let createEvent1 = Event(eventType: .stackCreated, payload: payload1, entityId: stack1Id)
        let createEvent2 = Event(eventType: .stackCreated, payload: payload2, entityId: stack2Id)

        // Deactivate stack1, activate stack2
        let deactivateData = try createEntityStatusPayload(id: stack1Id, status: "active")
        let deactivateEvent = Event(eventType: .stackDeactivated, payload: deactivateData, entityId: stack1Id)

        let activateData = try createEntityStatusPayload(id: stack2Id, status: "active")
        let activateEvent = Event(eventType: .stackActivated, payload: activateData, entityId: stack2Id)

        context.insert(createEvent1)
        context.insert(createEvent2)
        context.insert(deactivateEvent)
        context.insert(activateEvent)
        try context.save()

        // Apply all events in order
        try applyEvents([createEvent1, createEvent2, deactivateEvent, activateEvent], context: context)

        // Verify only stack2 is active now
        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)

        let stack1 = stacks.first { $0.id == stack1Id }
        let stack2 = stacks.first { $0.id == stack2Id }

        #expect(stack1?.isActive == false)
        #expect(stack2?.isActive == true)

        let activeCount = stacks.filter { $0.isActive }.count
        #expect(activeCount == 1)
    }

    // MARK: - Constraint Enforcement Tests (DEQ-136)

    @Test("applyStackActivated enforces single active constraint by deactivating others")
    func applyStackActivatedEnforcesConstraint() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create two stacks, both initially active (simulating a corrupted state)
        let stack1 = Stack(title: "Stack 1", isActive: true)
        let stack2 = Stack(title: "Stack 2", isActive: true)
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        // Both are active (constraint violated)
        #expect(stack1.isActive == true)
        #expect(stack2.isActive == true)

        // Activate stack2 via event - should deactivate stack1
        let payloadData = try createEntityStatusPayload(id: stack2.id, status: "active")
        let event = Event(eventType: .stackActivated, payload: payloadData, entityId: stack2.id)
        context.insert(event)
        try context.save()

        // Apply the activation event
        try applyEvents([event], context: context)

        // Verify constraint is now enforced: only stack2 should be active
        #expect(stack1.isActive == false)
        #expect(stack2.isActive == true)

        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)
        let activeCount = stacks.filter { $0.isActive }.count
        #expect(activeCount == 1)
    }

    @Test("Multiple rapid activation events result in only last activated stack being active")
    func multipleActivationEventsLastWins() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1Id = CUID.generate()
        let stack2Id = CUID.generate()
        let stack3Id = CUID.generate()

        // Create three stacks with none active
        let payload1 = try createStackPayload(id: stack1Id, title: "Stack 1", isActive: false)
        let payload2 = try createStackPayload(id: stack2Id, title: "Stack 2", isActive: false)
        let payload3 = try createStackPayload(id: stack3Id, title: "Stack 3", isActive: false)

        let createEvent1 = Event(eventType: .stackCreated, payload: payload1, entityId: stack1Id)
        let createEvent2 = Event(eventType: .stackCreated, payload: payload2, entityId: stack2Id)
        let createEvent3 = Event(eventType: .stackCreated, payload: payload3, entityId: stack3Id)

        // Three rapid activation events - without corresponding deactivation events
        let activateData1 = try createEntityStatusPayload(id: stack1Id, status: "active")
        let activateEvent1 = Event(eventType: .stackActivated, payload: activateData1, entityId: stack1Id)

        let activateData2 = try createEntityStatusPayload(id: stack2Id, status: "active")
        let activateEvent2 = Event(eventType: .stackActivated, payload: activateData2, entityId: stack2Id)

        let activateData3 = try createEntityStatusPayload(id: stack3Id, status: "active")
        let activateEvent3 = Event(eventType: .stackActivated, payload: activateData3, entityId: stack3Id)

        // Insert all events
        context.insert(createEvent1)
        context.insert(createEvent2)
        context.insert(createEvent3)
        context.insert(activateEvent1)
        context.insert(activateEvent2)
        context.insert(activateEvent3)
        try context.save()

        // Apply all events in order (create then activate, last activation wins)
        try applyEvents([
            createEvent1, createEvent2, createEvent3,
            activateEvent1, activateEvent2, activateEvent3
        ], context: context)

        // Verify only the last activated stack (stack3) is active
        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)

        let stack1 = stacks.first { $0.id == stack1Id }
        let stack2 = stacks.first { $0.id == stack2Id }
        let stack3 = stacks.first { $0.id == stack3Id }

        #expect(stack1?.isActive == false)
        #expect(stack2?.isActive == false)
        #expect(stack3?.isActive == true)

        let activeCount = stacks.filter { $0.isActive }.count
        #expect(activeCount == 1)
    }

    @Test("Deleted stack activation is ignored")
    func deletedStackActivationIsIgnored() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()

        // Step 1: Create the stack via an event (same pattern as other tests)
        let createPayload = try createStackPayload(id: stackId, title: "Test Stack", isActive: false)
        let createEvent = Event(eventType: .stackCreated, payload: createPayload, entityId: stackId)
        context.insert(createEvent)
        try context.save()
        try applyEvents([createEvent], context: context)

        // Verify stack was created
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        var stacks = try context.fetch(descriptor)
        #expect(stacks.count == 1)
        #expect(stacks.first?.isDeleted == false)
        #expect(stacks.first?.isActive == false)

        // Step 2: Delete the stack via an event
        let deletePayloadDict: [String: Any] = ["id": stackId, "deleted": true]
        let deletePayloadData = try JSONSerialization.data(withJSONObject: deletePayloadDict)
        let deleteEvent = Event(eventType: .stackDeleted, payload: deletePayloadData, entityId: stackId)
        context.insert(deleteEvent)
        try context.save()
        try applyEvents([deleteEvent], context: context)

        // Verify stack is now deleted
        stacks = try context.fetch(descriptor)
        #expect(stacks.count == 1)
        #expect(stacks.first?.isDeleted == true)
        #expect(stacks.first?.isActive == false)

        // Step 3: Try to activate the deleted stack via event
        let activatePayloadData = try createEntityStatusPayload(id: stackId, status: "active")
        let activateEvent = Event(eventType: .stackActivated, payload: activatePayloadData, entityId: stackId)
        context.insert(activateEvent)
        try context.save()
        try applyEvents([activateEvent], context: context)

        // Step 4: Verify the deleted stack was NOT activated (guard should prevent it)
        stacks = try context.fetch(descriptor)
        #expect(stacks.count == 1)
        guard let finalStack = stacks.first else {
            Issue.record("Failed to fetch stack")
            return
        }

        #expect(finalStack.isDeleted == true)
        #expect(finalStack.isActive == false)
    }

    @Test("Stack deletion sets isActive to false")
    func stackDeletionSetsIsActiveFalse() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create an active stack
        let stack = Stack(title: "Active Stack", isActive: true)
        context.insert(stack)
        try context.save()

        #expect(stack.isActive == true)
        #expect(stack.isDeleted == false)

        // Create a stack.deleted event
        let payloadDict: [String: Any] = ["id": stack.id, "deleted": true]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict)
        let event = Event(eventType: .stackDeleted, payload: payloadData, entityId: stack.id)
        context.insert(event)
        try context.save()

        // Apply the deletion event
        try applyEvents([event], context: context)

        // Verify the stack is now deleted and inactive
        #expect(stack.isDeleted == true)
        #expect(stack.isActive == false)
    }
}
