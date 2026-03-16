//
//  ProjectorServiceReminderTests.swift
//  DequeueTests
//
//  Tests for ProjectorService reminder event projection:
//  reminderCreated, reminderUpdated, reminderDeleted, reminderSnoozed
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ProjectorService Reminder Events", .serialized)
@MainActor
struct ProjectorServiceReminderTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            SyncConflict.self, Tag.self, Device.self, Arc.self, Attachment.self,
            configurations: config
        )
    }

    // MARK: - reminderCreated Tests

    @Test("reminderCreated: creates reminder with correct fields from event")
    func createsReminderFromEvent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let remId = CUID.generate()
        let stackId = CUID.generate()
        let remindAtMs: Int64 = 1_741_000_000_000

        let payload = try JSONSerialization.data(withJSONObject: [
            "id": remId, "parentId": stackId, "parentType": "stack",
            "status": "active", "remindAt": remindAtMs, "deleted": false
        ] as [String: Any])

        let event = Event(
            eventType: .reminderCreated,
            payload: payload,
            entityId: remId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Reminder> { $0.id == remId }
        let reminders = try context.fetch(FetchDescriptor<Reminder>(predicate: predicate))
        #expect(reminders.count == 1)
        let rem = try #require(reminders.first)
        #expect(rem.parentId == stackId)
        #expect(rem.parentType == .stack)
        #expect(rem.status == .active)
        #expect(rem.isDeleted == false)
        #expect(rem.syncState == .synced)

        let expectedDate = Date(timeIntervalSince1970: Double(remindAtMs) / 1_000.0)
        #expect(abs(rem.remindAt.timeIntervalSince(expectedDate)) < 1.0)
    }

    @Test("reminderCreated: links reminder to parent stack")
    func linksReminderToParentStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let remId = CUID.generate()
        let remindAtMs: Int64 = 1_741_000_000_000

        let payload = try JSONSerialization.data(withJSONObject: [
            "id": remId, "parentId": stack.id, "parentType": "stack",
            "status": "active", "remindAt": remindAtMs, "deleted": false
        ] as [String: Any])

        let event = Event(
            eventType: .reminderCreated, payload: payload, entityId: remId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)
        try await ProjectorService.apply(event: event, context: context)

        #expect(stack.reminders.count == 1)
        #expect(stack.reminders.first?.id == remId)
    }

    @Test("reminderCreated: links reminder to parent task")
    func linksReminderToParentTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stack = Stack(title: "Parent Stack")
        context.insert(stack)
        let task = QueueTask(title: "Parent Task", stack: stack)
        context.insert(task)
        try context.save()

        let remId = CUID.generate()
        let remindAtMs: Int64 = 1_741_000_000_000

        let payload = try JSONSerialization.data(withJSONObject: [
            "id": remId, "parentId": task.id, "parentType": "task",
            "status": "active", "remindAt": remindAtMs, "deleted": false
        ] as [String: Any])

        let event = Event(
            eventType: .reminderCreated, payload: payload, entityId: remId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)
        try await ProjectorService.apply(event: event, context: context)

        #expect(task.reminders.count == 1)
        #expect(task.reminders.first?.id == remId)
    }

    @Test("reminderCreated: LWW skips older event when reminder already exists with newer timestamp")
    func lwwSkipsOlderReminderCreated() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let remId = CUID.generate()
        let future = Date().addingTimeInterval(3_600)

        // Insert a reminder that was updated at a future timestamp
        let existing = Reminder(
            id: remId, parentId: "s1", parentType: .stack,
            status: .snoozed, remindAt: future.addingTimeInterval(7_200)
        )
        existing.updatedAt = future  // newer than the event below
        context.insert(existing)
        try context.save()

        // Event is older than current state
        let olderTimestamp = future.addingTimeInterval(-3_600)
        let remindAtMs = Int64(future.timeIntervalSince1970 * 1_000)
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": remId, "parentId": "s1", "parentType": "stack",
            "status": "active", "remindAt": remindAtMs, "deleted": false
        ] as [String: Any])

        let event = Event(
            eventType: .reminderCreated, payload: payload,
            timestamp: olderTimestamp, entityId: remId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)
        try await ProjectorService.apply(event: event, context: context)

        // Status should remain snoozed (older event was not applied)
        #expect(existing.status == .snoozed)
    }

    // MARK: - reminderUpdated Tests

    @Test("reminderUpdated: updates remindAt and status on existing reminder")
    func updatesExistingReminder() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldDate = Date().addingTimeInterval(-3_600)
        let reminder = Reminder(
            id: "rem-upd1", parentId: "s1", parentType: .stack,
            status: .active, remindAt: oldDate
        )
        reminder.updatedAt = oldDate
        context.insert(reminder)
        try context.save()

        let newDate = Date().addingTimeInterval(7_200)
        let newDateMs = Int64(newDate.timeIntervalSince1970 * 1_000)
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": "rem-upd1", "parentId": "s1", "parentType": "stack",
            "status": "snoozed", "remindAt": newDateMs, "deleted": false
        ] as [String: Any])

        let event = Event(
            eventType: .reminderUpdated, payload: payload,
            timestamp: Date(), entityId: "rem-upd1",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)
        try await ProjectorService.apply(event: event, context: context)

        #expect(reminder.status == .snoozed)
        #expect(abs(reminder.remindAt.timeIntervalSince(newDate)) < 1.0)
        #expect(reminder.syncState == .synced)
    }

    @Test("reminderUpdated: no-op when reminder does not exist")
    func noOpWhenReminderMissing() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let remindAtMs = Int64(Date().timeIntervalSince1970 * 1_000)
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": "nonexistent-rem", "parentId": "s1", "parentType": "stack",
            "status": "active", "remindAt": remindAtMs, "deleted": false
        ] as [String: Any])

        let event = Event(
            eventType: .reminderUpdated, payload: payload, entityId: "nonexistent-rem",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw; no reminder created
        try await ProjectorService.apply(event: event, context: context)

        let all = try context.fetch(FetchDescriptor<Reminder>())
        #expect(all.isEmpty)
    }

    @Test("reminderUpdated: LWW skips update when reminder is soft-deleted")
    func lwwSkipsUpdateOnSoftDeletedReminder() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let past = Date().addingTimeInterval(-7_200)
        let reminder = Reminder(
            id: "rem-lww-del", parentId: "s1", parentType: .stack,
            status: .active, remindAt: past
        )
        reminder.updatedAt = past
        context.insert(reminder)
        try context.save()

        // Soft-delete via a reminderDeleted event (same code path production uses)
        let deletePayload = try JSONSerialization.data(withJSONObject: ["reminderId": "rem-lww-del"])
        let deleteEvent = Event(
            eventType: .reminderDeleted, payload: deletePayload,
            timestamp: past.addingTimeInterval(60), entityId: "rem-lww-del",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)
        #expect(reminder.isDeleted == true, "reminderDeleted event must soft-delete the reminder")

        // Now apply a reminderUpdated event (newer than deleteEvent) that would change status to snoozed
        let remindAtMs = Int64(Date().timeIntervalSince1970 * 1_000)
        let updatePayload = try JSONSerialization.data(withJSONObject: [
            "id": "rem-lww-del", "parentId": "s1", "parentType": "stack",
            "status": "snoozed", "remindAt": remindAtMs, "deleted": false
        ] as [String: Any])

        let updateEvent = Event(
            eventType: .reminderUpdated, payload: updatePayload,
            timestamp: Date(), entityId: "rem-lww-del",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(updateEvent)
        try await ProjectorService.apply(event: updateEvent, context: context)

        // Status must not have changed to snoozed — the event should be skipped for deleted reminders
        #expect(reminder.status == .active,
            "Status should stay .active; applyReminderUpdated must skip soft-deleted reminders")
    }

    // MARK: - reminderDeleted Tests

    @Test("reminderDeleted: marks reminder as deleted")
    func marksReminderDeleted() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let past = Date().addingTimeInterval(-3_600)
        let reminder = Reminder(
            id: "rem-del1", parentId: "s1", parentType: .stack,
            status: .active, remindAt: past
        )
        reminder.updatedAt = past
        context.insert(reminder)
        try context.save()

        #expect(reminder.isDeleted == false)

        let payload = try JSONSerialization.data(withJSONObject: ["reminderId": "rem-del1"])
        let event = Event(
            eventType: .reminderDeleted, payload: payload,
            timestamp: Date(), entityId: "rem-del1",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)
        try await ProjectorService.apply(event: event, context: context)

        #expect(reminder.isDeleted == true)
        #expect(reminder.syncState == .synced)
    }

    @Test("reminderDeleted: no-op when reminder does not exist")
    func noOpWhenReminderMissingForDelete() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let payload = try JSONSerialization.data(withJSONObject: ["reminderId": "ghost-rem2"])
        let event = Event(
            eventType: .reminderDeleted, payload: payload, entityId: "ghost-rem2",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let all = try context.fetch(FetchDescriptor<Reminder>())
        #expect(all.isEmpty)
    }

    // MARK: - reminderSnoozed Tests

    @Test("reminderSnoozed: sets status to snoozed and updates remindAt")
    func snoozesReminder() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let past = Date().addingTimeInterval(-3_600)
        let reminder = Reminder(
            id: "rem-snz1", parentId: "s1", parentType: .stack,
            status: .active, remindAt: past
        )
        reminder.updatedAt = past
        context.insert(reminder)
        try context.save()

        #expect(reminder.status == .active)

        let snoozeDate = Date().addingTimeInterval(1_800)
        let snoozeDateMs = Int64(snoozeDate.timeIntervalSince1970 * 1_000)
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": "rem-snz1", "parentId": "s1", "parentType": "stack",
            "status": "snoozed", "remindAt": snoozeDateMs, "deleted": false
        ] as [String: Any])

        let event = Event(
            eventType: .reminderSnoozed, payload: payload,
            timestamp: Date(), entityId: "rem-snz1",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)
        try await ProjectorService.apply(event: event, context: context)

        #expect(reminder.status == .snoozed)
        #expect(abs(reminder.remindAt.timeIntervalSince(snoozeDate)) < 1.0)
        #expect(reminder.syncState == .synced)
    }

    @Test("reminderSnoozed: LWW skips snooze when reminder is soft-deleted")
    func lwwSkipsSnoozeOnSoftDeletedReminder() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let past = Date().addingTimeInterval(-7_200)
        let reminder = Reminder(
            id: "rem-snz-del", parentId: "s1", parentType: .stack,
            status: .active, remindAt: past
        )
        reminder.updatedAt = past
        context.insert(reminder)
        try context.save()

        // Soft-delete via a reminderDeleted event (same code path production uses)
        let deletePayload = try JSONSerialization.data(withJSONObject: ["reminderId": "rem-snz-del"])
        let deleteEvent = Event(
            eventType: .reminderDeleted, payload: deletePayload,
            timestamp: past.addingTimeInterval(60), entityId: "rem-snz-del",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)
        #expect(reminder.isDeleted == true, "reminderDeleted event must soft-delete the reminder")

        // Now apply a snoozed event (newer than deleteEvent)
        let snoozeDateMs = Int64(Date().addingTimeInterval(900).timeIntervalSince1970 * 1_000)
        let snoozePayload = try JSONSerialization.data(withJSONObject: [
            "id": "rem-snz-del", "parentId": "s1", "parentType": "stack",
            "status": "snoozed", "remindAt": snoozeDateMs, "deleted": false
        ] as [String: Any])

        let snoozeEvent = Event(
            eventType: .reminderSnoozed, payload: snoozePayload,
            timestamp: Date(), entityId: "rem-snz-del",
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(snoozeEvent)
        try await ProjectorService.apply(event: snoozeEvent, context: context)

        // Status must stay .active — snooze must be skipped for soft-deleted reminders
        #expect(reminder.status == .active,
            "Status should stay .active; applyReminderSnoozed must skip soft-deleted reminders")
    }
}
