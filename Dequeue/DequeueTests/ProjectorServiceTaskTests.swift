//
//  ProjectorServiceTaskTests.swift
//  DequeueTests
//
//  Tests for ProjectorService task event projection:
//  taskCreated, taskUpdated, taskDeleted, taskCompleted, taskActivated, taskClosed
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ProjectorService Task Events", .serialized)
@MainActor
struct ProjectorServiceTaskTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            SyncConflict.self, Tag.self, Device.self, Arc.self, Attachment.self,
            configurations: config
        )
    }

    private func makeTaskPayload(
        id: String,
        stackId: String? = nil,
        title: String = "Test Task",
        status: String = "pending",
        priority: Int? = nil,
        sortOrder: Int = 0,
        deleted: Bool = false,
        tags: [String]? = nil
    ) throws -> Data {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "status": status,
            "sortOrder": sortOrder,
            "deleted": deleted
        ]
        if let stackId { dict["stackId"] = stackId }
        if let priority { dict["priority"] = priority }
        if let tags { dict["tags"] = tags }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - taskCreated Tests

    @Test("taskCreated: creates task with correct fields from event")
    func createsTaskFromEvent() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let payload = try makeTaskPayload(id: taskId, title: "Buy groceries", status: "pending", priority: 2, sortOrder: 5)

        let event = Event(
            eventType: .taskCreated,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.title == "Buy groceries")
        #expect(task.status == .pending)
        #expect(task.priority == 2)
        #expect(task.sortOrder == 5)
        #expect(task.isDeleted == false)
        #expect(task.syncState == .synced)
    }

    @Test("taskCreated: assigns task to parent stack")
    func createsTaskLinkedToStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stack = Stack(title: "Work")
        context.insert(stack)
        try context.save()

        let taskId = CUID.generate()
        let payload = try makeTaskPayload(id: taskId, stackId: stack.id, title: "Write report")

        let event = Event(
            eventType: .taskCreated,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        let task = try #require(tasks.first)
        #expect(task.stack?.id == stack.id)
        #expect(stack.tasks.count == 1)
    }

    @Test("taskCreated: creates task without stack when stackId is absent")
    func createsTaskWithoutStack() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let payload = try makeTaskPayload(id: taskId, title: "Orphan task")

        let event = Event(
            eventType: .taskCreated,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        let task = try #require(tasks.first)
        #expect(task.stack == nil)
    }

    @Test("taskCreated: sets tags from payload")
    func createsTaskWithTags() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let payload = try makeTaskPayload(id: taskId, title: "Tagged task", tags: ["work", "urgent"])

        let event = Event(
            eventType: .taskCreated,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        let task = try #require(tasks.first)
        #expect(task.tags.sorted() == ["urgent", "work"])
    }

    @Test("taskCreated: LWW updates existing task when event is newer")
    func lwwUpdatesExistingTaskWhenNewer() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let oldDate = Date(timeIntervalSinceNow: -100)
        let existingTask = QueueTask(id: taskId, title: "Old Title", updatedAt: oldDate)
        context.insert(existingTask)
        try context.save()

        let payload = try makeTaskPayload(id: taskId, title: "New Title")

        let event = Event(
            eventType: .taskCreated,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        #expect(tasks.count == 1)
        #expect(tasks.first?.title == "New Title")
    }

    // MARK: - taskUpdated Tests

    @Test("taskUpdated: updates task fields from event")
    func updatesTaskFields() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let existingTask = QueueTask(
            id: taskId,
            title: "Original Title",
            updatedAt: Date(timeIntervalSinceNow: -100)
        )
        context.insert(existingTask)
        try context.save()

        let payload = try makeTaskPayload(id: taskId, title: "Updated Title", priority: 1, sortOrder: 3)

        let event = Event(
            eventType: .taskUpdated,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existingTask.title == "Updated Title")
        #expect(existingTask.priority == 1)
        #expect(existingTask.sortOrder == 3)
        #expect(existingTask.syncState == .synced)
    }

    @Test("taskUpdated: LWW skips stale event when local is newer")
    func lwwSkipsStaleUpdate() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let futureDate = Date(timeIntervalSinceNow: 100)
        let existingTask = QueueTask(id: taskId, title: "Newer Title", updatedAt: futureDate)
        context.insert(existingTask)
        try context.save()

        let payload = try makeTaskPayload(id: taskId, title: "Older Title")

        let event = Event(
            eventType: .taskUpdated,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Title should remain unchanged — stale event was ignored
        #expect(existingTask.title == "Newer Title")
    }

    @Test("taskUpdated: ignores update to deleted task")
    func updatedSkipsDeletedTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let baseTime = Date()
        let taskId = CUID.generate()

        // Step 1: Create task via event
        let createPayload = try makeTaskPayload(id: taskId, title: "Deleted Task")
        let createEvent = Event(
            eventType: .taskCreated, payload: createPayload,
            timestamp: baseTime, entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        // Step 2: Delete the task via event
        let deletePayload = try JSONSerialization.data(withJSONObject: ["taskId": taskId])
        let deleteEvent = Event(
            eventType: .taskDeleted, payload: deletePayload,
            timestamp: baseTime.addingTimeInterval(1), entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)

        // Step 3: Update event (even newer) — should be ignored for deleted task
        let updatePayload = try makeTaskPayload(id: taskId, title: "Should Not Apply")
        let updateEvent = Event(
            eventType: .taskUpdated, payload: updatePayload,
            timestamp: baseTime.addingTimeInterval(2), entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(updateEvent)
        try await ProjectorService.apply(event: updateEvent, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        // Title should remain "Deleted Task" — update on deleted task is ignored
        #expect(tasks.first?.title == "Deleted Task")
    }

    @Test("taskUpdated: no-ops when task not found")
    func updatedNoOpsForMissingTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let payload = try makeTaskPayload(id: CUID.generate(), title: "Ghost")
        let event = Event(
            eventType: .taskUpdated,
            payload: payload,
            entityId: CUID.generate(),
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)

        let allTasks = try context.fetch(FetchDescriptor<QueueTask>())
        #expect(allTasks.isEmpty)
    }

    // MARK: - taskDeleted Tests

    @Test("taskDeleted: marks task as deleted")
    func deletesTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let oldDate = Date(timeIntervalSinceNow: -100)
        let existingTask = QueueTask(id: taskId, title: "To Delete", updatedAt: oldDate)
        context.insert(existingTask)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: ["taskId": taskId])

        let event = Event(
            eventType: .taskDeleted,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existingTask.isDeleted == true)
        #expect(existingTask.syncState == .synced)
    }

    @Test("taskDeleted: LWW skips deletion when local is newer")
    func lwwSkipsDeletion() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let futureDate = Date(timeIntervalSinceNow: 100)
        let existingTask = QueueTask(id: taskId, title: "Persists", updatedAt: futureDate, isDeleted: false)
        context.insert(existingTask)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: ["taskId": taskId])

        let event = Event(
            eventType: .taskDeleted,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // isDeleted should remain false — stale delete was ignored
        #expect(existingTask.isDeleted == false)
    }

    @Test("taskDeleted: no-ops when task not found")
    func deletedNoOpsForMissingTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let payload = try JSONSerialization.data(withJSONObject: ["taskId": CUID.generate()])
        let event = Event(
            eventType: .taskDeleted,
            payload: payload,
            entityId: CUID.generate(),
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(event)

        // Should not throw
        try await ProjectorService.apply(event: event, context: context)
    }

    // MARK: - taskCompleted Tests

    @Test("taskCompleted: sets task status to completed")
    func completesTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let stackId = CUID.generate()
        let oldDate = Date(timeIntervalSinceNow: -100)
        let existingTask = QueueTask(id: taskId, title: "Active Task", status: .pending, updatedAt: oldDate)
        context.insert(existingTask)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: [
            "taskId": taskId, "stackId": stackId, "status": "completed"
        ] as [String: Any])

        let event = Event(
            eventType: .taskCompleted,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existingTask.status == .completed)
        #expect(existingTask.syncState == .synced)
    }

    @Test("taskCompleted: ignores completion of deleted task")
    func completedSkipsDeletedTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let baseTime = Date()
        let taskId = CUID.generate()

        // Step 1: Create task via event
        let createPayload = try makeTaskPayload(id: taskId, title: "Deleted", status: "pending")
        let createEvent = Event(
            eventType: .taskCreated, payload: createPayload,
            timestamp: baseTime, entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        // Step 2: Delete the task via event
        let deletePayload = try JSONSerialization.data(withJSONObject: ["taskId": taskId])
        let deleteEvent = Event(
            eventType: .taskDeleted, payload: deletePayload,
            timestamp: baseTime.addingTimeInterval(1), entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)

        // Step 3: Complete event — should be ignored for deleted task
        let completePayload = try JSONSerialization.data(withJSONObject: ["taskId": taskId, "status": "completed"] as [String: Any])
        let completeEvent = Event(
            eventType: .taskCompleted, payload: completePayload,
            timestamp: baseTime.addingTimeInterval(2), entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(completeEvent)
        try await ProjectorService.apply(event: completeEvent, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        // Status should remain pending — completion of deleted task is ignored
        #expect(tasks.first?.status == .pending)
    }

    // MARK: - taskActivated Tests

    @Test("taskActivated: sets task status to pending and updates stack activeTaskId")
    func activatesTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stack = Stack(title: "My Stack")
        context.insert(stack)

        let taskId = CUID.generate()
        let oldDate = Date(timeIntervalSinceNow: -100)
        let existingTask = QueueTask(id: taskId, title: "Backlog Task", status: .completed, updatedAt: oldDate, stack: stack)
        context.insert(existingTask)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: [
            "taskId": taskId, "stackId": stack.id, "status": "pending"
        ] as [String: Any])

        let event = Event(
            eventType: .taskActivated,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existingTask.status == .pending)
        #expect(existingTask.syncState == .synced)
        #expect(stack.activeTaskId == taskId)
    }

    @Test("taskActivated: ignores activation of deleted task")
    func activatedSkipsDeletedTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let baseTime = Date()
        let taskId = CUID.generate()

        // Step 1: Create task with completed status via event
        let createPayload = try makeTaskPayload(id: taskId, title: "Deleted Task", status: "completed")
        let createEvent = Event(
            eventType: .taskCreated, payload: createPayload,
            timestamp: baseTime, entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        // Step 2: Delete the task via event
        let deletePayload = try JSONSerialization.data(withJSONObject: ["taskId": taskId])
        let deleteEvent = Event(
            eventType: .taskDeleted, payload: deletePayload,
            timestamp: baseTime.addingTimeInterval(1), entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)

        // Step 3: Activate event — should be ignored for deleted task
        let activatePayload = try JSONSerialization.data(withJSONObject: ["taskId": taskId, "status": "pending"] as [String: Any])
        let activateEvent = Event(
            eventType: .taskActivated, payload: activatePayload,
            timestamp: baseTime.addingTimeInterval(2), entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(activateEvent)
        try await ProjectorService.apply(event: activateEvent, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        // Status should remain completed — activation of deleted task is ignored
        #expect(tasks.first?.status == .completed)
    }

    // MARK: - taskClosed Tests

    @Test("taskClosed: sets task status to closed")
    func closesTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let oldDate = Date(timeIntervalSinceNow: -100)
        let existingTask = QueueTask(id: taskId, title: "Active Task", status: .pending, updatedAt: oldDate)
        context.insert(existingTask)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: [
            "taskId": taskId, "status": "closed"
        ] as [String: Any])

        let event = Event(
            eventType: .taskClosed,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existingTask.status == .closed)
        #expect(existingTask.syncState == .synced)
    }

    @Test("taskClosed: LWW skips stale close event")
    func lwwSkipsStaleClose() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let futureDate = Date(timeIntervalSinceNow: 100)
        let existingTask = QueueTask(id: taskId, title: "Active", status: .pending, updatedAt: futureDate)
        context.insert(existingTask)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: [
            "taskId": taskId, "status": "closed"
        ] as [String: Any])

        let event = Event(
            eventType: .taskClosed,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date(timeIntervalSinceNow: -50)
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(existingTask.status == .pending)
    }
}
