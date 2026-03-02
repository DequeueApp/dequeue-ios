//
//  DataImportSkipCompletedTests.swift
//  DequeueTests
//
//  Tests for DataImportService.skipCompleted behavior with all
//  completed/closed status variants.
//

import Testing
import Foundation
import SwiftData
@testable import Dequeue

// MARK: - Test Container

private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Tag.self,
        Attachment.self,
        Arc.self,
        Device.self,
        SyncConflict.self,
        configurations: config
    )
}

// MARK: - Skip Completed Tests

@Suite("DataImportService skipCompleted", .serialized)
@MainActor
struct DataImportSkipCompletedTests {

    @Test("skipCompleted skips 'completed', 'done', 'finished' statuses")
    func skipCompletedVariants() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let json = """
        [
            {"title": "Active", "status": "pending"},
            {"title": "Completed", "status": "completed"},
            {"title": "Done", "status": "done"},
            {"title": "Finished", "status": "finished"}
        ]
        """

        let result = try await service.importTasks(
            content: json, format: .json, targetStack: stack,
            skipCompleted: true
        )

        #expect(result.imported == 1)
        #expect(result.skipped == 3)
    }

    @Test("skipCompleted skips 'closed', 'cancelled', 'canceled' statuses")
    func skipClosedVariants() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let json = """
        [
            {"title": "Active", "status": "pending"},
            {"title": "Closed", "status": "closed"},
            {"title": "Cancelled UK", "status": "cancelled"},
            {"title": "Canceled US", "status": "canceled"}
        ]
        """

        let result = try await service.importTasks(
            content: json, format: .json, targetStack: stack,
            skipCompleted: true
        )

        #expect(result.imported == 1)
        #expect(result.skipped == 3)
    }

    @Test("skipCompleted does not skip active statuses")
    func skipCompletedKeepsActive() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let json = """
        [
            {"title": "Pending", "status": "pending"},
            {"title": "Blocked", "status": "blocked"},
            {"title": "Waiting", "status": "waiting"},
            {"title": "NoStatus"}
        ]
        """

        let result = try await service.importTasks(
            content: json, format: .json, targetStack: stack,
            skipCompleted: true
        )

        #expect(result.imported == 4)
        #expect(result.skipped == 0)
    }
}
