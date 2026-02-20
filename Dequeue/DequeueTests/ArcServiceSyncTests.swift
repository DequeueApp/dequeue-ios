//
//  ArcServiceSyncTests.swift
//  DequeueTests
//
//  Tests for ArcService+Sync — upsertFromSync and fetchByIdIncludingDeleted
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Arc.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Attachment.self,
        Device.self,
        Tag.self,
        SyncConflict.self,
        configurations: config
    )
}

@Suite("ArcService Sync Operations", .serialized)
@MainActor
struct ArcServiceSyncTests {

    // MARK: - upsertFromSync Tests

    @Test("upsertFromSync creates new arc when none exists")
    func createsNewArc() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ArcService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let now = Date()
        let arc = try service.upsertFromSync(
            id: "arc-sync-1",
            title: "Synced Arc",
            description: "From server",
            status: .active,
            sortOrder: 0,
            colorHex: "FF0000",
            startTime: now,
            dueTime: now.addingTimeInterval(86_400),
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            userId: "user-1",
            revision: 5,
            serverId: "server-arc-1"
        )

        #expect(arc.id == "arc-sync-1")
        #expect(arc.title == "Synced Arc")
        #expect(arc.arcDescription == "From server")
        #expect(arc.status == .active)
        #expect(arc.sortOrder == 0)
        #expect(arc.colorHex == "FF0000")
        #expect(arc.startTime == now)
        #expect(arc.isDeleted == false)
        #expect(arc.userId == "user-1")
        #expect(arc.revision == 5)
        #expect(arc.serverId == "server-arc-1")
    }

    @Test("upsertFromSync updates existing arc")
    func updatesExistingArc() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ArcService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let now = Date()

        // Create initial arc via sync
        _ = try service.upsertFromSync(
            id: "arc-sync-2",
            title: "Original",
            description: nil,
            status: .active,
            sortOrder: 0,
            colorHex: nil,
            startTime: nil,
            dueTime: nil,
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            userId: "user-1",
            revision: 1,
            serverId: "server-2"
        )

        // Update via sync
        let updated = try service.upsertFromSync(
            id: "arc-sync-2",
            title: "Updated Title",
            description: "Now has a description",
            status: .paused,
            sortOrder: 3,
            colorHex: "00FF00",
            startTime: now,
            dueTime: now.addingTimeInterval(86_400 * 7),
            createdAt: now,
            updatedAt: now.addingTimeInterval(3600),
            isDeleted: false,
            userId: "user-1",
            revision: 2,
            serverId: "server-2"
        )

        #expect(updated.title == "Updated Title")
        #expect(updated.arcDescription == "Now has a description")
        #expect(updated.status == .paused)
        #expect(updated.sortOrder == 3)
        #expect(updated.colorHex == "00FF00")
        #expect(updated.revision == 2)
    }

    @Test("upsertFromSync handles deleted arcs by updating revision and updatedAt")
    func handlesDeletedArcs() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ArcService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let now = Date()

        // Create arc then sync deletion
        let created = try service.upsertFromSync(
            id: "arc-sync-3",
            title: "Soon Deleted",
            description: nil,
            status: .active,
            sortOrder: 0,
            colorHex: nil,
            startTime: nil,
            dueTime: nil,
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            userId: "user-1",
            revision: 1,
            serverId: "server-3"
        )

        let laterDate = now.addingTimeInterval(60)
        let deleted = try service.upsertFromSync(
            id: "arc-sync-3",
            title: "Soon Deleted",
            description: nil,
            status: .active,
            sortOrder: 0,
            colorHex: nil,
            startTime: nil,
            dueTime: nil,
            createdAt: now,
            updatedAt: laterDate,
            isDeleted: true,
            userId: "user-1",
            revision: 2,
            serverId: "server-3"
        )

        // Verify the returned arc is the same object (updated, not recreated)
        #expect(deleted.id == created.id)
        #expect(deleted.revision == 2)
        #expect(deleted.updatedAt == laterDate)
        #expect(deleted.syncState == .synced)

        // Verify isDeleted by re-fetching with predicate that checks stored value
        let arcId = "arc-sync-3"
        let descriptor = FetchDescriptor<Arc>(
            predicate: #Predicate<Arc> { $0.id == arcId && $0.isDeleted == true }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
    }

    @Test("upsertFromSync sets syncState to synced")
    func setsSyncStateToSynced() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ArcService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let now = Date()
        let arc = try service.upsertFromSync(
            id: "arc-sync-4",
            title: "Synced",
            description: nil,
            status: .active,
            sortOrder: 0,
            colorHex: nil,
            startTime: nil,
            dueTime: nil,
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            userId: "user-1",
            revision: 1,
            serverId: "server-4"
        )

        #expect(arc.syncState == .synced)
        #expect(arc.lastSyncedAt != nil)
    }

    @Test("upsertFromSync sets synced on updated existing arc")
    func setsSyncedOnUpdate() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ArcService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Pre-create an arc with pending sync
        let arc = Arc(id: "arc-sync-5", title: "Local", syncState: .pending)
        context.insert(arc)
        try context.save()

        #expect(arc.syncState == .pending)

        let now = Date()
        let updated = try service.upsertFromSync(
            id: "arc-sync-5",
            title: "From Server",
            description: nil,
            status: .active,
            sortOrder: 0,
            colorHex: nil,
            startTime: nil,
            dueTime: nil,
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            userId: "user-1",
            revision: 3,
            serverId: "server-5"
        )

        #expect(updated.syncState == .synced)
        #expect(updated.lastSyncedAt != nil)
    }

    // MARK: - fetchByIdIncludingDeleted Tests

    @Test("fetchByIdIncludingDeleted finds soft-deleted arcs")
    func findsDeletedArcs() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ArcService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Create arc normally, then soft-delete it
        let arc = Arc(id: "deleted-arc-1", title: "Deleted Arc")
        context.insert(arc)
        try context.save()

        arc.isDeleted = true
        try context.save()

        let found = try service.fetchByIdIncludingDeleted("deleted-arc-1")

        #expect(found != nil)
        #expect(found?.id == "deleted-arc-1")

        // Verify the soft-delete flag via predicate to avoid PersistentModel.isDeleted ambiguity
        let arcId = "deleted-arc-1"
        let descriptor = FetchDescriptor<Arc>(
            predicate: #Predicate<Arc> { $0.id == arcId && $0.isDeleted == true }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
    }

    @Test("fetchByIdIncludingDeleted finds non-deleted arcs")
    func findsNonDeletedArcs() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ArcService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let arc = Arc(id: "active-arc-1", title: "Active Arc", isDeleted: false)
        context.insert(arc)
        try context.save()

        let found = try service.fetchByIdIncludingDeleted("active-arc-1")

        #expect(found != nil)
        #expect(found?.id == "active-arc-1")
        #expect(found?.isDeleted == false)
    }

    @Test("fetchByIdIncludingDeleted returns nil for missing id")
    func returnsNilForMissingId() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = ArcService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let found = try service.fetchByIdIncludingDeleted("nonexistent-id")

        #expect(found == nil)
    }
}
