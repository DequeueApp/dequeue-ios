//
//  SyncConflictTests.swift
//  DequeueTests
//
//  Tests for sync conflict detection and logging
//

import Testing
import Foundation
import SwiftData
@testable import Dequeue

@Suite("Sync Conflict Tests")
@MainActor
struct SyncConflictTests {

    @Test("SyncConflict model initializes correctly")
    func testSyncConflictInit() async {
        let localTime = Date()
        let remoteTime = Date().addingTimeInterval(-60)

        let conflict = SyncConflict(
            entityType: .stack,
            entityId: "test-123",
            localTimestamp: localTime,
            remoteTimestamp: remoteTime,
            conflictType: .update,
            resolution: .keptLocal
        )

        #expect(conflict.entityType == .stack)
        #expect(conflict.entityId == "test-123")
        #expect(conflict.conflictType == .update)
        #expect(conflict.resolution == .keptLocal)
        #expect(conflict.isResolved == false) // Default
    }

    @Test("SyncConflict provides human-readable description")
    func testConflictDescription() async {
        let localTime = Date()
        let remoteTime = Date().addingTimeInterval(-120) // 2 minutes ago

        let conflict = SyncConflict(
            entityType: .task,
            entityId: "task-456",
            localTimestamp: localTime,
            remoteTimestamp: remoteTime,
            conflictType: .delete,
            resolution: .keptLocal
        )

        let description = conflict.conflictDescription
        #expect(description.contains("Task"))
        #expect(description.contains("conflict"))
        #expect(description.contains("kept local"))
    }

    @Test("Conflict detection works with SwiftData")
    func testConflictPersistence() async throws {
        let container = try ModelContainer(
            for: SyncConflict.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let conflict = SyncConflict(
            entityType: .reminder,
            entityId: "reminder-789",
            localTimestamp: Date(),
            remoteTimestamp: Date().addingTimeInterval(-30),
            conflictType: .statusChange,
            resolution: .keptRemote
        )

        context.insert(conflict)
        try context.save()

        // Fetch and verify
        let descriptor = FetchDescriptor<SyncConflict>()
        let conflicts = try context.fetch(descriptor)

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.entityType == .reminder)
    }

    @Test("Can filter conflicts by entity type")
    func testFilterByEntityType() async throws {
        let container = try ModelContainer(
            for: SyncConflict.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        // Insert multiple conflicts
        let stackConflict = SyncConflict(
            entityType: .stack,
            entityId: "stack-1",
            localTimestamp: Date(),
            remoteTimestamp: Date().addingTimeInterval(-10),
            conflictType: .update,
            resolution: .keptLocal
        )

        let taskConflict = SyncConflict(
            entityType: .task,
            entityId: "task-1",
            localTimestamp: Date(),
            remoteTimestamp: Date().addingTimeInterval(-20),
            conflictType: .update,
            resolution: .keptLocal
        )

        context.insert(stackConflict)
        context.insert(taskConflict)
        try context.save()

        // Filter by entity type
        let entityTypeRaw = SyncConflictEntityType.stack.rawValue
        let predicate = #Predicate<SyncConflict> { conflict in
            conflict.entityTypeRaw == entityTypeRaw
        }
        let descriptor = FetchDescriptor<SyncConflict>(predicate: predicate)
        let stackConflicts = try context.fetch(descriptor)

        #expect(stackConflicts.count == 1)
        #expect(stackConflicts.first?.entityType == .stack)
    }

    @Test("Can query recent conflicts")
    func testRecentConflicts() async throws {
        let container = try ModelContainer(
            for: SyncConflict.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3_600)

        // Old conflict
        let oldConflict = SyncConflict(
            entityType: .stack,
            entityId: "stack-old",
            localTimestamp: now,
            remoteTimestamp: now,
            conflictType: .update,
            resolution: .keptLocal,
            detectedAt: oneHourAgo
        )

        // Recent conflict
        let recentConflict = SyncConflict(
            entityType: .stack,
            entityId: "stack-recent",
            localTimestamp: now,
            remoteTimestamp: now,
            conflictType: .update,
            resolution: .keptLocal,
            detectedAt: now
        )

        context.insert(oldConflict)
        context.insert(recentConflict)
        try context.save()

        // Query conflicts from last 30 minutes
        let cutoff = now.addingTimeInterval(-1_800) // 30 minutes ago
        let predicate = #Predicate<SyncConflict> { conflict in
            conflict.detectedAt > cutoff
        }
        let descriptor = FetchDescriptor<SyncConflict>(predicate: predicate)
        let recent = try context.fetch(descriptor)

        #expect(recent.count == 1)
        #expect(recent.first?.entityId == "stack-recent")
    }
}
