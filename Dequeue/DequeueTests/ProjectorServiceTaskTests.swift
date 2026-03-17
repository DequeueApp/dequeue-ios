//
//  ProjectorServiceTaskTests.swift
//  DequeueTests
//
//  Tests for ProjectorService task event projection:
//  taskCreated, taskUpdated, taskDeleted, taskCompleted, taskActivated, taskClosed,
//  taskReordered, taskDelegatedToAI
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

    // MARK: - taskReordered Tests

    @Test("taskReordered: updates sortOrder for all tasks in payload")
    func reordersMultipleTasks() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldDate = Date(timeIntervalSinceNow: -200)
        let id1 = CUID.generate()
        let id2 = CUID.generate()
        let id3 = CUID.generate()

        let task1 = QueueTask(id: id1, title: "Task 1", updatedAt: oldDate)
        task1.sortOrder = 0
        let task2 = QueueTask(id: id2, title: "Task 2", updatedAt: oldDate)
        task2.sortOrder = 1
        let task3 = QueueTask(id: id3, title: "Task 3", updatedAt: oldDate)
        task3.sortOrder = 2
        context.insert(task1)
        context.insert(task2)
        context.insert(task3)
        try context.save()

        // Reverse order: task3 → 0, task2 → 1, task1 → 2
        let payload = try JSONSerialization.data(withJSONObject: [
            "taskIds": [id3, id2, id1],
            "sortOrders": [0, 1, 2]
        ] as [String: Any])

        let event = Event(
            eventType: .taskReordered,
            payload: payload,
            entityId: id1,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(task1.sortOrder == 2)
        #expect(task2.sortOrder == 1)
        #expect(task3.sortOrder == 0)
        #expect(task1.syncState == .synced)
    }

    @Test("taskReordered: LWW skips task whose local timestamp is newer")
    func reorderLwwSkipsNewerTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let id1 = CUID.generate()
        let id2 = CUID.generate()

        // task1 has a future timestamp (local is newer)
        let task1 = QueueTask(id: id1, title: "Task 1", updatedAt: Date(timeIntervalSinceNow: 500))
        task1.sortOrder = 0
        // task2 has an old timestamp (event is newer)
        let task2 = QueueTask(id: id2, title: "Task 2", updatedAt: Date(timeIntervalSinceNow: -200))
        task2.sortOrder = 1
        context.insert(task1)
        context.insert(task2)
        try context.save()

        let payload = try JSONSerialization.data(withJSONObject: [
            "taskIds": [id1, id2],
            "sortOrders": [99, 88]
        ] as [String: Any])

        let event = Event(
            eventType: .taskReordered,
            payload: payload,
            entityId: id1,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // task1 should NOT be updated (local is newer)
        #expect(task1.sortOrder == 0)
        // task2 SHOULD be updated (event is newer)
        #expect(task2.sortOrder == 88)
    }

    @Test("taskReordered: skips deleted tasks silently")
    func reorderSkipsDeletedTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldDate = Date(timeIntervalSinceNow: -200)
        let taskId = CUID.generate()

        // Create then soft-delete the task via event sourcing
        let createPayload = try makeTaskPayload(id: taskId, title: "Deleted Task")
        let createEvent = Event(
            eventType: .taskCreated, payload: createPayload,
            timestamp: oldDate, entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        let deletePayload = try JSONSerialization.data(withJSONObject: ["id": taskId] as [String: Any])
        let deleteEvent = Event(
            eventType: .taskDeleted, payload: deletePayload,
            timestamp: oldDate.addingTimeInterval(10), entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)

        // Now try to reorder the deleted task
        let reorderPayload = try JSONSerialization.data(withJSONObject: [
            "taskIds": [taskId],
            "sortOrders": [42]
        ] as [String: Any])

        let reorderEvent = Event(
            eventType: .taskReordered,
            payload: reorderPayload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        reorderEvent.timestamp = Date()
        context.insert(reorderEvent)
        try await ProjectorService.apply(event: reorderEvent, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        let task = try #require(tasks.first)
        // sortOrder should NOT be 42 — deleted task reorder is skipped
        #expect(task.sortOrder != 42)
        #expect(task.isDeleted == true)
    }

    // MARK: - taskDelegatedToAI Tests

    private func makeTaskState(
        id: String,
        stackId: String = "stack1",
        title: String = "Test Task",
        status: String = "pending",
        delegatedToAI: Bool = false,
        aiAgentId: String? = nil,
        aiDelegatedAt: Int64? = nil,
        updatedAt: Int64? = nil
    ) -> [String: Any] {
        var state: [String: Any] = [
            "id": id,
            "stackId": stackId,
            "title": title,
            "status": status,
            "sortOrder": 0,
            "createdAt": Int64(Date(timeIntervalSinceNow: -100).timeIntervalSince1970 * 1_000),
            "updatedAt": updatedAt ?? Int64(Date().timeIntervalSince1970 * 1_000),
            "deleted": false,
            "delegatedToAI": delegatedToAI
        ]
        if let aiAgentId { state["aiAgentId"] = aiAgentId }
        if let aiDelegatedAt { state["aiDelegatedAt"] = aiDelegatedAt }
        return state
    }

    @Test("taskDelegatedToAI: sets delegatedToAI, aiAgentId, and aiDelegatedAt on task")
    func delegatesToAI() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let oldDate = Date(timeIntervalSinceNow: -100)
        let task = QueueTask(id: taskId, title: "Automate me", status: .pending, updatedAt: oldDate)
        task.delegatedToAI = false
        context.insert(task)
        try context.save()

        let delegatedAtMs = Int64(Date().timeIntervalSince1970 * 1_000)
        let fullState = makeTaskState(
            id: taskId,
            delegatedToAI: true,
            aiAgentId: "agent-xyz",
            aiDelegatedAt: delegatedAtMs
        )

        let payloadDict: [String: Any] = [
            "taskId": taskId,
            "stackId": "stack1",
            "status": "pending",
            "fullState": fullState
        ]
        let payload = try JSONSerialization.data(withJSONObject: payloadDict)

        let event = Event(
            eventType: .taskDelegatedToAI,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        event.timestamp = Date()
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        #expect(task.delegatedToAI == true)
        #expect(task.aiAgentId == "agent-xyz")
        #expect(task.aiDelegatedAt != nil)
        #expect(task.syncState == .synced)
    }

    @Test("taskDelegatedToAI: LWW skips stale delegation event")
    func delegateToAILwwSkipsStale() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        // Task has a future updatedAt — local is newer
        let futureDate = Date(timeIntervalSinceNow: 500)
        let task = QueueTask(id: taskId, title: "Modern Task", status: .pending, updatedAt: futureDate)
        task.delegatedToAI = false
        context.insert(task)
        try context.save()

        let fullState = makeTaskState(id: taskId, delegatedToAI: true, aiAgentId: "agent-abc")
        let payloadDict: [String: Any] = [
            "taskId": taskId,
            "stackId": "stack1",
            "status": "pending",
            "fullState": fullState
        ]
        let payload = try JSONSerialization.data(withJSONObject: payloadDict)

        let event = Event(
            eventType: .taskDelegatedToAI,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        // Event is older than local state
        event.timestamp = Date(timeIntervalSinceNow: -50)
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Should not be updated — event is stale
        #expect(task.delegatedToAI == false)
        #expect(task.aiAgentId == nil)
    }

    @Test("taskDelegatedToAI: ignores delegation for deleted task")
    func delegateToAIIgnoresDeleted() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let taskId = CUID.generate()
        let baseTime = Date(timeIntervalSinceNow: -100)

        // Create then delete the task
        let createPayload = try makeTaskPayload(id: taskId, title: "Doomed Task")
        let createEvent = Event(
            eventType: .taskCreated, payload: createPayload,
            timestamp: baseTime, entityId: taskId, userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(createEvent)
        try await ProjectorService.apply(event: createEvent, context: context)

        let deletePayload = try JSONSerialization.data(withJSONObject: ["id": taskId] as [String: Any])
        let deleteEvent = Event(
            eventType: .taskDeleted, payload: deletePayload,
            timestamp: baseTime.addingTimeInterval(10), entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        context.insert(deleteEvent)
        try await ProjectorService.apply(event: deleteEvent, context: context)

        // Now try to delegate deleted task to AI
        let fullState = makeTaskState(id: taskId, delegatedToAI: true, aiAgentId: "agent-xyz")
        let payloadDict: [String: Any] = [
            "taskId": taskId,
            "stackId": "stack1",
            "status": "pending",
            "fullState": fullState
        ]
        let payload = try JSONSerialization.data(withJSONObject: payloadDict)

        let delegateEvent = Event(
            eventType: .taskDelegatedToAI,
            payload: payload,
            entityId: taskId,
            userId: "u", deviceId: "d", appId: "a"
        )
        delegateEvent.timestamp = Date()
        context.insert(delegateEvent)
        try await ProjectorService.apply(event: delegateEvent, context: context)

        let predicate = #Predicate<QueueTask> { $0.id == taskId }
        let tasks = try context.fetch(FetchDescriptor<QueueTask>(predicate: predicate))
        let task = try #require(tasks.first)
        // delegatedToAI should remain false — deleted task is skipped
        #expect(task.delegatedToAI == false)
        #expect(task.isDeleted == true)
    }
}
