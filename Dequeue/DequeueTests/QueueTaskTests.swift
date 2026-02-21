//
//  QueueTaskTests.swift
//  DequeueTests
//
//  Tests for QueueTask model
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

/// Helper to create in-memory container for QueueTask tests
private func makeTaskTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self, QueueTask.self, Reminder.self, Arc.self, Tag.self,
        configurations: config
    )
}

@Suite("QueueTask Model Tests", .serialized)
@MainActor
struct QueueTaskTests {

    // MARK: - Default Init Tests

    @Test("QueueTask initializes with default values")
    func defaultInit() {
        let task = QueueTask(title: "Test Task")

        #expect(task.title == "Test Task")
        #expect(task.taskDescription == nil)
        #expect(task.startTime == nil)
        #expect(task.dueTime == nil)
        #expect(task.locationAddress == nil)
        #expect(task.locationLatitude == nil)
        #expect(task.locationLongitude == nil)
        #expect(task.attachments.isEmpty)
        #expect(task.tags.isEmpty)
        #expect(task.status == .pending)
        #expect(task.priority == nil)
        #expect(task.blockedReason == nil)
        #expect(task.sortOrder == 0)
        #expect(task.lastActiveTime == nil)
        #expect(task.isDeleted == false)
        #expect(task.delegatedToAI == false)
        #expect(task.aiAgentId == nil)
        #expect(task.aiDelegatedAt == nil)
        #expect(task.userId == nil)
        #expect(task.deviceId == nil)
        #expect(task.syncState == .pending)
        #expect(task.lastSyncedAt == nil)
        #expect(task.serverId == nil)
        #expect(task.revision == 1)
        #expect(task.stack == nil)
        #expect(task.parentTaskId == nil)
        #expect(task.reminders.isEmpty)
    }

    // MARK: - Custom Init Tests

    @Test("QueueTask initializes with all custom values")
    func customInit() {
        let id = "task-custom-123"
        let now = Date()
        let startTime = now.addingTimeInterval(3600)
        let dueTime = now.addingTimeInterval(7200)
        let delegatedAt = now.addingTimeInterval(-300)

        let task = QueueTask(
            id: id,
            title: "Custom Task",
            taskDescription: "A detailed description",
            startTime: startTime,
            dueTime: dueTime,
            locationAddress: "123 Main St",
            locationLatitude: 40.7128,
            locationLongitude: -74.0060,
            attachments: ["file1.png", "file2.pdf"],
            tags: ["urgent", "work"],
            status: .completed,
            priority: 1,
            blockedReason: "Waiting on review",
            sortOrder: 5,
            lastActiveTime: now,
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            delegatedToAI: true,
            aiAgentId: "agent-ada",
            aiDelegatedAt: delegatedAt,
            userId: "user-v",
            deviceId: "device-mac",
            syncState: .synced,
            lastSyncedAt: now,
            serverId: "server-id-99",
            revision: 7,
            parentTaskId: "parent-task-1"
        )

        #expect(task.id == id)
        #expect(task.title == "Custom Task")
        #expect(task.taskDescription == "A detailed description")
        #expect(task.startTime == startTime)
        #expect(task.dueTime == dueTime)
        #expect(task.locationAddress == "123 Main St")
        #expect(task.locationLatitude == 40.7128)
        #expect(task.locationLongitude == -74.0060)
        #expect(task.attachments == ["file1.png", "file2.pdf"])
        #expect(task.tags == ["urgent", "work"])
        #expect(task.status == .completed)
        #expect(task.priority == 1)
        #expect(task.blockedReason == "Waiting on review")
        #expect(task.sortOrder == 5)
        #expect(task.lastActiveTime == now)
        #expect(task.isDeleted == false)
        #expect(task.delegatedToAI == true)
        #expect(task.aiAgentId == "agent-ada")
        #expect(task.aiDelegatedAt == delegatedAt)
        #expect(task.userId == "user-v")
        #expect(task.deviceId == "device-mac")
        #expect(task.syncState == .synced)
        #expect(task.lastSyncedAt == now)
        #expect(task.serverId == "server-id-99")
        #expect(task.revision == 7)
        #expect(task.parentTaskId == "parent-task-1")
    }

    // MARK: - hasParent Tests

    @Test("hasParent is false when parentTaskId is nil")
    func hasParentFalseWhenNil() {
        let task = QueueTask(title: "Root Task")
        #expect(task.hasParent == false)
    }

    @Test("hasParent is true when parentTaskId is set")
    func hasParentTrueWhenSet() {
        let task = QueueTask(
            title: "Subtask",
            parentTaskId: "parent-123"
        )
        #expect(task.hasParent == true)
    }

    // MARK: - AI Delegation Tests

    @Test("AI delegation fields default to off")
    func aiDelegationDefaults() {
        let task = QueueTask(title: "Normal Task")

        #expect(task.delegatedToAI == false)
        #expect(task.aiAgentId == nil)
        #expect(task.aiDelegatedAt == nil)
    }

    @Test("AI delegation fields store values correctly")
    func aiDelegationFields() {
        let now = Date()
        let task = QueueTask(
            title: "AI Task",
            delegatedToAI: true,
            aiAgentId: "agent-claw",
            aiDelegatedAt: now
        )

        #expect(task.delegatedToAI == true)
        #expect(task.aiAgentId == "agent-claw")
        #expect(task.aiDelegatedAt == now)
    }

    // MARK: - Status Tests

    @Test("Task status values")
    func taskStatusValues() {
        let pending = QueueTask(title: "P", status: .pending)
        let completed = QueueTask(title: "C", status: .completed)
        let blocked = QueueTask(title: "B", status: .blocked)
        let closed = QueueTask(title: "X", status: .closed)

        #expect(pending.status == .pending)
        #expect(completed.status == .completed)
        #expect(blocked.status == .blocked)
        #expect(closed.status == .closed)
    }

    // MARK: - activeReminders Tests (with ModelContainer)

    @Test("activeReminders is empty on fresh task")
    func activeRemindersEmpty() {
        let task = QueueTask(title: "No reminders")
        #expect(task.activeReminders.isEmpty)
    }

    // MARK: - Persistence Tests

    @Test("QueueTask persists and fetches from ModelContainer")
    func persistsInContainer() async throws {
        let container = try makeTaskTestContainer()
        let context = container.mainContext

        let task = QueueTask(
            title: "Persisted Task",
            taskDescription: "Stored in SwiftData",
            sortOrder: 3
        )
        let taskId = task.id
        context.insert(task)
        try context.save()

        let descriptor = FetchDescriptor<QueueTask>(
            predicate: #Predicate { $0.id == taskId }
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Persisted Task")
        #expect(fetched.first?.taskDescription == "Stored in SwiftData")
        #expect(fetched.first?.sortOrder == 3)
    }

    // MARK: - Stack Relationship Tests

    @Test("QueueTask links to stack")
    func linksToStack() async throws {
        let container = try makeTaskTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Parent Stack")
        context.insert(stack)

        let task = QueueTask(title: "Child Task", sortOrder: 0)
        context.insert(task)
        stack.tasks.append(task)

        try context.save()

        #expect(task.stack?.id == stack.id)
    }
}
