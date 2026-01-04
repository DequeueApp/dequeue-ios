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
        try ProjectorService.applyEvents([event], context: context)

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
        try ProjectorService.applyEvents([event], context: context)

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
        try ProjectorService.applyEvents([event], context: context)

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
        try ProjectorService.applyEvents([event], context: context)

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
        try ProjectorService.applyEvents([event], context: context)

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
        try ProjectorService.applyEvents([event], context: context)

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
        try ProjectorService.applyEvents([event], context: context)

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
        try ProjectorService.applyEvents([event1, event2, event3], context: context)

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
        try ProjectorService.applyEvents([createEvent1, createEvent2, deactivateEvent, activateEvent], context: context)

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
}
