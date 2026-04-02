//
//  ProjectorServiceTagTests.swift
//  DequeueTests
//
//  Tests for ProjectorService tag event projection:
//  tagCreated, tagUpdated, tagDeleted
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ProjectorService Tag Events", .serialized)
@MainActor
struct ProjectorServiceTagTests {
    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            SyncConflict.self, Dequeue.Tag.self, Device.self, Arc.self, Attachment.self,
            configurations: config
        )
    }

    private func makeTagPayload(
        id: String,
        name: String = "Test Tag",
        colorHex: String? = "#FF5500",
        createdAt: Date? = nil,
        deleted: Bool = false
    ) throws -> Data {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "normalizedName": name.lowercased().trimmingCharacters(in: .whitespaces),
            "deleted": deleted
        ]
        if let colorHex { dict["colorHex"] = colorHex }
        if let createdAt {
            dict["createdAt"] = Int64(createdAt.timeIntervalSince1970 * 1_000)
        }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func makeDeletePayload(tagId: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tagId": tagId] as [String: Any])
    }

    // MARK: - tagCreated Tests

    @Test("tagCreated: creates tag with correct fields from event")
    func createsTagFromEvent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tagId = CUID.generate()
        let payload = try makeTagPayload(id: tagId, name: "Work", colorHex: "#3399FF")

        let event = Event(
            eventType: .tagCreated, payload: payload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Tag> { $0.id == tagId }
        let tags = try context.fetch(FetchDescriptor<Dequeue.Tag>(predicate: predicate))
        #expect(tags.count == 1)
        let tag = try #require(tags.first)
        #expect(tag.name == "Work")
        #expect(tag.colorHex == "#3399FF")
        #expect(tag.isDeleted == false)
        #expect(tag.syncState == .synced)
    }

    @Test("tagCreated: creates tag without colorHex when not provided")
    func createsTagWithoutColor() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tagId = CUID.generate()
        let payload = try makeTagPayload(id: tagId, name: "No Color", colorHex: nil)

        let event = Event(
            eventType: .tagCreated, payload: payload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Tag> { $0.id == tagId }
        let tags = try context.fetch(FetchDescriptor<Dequeue.Tag>(predicate: predicate))
        let tag = try #require(tags.first)
        #expect(tag.colorHex == nil)
    }

    @Test("tagCreated: uses payload createdAt timestamp when provided")
    func usesPayloadCreatedAt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tagId = CUID.generate()
        let originalCreatedAt = Date(timeIntervalSinceNow: -3_600) // 1 hour ago
        let payload = try makeTagPayload(id: tagId, name: "Tagged", createdAt: originalCreatedAt)

        let event = Event(
            eventType: .tagCreated, payload: payload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Tag> { $0.id == tagId }
        let tags = try context.fetch(FetchDescriptor<Dequeue.Tag>(predicate: predicate))
        let tag = try #require(tags.first)
        // createdAt should be set from the payload (within 1 second tolerance for ms rounding)
        let drift = abs(tag.createdAt.timeIntervalSince(originalCreatedAt))
        #expect(drift < 1.0, "Expected createdAt to match payload; drift was \(drift)s")
    }

    @Test("tagCreated: LWW updates existing tag when event is newer")
    func tagCreatedLWWUpdatesWhenNewer() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tagId = CUID.generate()
        let existing = Dequeue.Tag(id: tagId, name: "Old Name", colorHex: nil, syncState: .synced)
        existing.updatedAt = Date(timeIntervalSinceNow: -60) // older
        context.insert(existing)
        try context.save()

        let payload = try makeTagPayload(id: tagId, name: "New Name", colorHex: "#AABBCC")
        let event = Event(
            eventType: .tagCreated, payload: payload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date() // newer than existing
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existing.name == "New Name")
        #expect(existing.colorHex == "#AABBCC")
    }

    @Test("tagCreated: LWW skips update when existing tag is newer")
    func tagCreatedLWWSkipsWhenStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tagId = CUID.generate()
        let existing = Dequeue.Tag(id: tagId, name: "Current Name", colorHex: "#111111", syncState: .synced)
        existing.updatedAt = Date(timeIntervalSinceNow: 60) // newer than event
        context.insert(existing)
        try context.save()

        let payload = try makeTagPayload(id: tagId, name: "Stale Name", colorHex: "#999999")
        let event = Event(
            eventType: .tagCreated, payload: payload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -60) // older
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existing.name == "Current Name")
        #expect(existing.colorHex == "#111111")
    }

    // MARK: - tagUpdated Tests

    @Test("tagUpdated: updates tag name and colorHex")
    func updatesTagFields() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tagId = CUID.generate()
        let tag = Dequeue.Tag(id: tagId, name: "Original", colorHex: "#000000", syncState: .synced)
        tag.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(tag)
        try context.save()

        let payload = try makeTagPayload(id: tagId, name: "Updated", colorHex: "#FF0000")
        let event = Event(
            eventType: .tagUpdated, payload: payload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date() // newer
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(tag.name == "Updated")
        #expect(tag.colorHex == "#FF0000")
        #expect(tag.syncState == .synced)
    }

    @Test("tagUpdated: LWW skips stale update")
    func tagUpdatedSkipsStaleUpdate() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tagId = CUID.generate()
        let tag = Dequeue.Tag(id: tagId, name: "Current", colorHex: "#FFFFFF", syncState: .synced)
        tag.updatedAt = Date(timeIntervalSinceNow: 60) // newer than event
        context.insert(tag)
        try context.save()

        let payload = try makeTagPayload(id: tagId, name: "Stale", colorHex: "#000000")
        let event = Event(
            eventType: .tagUpdated, payload: payload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -60) // older
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(tag.name == "Current")
        #expect(tag.colorHex == "#FFFFFF")
    }

    @Test("tagUpdated: no-op for soft-deleted tag")
    func tagUpdatedSkipsDeletedTag() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Soft-delete via tagDeleted event first
        let tagId = CUID.generate()
        let tag = Dequeue.Tag(id: tagId, name: "Deleted Tag", colorHex: nil, syncState: .synced)
        tag.updatedAt = Date(timeIntervalSinceNow: -120)
        context.insert(tag)
        try context.save()

        // Apply delete event to soft-delete
        let deletePayload = try makeDeletePayload(tagId: tagId)
        let deleteEvent = Event(
            eventType: .tagDeleted, payload: deletePayload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        deleteEvent.timestamp = Date(timeIntervalSinceNow: -60)
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)
        #expect(tag.isDeleted == true, "tagDeleted event must soft-delete the tag")

        // Now attempt an update (newer than delete, but tag is deleted)
        let updatePayload = try makeTagPayload(id: tagId, name: "Revived", colorHex: "#ABCDEF")
        let updateEvent = Event(
            eventType: .tagUpdated, payload: updatePayload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        updateEvent.timestamp = Date() // newer than delete
        context.insert(updateEvent)
        try await ProjectorService.apply(event: updateEvent, context: context)

        // Name must NOT change — deleted tags are skipped
        #expect(tag.name == "Deleted Tag",
            "tagUpdated must not revive a soft-deleted tag")
    }

    @Test("tagUpdated: no-op when tag does not exist")
    func tagUpdatedMissingTagIsNoOp() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let payload = try makeTagPayload(id: "ghost-tag-id", name: "Ghost")
        let event = Event(
            eventType: .tagUpdated, payload: payload, entityId: "ghost-tag-id",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Must not throw
        try await ProjectorService.apply(event: event, context: context)

        let tags = try context.fetch(FetchDescriptor<Dequeue.Tag>())
        #expect(tags.isEmpty)
    }

    // MARK: - tagDeleted Tests

    @Test("tagDeleted: soft-deletes tag and updates timestamp")
    func softDeletesTag() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tagId = CUID.generate()
        let tag = Dequeue.Tag(id: tagId, name: "To Delete", colorHex: "#123456", syncState: .synced)
        tag.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(tag)
        try context.save()

        #expect(tag.isDeleted == false)

        let deletePayload = try makeDeletePayload(tagId: tagId)
        let event = Event(
            eventType: .tagDeleted, payload: deletePayload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(tag.isDeleted == true)
        #expect(tag.syncState == .synced)
        // updatedAt should be set to the event timestamp (within 1s)
        let drift = abs(tag.updatedAt.timeIntervalSince(event.timestamp))
        #expect(drift < 1.0, "updatedAt should match event timestamp; drift was \(drift)s")
    }

    @Test("tagDeleted: LWW skips stale delete")
    func tagDeletedSkipsStaleDelete() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let tagId = CUID.generate()
        let tag = Dequeue.Tag(id: tagId, name: "Live Tag", colorHex: nil, syncState: .synced)
        tag.updatedAt = Date(timeIntervalSinceNow: 60) // newer than event
        context.insert(tag)
        try context.save()

        let deletePayload = try makeDeletePayload(tagId: tagId)
        let event = Event(
            eventType: .tagDeleted, payload: deletePayload, entityId: tagId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -60) // older
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(tag.isDeleted == false, "Stale delete should not soft-delete the tag")
    }

    @Test("tagDeleted: no-op when tag does not exist")
    func tagDeletedMissingTagIsNoOp() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let deletePayload = try makeDeletePayload(tagId: "ghost-tag-del")
        let event = Event(
            eventType: .tagDeleted, payload: deletePayload, entityId: "ghost-tag-del",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Must not throw
        try await ProjectorService.apply(event: event, context: context)

        let tags = try context.fetch(FetchDescriptor<Dequeue.Tag>())
        #expect(tags.isEmpty)
    }
}
