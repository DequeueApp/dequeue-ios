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
    func createArcSetsTitle() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")

        #expect(arc.title == "Test Arc")
    }

    @Test("createArc creates arc with description")
    @MainActor
    func createArcSetsDescription() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc", description: "Test description")

        #expect(arc.arcDescription == "Test description")
    }

    @Test("createArc creates arc with color")
    @MainActor
    func createArcSetsColor() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc", colorHex: "FF0000")

        #expect(arc.colorHex == "FF0000")
    }

    @Test("createArc sets initial status to active")
    @MainActor
    func createArcSetsActiveStatus() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")

        #expect(arc.status == .active)
    }

    @Test("createArc sets syncState to pending")
    @MainActor
    func createArcSetsSyncState() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")

        #expect(arc.syncState == .pending)
    }

    @Test("createArc enforces max active arcs limit")
    @MainActor
    func createArcEnforcesLimit() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        // Create 5 active arcs (the limit)
        for index in 0..<5 {
            _ = try await service.createArc(title: "Arc \(index)")
        }

        // Trying to create a 6th should throw
        await #expect(throws: ArcServiceError.self) {
            _ = try await service.createArc(title: "Arc 6")
        }
    }

    // MARK: - Update Arc Tests

    @Test("updateArc changes title")
    @MainActor
    func updateArcChangesTitle() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Original Title")
        try await service.updateArc(arc, title: "New Title")

        #expect(arc.title == "New Title")
    }

    @Test("updateArc changes description")
    @MainActor
    func updateArcChangesDescription() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc", description: "Original")
        try await service.updateArc(arc, description: "Updated")

        #expect(arc.arcDescription == "Updated")
    }

    @Test("updateArc changes color")
    @MainActor
    func updateArcChangesColor() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc", colorHex: "FF0000")
        try await service.updateArc(arc, colorHex: "00FF00")

        #expect(arc.colorHex == "00FF00")
    }

    // MARK: - Delete Arc Tests

    @Test("deleteArc removes stacks from arc")
    @MainActor
    func deleteArcRemovesStacks() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        try await service.assignStack(stack, to: arc)
        #expect(stack.arc?.id == arc.id)

        try await service.deleteArc(arc)
        #expect(stack.arc == nil)
        #expect(stack.arcId == nil)
    }

    @Test("deleteArc updates arc metadata")
    @MainActor
    func deleteArcUpdatesMetadata() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device-delete"
        )

        let arc = try await service.createArc(title: "Test Arc For Delete")
        let originalUpdatedAt = arc.updatedAt
        let originalRevision = arc.revision

        try await service.deleteArc(arc)

        // Verify deletion updates metadata fields
        #expect(arc.syncState == .pending)
        #expect(arc.revision > originalRevision)
        #expect(arc.updatedAt > originalUpdatedAt)
    }

    // MARK: - Status Operations Tests

    @Test("markAsCompleted sets status to completed")
    @MainActor
    func markAsCompletedSetsStatus() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        try await service.markAsCompleted(arc)

        #expect(arc.status == .completed)
    }

    @Test("pause sets status to paused")
    @MainActor
    func pauseSetsStatus() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        try await service.pause(arc)

        #expect(arc.status == .paused)
    }

    @Test("resume sets status to active")
    @MainActor
    func resumeSetsStatus() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        try await service.pause(arc)
        try await service.resume(arc)

        #expect(arc.status == .active)
    }

    @Test("resume from completed sets status to active")
    @MainActor
    func resumeFromCompletedSetsStatus() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        try await service.markAsCompleted(arc)
        try await service.resume(arc)

        #expect(arc.status == .active)
    }

    // MARK: - Stack Assignment Tests

    @Test("assignStack sets stack's arc property")
    @MainActor
    func assignStackSetsArcProperty() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        try await service.assignStack(stack, to: arc)

        #expect(stack.arc?.id == arc.id)
        #expect(stack.arcId == arc.id)
    }

    @Test("assignStack adds stack to arc's stacks array")
    @MainActor
    func assignStackAddsToArray() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        try await service.assignStack(stack, to: arc)

        #expect(arc.stacks.contains { $0.id == stack.id })
    }

    @Test("removeStack clears stack's arc property")
    @MainActor
    func removeStackClearsArcProperty() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        try await service.assignStack(stack, to: arc)
        try await service.removeStack(stack, from: arc)

        #expect(stack.arc == nil)
        #expect(stack.arcId == nil)
    }

    // MARK: - Reorder Tests

    @Test("updateSortOrders updates arc sort orders")
    @MainActor
    func updateSortOrdersChangesOrder() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc1 = try await service.createArc(title: "Arc 1")
        let arc2 = try await service.createArc(title: "Arc 2")
        let arc3 = try await service.createArc(title: "Arc 3")

        // Reverse the order
        let reordered = [arc3, arc2, arc1]
        try await service.updateSortOrders(reordered)

        #expect(arc3.sortOrder == 0)
        #expect(arc2.sortOrder == 1)
        #expect(arc1.sortOrder == 2)
    }

    @Test("updateSortOrders sets syncState to pending")
    @MainActor
    func updateSortOrdersSetsSyncState() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc1 = try await service.createArc(title: "Arc 1")
        let arc2 = try await service.createArc(title: "Arc 2")

        // Mark as synced first
        arc1.syncState = .synced
        arc2.syncState = .synced

        // Swap order
        let reordered = [arc2, arc1]
        try await service.updateSortOrders(reordered)

        #expect(arc1.syncState == .pending)
        #expect(arc2.syncState == .pending)
    }

    // MARK: - Query Tests

    @Test("canCreateNewArc returns true when under limit")
    @MainActor
    func canCreateNewArcUnderLimit() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        _ = try await service.createArc(title: "Arc 1")
        _ = try await service.createArc(title: "Arc 2")

        #expect(try await service.canCreateNewArc() == true)
    }

    @Test("canCreateNewArc returns false when at limit")
    @MainActor
    func canCreateNewArcAtLimit() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        for index in 0..<5 {
            _ = try await service.createArc(title: "Arc \(index)")
        }

        #expect(try await service.canCreateNewArc() == false)
    }

    @Test("paused arcs don't count toward limit")
    @MainActor
    func pausedArcsDontCountTowardLimit() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        // Create 5 arcs and pause 2
        for index in 0..<5 {
            let arc = try await service.createArc(title: "Arc \(index)")
            if index < 2 {
                try await service.pause(arc)
            }
        }

        // Should be able to create more since 2 are paused
        #expect(try await service.canCreateNewArc() == true)
    }

    @Test("completed arcs don't count toward limit")
    @MainActor
    func completedArcsDontCountTowardLimit() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        // Create 5 arcs and complete 1
        for index in 0..<5 {
            let arc = try await service.createArc(title: "Arc \(index)")
            if index == 0 {
                try await service.markAsCompleted(arc)
            }
        }

        // Should be able to create more since 1 is completed
        #expect(try await service.canCreateNewArc() == true)
    }

    // MARK: - History Revert Tests

    @Test("revertToHistoricalState restores arc to previous state")
    @MainActor
    func revertToHistoricalStateRestoresPreviousState() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        // Create an arc with initial state
        let arc = try await service.createArc(
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
        try await service.updateArc(
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
        try await service.revertToHistoricalState(arc, from: creationEvent)

        // Verify the arc was reverted to original values
        #expect(arc.title == "Original Title")
        #expect(arc.arcDescription == "Original Description")
        #expect(arc.colorHex == "FF0000")
        #expect(arc.syncState == .pending) // Should be marked for sync
    }

    // MARK: - Start and Due Date Tests

    @Test("createArc creates arc with start and due dates")
    @MainActor
    func createArcSetsStartAndDueDates() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let startDate = Date()
        let dueDate = Date().addingTimeInterval(86_400 * 7) // 7 days later

        let arc = try await service.createArc(
            title: "Test Arc",
            startTime: startDate,
            dueTime: dueDate
        )

        #expect(arc.startTime == startDate)
        #expect(arc.dueTime == dueDate)
    }

    @Test("createArc creates arc without dates by default")
    @MainActor
    func createArcWithoutDatesHasNilDates() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")

        #expect(arc.startTime == nil)
        #expect(arc.dueTime == nil)
    }

    @Test("updateArc sets start date")
    @MainActor
    func updateArcSetsStartDate() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        let startDate = Date()

        try await service.updateArc(arc, startTime: .set(startDate))

        #expect(arc.startTime == startDate)
    }

    @Test("updateArc sets due date")
    @MainActor
    func updateArcSetsDueDate() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let arc = try await service.createArc(title: "Test Arc")
        let dueDate = Date().addingTimeInterval(86_400 * 7)

        try await service.updateArc(arc, dueTime: .set(dueDate))

        #expect(arc.dueTime == dueDate)
    }

    @Test("updateArc clears start date when set to clear")
    @MainActor
    func updateArcClearsStartDate() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let startDate = Date()
        let arc = try await service.createArc(title: "Test Arc", startTime: startDate)
        #expect(arc.startTime != nil)

        try await service.updateArc(arc, startTime: .clear)

        #expect(arc.startTime == nil)
    }

    @Test("updateArc clears due date when set to clear")
    @MainActor
    func updateArcClearsDueDate() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let dueDate = Date().addingTimeInterval(86_400 * 7)
        let arc = try await service.createArc(title: "Test Arc", dueTime: dueDate)
        #expect(arc.dueTime != nil)

        try await service.updateArc(arc, dueTime: .clear)

        #expect(arc.dueTime == nil)
    }

    @Test("updateArc preserves existing dates when not specified")
    @MainActor
    func updateArcPreservesDatesWhenNotSpecified() async throws {
        let container = try Self.makeTestContainer()
        let context = container.mainContext
        let service = ArcService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let startDate = Date()
        let dueDate = Date().addingTimeInterval(86_400 * 7)
        let arc = try await service.createArc(
            title: "Test Arc",
            startTime: startDate,
            dueTime: dueDate
        )

        // Update only the title, dates should be preserved
        try await service.updateArc(arc, title: "Updated Title")

        #expect(arc.startTime == startDate)
        #expect(arc.dueTime == dueDate)
    }
}
