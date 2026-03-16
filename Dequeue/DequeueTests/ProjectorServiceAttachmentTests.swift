//
//  ProjectorServiceAttachmentTests.swift
//  DequeueTests
//
//  Tests for ProjectorService attachment event projection:
//  attachmentAdded, attachmentRemoved
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ProjectorService Attachment Events", .serialized)
@MainActor
struct ProjectorServiceAttachmentTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            SyncConflict.self, Dequeue.Tag.self, Device.self, Arc.self, Attachment.self,
            configurations: config
        )
    }

    private func makeAttachmentPayload(
        id: String,
        parentId: String = "parent-stack-id",
        parentType: String = "stack",
        filename: String = "photo.jpg",
        mimeType: String = "image/jpeg",
        sizeBytes: Int64 = 204_800,
        url: String? = "https://cdn.example.com/attachments/photo.jpg",
        createdAt: Date? = nil,
        deleted: Bool = false
    ) throws -> Data {
        var dict: [String: Any] = [
            "id": id,
            "parentId": parentId,
            "parentType": parentType,
            "filename": filename,
            "mimeType": mimeType,
            "sizeBytes": sizeBytes,
            "deleted": deleted
        ]
        if let url { dict["url"] = url }
        if let createdAt {
            dict["createdAt"] = Int64(createdAt.timeIntervalSince1970 * 1_000)
        }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func makeRemovePayload(attachmentId: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["attachmentId": attachmentId] as [String: Any])
    }

    // MARK: - attachmentAdded: New Attachment Tests

    @Test("attachmentAdded: creates attachment with correct fields from event")
    func createsAttachmentFromEvent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let parentId = CUID.generate()
        let payload = try makeAttachmentPayload(
            id: attachmentId,
            parentId: parentId,
            parentType: "stack",
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 512_000,
            url: "https://cdn.example.com/document.pdf"
        )

        let event = Event(
            eventType: .attachmentAdded, payload: payload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Attachment> { $0.id == attachmentId }
        let attachments = try context.fetch(FetchDescriptor<Dequeue.Attachment>(predicate: predicate))
        #expect(attachments.count == 1)
        let attachment = try #require(attachments.first)
        #expect(attachment.filename == "document.pdf")
        #expect(attachment.mimeType == "application/pdf")
        #expect(attachment.sizeBytes == 512_000)
        #expect(attachment.parentId == parentId)
        #expect(attachment.parentType == .stack)
        #expect(attachment.remoteUrl == "https://cdn.example.com/document.pdf")
        #expect(attachment.isDeleted == false)
        #expect(attachment.syncState == .synced)
    }

    @Test("attachmentAdded: sets uploadState to completed when URL is provided")
    func setsUploadStateCompletedWithUrl() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let payload = try makeAttachmentPayload(
            id: attachmentId,
            url: "https://cdn.example.com/file.png"
        )

        let event = Event(
            eventType: .attachmentAdded, payload: payload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Attachment> { $0.id == attachmentId }
        let attachments = try context.fetch(FetchDescriptor<Dequeue.Attachment>(predicate: predicate))
        let attachment = try #require(attachments.first)
        #expect(attachment.uploadState == .completed)
    }

    @Test("attachmentAdded: sets uploadState to pending when URL is nil")
    func setsUploadStatePendingWithoutUrl() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let payload = try makeAttachmentPayload(
            id: attachmentId,
            url: nil
        )

        let event = Event(
            eventType: .attachmentAdded, payload: payload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Attachment> { $0.id == attachmentId }
        let attachments = try context.fetch(FetchDescriptor<Dequeue.Attachment>(predicate: predicate))
        let attachment = try #require(attachments.first)
        #expect(attachment.uploadState == .pending)
        #expect(attachment.remoteUrl == nil)
    }

    @Test("attachmentAdded: localPath is nil on creation (download-on-demand)")
    func localPathIsNilOnCreation() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let payload = try makeAttachmentPayload(id: attachmentId)

        let event = Event(
            eventType: .attachmentAdded, payload: payload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Attachment> { $0.id == attachmentId }
        let attachments = try context.fetch(FetchDescriptor<Dequeue.Attachment>(predicate: predicate))
        let attachment = try #require(attachments.first)
        #expect(attachment.localPath == nil,
            "Synced attachments must have nil localPath; they are downloaded on demand")
    }

    @Test("attachmentAdded: uses payload createdAt timestamp when provided")
    func usesPayloadCreatedAt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let originalCreatedAt = Date(timeIntervalSinceNow: -7200) // 2 hours ago
        let payload = try makeAttachmentPayload(
            id: attachmentId,
            createdAt: originalCreatedAt
        )

        let event = Event(
            eventType: .attachmentAdded, payload: payload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Attachment> { $0.id == attachmentId }
        let attachments = try context.fetch(FetchDescriptor<Dequeue.Attachment>(predicate: predicate))
        let attachment = try #require(attachments.first)
        let drift = abs(attachment.createdAt.timeIntervalSince(originalCreatedAt))
        #expect(drift < 1.0, "Expected createdAt from payload; drift was \(drift)s")
    }

    @Test("attachmentAdded: falls back to event timestamp when createdAt not in payload")
    func fallsBackToEventTimestampForCreatedAt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let payload = try makeAttachmentPayload(id: attachmentId, createdAt: nil)

        let eventTimestamp = Date(timeIntervalSinceNow: -300)
        let event = Event(
            eventType: .attachmentAdded, payload: payload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = eventTimestamp
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Attachment> { $0.id == attachmentId }
        let attachments = try context.fetch(FetchDescriptor<Dequeue.Attachment>(predicate: predicate))
        let attachment = try #require(attachments.first)
        let drift = abs(attachment.createdAt.timeIntervalSince(eventTimestamp))
        #expect(drift < 1.0, "Expected createdAt to fall back to event.timestamp; drift was \(drift)s")
    }

    @Test("attachmentAdded: respects deleted flag from payload")
    func respectsDeletedFlagFromPayload() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let payload = try makeAttachmentPayload(id: attachmentId, deleted: true)

        let event = Event(
            eventType: .attachmentAdded, payload: payload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Dequeue.Attachment> { $0.id == attachmentId }
        let attachments = try context.fetch(FetchDescriptor<Dequeue.Attachment>(predicate: predicate))
        let attachment = try #require(attachments.first)
        #expect(attachment.isDeleted == true)
    }

    // MARK: - attachmentAdded: LWW Update Tests

    @Test("attachmentAdded: LWW updates existing attachment when event is newer")
    func attachmentAddedLWWUpdatesWhenNewer() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let existing = Dequeue.Attachment(
            id: attachmentId,
            parentId: "old-parent",
            parentType: .stack,
            filename: "old-name.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 100,
            syncState: .synced
        )
        existing.updatedAt = Date(timeIntervalSinceNow: -120) // older than event
        context.insert(existing)
        try context.save()

        let payload = try makeAttachmentPayload(
            id: attachmentId,
            filename: "new-name.jpg",
            mimeType: "image/png",
            sizeBytes: 999,
            url: "https://cdn.example.com/new-name.jpg"
        )
        let event = Event(
            eventType: .attachmentAdded, payload: payload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date() // newer
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existing.filename == "new-name.jpg")
        #expect(existing.mimeType == "image/png")
        #expect(existing.sizeBytes == 999)
        #expect(existing.remoteUrl == "https://cdn.example.com/new-name.jpg")
        #expect(existing.uploadState == .completed)
        #expect(existing.syncState == .synced)
    }

    @Test("attachmentAdded: LWW skips update when existing attachment is newer")
    func attachmentAddedLWWSkipsWhenStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let existing = Dequeue.Attachment(
            id: attachmentId,
            parentId: "current-parent",
            parentType: .stack,
            filename: "current-file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 500,
            syncState: .synced
        )
        existing.updatedAt = Date(timeIntervalSinceNow: 60) // newer than event
        context.insert(existing)
        try context.save()

        let payload = try makeAttachmentPayload(
            id: attachmentId,
            filename: "stale-file.pdf",
            sizeBytes: 1
        )
        let event = Event(
            eventType: .attachmentAdded, payload: payload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -60) // older
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existing.filename == "current-file.pdf",
            "LWW: stale event must not overwrite newer local state")
        #expect(existing.sizeBytes == 500)
    }

    @Test("attachmentAdded: skips update for soft-deleted attachment")
    func attachmentAddedSkipsDeletedAttachment() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()

        // Insert with a URL so it has .completed upload state
        let createPayload = try makeAttachmentPayload(
            id: attachmentId,
            filename: "deleted-file.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 200
        )
        let createEvent = Event(
            eventType: .attachmentAdded, payload: createPayload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        createEvent.timestamp = Date(timeIntervalSinceNow: -120)
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        // Soft-delete via attachmentRemoved event
        let removePayload = try makeRemovePayload(attachmentId: attachmentId)
        let removeEvent = Event(
            eventType: .attachmentRemoved, payload: removePayload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        removeEvent.timestamp = Date(timeIntervalSinceNow: -60)
        context.insert(removeEvent)
        try await ProjectorService.apply(event: removeEvent, context: context)

        // Confirm soft-delete applied
        let predicate = #Predicate<Dequeue.Attachment> { $0.id == attachmentId }
        let afterRemove = try context.fetch(FetchDescriptor<Dequeue.Attachment>(predicate: predicate))
        let existing = try #require(afterRemove.first)
        #expect(existing.isDeleted == true, "attachmentRemoved event must soft-delete the attachment")

        // Now attempt an attachmentAdded update (newer than remove event)
        let updatePayload = try makeAttachmentPayload(
            id: attachmentId,
            filename: "revived-file.jpg",
            sizeBytes: 999
        )
        let updateEvent = Event(
            eventType: .attachmentAdded, payload: updatePayload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        updateEvent.timestamp = Date() // newer than removeEvent
        context.insert(updateEvent)
        try await ProjectorService.apply(event: updateEvent, context: context)

        #expect(existing.filename == "deleted-file.jpg",
            "attachmentAdded must not update a soft-deleted attachment")
        #expect(existing.isDeleted == true)
    }

    // MARK: - attachmentRemoved Tests

    @Test("attachmentRemoved: soft-deletes attachment and updates timestamps")
    func softDeletesAttachment() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let attachment = Attachment(
            id: attachmentId,
            parentId: "parent",
            parentType: .stack,
            filename: "to-delete.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 300,
            syncState: .synced
        )
        attachment.updatedAt = Date(timeIntervalSinceNow: -60)
        context.insert(attachment)
        try context.save()

        #expect(attachment.isDeleted == false)

        let removePayload = try makeRemovePayload(attachmentId: attachmentId)
        let event = Event(
            eventType: .attachmentRemoved, payload: removePayload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(attachment.isDeleted == true)
        #expect(attachment.syncState == .synced)
        let drift = abs(attachment.updatedAt.timeIntervalSince(event.timestamp))
        #expect(drift < 1.0, "updatedAt should match event timestamp; drift was \(drift)s")
    }

    @Test("attachmentRemoved: LWW skips stale delete")
    func attachmentRemovedSkipsStaleDelete() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let attachmentId = CUID.generate()
        let attachment = Attachment(
            id: attachmentId,
            parentId: "parent",
            parentType: .stack,
            filename: "live-file.png",
            mimeType: "image/png",
            sizeBytes: 400,
            syncState: .synced
        )
        attachment.updatedAt = Date(timeIntervalSinceNow: 60) // newer than event
        context.insert(attachment)
        try context.save()

        let removePayload = try makeRemovePayload(attachmentId: attachmentId)
        let event = Event(
            eventType: .attachmentRemoved, payload: removePayload, entityId: attachmentId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -60) // older than attachment
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(attachment.isDeleted == false,
            "LWW: stale remove event must not soft-delete a newer attachment")
    }

    @Test("attachmentRemoved: no-op when attachment does not exist")
    func attachmentRemovedMissingAttachmentIsNoOp() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let removePayload = try makeRemovePayload(attachmentId: "ghost-attachment-id")
        let event = Event(
            eventType: .attachmentRemoved, payload: removePayload, entityId: "ghost-attachment-id",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Must not throw
        try await ProjectorService.apply(event: event, context: context)

        let attachments = try context.fetch(FetchDescriptor<Dequeue.Attachment>())
        #expect(attachments.isEmpty)
    }
}
