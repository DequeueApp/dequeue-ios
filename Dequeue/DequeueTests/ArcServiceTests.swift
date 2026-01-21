//
//  ArcServiceTests.swift
//  DequeueTests
//
//  Tests for ArcService - Arc CRUD operations and stack management
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ArcService Tests", .serialized)
struct ArcServiceTests {
    // MARK: - Test Helpers

    /// Creates an in-memory model container for ArcService tests with unique isolation
    private static func makeTestContainer() throws -> ModelContainer {
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
    // MARK: - Create Arc Tests

    @Test("createArc creates arc with correct title")
    @MainActor
    func createArcSetsTitle() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")

        #expect(arc.title == "Test Arc")
    }

    @Test("createArc creates arc with description")
    @MainActor
    func createArcSetsDescription() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc", description: "Test description")

        #expect(arc.arcDescription == "Test description")
    }

    @Test("createArc creates arc with color")
    @MainActor
    func createArcSetsColor() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc", colorHex: "FF0000")

        #expect(arc.colorHex == "FF0000")
    }

    @Test("createArc sets initial status to active")
    @MainActor
    func createArcSetsActiveStatus() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")

        #expect(arc.status == .active)
    }

    @Test("createArc sets syncState to pending")
    @MainActor
    func createArcSetsSyncState() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")

        #expect(arc.syncState == .pending)
    }

    @Test("createArc enforces max active arcs limit")
    @MainActor
    func createArcEnforcesLimit() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        // Create 5 active arcs (the limit)
        for index in 0..<5 {
            _ = try service.createArc(title: "Arc \(index)")
        }

        // Trying to create a 6th should throw
        #expect(throws: ArcServiceError.self) {
            _ = try service.createArc(title: "Arc 6")
        }
    }

    // MARK: - Update Arc Tests

    @Test("updateArc changes title")
    @MainActor
    func updateArcChangesTitle() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Original Title")
        try service.updateArc(arc, title: "New Title")

        #expect(arc.title == "New Title")
    }

    @Test("updateArc changes description")
    @MainActor
    func updateArcChangesDescription() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc", description: "Original")
        try service.updateArc(arc, description: "Updated")

        #expect(arc.arcDescription == "Updated")
    }

    @Test("updateArc changes color")
    @MainActor
    func updateArcChangesColor() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc", colorHex: "FF0000")
        try service.updateArc(arc, colorHex: "00FF00")

        #expect(arc.colorHex == "00FF00")
    }

    // MARK: - Delete Arc Tests

    @Test("deleteArc removes stacks from arc")
    @MainActor
    func deleteArcRemovesStacks() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        try service.assignStack(stack, to: arc)
        #expect(stack.arc?.id == arc.id)

        try service.deleteArc(arc)
        #expect(stack.arc == nil)
        #expect(stack.arcId == nil)
    }

    @Test("deleteArc updates arc metadata")
    @MainActor
    func deleteArcUpdatesMetadata() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device-delete"
        )

        let arc = try service.createArc(title: "Test Arc For Delete")
        let originalUpdatedAt = arc.updatedAt
        let originalRevision = arc.revision

        try service.deleteArc(arc)

        // Verify deletion updates metadata fields
        #expect(arc.syncState == .pending)
        #expect(arc.revision > originalRevision)
        #expect(arc.updatedAt > originalUpdatedAt)
    }

    // MARK: - Status Operations Tests

    @Test("markAsCompleted sets status to completed")
    @MainActor
    func markAsCompletedSetsStatus() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")
        try service.markAsCompleted(arc)

        #expect(arc.status == .completed)
    }

    @Test("pause sets status to paused")
    @MainActor
    func pauseSetsStatus() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")
        try service.pause(arc)

        #expect(arc.status == .paused)
    }

    @Test("resume sets status to active")
    @MainActor
    func resumeSetsStatus() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")
        try service.pause(arc)
        try service.resume(arc)

        #expect(arc.status == .active)
    }

    @Test("resume from completed sets status to active")
    @MainActor
    func resumeFromCompletedSetsStatus() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")
        try service.markAsCompleted(arc)
        try service.resume(arc)

        #expect(arc.status == .active)
    }

    // MARK: - Stack Assignment Tests

    @Test("assignStack sets stack's arc property")
    @MainActor
    func assignStackSetsArcProperty() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        try service.assignStack(stack, to: arc)

        #expect(stack.arc?.id == arc.id)
        #expect(stack.arcId == arc.id)
    }

    @Test("assignStack adds stack to arc's stacks array")
    @MainActor
    func assignStackAddsToArray() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        try service.assignStack(stack, to: arc)

        #expect(arc.stacks.contains { $0.id == stack.id })
    }

    @Test("removeStack clears stack's arc property")
    @MainActor
    func removeStackClearsArcProperty() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try service.createArc(title: "Test Arc")
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        try service.assignStack(stack, to: arc)
        try service.removeStack(stack, from: arc)

        #expect(stack.arc == nil)
        #expect(stack.arcId == nil)
    }

    // MARK: - Reorder Tests

    @Test("updateSortOrders updates arc sort orders")
    @MainActor
    func updateSortOrdersChangesOrder() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc1 = try service.createArc(title: "Arc 1")
        let arc2 = try service.createArc(title: "Arc 2")
        let arc3 = try service.createArc(title: "Arc 3")

        // Reverse the order
        let reordered = [arc3, arc2, arc1]
        try service.updateSortOrders(reordered)

        #expect(arc3.sortOrder == 0)
        #expect(arc2.sortOrder == 1)
        #expect(arc1.sortOrder == 2)
    }

    @Test("updateSortOrders sets syncState to pending")
    @MainActor
    func updateSortOrdersSetsSyncState() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc1 = try service.createArc(title: "Arc 1")
        let arc2 = try service.createArc(title: "Arc 2")

        // Mark as synced first
        arc1.syncState = .synced
        arc2.syncState = .synced

        // Swap order
        let reordered = [arc2, arc1]
        try service.updateSortOrders(reordered)

        #expect(arc1.syncState == .pending)
        #expect(arc2.syncState == .pending)
    }

    // MARK: - Query Tests

    @Test("canCreateNewArc returns true when under limit")
    @MainActor
    func canCreateNewArcUnderLimit() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        _ = try service.createArc(title: "Arc 1")
        _ = try service.createArc(title: "Arc 2")

        #expect(try service.canCreateNewArc() == true)
    }

    @Test("canCreateNewArc returns false when at limit")
    @MainActor
    func canCreateNewArcAtLimit() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        for index in 0..<5 {
            _ = try service.createArc(title: "Arc \(index)")
        }

        #expect(try service.canCreateNewArc() == false)
    }

    @Test("paused arcs don't count toward limit")
    @MainActor
    func pausedArcsDontCountTowardLimit() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        // Create 5 arcs and pause 2
        for index in 0..<5 {
            let arc = try service.createArc(title: "Arc \(index)")
            if index < 2 {
                try service.pause(arc)
            }
        }

        // Should be able to create more since 2 are paused
        #expect(try service.canCreateNewArc() == true)
    }

    @Test("completed arcs don't count toward limit")
    @MainActor
    func completedArcsDontCountTowardLimit() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        // Create 5 arcs and complete 1
        for index in 0..<5 {
            let arc = try service.createArc(title: "Arc \(index)")
            if index == 0 {
                try service.markAsCompleted(arc)
            }
        }

        // Should be able to create more since 1 is completed
        #expect(try service.canCreateNewArc() == true)
    }

    // MARK: - History Revert Tests

    @Test("revertToHistoricalState restores arc to previous state")
    @MainActor
    func revertToHistoricalStateRestoresPreviousState() throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        // Create an arc with initial state
        let arc = try service.createArc(
            title: "Original Title",
            description: "Original Description",
            colorHex: "FF0000"
        )
        let arcId = arc.id

        // Fetch the creation event
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate<Event> { $0.entityId == arcId && $0.type == "arc.created" }
        )
        let events = try context.fetch(descriptor)
        guard let creationEvent = events.first else {
            Issue.record("Creation event not found")
            return
        }

        // Update the arc to a new state
        try service.updateArc(
            arc,
            title: "Modified Title",
            description: "Modified Description",
            colorHex: "00FF00"
        )

        // Verify the arc was modified
        #expect(arc.title == "Modified Title")
        #expect(arc.arcDescription == "Modified Description")
        #expect(arc.colorHex == "00FF00")

        // Revert to the historical state from the creation event
        try service.revertToHistoricalState(arc, from: creationEvent)

        // Verify the arc was reverted to original values
        #expect(arc.title == "Original Title")
        #expect(arc.arcDescription == "Original Description")
        #expect(arc.colorHex == "FF0000")
        #expect(arc.syncState == .pending) // Should be marked for sync
    }
}
