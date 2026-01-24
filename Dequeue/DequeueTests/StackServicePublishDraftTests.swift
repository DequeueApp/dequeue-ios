//
//  StackServicePublishDraftTests.swift
//  DequeueTests
//
//  Tests for StackService publishDraft functionality (DEQ-213)
//  Verifies that publishing a draft emits stack.updated, not stack.created
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test-only decodable version of StackUpdatedPayload

/// Decodable version of StackUpdatedPayload for test verification
private struct StackUpdatedPayloadReadable: Decodable {
    let stackId: String
    let fullState: StackState
}

@Suite("StackService PublishDraft Tests", .serialized)
struct StackServicePublishDraftTests {

    // MARK: - Test Helpers

    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self, Tag.self, Arc.self, Attachment.self,
            configurations: config
        )
    }

    // MARK: - publishDraft Event Tests

    @Test("publishDraft emits stack.updated event, not stack.created")
    @MainActor
    func publishDraftEmitsUpdatedEvent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Create a draft stack
        let draft = try await service.createStack(title: "My Draft", isDraft: true)
        #expect(draft.isDraft == true)

        // Count events before publishing
        let eventDescriptor = FetchDescriptor<Event>()
        let eventsBefore = try context.fetch(eventDescriptor)
        let createdEventsBefore = eventsBefore.filter { $0.eventType == .stackCreated }.count
        let updatedEventsBefore = eventsBefore.filter { $0.eventType == .stackUpdated }.count

        // Publish the draft
        try await service.publishDraft(draft)

        // Verify state change
        #expect(draft.isDraft == false)

        // Count events after publishing
        let eventsAfter = try context.fetch(eventDescriptor)
        let createdEventsAfter = eventsAfter.filter { $0.eventType == .stackCreated }.count
        let updatedEventsAfter = eventsAfter.filter { $0.eventType == .stackUpdated }.count

        // Should have NO new stack.created events (bug was that it created one)
        #expect(createdEventsAfter == createdEventsBefore, "publishDraft should NOT emit stack.created event")

        // Should have ONE new stack.updated event
        #expect(updatedEventsAfter == updatedEventsBefore + 1, "publishDraft should emit stack.updated event")
    }

    @Test("Draft creation followed by publish produces exactly one stack.created event")
    @MainActor
    func draftCreationAndPublishProducesOneCreatedEvent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Simulate the full user flow: create draft, then publish
        let draft = try await service.createStack(
            title: "Test Stack",
            description: "Test description",
            isDraft: true
        )

        // Publish the draft (simulates user clicking "Create" button)
        try await service.publishDraft(draft)

        // Count total stack.created events
        let eventDescriptor = FetchDescriptor<Event>()
        let events = try context.fetch(eventDescriptor)
        let stackCreatedEvents = events.filter {
            $0.eventType == .stackCreated && $0.entityId == draft.id
        }

        // Should have exactly ONE stack.created event for this stack
        #expect(stackCreatedEvents.count == 1, "Expected exactly 1 stack.created event, got \(stackCreatedEvents.count)")
    }

    @Test("publishDraft stack.updated event contains isDraft = false")
    @MainActor
    func publishDraftEventContainsCorrectState() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await service.createStack(title: "Draft to Publish", isDraft: true)
        let draftId = draft.id

        try await service.publishDraft(draft)

        // Find the stack.updated event for this stack
        let eventDescriptor = FetchDescriptor<Event>()
        let events = try context.fetch(eventDescriptor)
        let updateEvent = events.first {
            $0.eventType == .stackUpdated && $0.entityId == draftId
        }

        #expect(updateEvent != nil, "Should have stack.updated event after publish")

        // Decode and verify the payload contains isDraft = false in fullState
        if let event = updateEvent {
            let payload = try event.decodePayload(StackUpdatedPayloadReadable.self)
            #expect(payload.fullState.isDraft == false, "Published stack should have isDraft = false in event payload")
        }
    }

    @Test("publishDraft is idempotent - calling on non-draft stack does nothing")
    @MainActor
    func publishDraftIdempotentForNonDraft() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Create a non-draft stack
        let stack = try await service.createStack(title: "Regular Stack", isDraft: false)
        #expect(stack.isDraft == false)

        // Count events before
        let eventDescriptor = FetchDescriptor<Event>()
        let eventsBefore = try context.fetch(eventDescriptor)
        let countBefore = eventsBefore.count

        // Try to publish a non-draft (should be no-op)
        try await service.publishDraft(stack)

        // Count events after
        let eventsAfter = try context.fetch(eventDescriptor)
        let countAfter = eventsAfter.count

        // No new events should be created
        #expect(countAfter == countBefore, "publishDraft on non-draft should not create events")
    }

    @Test("publishDraft updates syncState to pending")
    @MainActor
    func publishDraftSetsSyncStatePending() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await service.createStack(title: "Sync Test Draft", isDraft: true)

        // Set to synced to test the transition
        draft.syncState = .synced
        try context.save()

        try await service.publishDraft(draft)

        #expect(draft.syncState == .pending, "publishDraft should set syncState to .pending")
    }

    @Test("publishDraft updates updatedAt timestamp")
    @MainActor
    func publishDraftUpdatesTimestamp() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await service.createStack(title: "Timestamp Test", isDraft: true)
        let originalTimestamp = draft.updatedAt

        // Wait a tiny bit to ensure timestamps differ
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        try await service.publishDraft(draft)

        #expect(draft.updatedAt > originalTimestamp, "publishDraft should update the timestamp")
    }

    // MARK: - Full Flow Integration Tests

    @Test("Complete draft lifecycle: create, update, publish produces correct events")
    @MainActor
    func completeDraftLifecycleProducesCorrectEvents() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Step 1: Create draft (simulates title blur in UI)
        let draft = try await service.createStack(title: "Initial Title", isDraft: true)

        // Step 2: Update draft (simulates description change)
        try await service.updateDraft(draft, title: "Updated Title", description: "Added description")

        // Step 3: Publish draft (simulates clicking Create button)
        try await service.publishDraft(draft)

        // Verify final state
        #expect(draft.isDraft == false)
        #expect(draft.title == "Updated Title")

        // Count events by type for this stack
        let eventDescriptor = FetchDescriptor<Event>()
        let events = try context.fetch(eventDescriptor)
        let stackEvents = events.filter { $0.entityId == draft.id }

        let createdCount = stackEvents.filter { $0.eventType == .stackCreated }.count
        let updatedCount = stackEvents.filter { $0.eventType == .stackUpdated }.count

        // Should have exactly 1 created event (from initial draft creation)
        #expect(createdCount == 1, "Expected 1 stack.created, got \(createdCount)")

        // Should have exactly 2 updated events (1 from updateDraft, 1 from publishDraft)
        #expect(updatedCount == 2, "Expected 2 stack.updated events, got \(updatedCount)")
    }

    @Test("Draft created with isDraft=true, published stack has isDraft=false")
    @MainActor
    func draftStateTransitionsCorrectly() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await service.createStack(title: "State Test", isDraft: true)

        // Verify initial state
        #expect(draft.isDraft == true, "Newly created draft should have isDraft = true")
        #expect(draft.isActive == false, "Draft should not be active")

        try await service.publishDraft(draft)

        // Verify published state
        #expect(draft.isDraft == false, "Published stack should have isDraft = false")
    }

    // MARK: - Event Payload Verification Tests

    @Test("stack.created event for draft has isDraft = true in payload")
    @MainActor
    func draftCreatedEventHasIsDraftTrue() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await service.createStack(title: "Payload Test Draft", isDraft: true)

        // Find the stack.created event
        let eventDescriptor = FetchDescriptor<Event>()
        let events = try context.fetch(eventDescriptor)
        let createdEvent = events.first {
            $0.eventType == .stackCreated && $0.entityId == draft.id
        }

        #expect(createdEvent != nil)

        if let event = createdEvent {
            let payload = try event.decodePayload(StackCreatedPayload.self)
            #expect(payload.state.isDraft == true, "Draft creation event should have isDraft = true")
        }
    }

    @Test("Multiple drafts can be created and published independently")
    @MainActor
    func multipleDraftsIndependent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft1 = try await service.createStack(title: "Draft 1", isDraft: true)
        let draft2 = try await service.createStack(title: "Draft 2", isDraft: true)

        // Publish only draft1
        try await service.publishDraft(draft1)

        #expect(draft1.isDraft == false)
        #expect(draft2.isDraft == true)

        // Count created events - should be 2 (one for each draft creation)
        let eventDescriptor = FetchDescriptor<Event>()
        let events = try context.fetch(eventDescriptor)
        let createdEvents = events.filter { $0.eventType == .stackCreated }

        #expect(createdEvents.count == 2, "Each draft creation should produce exactly one stack.created event")
    }
}
