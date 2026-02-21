//
//  ReminderTests.swift
//  DequeueTests
//
//  Tests for Reminder model
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

/// Helper to create in-memory container for Reminder tests
private func makeReminderTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self, QueueTask.self, Reminder.self, Arc.self, Tag.self,
        configurations: config
    )
}

@Suite("Reminder Model Tests", .serialized)
@MainActor
struct ReminderTests {

    // MARK: - Default Init Tests

    @Test("Reminder initializes with default values")
    func defaultInit() {
        let futureDate = Date().addingTimeInterval(3600)
        let reminder = Reminder(
            parentId: "parent-1",
            parentType: .stack,
            remindAt: futureDate
        )

        #expect(reminder.parentId == "parent-1")
        #expect(reminder.parentType == .stack)
        #expect(reminder.status == .active)
        #expect(reminder.snoozedFrom == nil)
        #expect(reminder.remindAt == futureDate)
        #expect(reminder.isDeleted == false)
        #expect(reminder.userId == nil)
        #expect(reminder.deviceId == nil)
        #expect(reminder.syncState == .pending)
        #expect(reminder.lastSyncedAt == nil)
        #expect(reminder.serverId == nil)
        #expect(reminder.revision == 1)
        #expect(reminder.stack == nil)
        #expect(reminder.task == nil)
        #expect(reminder.arc == nil)
    }

    // MARK: - Custom Init Tests

    @Test("Reminder initializes with all custom values")
    func customInit() {
        let id = "rem-custom-1"
        let now = Date()
        let remindAt = now.addingTimeInterval(7200)
        let snoozedFrom = now.addingTimeInterval(-600)

        let reminder = Reminder(
            id: id,
            parentId: "task-42",
            parentType: .task,
            status: .snoozed,
            snoozedFrom: snoozedFrom,
            remindAt: remindAt,
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            userId: "user-v",
            deviceId: "device-mac",
            syncState: .synced,
            lastSyncedAt: now,
            serverId: "server-rem-1",
            revision: 3
        )

        #expect(reminder.id == id)
        #expect(reminder.parentId == "task-42")
        #expect(reminder.parentType == .task)
        #expect(reminder.status == .snoozed)
        #expect(reminder.snoozedFrom == snoozedFrom)
        #expect(reminder.remindAt == remindAt)
        #expect(reminder.isDeleted == false)
        #expect(reminder.userId == "user-v")
        #expect(reminder.deviceId == "device-mac")
        #expect(reminder.syncState == .synced)
        #expect(reminder.lastSyncedAt == now)
        #expect(reminder.serverId == "server-rem-1")
        #expect(reminder.revision == 3)
    }

    // MARK: - isPastDue Tests

    @Test("isPastDue is true when remindAt is in the past")
    func isPastDueTrue() {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let reminder = Reminder(
            parentId: "parent-1",
            parentType: .stack,
            remindAt: pastDate
        )

        #expect(reminder.isPastDue == true)
    }

    @Test("isPastDue is false when remindAt is in the future")
    func isPastDueFalse() {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let reminder = Reminder(
            parentId: "parent-1",
            parentType: .stack,
            remindAt: futureDate
        )

        #expect(reminder.isPastDue == false)
    }

    // MARK: - isUpcoming Tests

    @Test("isUpcoming is true when active and in the future")
    func isUpcomingTrue() {
        let futureDate = Date().addingTimeInterval(3600)
        let reminder = Reminder(
            parentId: "parent-1",
            parentType: .task,
            status: .active,
            remindAt: futureDate
        )

        #expect(reminder.isUpcoming == true)
    }

    @Test("isUpcoming is false when active but in the past")
    func isUpcomingFalseWhenPast() {
        let pastDate = Date().addingTimeInterval(-3600)
        let reminder = Reminder(
            parentId: "parent-1",
            parentType: .task,
            status: .active,
            remindAt: pastDate
        )

        #expect(reminder.isUpcoming == false)
    }

    @Test("isUpcoming is false when snoozed even if in the future")
    func isUpcomingFalseWhenSnoozed() {
        let futureDate = Date().addingTimeInterval(3600)
        let reminder = Reminder(
            parentId: "parent-1",
            parentType: .task,
            status: .snoozed,
            remindAt: futureDate
        )

        #expect(reminder.isUpcoming == false)
    }

    @Test("isUpcoming is false when fired")
    func isUpcomingFalseWhenFired() {
        let futureDate = Date().addingTimeInterval(3600)
        let reminder = Reminder(
            parentId: "parent-1",
            parentType: .task,
            status: .fired,
            remindAt: futureDate
        )

        #expect(reminder.isUpcoming == false)
    }

    // MARK: - Parent Type Tests

    @Test("Reminder with stack parent type")
    func stackParentType() {
        let reminder = Reminder(
            parentId: "stack-1",
            parentType: .stack,
            remindAt: Date()
        )

        #expect(reminder.parentType == .stack)
    }

    @Test("Reminder with task parent type")
    func taskParentType() {
        let reminder = Reminder(
            parentId: "task-1",
            parentType: .task,
            remindAt: Date()
        )

        #expect(reminder.parentType == .task)
    }

    @Test("Reminder with arc parent type")
    func arcParentType() {
        let reminder = Reminder(
            parentId: "arc-1",
            parentType: .arc,
            remindAt: Date()
        )

        #expect(reminder.parentType == .arc)
    }

    // MARK: - Status Tests

    @Test("Reminder status values")
    func statusValues() {
        let active = Reminder(
            parentId: "p",
            parentType: .stack,
            status: .active,
            remindAt: Date()
        )
        let snoozed = Reminder(
            parentId: "p",
            parentType: .stack,
            status: .snoozed,
            remindAt: Date()
        )
        let fired = Reminder(
            parentId: "p",
            parentType: .stack,
            status: .fired,
            remindAt: Date()
        )

        #expect(active.status == .active)
        #expect(snoozed.status == .snoozed)
        #expect(fired.status == .fired)
    }

    // MARK: - Persistence Tests

    @Test("Reminder persists in ModelContainer")
    func persistsInContainer() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext

        let remindAt = Date().addingTimeInterval(3600)
        let reminder = Reminder(
            parentId: "stack-abc",
            parentType: .stack,
            remindAt: remindAt
        )
        let reminderId = reminder.id
        context.insert(reminder)
        try context.save()

        let descriptor = FetchDescriptor<Reminder>(
            predicate: #Predicate { $0.id == reminderId }
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.parentId == "stack-abc")
        #expect(fetched.first?.parentType == .stack)
    }

    // MARK: - Relationship Tests

    @Test("Reminder links to task via inverse relationship")
    func linksToTask() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext

        let task = QueueTask(title: "Task with Reminder")
        context.insert(task)

        let reminder = Reminder(
            parentId: task.id,
            parentType: .task,
            remindAt: Date().addingTimeInterval(3600)
        )
        context.insert(reminder)
        task.reminders.append(reminder)

        try context.save()

        #expect(reminder.task?.id == task.id)
        #expect(task.reminders.count == 1)
    }

    // MARK: - Soft Delete Tests

    @Test("isDeleted defaults to false")
    func isDeletedDefault() {
        let reminder = Reminder(
            parentId: "p",
            parentType: .stack,
            remindAt: Date()
        )

        #expect(reminder.isDeleted == false)
    }

    @Test("isDeleted can be set to true")
    func isDeletedTrue() {
        let reminder = Reminder(
            parentId: "p",
            parentType: .stack,
            remindAt: Date(),
            isDeleted: true
        )

        #expect(reminder.isDeleted == true)
    }
}
