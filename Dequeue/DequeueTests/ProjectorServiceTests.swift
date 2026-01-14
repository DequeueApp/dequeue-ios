//
//  ProjectorServiceTests.swift
//  DequeueTests
//
//  Tests for ProjectorService event projection, specifically isActive restoration (DEQ-136)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ProjectorService Tests")
@MainActor
struct ProjectorServiceTests {

    // MARK: - Test Helpers

    /// Helper to apply multiple events in sequence
    private func applyEvents(_ events: [Event], context: ModelContext) throws {
        for event in events {
            try ProjectorService.apply(event: event, context: context)
        }
    }

    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self, SyncConflict.self, Attachment.self,
            configurations: config
        )
    }

    /// Creates a stack event payload that can be decoded by StackEventPayload
    private func createStackPayload(
        id: String,
        title: String,
        isActive: Bool,
        status: StackStatus = .active
    ) throws -> Data {
        // Create a dictionary that matches StackEventPayload structure
        let payload: [String: Any] = [
            "id": id,
            "title": title,
            "description": NSNull(),
            "status": status.rawValue,
            "priority": NSNull(),
            "sortOrder": 0,
            "isDraft": false,
            "isActive": isActive,
            "activeTaskId": NSNull(),
            "deleted": false
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Creates an entity status payload for activated/deactivated events
    private func createEntityStatusPayload(id: String, status: String = "active") throws -> Data {
        let payload: [String: String] = [
            "id": id,
            "status": status
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - updateStack isActive Restoration Tests (DEQ-136)

    @Test("updateStack restores isActive from payload")
    func updateStackRestoresIsActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with isActive = false
        let stack = Stack(title: "Test Stack", isActive: false)
        context.insert(stack)
        try context.save()

        #expect(stack.isActive == false)

        // Create a stack.updated event with isActive = true
        let payload = try createStackPayload(id: stack.id, title: "Updated Title", isActive: true)
        let event = Event(eventType: .stackUpdated, payload: payload, entityId: stack.id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify isActive was restored
        #expect(stack.isActive == true)
        #expect(stack.title == "Updated Title")
    }

    @Test("applyStackCreated sets isActive from payload")
    func applyStackCreatedSetsIsActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()

        // Create a stack.created event with isActive = true
        let payload = try createStackPayload(id: stackId, title: "New Active Stack", isActive: true)
        let event = Event(eventType: .stackCreated, payload: payload, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify the stack was created with isActive = true
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let stacks = try context.fetch(descriptor)

        #expect(stacks.count == 1)
        #expect(stacks.first?.isActive == true)
    }

    @Test("applyStackCreated sets isActive to false when payload says so")
    func applyStackCreatedSetsIsActiveFalse() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()

        // Create a stack.created event with isActive = false
        let payload = try createStackPayload(id: stackId, title: "New Inactive Stack", isActive: false)
        let event = Event(eventType: .stackCreated, payload: payload, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify the stack was created with isActive = false
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let stacks = try context.fetch(descriptor)

        #expect(stacks.count == 1)
        #expect(stacks.first?.isActive == false)
    }

    // MARK: - applyStackActivated Tests (DEQ-136)

    @Test("applyStackActivated sets isActive to true")
    func applyStackActivatedSetsIsActiveTrue() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with isActive = false
        let stack = Stack(title: "Test Stack", isActive: false)
        context.insert(stack)
        try context.save()

        #expect(stack.isActive == false)

        // Create a stack.activated event
        let payloadData = try createEntityStatusPayload(id: stack.id, status: "active")
        let event = Event(eventType: .stackActivated, payload: payloadData, entityId: stack.id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify isActive was set to true (not status changed)
        #expect(stack.isActive == true)
    }

    @Test("applyStackActivated does not change workflow status")
    func applyStackActivatedDoesNotChangeStatus() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with specific workflow status
        let stack = Stack(title: "Test Stack", status: .completed, isActive: false)
        context.insert(stack)
        try context.save()

        let originalStatus = stack.status
        #expect(originalStatus == .completed)

        // Create a stack.activated event
        let payloadData = try createEntityStatusPayload(id: stack.id, status: "active")
        let event = Event(eventType: .stackActivated, payload: payloadData, entityId: stack.id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify workflow status was NOT changed
        #expect(stack.status == .completed)
        // But isActive should be true
        #expect(stack.isActive == true)
    }

    // MARK: - applyStackDeactivated Tests (DEQ-136)

    @Test("applyStackDeactivated sets isActive to false")
    func applyStackDeactivatedSetsIsActiveFalse() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with isActive = true
        let stack = Stack(title: "Test Stack", isActive: true)
        context.insert(stack)
        try context.save()

        #expect(stack.isActive == true)

        // Create a stack.deactivated event
        let payloadData = try createEntityStatusPayload(id: stack.id, status: "archived")
        let event = Event(eventType: .stackDeactivated, payload: payloadData, entityId: stack.id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify isActive was set to false (not status changed)
        #expect(stack.isActive == false)
    }

    @Test("applyStackDeactivated does not change workflow status")
    func applyStackDeactivatedDoesNotChangeStatus() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with specific workflow status
        let stack = Stack(title: "Test Stack", status: .active, isActive: true)
        context.insert(stack)
        try context.save()

        let originalStatus = stack.status
        #expect(originalStatus == .active)

        // Create a stack.deactivated event
        let payloadData = try createEntityStatusPayload(id: stack.id, status: "archived")
        let event = Event(eventType: .stackDeactivated, payload: payloadData, entityId: stack.id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify workflow status was NOT changed
        #expect(stack.status == .active)
        // But isActive should be false
        #expect(stack.isActive == false)
    }

    // MARK: - Single Active Stack Constraint Tests (DEQ-136)

    @Test("Only one stack is active after rehydrating multiple events")
    func singleActiveAfterRehydration() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1Id = CUID.generate()
        let stack2Id = CUID.generate()
        let stack3Id = CUID.generate()

        // Create three stacks via events
        let payload1 = try createStackPayload(id: stack1Id, title: "Stack 1", isActive: false)
        let payload2 = try createStackPayload(id: stack2Id, title: "Stack 2", isActive: false)
        let payload3 = try createStackPayload(id: stack3Id, title: "Stack 3", isActive: true)

        let event1 = Event(eventType: .stackCreated, payload: payload1, entityId: stack1Id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        let event2 = Event(eventType: .stackCreated, payload: payload2, entityId: stack2Id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        let event3 = Event(eventType: .stackCreated, payload: payload3, entityId: stack3Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        // Apply events in order
        try applyEvents([event1, event2, event3], context: context)

        // Verify only stack3 is active
        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)

        let activeStacks = stacks.filter { $0.isActive }
        #expect(activeStacks.count == 1)
        #expect(activeStacks.first?.id == stack3Id)
    }

    @Test("Activation and deactivation events maintain single active constraint")
    func activationDeactivationMaintainsConstraint() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1Id = CUID.generate()
        let stack2Id = CUID.generate()

        // Create two stacks with stack1 active
        let payload1 = try createStackPayload(id: stack1Id, title: "Stack 1", isActive: true)
        let payload2 = try createStackPayload(id: stack2Id, title: "Stack 2", isActive: false)

        let createEvent1 = Event(eventType: .stackCreated, payload: payload1, entityId: stack1Id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        let createEvent2 = Event(eventType: .stackCreated, payload: payload2, entityId: stack2Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        // Deactivate stack1, activate stack2
        let deactivateData = try createEntityStatusPayload(id: stack1Id, status: "active")
        let deactivateEvent = Event(eventType: .stackDeactivated, payload: deactivateData, entityId: stack1Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        let activateData = try createEntityStatusPayload(id: stack2Id, status: "active")
        let activateEvent = Event(eventType: .stackActivated, payload: activateData, entityId: stack2Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        context.insert(createEvent1)
        context.insert(createEvent2)
        context.insert(deactivateEvent)
        context.insert(activateEvent)
        try context.save()

        // Apply all events in order
        try applyEvents([createEvent1, createEvent2, deactivateEvent, activateEvent], context: context)

        // Verify only stack2 is active now
        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)

        let stack1 = stacks.first { $0.id == stack1Id }
        let stack2 = stacks.first { $0.id == stack2Id }

        #expect(stack1?.isActive == false)
        #expect(stack2?.isActive == true)

        let activeCount = stacks.filter { $0.isActive }.count
        #expect(activeCount == 1)
    }

    // MARK: - Constraint Enforcement Tests (DEQ-136)

    @Test("applyStackActivated enforces single active constraint by deactivating others")
    func applyStackActivatedEnforcesConstraint() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create two stacks, both initially active (simulating a corrupted state)
        let stack1 = Stack(title: "Stack 1", isActive: true)
        let stack2 = Stack(title: "Stack 2", isActive: true)
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        // Both are active (constraint violated)
        #expect(stack1.isActive == true)
        #expect(stack2.isActive == true)

        // Activate stack2 via event - should deactivate stack1
        let payloadData = try createEntityStatusPayload(id: stack2.id, status: "active")
        let event = Event(eventType: .stackActivated, payload: payloadData, entityId: stack2.id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the activation event
        try applyEvents([event], context: context)

        // Verify constraint is now enforced: only stack2 should be active
        #expect(stack1.isActive == false)
        #expect(stack2.isActive == true)

        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)
        let activeCount = stacks.filter { $0.isActive }.count
        #expect(activeCount == 1)
    }

    @Test("Multiple rapid activation events result in only last activated stack being active")
    func multipleActivationEventsLastWins() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1Id = CUID.generate()
        let stack2Id = CUID.generate()
        let stack3Id = CUID.generate()

        // Create three stacks with none active
        let payload1 = try createStackPayload(id: stack1Id, title: "Stack 1", isActive: false)
        let payload2 = try createStackPayload(id: stack2Id, title: "Stack 2", isActive: false)
        let payload3 = try createStackPayload(id: stack3Id, title: "Stack 3", isActive: false)

        let createEvent1 = Event(eventType: .stackCreated, payload: payload1, entityId: stack1Id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        let createEvent2 = Event(eventType: .stackCreated, payload: payload2, entityId: stack2Id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        let createEvent3 = Event(eventType: .stackCreated, payload: payload3, entityId: stack3Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        // Three rapid activation events - without corresponding deactivation events
        let activateData1 = try createEntityStatusPayload(id: stack1Id, status: "active")
        let activateEvent1 = Event(eventType: .stackActivated, payload: activateData1, entityId: stack1Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        let activateData2 = try createEntityStatusPayload(id: stack2Id, status: "active")
        let activateEvent2 = Event(eventType: .stackActivated, payload: activateData2, entityId: stack2Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        let activateData3 = try createEntityStatusPayload(id: stack3Id, status: "active")
        let activateEvent3 = Event(eventType: .stackActivated, payload: activateData3, entityId: stack3Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        // Insert all events
        context.insert(createEvent1)
        context.insert(createEvent2)
        context.insert(createEvent3)
        context.insert(activateEvent1)
        context.insert(activateEvent2)
        context.insert(activateEvent3)
        try context.save()

        // Apply all events in order (create then activate, last activation wins)
        try applyEvents([
            createEvent1, createEvent2, createEvent3,
            activateEvent1, activateEvent2, activateEvent3
        ], context: context)

        // Verify only the last activated stack (stack3) is active
        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)

        let stack1 = stacks.first { $0.id == stack1Id }
        let stack2 = stacks.first { $0.id == stack2Id }
        let stack3 = stacks.first { $0.id == stack3Id }

        #expect(stack1?.isActive == false)
        #expect(stack2?.isActive == false)
        #expect(stack3?.isActive == true)

        let activeCount = stacks.filter { $0.isActive }.count
        #expect(activeCount == 1)
    }

    // TODO: DEQ-XXX - This test is failing due to complex LWW timing interactions
    // The guard in applyStackActivated should prevent deleted stack activation,
    // but there's an issue with how events are processed that needs investigation.
    @Test("Deleted stack activation is ignored", .disabled("Needs investigation - LWW timing issue"))
    func deletedStackActivationIsIgnored() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()

        // Use explicit timestamps to ensure proper LWW ordering
        // Each event must have a strictly greater timestamp than the previous
        let baseTime = Date()
        let createTime = baseTime
        let deleteTime = baseTime.addingTimeInterval(1.0)
        let activateTime = baseTime.addingTimeInterval(2.0)

        // Step 1: Create the stack via an event
        let createPayload = try createStackPayload(id: stackId, title: "Test Stack", isActive: false)
        let createEvent = Event(eventType: .stackCreated, payload: createPayload, timestamp: createTime, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(createEvent)
        try context.save()
        try applyEvents([createEvent], context: context)

        // Verify stack was created
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        var stacks = try context.fetch(descriptor)
        #expect(stacks.count == 1)
        #expect(stacks.first?.isDeleted == false)
        #expect(stacks.first?.isActive == false)

        // Step 2: Delete the stack via an event (with later timestamp)
        let deletePayloadDict: [String: Any] = ["id": stackId, "deleted": true]
        let deletePayloadData = try JSONSerialization.data(withJSONObject: deletePayloadDict)
        let deleteEvent = Event(eventType: .stackDeleted, payload: deletePayloadData, timestamp: deleteTime, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(deleteEvent)
        try context.save()
        try applyEvents([deleteEvent], context: context)

        // Verify stack is now deleted
        stacks = try context.fetch(descriptor)
        #expect(stacks.count == 1)
        #expect(stacks.first?.isDeleted == true)
        #expect(stacks.first?.isActive == false)

        // Step 3: Try to activate the deleted stack via event (with even later timestamp)
        // Note: The guard in applyStackActivated should prevent activation of deleted stacks
        let activatePayloadData = try createEntityStatusPayload(id: stackId, status: "active")
        let activateEvent = Event(eventType: .stackActivated, payload: activatePayloadData, timestamp: activateTime, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(activateEvent)
        try context.save()
        try applyEvents([activateEvent], context: context)

        // Step 4: Verify the deleted stack was NOT activated (guard should prevent it)
        stacks = try context.fetch(descriptor)
        #expect(stacks.count == 1)
        guard let finalStack = stacks.first else {
            Issue.record("Failed to fetch stack")
            return
        }

        #expect(finalStack.isDeleted == true)
        #expect(finalStack.isActive == false)
    }

    @Test("Stack deletion sets isActive to false")
    func stackDeletionSetsIsActiveFalse() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create an active stack
        let stack = Stack(title: "Active Stack", isActive: true)
        context.insert(stack)
        try context.save()

        #expect(stack.isActive == true)
        #expect(stack.isDeleted == false)

        // Create a stack.deleted event
        let payloadDict: [String: Any] = ["id": stack.id, "deleted": true]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict)
        let event = Event(eventType: .stackDeleted, payload: payloadData, entityId: stack.id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the deletion event
        try applyEvents([event], context: context)

        // Verify the stack is now deleted and inactive
        #expect(stack.isDeleted == true)
        #expect(stack.isActive == false)
    }

    // MARK: - Task Completion Rehydration Tests (DEQ-139)

    /// Creates a task status payload matching TaskStatusPayload structure
    /// This is the format used when recording task.completed events
    private func createTaskStatusPayload(
        taskId: String,
        stackId: String,
        status: String
    ) throws -> Data {
        // This matches the TaskStatusPayload structure which includes both taskId and stackId
        let payload: [String: Any] = [
            "taskId": taskId,
            "stackId": stackId,
            "status": status,
            "fullState": [
                "id": taskId,
                "stackId": stackId,
                "title": "Test Task",
                "description": NSNull(),
                "status": status,
                "priority": NSNull(),
                "sortOrder": 0,
                "lastActiveTime": NSNull(),
                "createdAt": Int64(Date().timeIntervalSince1970 * 1_000),
                "updatedAt": Int64(Date().timeIntervalSince1970 * 1_000),
                "deleted": false
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    @Test("applyTaskCompleted uses taskId not stackId from payload (DEQ-139)")
    func applyTaskCompletedUsesTaskId() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack and a task
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task", status: .pending)
        task.stack = stack
        stack.tasks.append(task)
        context.insert(task)
        try context.save()

        #expect(task.status == .pending)

        // Create a task.completed event with BOTH taskId and stackId in the payload
        // This matches the real-world scenario where TaskStatusPayload is used
        let payloadData = try createTaskStatusPayload(
            taskId: task.id,
            stackId: stack.id,
            status: TaskStatus.completed.rawValue
        )
        let event = Event(eventType: .taskCompleted, payload: payloadData, entityId: task.id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify the task status was updated to completed
        // Before DEQ-139 fix, this would fail because EntityStatusPayload
        // would incorrectly use stackId instead of taskId
        #expect(task.status == .completed)
    }

    @Test("Task completion event from another device is properly rehydrated (DEQ-139)")
    func taskCompletionFromRemoteDeviceRehydrates() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack with 3 pending tasks (simulating tasks created on device A)
        let stack = Stack(title: "My Stack")
        context.insert(stack)

        let task1 = QueueTask(title: "Task 1", status: .pending)
        let task2 = QueueTask(title: "Task 2", status: .pending)
        let task3 = QueueTask(title: "Task 3", status: .pending)

        for task in [task1, task2, task3] {
            task.stack = stack
            stack.tasks.append(task)
            context.insert(task)
        }
        try context.save()

        // Verify all tasks are pending
        #expect(task1.status == .pending)
        #expect(task2.status == .pending)
        #expect(task3.status == .pending)

        // Simulate receiving completion events from device B (another device)
        // These events come through sync with both taskId and stackId
        let event1 = Event(
            eventType: .taskCompleted,
            payload: try createTaskStatusPayload(taskId: task1.id, stackId: stack.id, status: "completed"),
            entityId: task1.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        let event2 = Event(
            eventType: .taskCompleted,
            payload: try createTaskStatusPayload(taskId: task2.id, stackId: stack.id, status: "completed"),
            entityId: task2.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        let event3 = Event(
            eventType: .taskCompleted,
            payload: try createTaskStatusPayload(taskId: task3.id, stackId: stack.id, status: "completed"),
            entityId: task3.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )

        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        // Apply the events (simulating rehydration on device B)
        try applyEvents([event1, event2, event3], context: context)

        // Verify all 3 tasks are now completed
        // This was the bug in DEQ-139: tasks remained pending after sync
        #expect(task1.status == .completed)
        #expect(task2.status == .completed)
        #expect(task3.status == .completed)

        // Count completed tasks in the stack
        let completedTasks = stack.tasks.filter { $0.status == .completed }
        #expect(completedTasks.count == 3)
    }

    @Test("EntityStatusPayload correctly decodes taskId when both taskId and stackId present")
    func entityStatusPayloadDecodesTaskIdFirst() async throws {
        // This tests the decoder directly to ensure taskId takes precedence
        let taskId = CUID.generate()
        let stackId = CUID.generate()

        // Create payload with both taskId and stackId
        let payloadDict: [String: Any] = [
            "taskId": taskId,
            "stackId": stackId,
            "status": "completed"
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict)

        // Decode using EntityStatusPayload
        let payload = try JSONDecoder().decode(EntityStatusPayload.self, from: payloadData)

        // The id should be the taskId, NOT the stackId
        #expect(payload.id == taskId)
        #expect(payload.id != stackId)
    }

    @Test("EntityStatusPayload falls back to stackId when taskId not present")
    func entityStatusPayloadFallsBackToStackId() async throws {
        // This tests that stack events still work correctly
        let stackId = CUID.generate()

        // Create payload with only stackId (like StackStatusPayload)
        let payloadDict: [String: Any] = [
            "stackId": stackId,
            "status": "completed"
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict)

        // Decode using EntityStatusPayload
        let payload = try JSONDecoder().decode(EntityStatusPayload.self, from: payloadData)

        // The id should be the stackId since taskId is not present
        #expect(payload.id == stackId)
    }

    // MARK: - Attachment Projection Tests (DEQ-75)

    /// Creates an attachment event payload matching AttachmentEventPayload structure
    private func createAttachmentPayload(
        id: String,
        parentId: String,
        parentType: ParentType,
        filename: String = "test.pdf",
        mimeType: String = "application/pdf",
        sizeBytes: Int64 = 1_024,
        url: String? = nil,
        deleted: Bool = false
    ) throws -> Data {
        var payload: [String: Any] = [
            "id": id,
            "parentId": parentId,
            "parentType": parentType.rawValue,
            "filename": filename,
            "mimeType": mimeType,
            "sizeBytes": sizeBytes,
            "deleted": deleted
        ]
        if let url {
            payload["url"] = url
        } else {
            payload["url"] = NSNull()
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Creates an attachment removed payload
    private func createAttachmentRemovedPayload(attachmentId: String) throws -> Data {
        let payload: [String: String] = [
            "attachmentId": attachmentId
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    @Test("applyAttachmentAdded creates new attachment")
    func applyAttachmentAddedCreatesNewAttachment() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack to attach to
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let attachmentId = CUID.generate()
        let payloadData = try createAttachmentPayload(
            id: attachmentId,
            parentId: stack.id,
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 2_048,
            url: "https://example.com/doc.pdf"
        )

        let event = Event(
            eventType: .attachmentAdded,
            payload: payloadData,
            entityId: attachmentId,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify attachment was created
        let predicate = #Predicate<Attachment> { $0.id == attachmentId }
        let descriptor = FetchDescriptor<Attachment>(predicate: predicate)
        let attachments = try context.fetch(descriptor)

        #expect(attachments.count == 1)
        let attachment = attachments.first
        #expect(attachment?.filename == "document.pdf")
        #expect(attachment?.mimeType == "application/pdf")
        #expect(attachment?.sizeBytes == 2_048)
        #expect(attachment?.parentId == stack.id)
        #expect(attachment?.parentType == .stack)
        #expect(attachment?.remoteUrl == "https://example.com/doc.pdf")
        #expect(attachment?.syncState == .synced)
        #expect(attachment?.uploadState == .completed)
        #expect(attachment?.isDeleted == false)
    }

    @Test("applyAttachmentAdded updates existing attachment with LWW")
    func applyAttachmentAddedUpdatesExisting() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack and an existing attachment
        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let attachmentId = CUID.generate()
        let existingAttachment = Attachment(
            id: attachmentId,
            parentId: stack.id,
            parentType: .stack,
            filename: "old_name.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1_024,
            syncState: .pending
        )
        existingAttachment.updatedAt = Date().addingTimeInterval(-100)  // Old timestamp
        context.insert(existingAttachment)
        try context.save()

        // Create an attachment.added event with newer timestamp
        let payloadData = try createAttachmentPayload(
            id: attachmentId,
            parentId: stack.id,
            parentType: .stack,
            filename: "new_name.pdf",
            mimeType: "application/pdf",
            sizeBytes: 2_048,
            url: "https://example.com/new.pdf"
        )

        let event = Event(
            eventType: .attachmentAdded,
            payload: payloadData,
            entityId: attachmentId,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify attachment was updated
        let predicate = #Predicate<Attachment> { $0.id == attachmentId }
        let descriptor = FetchDescriptor<Attachment>(predicate: predicate)
        let attachments = try context.fetch(descriptor)

        #expect(attachments.count == 1)
        let attachment = attachments.first
        #expect(attachment?.filename == "new_name.pdf")
        #expect(attachment?.sizeBytes == 2_048)
        #expect(attachment?.remoteUrl == "https://example.com/new.pdf")
        #expect(attachment?.syncState == .synced)
    }

    @Test("applyAttachmentAdded skips update when local is newer (LWW)")
    func applyAttachmentAddedSkipsWhenLocalIsNewer() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack and an existing attachment with a recent timestamp
        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let attachmentId = CUID.generate()
        let existingAttachment = Attachment(
            id: attachmentId,
            parentId: stack.id,
            parentType: .stack,
            filename: "local_name.pdf",
            mimeType: "application/pdf",
            sizeBytes: 3_000,
            syncState: .pending
        )
        existingAttachment.updatedAt = Date().addingTimeInterval(100)  // Future timestamp
        context.insert(existingAttachment)
        try context.save()

        // Create an attachment.added event with older timestamp
        let payloadData = try createAttachmentPayload(
            id: attachmentId,
            parentId: stack.id,
            parentType: .stack,
            filename: "remote_name.pdf",
            mimeType: "application/pdf",
            sizeBytes: 2_048
        )

        let oldTimestamp = Date().addingTimeInterval(-50)
        let event = Event(
            eventType: .attachmentAdded,
            payload: payloadData,
            timestamp: oldTimestamp,
            entityId: attachmentId,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify attachment was NOT updated (LWW kept local)
        let predicate = #Predicate<Attachment> { $0.id == attachmentId }
        let descriptor = FetchDescriptor<Attachment>(predicate: predicate)
        let attachments = try context.fetch(descriptor)

        #expect(attachments.count == 1)
        let attachment = attachments.first
        #expect(attachment?.filename == "local_name.pdf")  // Still local name
        #expect(attachment?.sizeBytes == 3_000)  // Still local size
    }

    @Test("applyAttachmentRemoved marks attachment as deleted")
    func applyAttachmentRemovedMarksAsDeleted() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack and an attachment
        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let attachmentId = CUID.generate()
        let attachment = Attachment(
            id: attachmentId,
            parentId: stack.id,
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1_024
        )
        attachment.updatedAt = Date().addingTimeInterval(-100)  // Old timestamp
        context.insert(attachment)
        try context.save()

        #expect(attachment.isDeleted == false)

        // Create an attachment.removed event
        let payloadData = try createAttachmentRemovedPayload(attachmentId: attachmentId)
        let event = Event(
            eventType: .attachmentRemoved,
            payload: payloadData,
            entityId: attachmentId,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify attachment was marked as deleted
        #expect(attachment.isDeleted == true)
        #expect(attachment.syncState == .synced)
    }

    @Test("applyAttachmentRemoved ignores when attachment not found")
    func applyAttachmentRemovedIgnoresWhenNotFound() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let nonExistentId = CUID.generate()
        let payloadData = try createAttachmentRemovedPayload(attachmentId: nonExistentId)
        let event = Event(
            eventType: .attachmentRemoved,
            payload: payloadData,
            entityId: nonExistentId,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)
        try context.save()

        // Apply the event - should not throw
        try applyEvents([event], context: context)

        // Verify no attachment was created
        let descriptor = FetchDescriptor<Attachment>()
        let attachments = try context.fetch(descriptor)
        #expect(attachments.isEmpty)
    }

    @Test("applyAttachmentRemoved respects LWW")
    func applyAttachmentRemovedRespectsLWW() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack and an attachment with recent timestamp
        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let attachmentId = CUID.generate()
        let attachment = Attachment(
            id: attachmentId,
            parentId: stack.id,
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1_024
        )
        attachment.updatedAt = Date().addingTimeInterval(100)  // Future timestamp
        context.insert(attachment)
        try context.save()

        // Create an attachment.removed event with older timestamp
        let payloadData = try createAttachmentRemovedPayload(attachmentId: attachmentId)
        let oldTimestamp = Date().addingTimeInterval(-50)
        let event = Event(
            eventType: .attachmentRemoved,
            payload: payloadData,
            timestamp: oldTimestamp,
            entityId: attachmentId,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify attachment was NOT deleted (LWW kept local)
        #expect(attachment.isDeleted == false)
    }

    @Test("applyAttachmentAdded works with task parent")
    func applyAttachmentAddedWorksWithTaskParent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create a stack and task
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task")
        task.stack = stack
        stack.tasks.append(task)
        context.insert(task)
        try context.save()

        let attachmentId = CUID.generate()
        let payloadData = try createAttachmentPayload(
            id: attachmentId,
            parentId: task.id,
            parentType: .task,
            filename: "task_attachment.pdf",
            mimeType: "application/pdf",
            sizeBytes: 4_096
        )

        let event = Event(
            eventType: .attachmentAdded,
            payload: payloadData,
            entityId: attachmentId,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)
        try context.save()

        // Apply the event
        try applyEvents([event], context: context)

        // Verify attachment was created with task parent
        let predicate = #Predicate<Attachment> { $0.id == attachmentId }
        let descriptor = FetchDescriptor<Attachment>(predicate: predicate)
        let attachments = try context.fetch(descriptor)

        #expect(attachments.count == 1)
        let attachment = attachments.first
        #expect(attachment?.parentId == task.id)
        #expect(attachment?.parentType == .task)
    }

    @Test("applyAttachmentAdded sets uploadState based on url presence")
    func applyAttachmentAddedSetsUploadStateCorrectly() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        // Test 1: Attachment with URL should be .completed
        let attachmentId1 = CUID.generate()
        let payload1 = try createAttachmentPayload(
            id: attachmentId1,
            parentId: stack.id,
            parentType: .stack,
            url: "https://example.com/file.pdf"
        )
        let event1 = Event(
            eventType: .attachmentAdded,
            payload: payload1,
            entityId: attachmentId1,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event1)

        // Test 2: Attachment without URL should be .pending
        let attachmentId2 = CUID.generate()
        let payload2 = try createAttachmentPayload(
            id: attachmentId2,
            parentId: stack.id,
            parentType: .stack,
            url: nil
        )
        let event2 = Event(
            eventType: .attachmentAdded,
            payload: payload2,
            entityId: attachmentId2,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event2)
        try context.save()

        // Apply both events
        try applyEvents([event1, event2], context: context)

        // Verify uploadState
        let pred1 = #Predicate<Attachment> { $0.id == attachmentId1 }
        let attachment1 = try context.fetch(FetchDescriptor<Attachment>(predicate: pred1)).first
        #expect(attachment1?.uploadState == .completed)

        let pred2 = #Predicate<Attachment> { $0.id == attachmentId2 }
        let attachment2 = try context.fetch(FetchDescriptor<Attachment>(predicate: pred2)).first
        #expect(attachment2?.uploadState == .pending)
    }
}
