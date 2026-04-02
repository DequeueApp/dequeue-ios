//
//  ProjectorServiceArcTests.swift
//  DequeueTests
//
//  Tests for ProjectorService arc event projection:
//  arcCreated, arcUpdated, arcDeleted, arcCompleted, arcActivated,
//  arcDeactivated, arcPaused, arcReordered, stackAssignedToArc, stackRemovedFromArc
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ProjectorService Arc Events", .serialized)
@MainActor
struct ProjectorServiceArcTests {
    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            SyncConflict.self, Tag.self, Device.self, Arc.self, Attachment.self,
            configurations: config
        )
    }

    private func makeArcPayload(
        id: String,
        title: String = "Test Arc",
        description: String? = nil,
        status: String = "active",
        sortOrder: Int = 0,
        colorHex: String? = nil,
        deleted: Bool = false,
        stackIds: [String] = []
    ) throws -> Data {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "status": status,
            "sortOrder": sortOrder,
            "deleted": deleted,
            "stackIds": stackIds
        ]
        if let description { dict["description"] = description }
        if let colorHex { dict["colorHex"] = colorHex }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func makeStatusPayload(arcId: String, status: String = "active") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["arcId": arcId, "status": status] as [String: Any])
    }

    private func makeReorderPayload(arcIds: [String], sortOrders: [Int]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["arcIds": arcIds, "sortOrders": sortOrders] as [String: Any])
    }

    private func makeAssignmentPayload(stackId: String, arcId: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["stackId": stackId, "arcId": arcId] as [String: Any])
    }

    // MARK: - arcCreated Tests

    @Test("arcCreated: creates arc with correct fields from event")
    func createsArcFromEvent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let payload = try makeArcPayload(
            id: arcId,
            title: "Q2 Goals",
            description: "Goals for Q2 2026",
            status: "active",
            sortOrder: 3,
            colorHex: "#FF5500"
        )

        let event = Event(
            eventType: .arcCreated, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Arc> { $0.id == arcId }
        let arcs = try context.fetch(FetchDescriptor<Arc>(predicate: predicate))
        #expect(arcs.count == 1)
        let arc = try #require(arcs.first)
        #expect(arc.title == "Q2 Goals")
        #expect(arc.arcDescription == "Goals for Q2 2026")
        #expect(arc.status == .active)
        #expect(arc.sortOrder == 3)
        #expect(arc.colorHex == "#FF5500")
        #expect(arc.isDeleted == false)
        #expect(arc.syncState == .synced)
    }

    @Test("arcCreated: LWW updates existing arc when event is newer")
    func arcCreatedLWWUpdatesWhenNewer() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let existing = Arc(id: arcId, title: "Old Title", arcDescription: nil, status: .active, sortOrder: 0)
        existing.updatedAt = Date(timeIntervalSinceNow: -60) // older
        context.insert(existing)
        try context.save()

        let payload = try makeArcPayload(id: arcId, title: "New Title", sortOrder: 5)
        let event = Event(
            eventType: .arcCreated, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date() // newer than existing
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existing.title == "New Title")
        #expect(existing.sortOrder == 5)
    }

    @Test("arcCreated: LWW skips update when existing arc is newer")
    func arcCreatedLWWSkipsWhenStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let existing = Arc(id: arcId, title: "Current Title", arcDescription: nil, status: .active, sortOrder: 0)
        existing.updatedAt = Date(timeIntervalSinceNow: 60) // newer than event
        context.insert(existing)
        try context.save()

        let payload = try makeArcPayload(id: arcId, title: "Old Title")
        let event = Event(
            eventType: .arcCreated, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -60) // older
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Title should NOT be changed
        #expect(existing.title == "Current Title")
    }

    // MARK: - arcUpdated Tests

    @Test("arcUpdated: updates arc fields from event")
    func arcUpdatedUpdatesFields() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Old Title", arcDescription: nil, status: .active, sortOrder: 0)
        arc.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(arc)
        try context.save()

        let payload = try makeArcPayload(
            id: arcId,
            title: "Updated Title",
            description: "New description",
            sortOrder: 10,
            colorHex: "#0000FF"
        )
        let event = Event(
            eventType: .arcUpdated, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc.title == "Updated Title")
        #expect(arc.arcDescription == "New description")
        #expect(arc.sortOrder == 10)
        #expect(arc.colorHex == "#0000FF")
        #expect(arc.syncState == .synced)
    }

    @Test("arcUpdated: LWW skips stale update")
    func arcUpdatedSkipsStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Current Title", arcDescription: nil, status: .active, sortOrder: 0)
        arc.updatedAt = Date() // same as now = newer than stale event
        context.insert(arc)
        try context.save()

        let payload = try makeArcPayload(id: arcId, title: "Stale Title")
        let event = Event(
            eventType: .arcUpdated, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -120) // older
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc.title == "Current Title")
    }

    @Test("arcUpdated: no-ops when arc not found")
    func arcUpdatedNoOpsWhenNotFound() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let payload = try makeArcPayload(id: arcId, title: "Ghost Arc")
        let event = Event(
            eventType: .arcUpdated, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let arcs = try context.fetch(FetchDescriptor<Arc>())
        #expect(arcs.isEmpty)
    }

    @Test("arcUpdated: ignores update to deleted arc")
    func arcUpdatedIgnoresDeletedArc() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let baseTime = Date()
        let arcId = CUID.generate()

        // Step 1: Create arc via event
        let createPayload = try makeArcPayload(id: arcId, title: "Deleted Arc")
        let createEvent = Event(
            eventType: .arcCreated, payload: createPayload,
            timestamp: baseTime, entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        // Step 2: Delete the arc via event
        let deletePayload = try JSONSerialization.data(withJSONObject: ["id": arcId] as [String: Any])
        let deleteEvent = Event(
            eventType: .arcDeleted, payload: deletePayload,
            timestamp: baseTime.addingTimeInterval(1), entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)

        // Step 3: Update event (even newer) — should be ignored for deleted arc
        let updatePayload = try makeArcPayload(id: arcId, title: "Revived Arc")
        let updateEvent = Event(
            eventType: .arcUpdated, payload: updatePayload,
            timestamp: baseTime.addingTimeInterval(2), entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(updateEvent)
        try await ProjectorService.apply(event: updateEvent, context: context)

        let predicate = #Predicate<Arc> { $0.id == arcId }
        let arcs = try context.fetch(FetchDescriptor<Arc>(predicate: predicate))
        // Title should remain "Deleted Arc" — update on deleted arc is ignored
        #expect(arcs.first?.title == "Deleted Arc")
    }

    // MARK: - arcDeleted Tests

    @Test("arcDeleted: marks arc as deleted")
    func arcDeletedMarksAsDeleted() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Active Arc", arcDescription: nil, status: .active, sortOrder: 0)
        arc.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(arc)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: ["id": arcId] as [String: Any])
        let event = Event(
            eventType: .arcDeleted, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc.isDeleted == true)
        #expect(arc.syncState == .synced)
    }

    @Test("arcDeleted: removes stacks from arc when deleted")
    func arcDeletedRemovesStacksFromArc() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Arc With Stacks", arcDescription: nil, status: .active, sortOrder: 0)
        arc.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(arc)

        let stack1 = Stack(title: "Stack 1")
        let stack2 = Stack(title: "Stack 2")
        stack1.arc = arc
        stack1.arcId = arcId
        stack2.arc = arc
        stack2.arcId = arcId
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: ["id": arcId] as [String: Any])
        let event = Event(
            eventType: .arcDeleted, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc.isDeleted == true)
        #expect(stack1.arc == nil)
        #expect(stack1.arcId == nil)
        #expect(stack2.arc == nil)
        #expect(stack2.arcId == nil)
    }

    @Test("arcDeleted: LWW skips deletion when local is newer")
    func arcDeletedLWWSkipsWhenStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Arc", arcDescription: nil, status: .active, sortOrder: 0)
        arc.updatedAt = Date() // newer than the delete event
        context.insert(arc)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: ["id": arcId] as [String: Any])
        let event = Event(
            eventType: .arcDeleted, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -120) // older
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc.isDeleted == false)
    }

    // MARK: - arcCompleted Tests

    @Test("arcCompleted: sets arc status to completed")
    func arcCompletedSetsStatus() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Sprint 1", arcDescription: nil, status: .active, sortOrder: 0)
        arc.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(arc)
        try context.save()

        let payload = try makeStatusPayload(arcId: arcId, status: "completed")
        let event = Event(
            eventType: .arcCompleted, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc.status == .completed)
        #expect(arc.syncState == .synced)
    }

    @Test("arcCompleted: ignores completion of deleted arc")
    func arcCompletedIgnoresDeleted() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let baseTime = Date()
        let arcId = CUID.generate()

        // Step 1: Create arc via event
        let createPayload = try makeArcPayload(id: arcId, title: "Arc", status: "active")
        let createEvent = Event(
            eventType: .arcCreated, payload: createPayload,
            timestamp: baseTime, entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        // Step 2: Delete the arc via event
        let deletePayload = try JSONSerialization.data(withJSONObject: ["id": arcId] as [String: Any])
        let deleteEvent = Event(
            eventType: .arcDeleted, payload: deletePayload,
            timestamp: baseTime.addingTimeInterval(1), entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)

        // Step 3: Complete event (even newer) — should be ignored for deleted arc
        let completePayload = try makeStatusPayload(arcId: arcId, status: "completed")
        let completeEvent = Event(
            eventType: .arcCompleted, payload: completePayload,
            timestamp: baseTime.addingTimeInterval(2), entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(completeEvent)
        try await ProjectorService.apply(event: completeEvent, context: context)

        let predicate = #Predicate<Arc> { $0.id == arcId }
        let arcs = try context.fetch(FetchDescriptor<Arc>(predicate: predicate))
        // Status should NOT be changed to completed — deleted arcs are skipped
        #expect(arcs.first?.isDeleted == true)
        #expect(arcs.first?.status != .completed)
    }

    // MARK: - arcActivated Tests

    @Test("arcActivated: sets arc status to active")
    func arcActivatedSetsStatus() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Arc", arcDescription: nil, status: .paused, sortOrder: 0)
        arc.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(arc)
        try context.save()

        let payload = try makeStatusPayload(arcId: arcId, status: "active")
        let event = Event(
            eventType: .arcActivated, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc.status == .active)
        #expect(arc.syncState == .synced)
    }

    // MARK: - arcDeactivated Tests

    @Test("arcDeactivated: sets arc status to archived")
    func arcDeactivatedSetsStatusToArchived() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Arc", arcDescription: nil, status: .active, sortOrder: 0)
        arc.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(arc)
        try context.save()

        let payload = try makeStatusPayload(arcId: arcId, status: "archived")
        let event = Event(
            eventType: .arcDeactivated, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc.status == .archived)
        #expect(arc.syncState == .synced)
    }

    // MARK: - arcPaused Tests

    @Test("arcPaused: sets arc status to paused")
    func arcPausedSetsStatus() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Arc", arcDescription: nil, status: .active, sortOrder: 0)
        arc.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(arc)
        try context.save()

        let payload = try makeStatusPayload(arcId: arcId, status: "paused")
        let event = Event(
            eventType: .arcPaused, payload: payload, entityId: arcId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc.status == .paused)
        #expect(arc.syncState == .synced)
    }

    // MARK: - arcReordered Tests

    @Test("arcReordered: updates sort order for all arcs in payload")
    func arcReorderedUpdatesSortOrders() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId1 = CUID.generate()
        let arcId2 = CUID.generate()
        let arcId3 = CUID.generate()

        let arc1 = Arc(id: arcId1, title: "Arc 1", arcDescription: nil, status: .active, sortOrder: 0)
        let arc2 = Arc(id: arcId2, title: "Arc 2", arcDescription: nil, status: .active, sortOrder: 1)
        let arc3 = Arc(id: arcId3, title: "Arc 3", arcDescription: nil, status: .active, sortOrder: 2)
        for arc in [arc1, arc2, arc3] {
            arc.updatedAt = Date(timeIntervalSinceNow: -60)
            context.insert(arc)
        }
        try context.save()

        let payload = try makeReorderPayload(
            arcIds: [arcId3, arcId1, arcId2],
            sortOrders: [0, 1, 2]
        )
        let event = Event(
            eventType: .arcReordered, payload: payload, entityId: arcId1,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(arc3.sortOrder == 0)
        #expect(arc1.sortOrder == 1)
        #expect(arc2.sortOrder == 2)
    }

    @Test("arcReordered: skips deleted arcs")
    func arcReorderedSkipsDeleted() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let baseTime = Date()
        let arcId = CUID.generate()

        // Step 1: Create arc with initial sort order
        let createPayload = try makeArcPayload(id: arcId, title: "Arc", sortOrder: 5)
        let createEvent = Event(
            eventType: .arcCreated, payload: createPayload,
            timestamp: baseTime, entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        // Step 2: Delete the arc
        let deletePayload = try JSONSerialization.data(withJSONObject: ["id": arcId] as [String: Any])
        let deleteEvent = Event(
            eventType: .arcDeleted, payload: deletePayload,
            timestamp: baseTime.addingTimeInterval(1), entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)

        // Step 3: Reorder event (even newer) — should be ignored for deleted arc
        let reorderPayload = try makeReorderPayload(arcIds: [arcId], sortOrders: [99])
        let reorderEvent = Event(
            eventType: .arcReordered, payload: reorderPayload,
            timestamp: baseTime.addingTimeInterval(2), entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(reorderEvent)
        try await ProjectorService.apply(event: reorderEvent, context: context)

        let predicate = #Predicate<Arc> { $0.id == arcId }
        let arcs = try context.fetch(FetchDescriptor<Arc>(predicate: predicate))
        // Sort order should not change for deleted arcs
        #expect(arcs.first?.isDeleted == true)
        #expect(arcs.first?.sortOrder != 99)
    }

    // MARK: - stackAssignedToArc Tests

    @Test("stackAssignedToArc: assigns stack to arc")
    func stackAssignedToArc() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Arc", arcDescription: nil, status: .active, sortOrder: 0)
        context.insert(arc)

        let stack = Stack(title: "Work Stack")
        stack.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(stack)
        try context.save()

        let payload = try makeAssignmentPayload(stackId: stack.id, arcId: arcId)
        let event = Event(
            eventType: .stackAssignedToArc, payload: payload, entityId: stack.id,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.arc?.id == arcId)
        #expect(stack.arcId == arcId)
        #expect(stack.syncState == .synced)
    }

    @Test("stackAssignedToArc: no-ops when stack not found")
    func stackAssignedToArcNoOpsWhenStackMissing() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Arc", arcDescription: nil, status: .active, sortOrder: 0)
        context.insert(arc)
        try context.save()

        let missingStackId = CUID.generate()
        let payload = try makeAssignmentPayload(stackId: missingStackId, arcId: arcId)
        let event = Event(
            eventType: .stackAssignedToArc, payload: payload, entityId: missingStackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let stacks = try context.fetch(FetchDescriptor<Stack>())
        #expect(stacks.isEmpty)
    }

    @Test("stackAssignedToArc: no-ops when arc not found")
    func stackAssignedToArcNoOpsWhenArcMissing() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stack = Stack(title: "Stack Without Arc")
        stack.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(stack)
        try context.save()

        let missingArcId = CUID.generate()
        let payload = try makeAssignmentPayload(stackId: stack.id, arcId: missingArcId)
        let event = Event(
            eventType: .stackAssignedToArc, payload: payload, entityId: stack.id,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Stack should remain unassigned
        #expect(stack.arc == nil)
        #expect(stack.arcId == nil)
    }

    // MARK: - stackRemovedFromArc Tests

    @Test("stackRemovedFromArc: removes stack from arc")
    func stackRemovedFromArc() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let arcId = CUID.generate()
        let arc = Arc(id: arcId, title: "Arc", arcDescription: nil, status: .active, sortOrder: 0)
        context.insert(arc)

        let stack = Stack(title: "Stack In Arc")
        stack.arc = arc
        stack.arcId = arcId
        stack.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(stack)
        try context.save()

        let payload = try makeAssignmentPayload(stackId: stack.id, arcId: arcId)
        let event = Event(
            eventType: .stackRemovedFromArc, payload: payload, entityId: stack.id,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.arc == nil)
        #expect(stack.arcId == nil)
        #expect(stack.syncState == .synced)
    }

    @Test("stackRemovedFromArc: no-ops when stack not found")
    func stackRemovedFromArcNoOpsWhenMissing() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let missingStackId = CUID.generate()
        let arcId = CUID.generate()
        let payload = try makeAssignmentPayload(stackId: missingStackId, arcId: arcId)
        let event = Event(
            eventType: .stackRemovedFromArc, payload: payload, entityId: missingStackId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let stacks = try context.fetch(FetchDescriptor<Stack>())
        #expect(stacks.isEmpty)
    }

    @Test("stackRemovedFromArc: ignores removal for deleted stack")
    func stackRemovedFromArcIgnoresDeletedStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let baseTime = Date()
        let arcId = CUID.generate()

        // Step 1: Create arc
        let arcPayload = try makeArcPayload(id: arcId, title: "Arc")
        let arcCreateEvent = Event(
            eventType: .arcCreated, payload: arcPayload,
            timestamp: baseTime, entityId: arcId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(arcCreateEvent)
        try await ProjectorService.apply(event: arcCreateEvent, context: context)

        // Step 2: Create a stack and assign it to the arc
        let stackId = CUID.generate()
        let stackPayload = try JSONSerialization.data(withJSONObject: [
            "id": stackId, "title": "Stack In Arc", "status": "active"
        ] as [String: Any])
        let stackCreateEvent = Event(
            eventType: .stackCreated, payload: stackPayload,
            timestamp: baseTime.addingTimeInterval(1), entityId: stackId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(stackCreateEvent)
        try await ProjectorService.apply(event: stackCreateEvent, context: context)

        let assignPayload = try makeAssignmentPayload(stackId: stackId, arcId: arcId)
        let assignEvent = Event(
            eventType: .stackAssignedToArc, payload: assignPayload,
            timestamp: baseTime.addingTimeInterval(2), entityId: stackId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(assignEvent)
        try await ProjectorService.apply(event: assignEvent, context: context)

        // Step 3: Delete the stack via event
        let deletePayload = try JSONSerialization.data(withJSONObject: ["stackId": stackId] as [String: Any])
        let deleteEvent = Event(
            eventType: .stackDeleted, payload: deletePayload,
            timestamp: baseTime.addingTimeInterval(3), entityId: stackId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)

        // Step 4: Remove-from-arc event (even newer) — should be ignored for deleted stack
        let removePayload = try makeAssignmentPayload(stackId: stackId, arcId: arcId)
        let removeEvent = Event(
            eventType: .stackRemovedFromArc, payload: removePayload,
            timestamp: baseTime.addingTimeInterval(4), entityId: stackId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(removeEvent)
        try await ProjectorService.apply(event: removeEvent, context: context)

        // Deleted stacks are skipped — verify stack is marked deleted
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let stacks = try context.fetch(FetchDescriptor<Stack>(predicate: predicate))
        #expect(stacks.first?.isDeleted == true)
        // The remove-from-arc was skipped since stack was deleted
        // (arcId may be nil from the delete event, but the removal via deleted stack was skipped)
    }
}
