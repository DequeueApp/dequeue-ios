//
//  ProjectorServiceStackTests.swift
//  DequeueTests
//
//  Tests for ProjectorService stack event projection:
//  stackCreated, stackUpdated, stackDeleted, stackActivated, stackDeactivated,
//  stackCompleted, stackDiscarded, stackClosed, stackReordered
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ProjectorService Stack Events", .serialized)
@MainActor
struct ProjectorServiceStackTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            SyncConflict.self, Tag.self, Device.self, Arc.self, Attachment.self,
            configurations: config
        )
    }

    /// Creates a stack.discarded / stack.deleted payload using the `stackId` key.
    private func makeDeletedPayload(stackId: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["stackId": stackId])
    }

    /// Creates a stack status-change payload using the `stackId` key.
    private func makeStatusPayload(stackId: String, status: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["stackId": stackId, "status": status])
    }

    /// Creates a stack.reordered payload using the `stackIds` key.
    private func makeReorderPayload(stackIds: [String], sortOrders: [Int]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "stackIds": stackIds,
            "sortOrders": sortOrders
        ] as [String: Any])
    }

    /// Creates a stackCreated payload (StackEventPayload format).
    private func makeStackCreatedPayload(id: String, title: String = "Test Stack", status: String = "active", sortOrder: Int = 0) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": id,
            "title": title,
            "status": status,
            "sortOrder": sortOrder,
            "isDraft": false,
            "isActive": false,
            "deleted": false,
            "tagIds": [String]()
        ] as [String: Any])
    }

    /// Creates a stack via stackCreated + stackDiscarded events (matching task test pattern).
    /// Returns the projected Stack model. Pass `baseTime` to control timestamps.
    private func createThenDiscardStack(
        id: String,
        title: String = "Deleted Stack",
        context: ModelContext,
        baseTime: Date = Date(timeIntervalSinceNow: -200)
    ) async throws -> Stack {
        // 1. Create via event
        let createPayload = try makeStackCreatedPayload(id: id, title: title)
        let createEvent = Event(
            eventType: .stackCreated,
            payload: createPayload,
            entityId: id,
            userId: "u", deviceId: "d", appId: "a"
        )
        createEvent.timestamp = baseTime
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        // 2. Discard (soft-delete) via event
        let discardPayload = try makeDeletedPayload(stackId: id)
        let discardEvent = Event(
            eventType: .stackDiscarded,
            payload: discardPayload,
            entityId: id,
            userId: "u", deviceId: "d", appId: "a"
        )
        discardEvent.timestamp = baseTime.addingTimeInterval(10)
        context.insert(discardEvent)
        try await ProjectorService.apply(event: discardEvent, context: context)

        // 3. Fetch and return the projected stack
        let predicate = #Predicate<Stack> { $0.id == id }
        let stacks = try context.fetch(FetchDescriptor<Stack>(predicate: predicate))
        return try #require(stacks.first)
    }

    // MARK: - stackCompleted Tests

    @Test("stackCompleted: sets status to completed and clears isActive")
    func completedSetsStatusAndClearsIsActive() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Active Stack",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: -100),
            isActive: true
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStatusPayload(stackId: stackId, status: "completed")
        let event = Event(
            eventType: .stackCompleted,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.status == .completed)
        #expect(stack.isActive == false)
        #expect(stack.syncState == .synced)
    }

    @Test("stackCompleted: LWW skips stale event when local is newer")
    func completedLwwSkipsStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Stack",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: 200),  // local is newer
            isActive: true
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStatusPayload(stackId: stackId, status: "completed")
        let event = Event(
            eventType: .stackCompleted,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)  // stale
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // State should be unchanged
        #expect(stack.status == .active)
        #expect(stack.isActive == true)
    }

    @Test("stackCompleted: ignores completion of deleted stack")
    func completedSkipsDeletedStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        // Use event sourcing to create then soft-delete the stack (same pattern as task tests)
        let stack = try await createThenDiscardStack(id: stackId, context: context)
        #expect(stack.isDeleted == true)  // precondition: stack is deleted

        let payload = try makeStatusPayload(stackId: stackId, status: "completed")
        let event = Event(
            eventType: .stackCompleted,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Status should remain unchanged — deleted stack is skipped
        #expect(stack.status == .active)
    }

    @Test("stackCompleted: no-ops when stack not found")
    func completedNoOpsForMissingStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let payload = try makeStatusPayload(stackId: CUID.generate(), status: "completed")
        let event = Event(
            eventType: .stackCompleted,
            payload: payload,
            entityId: CUID.generate(),
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let allStacks = try context.fetch(FetchDescriptor<Stack>())
        #expect(allStacks.isEmpty)
    }

    // MARK: - stackDiscarded Tests

    @Test("stackDiscarded: marks stack as deleted and clears isActive")
    func discardedMarksDeletedAndClearsIsActive() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Draft Stack",
            updatedAt: Date(timeIntervalSinceNow: -100),
            isDeleted: false,
            isDraft: true,
            isActive: true
        )
        context.insert(stack)
        try context.save()

        let payload = try makeDeletedPayload(stackId: stackId)
        let event = Event(
            eventType: .stackDiscarded,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.isDeleted == true)
        #expect(stack.isActive == false)
        #expect(stack.syncState == .synced)
    }

    @Test("stackDiscarded: LWW skips when local is newer")
    func discardedLwwSkipsWhenLocalNewer() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Stack",
            updatedAt: Date(timeIntervalSinceNow: 300),  // local is newer
            isDeleted: false
        )
        context.insert(stack)
        try context.save()

        let payload = try makeDeletedPayload(stackId: stackId)
        let event = Event(
            eventType: .stackDiscarded,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)  // stale
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Stack should remain intact
        #expect(stack.isDeleted == false)
    }

    @Test("stackDiscarded: no-ops when stack not found")
    func discardedNoOpsForMissingStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let payload = try makeDeletedPayload(stackId: CUID.generate())
        let event = Event(
            eventType: .stackDiscarded,
            payload: payload,
            entityId: CUID.generate(),
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let allStacks = try context.fetch(FetchDescriptor<Stack>())
        #expect(allStacks.isEmpty)
    }

    // MARK: - stackClosed Tests

    @Test("stackClosed: sets status to closed")
    func closedSetsStatus() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Open Stack",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: -100)
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStatusPayload(stackId: stackId, status: "closed")
        let event = Event(
            eventType: .stackClosed,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.status == .closed)
        #expect(stack.syncState == .synced)
    }

    @Test("stackClosed: LWW skips stale event")
    func closedLwwSkipsStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Stack",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: 200)  // local is newer
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStatusPayload(stackId: stackId, status: "closed")
        let event = Event(
            eventType: .stackClosed,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)  // stale
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Status should remain active
        #expect(stack.status == .active)
    }

    @Test("stackClosed: ignores close of deleted stack")
    func closedSkipsDeletedStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        // Use event sourcing to create then soft-delete the stack (same pattern as task tests)
        let stack = try await createThenDiscardStack(id: stackId, title: "Gone Stack", context: context)
        #expect(stack.isDeleted == true)  // precondition: stack is deleted

        let payload = try makeStatusPayload(stackId: stackId, status: "closed")
        let event = Event(
            eventType: .stackClosed,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Deleted stack — status should be unchanged
        #expect(stack.status == .active)
    }

    @Test("stackClosed: no-ops when stack not found")
    func closedNoOpsForMissingStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let payload = try makeStatusPayload(stackId: CUID.generate(), status: "closed")
        let event = Event(
            eventType: .stackClosed,
            payload: payload,
            entityId: CUID.generate(),
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let allStacks = try context.fetch(FetchDescriptor<Stack>())
        #expect(allStacks.isEmpty)
    }

    // MARK: - stackReordered Tests

    @Test("stackReordered: updates sortOrder for all stacks in payload")
    func reorderedUpdatesAllSortOrders() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldDate = Date(timeIntervalSinceNow: -200)
        let id1 = CUID.generate()
        let id2 = CUID.generate()
        let id3 = CUID.generate()

        let stack1 = Stack(id: id1, title: "Stack 1", sortOrder: 0, updatedAt: oldDate)
        let stack2 = Stack(id: id2, title: "Stack 2", sortOrder: 1, updatedAt: oldDate)
        let stack3 = Stack(id: id3, title: "Stack 3", sortOrder: 2, updatedAt: oldDate)
        context.insert(stack1)
        context.insert(stack2)
        context.insert(stack3)
        try context.save()

        // Reverse order: stack3 → 0, stack2 → 1, stack1 → 2
        let payload = try makeReorderPayload(stackIds: [id3, id2, id1], sortOrders: [0, 1, 2])
        let event = Event(
            eventType: .stackReordered,
            payload: payload,
            entityId: id1,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack1.sortOrder == 2)
        #expect(stack2.sortOrder == 1)
        #expect(stack3.sortOrder == 0)
        #expect(stack1.syncState == .synced)
    }

    @Test("stackReordered: LWW skips stacks whose local timestamp is newer")
    func reorderedLwwSkipsNewerStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let id1 = CUID.generate()
        let id2 = CUID.generate()

        // stack1 has a future timestamp (local is newer — should NOT be reordered)
        let stack1 = Stack(id: id1, title: "Newer Stack", sortOrder: 0, updatedAt: Date(timeIntervalSinceNow: 500))
        // stack2 has an old timestamp (event IS newer — should be reordered)
        let stack2 = Stack(id: id2, title: "Older Stack", sortOrder: 1, updatedAt: Date(timeIntervalSinceNow: -200))
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        let payload = try makeReorderPayload(stackIds: [id1, id2], sortOrders: [99, 88])
        let event = Event(
            eventType: .stackReordered,
            payload: payload,
            entityId: id1,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // stack1: local is newer — should NOT be updated
        #expect(stack1.sortOrder == 0)
        // stack2: event is newer — SHOULD be updated
        #expect(stack2.sortOrder == 88)
    }

    @Test("stackReordered: skips deleted stacks silently")
    func reorderedSkipsDeletedStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        // Use event sourcing to create then soft-delete the stack (same pattern as task tests)
        let stack = try await createThenDiscardStack(id: stackId, context: context)
        #expect(stack.isDeleted == true)  // precondition: stack is deleted

        let originalSortOrder = stack.sortOrder

        let payload = try makeReorderPayload(stackIds: [stackId], sortOrders: [42])
        let event = Event(
            eventType: .stackReordered,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // sortOrder should NOT change — deleted stack reorder is skipped
        #expect(stack.sortOrder == originalSortOrder)
        #expect(stack.isDeleted == true)
    }

    @Test("stackReordered: no-ops for unknown stack ids in payload")
    func reorderedIgnoresUnknownIds() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let knownId = CUID.generate()
        let unknownId = CUID.generate()

        let stack = Stack(
            id: knownId, title: "Known Stack",
            sortOrder: 5,
            updatedAt: Date(timeIntervalSinceNow: -200)
        )
        context.insert(stack)
        try context.save()

        // Payload contains both known and unknown stack ids
        let payload = try makeReorderPayload(
            stackIds: [unknownId, knownId],
            sortOrders: [0, 10]
        )
        let event = Event(
            eventType: .stackReordered,
            payload: payload,
            entityId: knownId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        // Should not throw — unknown ids are silently skipped
        try await ProjectorService.apply(event: event, context: context)

        // Known stack's sortOrder should be updated (index 1 → sortOrder 10)
        #expect(stack.sortOrder == 10)
    }

    // MARK: - stackCreated Tests

    @Test("stackCreated: creates stack with correct fields from event")
    func createdBuildsStackFromPayload() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let payload = try makeStackCreatedPayload(id: stackId, title: "My Stack", status: "active", sortOrder: 3)
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Stack> { $0.id == stackId }
        let stacks = try context.fetch(FetchDescriptor<Stack>(predicate: predicate))
        let stack = try #require(stacks.first)
        #expect(stack.title == "My Stack")
        #expect(stack.status == .active)
        #expect(stack.sortOrder == 3)
        #expect(stack.syncState == .synced)
        #expect(stack.isDeleted == false)
    }

    @Test("stackCreated: uses payload createdAt timestamp when provided")
    func createdUsesPayloadCreatedAt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let originalCreatedAt = Date(timeIntervalSinceNow: -3600)  // 1 hour ago
        let createdAtMs = Int64(originalCreatedAt.timeIntervalSince1970 * 1_000)
        let payloadDict: [String: Any] = [
            "id": stackId,
            "title": "Timestamped Stack",
            "status": "active",
            "sortOrder": 0,
            "isDraft": false,
            "isActive": false,
            "deleted": false,
            "tagIds": [String](),
            "createdAt": createdAtMs
        ]
        let payload = try JSONSerialization.data(withJSONObject: payloadDict)
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Stack> { $0.id == stackId }
        let stacks = try context.fetch(FetchDescriptor<Stack>(predicate: predicate))
        let stack = try #require(stacks.first)
        // createdAt should match the payload timestamp (within 1s tolerance for ms conversion)
        #expect(abs(stack.createdAt.timeIntervalSince(originalCreatedAt)) < 1.0)
    }

    @Test("stackCreated: LWW updates existing stack when event is newer")
    func createdLwwUpdatesWhenEventIsNewer() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        // Insert an older stack locally
        let existingStack = Stack(
            id: stackId, title: "Old Title",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: -200)
        )
        context.insert(existingStack)
        try context.save()

        // stackCreated event is newer → should overwrite
        let payload = try makeStackCreatedPayload(id: stackId, title: "New Title From Event")
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existingStack.title == "New Title From Event")
        #expect(existingStack.syncState == .synced)
    }

    @Test("stackCreated: LWW skips update when existing stack is newer")
    func createdLwwSkipsWhenLocalIsNewer() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        // Insert a stack with a future timestamp (local is newer)
        let existingStack = Stack(
            id: stackId, title: "Local Title",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: 500)
        )
        context.insert(existingStack)
        try context.save()

        // Stale event — should be ignored
        let payload = try makeStackCreatedPayload(id: stackId, title: "Stale Title From Event")
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Title should remain unchanged
        #expect(existingStack.title == "Local Title")
    }

    // MARK: - stackUpdated Tests

    @Test("stackUpdated: updates stack fields from event")
    func updatedAppliesFieldChanges() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Original",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: -100)
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStackCreatedPayload(id: stackId, title: "Updated Title", status: "active", sortOrder: 7)
        let event = Event(
            eventType: .stackUpdated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.title == "Updated Title")
        #expect(stack.sortOrder == 7)
        #expect(stack.syncState == .synced)
    }

    @Test("stackUpdated: LWW skips stale update")
    func updatedLwwSkipsStaleEvent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Current Title",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: 300)  // local is newer
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStackCreatedPayload(id: stackId, title: "Stale Update", status: "active")
        let event = Event(
            eventType: .stackUpdated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)  // stale
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.title == "Current Title")
    }

    @Test("stackUpdated: no-ops when stack not found")
    func updatedNoOpsForMissingStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let payload = try makeStackCreatedPayload(id: CUID.generate(), title: "Ghost Stack")
        let event = Event(
            eventType: .stackUpdated,
            payload: payload,
            entityId: CUID.generate(),
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let allStacks = try context.fetch(FetchDescriptor<Stack>())
        #expect(allStacks.isEmpty)
    }

    @Test("stackUpdated: ignores update to deleted stack")
    func updatedSkipsDeletedStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = try await createThenDiscardStack(id: stackId, title: "Deleted Stack", context: context)
        #expect(stack.isDeleted == true)

        let originalTitle = stack.title
        let payload = try makeStackCreatedPayload(id: stackId, title: "Should Be Ignored", status: "active")
        let event = Event(
            eventType: .stackUpdated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.title == originalTitle)
    }

    // MARK: - stackDeleted Tests

    @Test("stackDeleted: marks stack as deleted and clears isActive")
    func deletedMarksStackAndClearsIsActive() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Active Stack",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: -100),
            isDeleted: false,
            isActive: true
        )
        context.insert(stack)
        try context.save()

        let payload = try makeDeletedPayload(stackId: stackId)
        let event = Event(
            eventType: .stackDeleted,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.isDeleted == true)
        #expect(stack.isActive == false)
        #expect(stack.syncState == .synced)
    }

    @Test("stackDeleted: LWW skips deletion when local is newer")
    func deletedLwwSkipsWhenLocalIsNewer() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Stack",
            updatedAt: Date(timeIntervalSinceNow: 400),  // local is newer
            isDeleted: false,
            isActive: true
        )
        context.insert(stack)
        try context.save()

        let payload = try makeDeletedPayload(stackId: stackId)
        let event = Event(
            eventType: .stackDeleted,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)  // stale
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Stack should remain intact
        #expect(stack.isDeleted == false)
        #expect(stack.isActive == true)
    }

    @Test("stackDeleted: no-ops when stack not found")
    func deletedNoOpsForMissingStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let payload = try makeDeletedPayload(stackId: CUID.generate())
        let event = Event(
            eventType: .stackDeleted,
            payload: payload,
            entityId: CUID.generate(),
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let allStacks = try context.fetch(FetchDescriptor<Stack>())
        #expect(allStacks.isEmpty)
    }

    // MARK: - stackActivated Tests

    @Test("stackActivated: sets isActive to true on the target stack")
    func activatedSetsIsActive() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Inactive Stack",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: -100),
            isActive: false
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStatusPayload(stackId: stackId, status: "active")
        let event = Event(
            eventType: .stackActivated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.isActive == true)
        #expect(stack.syncState == .synced)
    }

    @Test("stackActivated: deactivates all other active stacks (single-active constraint)")
    func activatedDeactivatesOtherStacks() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let targetId = CUID.generate()
        let otherId1 = CUID.generate()
        let otherId2 = CUID.generate()

        let target = Stack(id: targetId, title: "Target",   updatedAt: Date(timeIntervalSinceNow: -100), isActive: false)
        let other1 = Stack(id: otherId1, title: "Other 1", updatedAt: Date(timeIntervalSinceNow: -200), isActive: true)
        let other2 = Stack(id: otherId2, title: "Other 2", updatedAt: Date(timeIntervalSinceNow: -200), isActive: true)
        context.insert(target)
        context.insert(other1)
        context.insert(other2)
        try context.save()

        let payload = try makeStatusPayload(stackId: targetId, status: "active")
        let event = Event(
            eventType: .stackActivated,
            payload: payload,
            entityId: targetId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Target becomes active; others are deactivated
        #expect(target.isActive == true)
        #expect(other1.isActive == false)
        #expect(other2.isActive == false)
    }

    @Test("stackActivated: LWW skips stale event")
    func activatedLwwSkipsStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Stack",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: 300),  // local is newer
            isActive: false
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStatusPayload(stackId: stackId, status: "active")
        let event = Event(
            eventType: .stackActivated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)  // stale
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // isActive should remain false — stale event skipped
        #expect(stack.isActive == false)
    }

    @Test("stackActivated: ignores activation of deleted stack")
    func activatedSkipsDeletedStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = try await createThenDiscardStack(id: stackId, context: context)
        #expect(stack.isDeleted == true)

        let payload = try makeStatusPayload(stackId: stackId, status: "active")
        let event = Event(
            eventType: .stackActivated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Deleted stack should not become active
        #expect(stack.isActive == false)
    }

    // MARK: - stackDeactivated Tests

    @Test("stackDeactivated: clears isActive on the target stack")
    func deactivatedClearsIsActive() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Active Stack",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: -100),
            isActive: true
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStatusPayload(stackId: stackId, status: "active")
        let event = Event(
            eventType: .stackDeactivated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.isActive == false)
        #expect(stack.syncState == .synced)
    }

    @Test("stackDeactivated: LWW skips stale event")
    func deactivatedLwwSkipsStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let stack = Stack(
            id: stackId, title: "Stack",
            status: .active,
            updatedAt: Date(timeIntervalSinceNow: 300),  // local is newer
            isActive: true
        )
        context.insert(stack)
        try context.save()

        let payload = try makeStatusPayload(stackId: stackId, status: "active")
        let event = Event(
            eventType: .stackDeactivated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)  // stale
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // isActive should remain true — stale event skipped
        #expect(stack.isActive == true)
    }

    @Test("stackDeactivated: ignores deactivation of deleted stack")
    func deactivatedSkipsDeletedStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        // Create and discard the stack using event sourcing (the proven pattern).
        // After the discard, isDeleted = true and isActive = false.
        let stack = try await createThenDiscardStack(id: stackId, context: context)
        #expect(stack.isDeleted == true)

        // Record updatedAt before the deactivation event — it must not change.
        let updatedAtBeforeEvent = stack.updatedAt

        let payload = try makeStatusPayload(stackId: stackId, status: "active")
        let event = Event(
            eventType: .stackDeactivated,
            payload: payload,
            entityId: stackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        // Event is newer than stack.updatedAt — LWW alone would not block it.
        // Only the isDeleted guard blocks it.
        event.timestamp = stack.updatedAt.addingTimeInterval(100)
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Deleted guard fires before any writes — updatedAt must be unchanged
        #expect(stack.updatedAt == updatedAtBeforeEvent)
        #expect(stack.isDeleted == true)
    }
}
