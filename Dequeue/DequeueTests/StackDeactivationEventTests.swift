//
//  StackDeactivationEventTests.swift
//  DequeueTests
//
//  Tests for stack.deactivated event emission (DEQ-24)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Stack Deactivation Event Tests")
struct StackDeactivationEventTests {

    // MARK: - Test Helpers

    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            configurations: config
        )
    }

    private func fetchEvents(for entityId: String, in context: ModelContext) throws -> [Event] {
        let predicate = #Predicate<Event> { event in
            event.entityId == entityId
        }
        let descriptor = FetchDescriptor<Event>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchAllEvents(in context: ModelContext) throws -> [Event] {
        let descriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Deactivation Event Emission Tests

    @Test("setAsActive emits deactivation event for previous active stack")
    @MainActor
    func setAsActiveEmitsDeactivationEvent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        // Create two stacks - first becomes active
        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        #expect(first.isActive == true)
        #expect(second.isActive == false)

        // Activate second stack
        try service.setAsActive(second)

        // Fetch events for first stack
        let firstStackEvents = try fetchEvents(for: first.id, in: context)

        // Should have: created, activated, deactivated
        let deactivationEvents = firstStackEvents.filter { $0.type == EventType.stackDeactivated.rawValue }
        #expect(deactivationEvents.count == 1)
    }

    @Test("setAsActive does not emit deactivation event when activating same stack")
    @MainActor
    func setAsActiveNoDeactivationForSameStack() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let stack = try service.createStack(title: "Test Stack")
        #expect(stack.isActive == true)

        // Get event count before
        let eventsBefore = try fetchEvents(for: stack.id, in: context)
        let deactivationsBefore = eventsBefore.filter { $0.type == EventType.stackDeactivated.rawValue }

        // Activate the same stack again
        try service.setAsActive(stack)

        // Get event count after
        let eventsAfter = try fetchEvents(for: stack.id, in: context)
        let deactivationsAfter = eventsAfter.filter { $0.type == EventType.stackDeactivated.rawValue }

        // Should NOT have any new deactivation events
        #expect(deactivationsBefore.count == deactivationsAfter.count)
    }

    @Test("setAsActive does not emit deactivation event when no previous active stack")
    @MainActor
    func setAsActiveNoDeactivationWhenNoPrevious() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        // Create only drafts first
        _ = try service.createStack(title: "Draft 1", isDraft: true)
        _ = try service.createStack(title: "Draft 2", isDraft: true)

        // Create a non-draft stack (will be auto-activated as first)
        let stack = try service.createStack(title: "First Active")

        // Get all events
        let allEvents = try fetchAllEvents(in: context)
        let deactivationEvents = allEvents.filter { $0.type == EventType.stackDeactivated.rawValue }

        // Should NOT have any deactivation events (no previous active stack)
        #expect(deactivationEvents.count == 0)
    }

    // MARK: - Event Order Tests

    @Test("Deactivation event is recorded BEFORE activation event")
    @MainActor
    func deactivationEventBeforeActivation() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        // Activate second stack
        try service.setAsActive(second)

        // Fetch all events sorted by timestamp
        let allEvents = try fetchAllEvents(in: context)

        // Find the deactivation and activation events from this operation
        var deactivationTimestamp: Date?
        var activationTimestamp: Date?

        for event in allEvents {
            if event.type == EventType.stackDeactivated.rawValue && event.entityId == first.id {
                deactivationTimestamp = event.timestamp
            }
            if event.type == EventType.stackActivated.rawValue && event.entityId == second.id {
                // Get the LAST activation event for second stack (after setAsActive)
                activationTimestamp = event.timestamp
            }
        }

        #expect(deactivationTimestamp != nil)
        #expect(activationTimestamp != nil)

        // Deactivation should be before or equal to activation (same timestamp is OK)
        if let deact = deactivationTimestamp, let act = activationTimestamp {
            #expect(deact <= act)
        }
    }

    // MARK: - Event Payload Tests

    @Test("Deactivation event includes stack state")
    @MainActor
    func deactivationEventIncludesState() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        // Activate second stack
        try service.setAsActive(second)

        // Find deactivation event for first stack
        let firstStackEvents = try fetchEvents(for: first.id, in: context)
        let deactivationEvent = firstStackEvents.first { $0.type == EventType.stackDeactivated.rawValue }

        #expect(deactivationEvent != nil)

        // Verify event has correct entity ID and payload is not empty
        if let event = deactivationEvent {
            #expect(event.entityId == first.id)
            #expect(event.payload.count > 0)

            // Decode the StackStatusPayload (used for activation/deactivation events)
            let decoder = JSONDecoder()
            let payload = try decoder.decode(StackStatusPayload.self, from: event.payload)
            #expect(payload.stackId == first.id)
            #expect(payload.fullState.title == "First Stack")
        }
    }

    // MARK: - Multiple Activation Tests

    @Test("Event history shows activation/deactivation pairs")
    @MainActor
    func eventHistoryShowsPairs() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")
        let third = try service.createStack(title: "Third Stack")

        // Switch: first -> second -> third -> first
        try service.setAsActive(second)
        try service.setAsActive(third)
        try service.setAsActive(first)

        let allEvents = try fetchAllEvents(in: context)

        // Count deactivation events
        let deactivationEvents = allEvents.filter { $0.type == EventType.stackDeactivated.rawValue }

        // Should have 3 deactivation events:
        // 1. first deactivated (when second activated)
        // 2. second deactivated (when third activated)
        // 3. third deactivated (when first activated again)
        #expect(deactivationEvents.count == 3)

        // Verify each stack was deactivated at least once
        let deactivatedStackIds = Set(deactivationEvents.compactMap { $0.entityId })
        #expect(deactivatedStackIds.contains(first.id))
        #expect(deactivatedStackIds.contains(second.id))
        #expect(deactivatedStackIds.contains(third.id))
    }
}
