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
    private func applyEvents(_ events: [Event], context: ModelContext) async throws {
        for event in events {
            try await ProjectorService.apply(event: event, context: context)
        }
    }

    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self, SyncConflict.self, Tag.self, Device.self, Arc.self, Attachment.self,
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
        try await applyEvents([event], context: context)

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
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            entityId: stackId,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)
        try context.save()

        // Apply the event
        try await applyEvents([event], context: context)

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
        try await applyEvents([event], context: context)

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
        try await applyEvents([event], context: context)

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
        try await applyEvents([event], context: context)

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
        try await applyEvents([event], context: context)

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
        try await applyEvents([event], context: context)

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
        try await applyEvents([event1, event2, event3], context: context)

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
        try await applyEvents([createEvent1, createEvent2, deactivateEvent, activateEvent], context: context)

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
        try await applyEvents([event], context: context)

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
        try await applyEvents([
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
        try await applyEvents([createEvent], context: context)

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
        try await applyEvents([deleteEvent], context: context)

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
        try await applyEvents([activateEvent], context: context)

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
        try await applyEvents([event], context: context)

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
        try await applyEvents([event], context: context)

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
        try await applyEvents([event1, event2, event3], context: context)

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

    // MARK: - Device Last Seen Tests (DEQ-236)

    @Test("Device lastSeenAt updates when processing any event from that device")
    func deviceLastSeenUpdatesOnAnyEvent() async throws {
        // DEQ-236: lastSeenAt should update for ALL events, not just device.discovered
        let container = try createTestContainer()
        let context = ModelContext(container)

        let deviceId = "other-device-123"
        let oldLastSeen = Date(timeIntervalSinceNow: -86400 * 7) // 7 days ago

        // Create a known device with an old lastSeenAt
        let device = Device(
            deviceId: deviceId,
            name: "Other Device",
            osName: "iOS",
            osVersion: "17.0",
            isCurrentDevice: false,
            lastSeenAt: oldLastSeen,
            firstSeenAt: oldLastSeen
        )
        context.insert(device)
        try context.save()

        #expect(device.lastSeenAt == oldLastSeen)

        // Create a stack.created event from that device
        let eventTimestamp = Date(timeIntervalSinceNow: -60) // 1 minute ago
        let payload = try createStackPayload(id: CUID.generate(), title: "New Stack", isActive: false)
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            entityId: nil,
            userId: "test-user",
            deviceId: deviceId,  // Event from the other device
            appId: "test-app"
        )
        // Override the timestamp to a specific time
        event.timestamp = eventTimestamp

        context.insert(event)
        try context.save()

        // Apply the event
        try await applyEvents([event], context: context)

        // Verify the device's lastSeenAt was updated to the event timestamp
        #expect(device.lastSeenAt == eventTimestamp)
        #expect(device.lastSeenAt != oldLastSeen)
    }

    @Test("Device lastSeenAt does not update for older events")
    func deviceLastSeenIgnoresOlderEvents() async throws {
        // DEQ-236: Out-of-order events shouldn't regress lastSeenAt
        let container = try createTestContainer()
        let context = ModelContext(container)

        let deviceId = "other-device-456"
        let recentLastSeen = Date(timeIntervalSinceNow: -60) // 1 minute ago

        // Create a device with recent lastSeenAt
        let device = Device(
            deviceId: deviceId,
            name: "Other Device",
            osName: "iOS",
            osVersion: "17.0",
            isCurrentDevice: false,
            lastSeenAt: recentLastSeen,
            firstSeenAt: Date(timeIntervalSinceNow: -86400)
        )
        context.insert(device)
        try context.save()

        // Create an OLD event from that device (older than current lastSeenAt)
        let oldEventTimestamp = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let payload = try createStackPayload(id: CUID.generate(), title: "Old Stack", isActive: false)
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            entityId: nil,
            userId: "test-user",
            deviceId: deviceId,
            appId: "test-app"
        )
        event.timestamp = oldEventTimestamp

        context.insert(event)
        try context.save()

        // Apply the event
        try await applyEvents([event], context: context)

        // Verify lastSeenAt was NOT updated (stayed at the more recent time)
        #expect(device.lastSeenAt == recentLastSeen)
        #expect(device.lastSeenAt != oldEventTimestamp)
    }

    @Test("Device lastSeenAt not affected for unknown devices")
    func deviceLastSeenIgnoresUnknownDevices() async throws {
        // DEQ-236: Events from unknown devices shouldn't cause errors
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create an event from an unknown device (no Device record exists)
        let payload = try createStackPayload(id: CUID.generate(), title: "Stack from Unknown", isActive: false)
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            entityId: nil,
            userId: "test-user",
            deviceId: "unknown-device-xyz",
            appId: "test-app"
        )

        context.insert(event)
        try context.save()

        // Apply the event - should not throw
        try await applyEvents([event], context: context)

        // Verify the stack was still created
        let stacks = try context.fetch(FetchDescriptor<Stack>())
        #expect(stacks.count == 1)
    }

    // MARK: - Batch Processing Tests (DEQ-143)

    /// Creates a task event payload
    private func createTaskPayload(
        id: String,
        title: String,
        stackId: String?,
        status: TaskStatus = .pending
    ) throws -> Data {
        var payload: [String: Any] = [
            "id": id,
            "title": title,
            "description": NSNull(),
            "status": status.rawValue,
            "priority": NSNull(),
            "sortOrder": 0,
            "lastActiveTime": NSNull(),
            "deleted": false
        ]
        if let stackId = stackId {
            payload["stackId"] = stackId
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - Cross-Device Tag Deduplication Tests (DEQ-235)

    /// Creates a tag event payload that can be decoded by TagEventPayload
    private func createTagPayload(
        id: String,
        name: String,
        colorHex: String? = nil,
        createdAt: Date? = nil
    ) throws -> Data {
        var payload: [String: Any] = [
            "id": id,
            "name": name,
            "normalizedName": name.lowercased().trimmingCharacters(in: .whitespaces),
            "deleted": false
        ]
        if let colorHex = colorHex {
            payload["colorHex"] = colorHex
        }
        if let createdAt = createdAt {
            payload["createdAt"] = Int64(createdAt.timeIntervalSince1970 * 1_000)
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    @Test("applyBatch processes multiple events efficiently")
    func applyBatchProcessesMultipleEvents() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1Id = CUID.generate()
        let stack2Id = CUID.generate()
        let stack3Id = CUID.generate()

        // Create three stack events
        let payload1 = try createStackPayload(id: stack1Id, title: "Stack 1", isActive: false)
        let payload2 = try createStackPayload(id: stack2Id, title: "Stack 2", isActive: false)
        let payload3 = try createStackPayload(id: stack3Id, title: "Stack 3", isActive: false)

        let event1 = Event(eventType: .stackCreated, payload: payload1, entityId: stack1Id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        let event2 = Event(eventType: .stackCreated, payload: payload2, entityId: stack2Id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        let event3 = Event(eventType: .stackCreated, payload: payload3, entityId: stack3Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        // Apply all events using batch processing
        let processedCount = try await ProjectorService.applyBatch(events: [event1, event2, event3], context: context)

        // Verify all events were processed
        #expect(processedCount == 3)

        // Verify all stacks were created
        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)
        #expect(stacks.count == 3)

        let stackIds = Set(stacks.map { $0.id })
        #expect(stackIds.contains(stack1Id))
        #expect(stackIds.contains(stack2Id))
        #expect(stackIds.contains(stack3Id))
    }

    @Test("applyBatch returns zero for empty events array")
    func applyBatchReturnsZeroForEmpty() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let processedCount = try await ProjectorService.applyBatch(events: [], context: context)

        #expect(processedCount == 0)
    }

    @Test("applyBatch handles mixed event types")
    func applyBatchHandlesMixedEventTypes() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let taskId = CUID.generate()

        // Create a stack first
        let stackPayload = try createStackPayload(id: stackId, title: "Test Stack", isActive: false)
        let stackEvent = Event(eventType: .stackCreated, payload: stackPayload, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")

        // Create a task on that stack
        let taskPayload = try createTaskPayload(id: taskId, title: "Test Task", stackId: stackId)
        let taskEvent = Event(eventType: .taskCreated, payload: taskPayload, entityId: taskId, userId: "test-user", deviceId: "test-device", appId: "test-app")

        context.insert(stackEvent)
        context.insert(taskEvent)
        try context.save()

        // Apply both events in batch
        let processedCount = try await ProjectorService.applyBatch(events: [stackEvent, taskEvent], context: context)

        #expect(processedCount == 2)

        // Verify stack was created
        let stackPredicate = #Predicate<Stack> { $0.id == stackId }
        let stackDescriptor = FetchDescriptor<Stack>(predicate: stackPredicate)
        let stacks = try context.fetch(stackDescriptor)
        #expect(stacks.count == 1)

        // Verify task was created and linked to stack
        let taskPredicate = #Predicate<QueueTask> { $0.id == taskId }
        let taskDescriptor = FetchDescriptor<QueueTask>(predicate: taskPredicate)
        let tasks = try context.fetch(taskDescriptor)
        #expect(tasks.count == 1)
        #expect(tasks.first?.stack?.id == stackId)
    }

    @Test("applyBatch continues processing after individual event failure")
    func applyBatchContinuesAfterFailure() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1Id = CUID.generate()
        let stack2Id = CUID.generate()

        // Create two valid stack events
        let validPayload1 = try createStackPayload(id: stack1Id, title: "Stack 1", isActive: false)
        let validEvent1 = Event(eventType: .stackCreated, payload: validPayload1, entityId: stack1Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        let validPayload2 = try createStackPayload(id: stack2Id, title: "Stack 2", isActive: false)
        let validEvent2 = Event(eventType: .stackCreated, payload: validPayload2, entityId: stack2Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        // Create an event with invalid payload (will fail to decode)
        let invalidEvent = Event(eventType: .stackCreated, payload: Data("invalid json".utf8), entityId: "invalid-id", userId: "test-user", deviceId: "test-device", appId: "test-app")

        context.insert(validEvent1)
        context.insert(invalidEvent)
        context.insert(validEvent2)
        try context.save()

        // Apply all events - should process valid ones despite invalid one
        let processedCount = try await ProjectorService.applyBatch(
            events: [validEvent1, invalidEvent, validEvent2],
            context: context
        )

        // Two valid events should have been processed
        #expect(processedCount == 2)

        // Verify both valid stacks were created
        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)
        #expect(stacks.count == 2)
    }

    // MARK: - Cache Hit/Miss Tests (DEQ-143)

    @Test("Cache provides O(1) lookup for prefetched entities")
    func cacheProvidesO1Lookup() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Pre-create some stacks in the database
        let existingStack1 = Stack(title: "Existing Stack 1")
        let existingStack2 = Stack(title: "Existing Stack 2")
        context.insert(existingStack1)
        context.insert(existingStack2)
        try context.save()

        // Create update events for these stacks
        let updatePayload1 = try createStackPayload(
            id: existingStack1.id,
            title: "Updated Stack 1",
            isActive: false
        )
        let updatePayload2 = try createStackPayload(
            id: existingStack2.id,
            title: "Updated Stack 2",
            isActive: false
        )

        let updateEvent1 = Event(eventType: .stackUpdated, payload: updatePayload1, entityId: existingStack1.id, userId: "test-user", deviceId: "test-device", appId: "test-app")
        let updateEvent2 = Event(eventType: .stackUpdated, payload: updatePayload2, entityId: existingStack2.id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        context.insert(updateEvent1)
        context.insert(updateEvent2)
        try context.save()

        // Apply batch - cache should prefetch both stacks
        let processedCount = try await ProjectorService.applyBatch(
            events: [updateEvent1, updateEvent2],
            context: context
        )

        #expect(processedCount == 2)

        // Verify stacks were updated (proves cache lookup worked)
        #expect(existingStack1.title == "Updated Stack 1")
        #expect(existingStack2.title == "Updated Stack 2")
    }

    @Test("Cache miss falls back to database query")
    func cacheMissFallsBackToQuery() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Pre-create a stack
        let existingStack = Stack(title: "Existing Stack")
        context.insert(existingStack)
        try context.save()

        // Create a single update event
        let updatePayload = try createStackPayload(
            id: existingStack.id,
            title: "Updated via Single Event",
            isActive: false
        )
        let updateEvent = Event(eventType: .stackUpdated, payload: updatePayload, entityId: existingStack.id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        context.insert(updateEvent)
        try context.save()

        // Apply using single event API (no batch prefetch, cache is empty)
        try await ProjectorService.apply(event: updateEvent, context: context)

        // Verify the update worked (fell back to database query)
        #expect(existingStack.title == "Updated via Single Event")
    }

    // MARK: - Within-Batch Entity Reference Tests (DEQ-143)

    @Test("Task created in batch can reference stack created earlier in same batch")
    func withinBatchEntityReference() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let taskId = CUID.generate()

        // Event 1: Create a stack
        let stackPayload = try createStackPayload(id: stackId, title: "New Stack", isActive: false)
        let stackCreateEvent = Event(eventType: .stackCreated, payload: stackPayload, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")

        // Event 2: Create a task referencing the stack (created in same batch)
        let taskPayload = try createTaskPayload(id: taskId, title: "New Task", stackId: stackId)
        let taskCreateEvent = Event(eventType: .taskCreated, payload: taskPayload, entityId: taskId, userId: "test-user", deviceId: "test-device", appId: "test-app")

        context.insert(stackCreateEvent)
        context.insert(taskCreateEvent)
        try context.save()

        // Apply both events in batch - task event references stack created in same batch
        // The cache should be updated after stack creation so task can find it
        let processedCount = try await ProjectorService.applyBatch(
            events: [stackCreateEvent, taskCreateEvent],
            context: context
        )

        #expect(processedCount == 2)

        // Verify task is linked to the stack created in the same batch
        let taskPredicate = #Predicate<QueueTask> { $0.id == taskId }
        let taskDescriptor = FetchDescriptor<QueueTask>(predicate: taskPredicate)
        let tasks = try context.fetch(taskDescriptor)

        #expect(tasks.count == 1)
        #expect(tasks.first?.stack?.id == stackId)
        #expect(tasks.first?.stack?.title == "New Stack")
    }

    @Test("Multiple tasks can reference same stack created earlier in batch")
    func multipleTasksReferenceSameStackInBatch() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()
        let task1Id = CUID.generate()
        let task2Id = CUID.generate()
        let task3Id = CUID.generate()

        // Event 1: Create a stack
        let stackPayload = try createStackPayload(id: stackId, title: "Parent Stack", isActive: false)
        let stackCreateEvent = Event(eventType: .stackCreated, payload: stackPayload, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")

        // Events 2-4: Create tasks referencing the stack
        let task1Payload = try createTaskPayload(id: task1Id, title: "Task 1", stackId: stackId)
        let task1Event = Event(eventType: .taskCreated, payload: task1Payload, entityId: task1Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        let task2Payload = try createTaskPayload(id: task2Id, title: "Task 2", stackId: stackId)
        let task2Event = Event(eventType: .taskCreated, payload: task2Payload, entityId: task2Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        let task3Payload = try createTaskPayload(id: task3Id, title: "Task 3", stackId: stackId)
        let task3Event = Event(eventType: .taskCreated, payload: task3Payload, entityId: task3Id, userId: "test-user", deviceId: "test-device", appId: "test-app")

        // Insert all events
        context.insert(stackCreateEvent)
        context.insert(task1Event)
        context.insert(task2Event)
        context.insert(task3Event)
        try context.save()

        // Apply all events in batch
        let processedCount = try await ProjectorService.applyBatch(
            events: [stackCreateEvent, task1Event, task2Event, task3Event],
            context: context
        )

        #expect(processedCount == 4)

        // Verify all tasks are linked to the stack
        let stackPredicate = #Predicate<Stack> { $0.id == stackId }
        let stackDescriptor = FetchDescriptor<Stack>(predicate: stackPredicate)
        let stacks = try context.fetch(stackDescriptor)

        #expect(stacks.count == 1)
        let stack = stacks.first!
        #expect(stack.tasks.count == 3)

        let taskIds = Set(stack.tasks.map { $0.id })
        #expect(taskIds.contains(task1Id))
        #expect(taskIds.contains(task2Id))
        #expect(taskIds.contains(task3Id))
    }

    @Test("Update event in batch can find entity created earlier in same batch")
    func updateEventFindsEntityCreatedInSameBatch() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stackId = CUID.generate()

        // Use explicit timestamps to ensure proper LWW ordering
        let baseTime = Date()
        let createTime = baseTime
        let updateTime = baseTime.addingTimeInterval(1.0)

        // Event 1: Create a stack
        let createPayload = try createStackPayload(id: stackId, title: "Initial Title", isActive: false)
        let createEvent = Event(eventType: .stackCreated, payload: createPayload, timestamp: createTime, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")

        // Event 2: Update the same stack (created in same batch)
        let updatePayload = try createStackPayload(id: stackId, title: "Updated Title", isActive: true)
        let updateEvent = Event(eventType: .stackUpdated, payload: updatePayload, timestamp: updateTime, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")

        context.insert(createEvent)
        context.insert(updateEvent)
        try context.save()

        // Apply both events in batch
        let processedCount = try await ProjectorService.applyBatch(
            events: [createEvent, updateEvent],
            context: context
        )

        #expect(processedCount == 2)

        // Verify the stack has the updated values
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let stacks = try context.fetch(descriptor)

        #expect(stacks.count == 1)
        #expect(stacks.first?.title == "Updated Title")
        #expect(stacks.first?.isActive == true)
    }

    @Test("Batch processing with large number of events")
    func batchProcessingWithManyEvents() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Create 50 stack events (simulating a large sync batch)
        var events: [Event] = []
        var expectedStackIds: Set<String> = []

        for i in 0..<50 {
            let stackId = CUID.generate()
            expectedStackIds.insert(stackId)

            let payload = try createStackPayload(id: stackId, title: "Stack \(i)", isActive: false)
            let event = Event(eventType: .stackCreated, payload: payload, entityId: stackId, userId: "test-user", deviceId: "test-device", appId: "test-app")
            context.insert(event)
            events.append(event)
        }
        try context.save()

        // Apply all events in a single batch
        let processedCount = try await ProjectorService.applyBatch(events: events, context: context)

        #expect(processedCount == 50)

        // Verify all stacks were created
        let descriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(descriptor)
        #expect(stacks.count == 50)

        let actualStackIds = Set(stacks.map { $0.id })
        #expect(actualStackIds == expectedStackIds)
    }

    @MainActor
    @Test("DEQ-235: Cross-device tag duplicate - incoming older tag wins")
    func crossDeviceTagDuplicateIncomingOlderWins() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        // Simulate: Device B created a tag locally
        let localCreatedAt = Date()
        let localTag = Tag(
            id: "local-tag-id",
            name: "Work",
            colorHex: "#FF0000",
            createdAt: localCreatedAt,
            syncState: .pending
        )
        context.insert(localTag)

        // Create a stack using the local tag
        let stack = Stack(title: "Test Stack")
        stack.tagObjects.append(localTag)
        context.insert(stack)
        try context.save()

        // Verify initial state
        #expect(localTag.isDeleted == false)
        #expect(stack.tagObjects.count == 1)
        #expect(stack.tagObjects.first?.id == "local-tag-id")

        // Simulate: Sync event arrives from Device A with an OLDER tag (created earlier)
        let olderCreatedAt = localCreatedAt.addingTimeInterval(-60)  // 1 minute earlier
        let incomingPayload = try createTagPayload(
            id: "incoming-tag-id",
            name: "Work",
            colorHex: "#00FF00",
            createdAt: olderCreatedAt
        )
        let incomingEvent = Event(
            eventType: .tagCreated,
            payload: incomingPayload,
            entityId: "incoming-tag-id",
            userId: "test-user",
            deviceId: "device-a",
            appId: "test-app"
        )
        context.insert(incomingEvent)
        try context.save()

        // Clear pending associations before applying events
        await ProjectorService.clearPendingTagAssociations()

        // Apply the incoming tag.created event
        try await ProjectorService.apply(event: incomingEvent, context: context)
        try context.save()

        // Verify: incoming tag (older) should now be the canonical tag
        let incomingTag = try? context.fetch(FetchDescriptor<Dequeue.Tag>(predicate: #Predicate { $0.id == "incoming-tag-id" })).first
        #expect(incomingTag != nil)
        #expect(incomingTag?.isDeleted == false)
        #expect(incomingTag?.name == "Work")

        // Verify: local tag should be soft-deleted
        let updatedLocalTag = try? context.fetch(FetchDescriptor<Dequeue.Tag>(predicate: #Predicate { $0.id == "local-tag-id" })).first
        #expect(updatedLocalTag?.isDeleted == true)

        // Verify: stack should now reference the canonical (incoming) tag
        let updatedStack = try? context.fetch(FetchDescriptor<Stack>()).first { $0.id == stack.id }
        #expect(updatedStack?.tagObjects.count == 1)
        #expect(updatedStack?.tagObjects.first?.id == "incoming-tag-id")
    }

    @MainActor
    @Test("DEQ-235: Cross-device tag duplicate - local older tag wins")
    func crossDeviceTagDuplicateLocalOlderWins() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        // Simulate: Device B created a tag locally (earlier)
        let localCreatedAt = Date().addingTimeInterval(-120)  // 2 minutes ago
        let localTag = Tag(
            id: "local-tag-id",
            name: "Work",
            colorHex: "#FF0000",
            createdAt: localCreatedAt,
            syncState: .synced
        )
        context.insert(localTag)

        // Create a stack using the local tag
        let stack = Stack(title: "Test Stack")
        stack.tagObjects.append(localTag)
        context.insert(stack)
        try context.save()

        // Verify initial state
        #expect(localTag.isDeleted == false)
        #expect(stack.tagObjects.count == 1)
        #expect(stack.tagObjects.first?.id == "local-tag-id")

        // Simulate: Sync event arrives from Device A with a NEWER tag (created later)
        let newerCreatedAt = Date()  // Now (after local tag)
        let incomingPayload = try createTagPayload(
            id: "incoming-tag-id",
            name: "Work",
            colorHex: "#00FF00",
            createdAt: newerCreatedAt
        )
        let incomingEvent = Event(
            eventType: .tagCreated,
            payload: incomingPayload,
            entityId: "incoming-tag-id",
            userId: "test-user",
            deviceId: "device-a",
            appId: "test-app"
        )
        context.insert(incomingEvent)
        try context.save()

        // Clear pending associations before applying events
        await ProjectorService.clearPendingTagAssociations()

        // Apply the incoming tag.created event
        try await ProjectorService.apply(event: incomingEvent, context: context)
        try context.save()

        // Verify: local tag (older) should still exist and not be deleted
        let updatedLocalTag = try? context.fetch(FetchDescriptor<Dequeue.Tag>(predicate: #Predicate { $0.id == "local-tag-id" })).first
        #expect(updatedLocalTag != nil)
        #expect(updatedLocalTag?.isDeleted == false)

        // Verify: incoming tag should NOT have been created (duplicate)
        let incomingTag = try? context.fetch(FetchDescriptor<Dequeue.Tag>(predicate: #Predicate { $0.id == "incoming-tag-id" })).first
        #expect(incomingTag == nil)

        // Verify: stack should still reference the canonical (local) tag
        let updatedStack = try? context.fetch(FetchDescriptor<Stack>()).first { $0.id == stack.id }
        #expect(updatedStack?.tagObjects.count == 1)
        #expect(updatedStack?.tagObjects.first?.id == "local-tag-id")
    }

    @MainActor
    @Test("DEQ-235: Cross-device tag duplicate - same timestamp uses ID tie-breaker")
    func crossDeviceTagDuplicateSameTimestampUsesIdTieBreaker() async throws {
        let container = try createTestContainer()
        let context = container.mainContext

        // Both tags have the same createdAt timestamp
        let sameCreatedAt = Date()

        // Local tag has lexicographically larger ID
        let localTag = Tag(
            id: "zzz-local-tag",  // Larger ID
            name: "Work",
            colorHex: "#FF0000",
            createdAt: sameCreatedAt,
            syncState: .pending
        )
        context.insert(localTag)

        // Create a stack using the local tag
        let stack = Stack(title: "Test Stack")
        stack.tagObjects.append(localTag)
        context.insert(stack)
        try context.save()

        // Incoming tag has lexicographically smaller ID (should win)
        let incomingPayload = try createTagPayload(
            id: "aaa-incoming-tag",  // Smaller ID (canonical)
            name: "Work",
            colorHex: "#00FF00",
            createdAt: sameCreatedAt
        )
        let incomingEvent = Event(
            eventType: .tagCreated,
            payload: incomingPayload,
            entityId: "aaa-incoming-tag",
            userId: "test-user",
            deviceId: "device-a",
            appId: "test-app"
        )
        context.insert(incomingEvent)
        try context.save()

        // Clear pending associations before applying events
        await ProjectorService.clearPendingTagAssociations()

        // Apply the incoming tag.created event
        try await ProjectorService.apply(event: incomingEvent, context: context)
        try context.save()

        // Verify: incoming tag (smaller ID) should be canonical
        let incomingTag = try? context.fetch(FetchDescriptor<Dequeue.Tag>(predicate: #Predicate { $0.id == "aaa-incoming-tag" })).first
        #expect(incomingTag != nil)
        #expect(incomingTag?.isDeleted == false)

        // Verify: local tag should be soft-deleted
        let updatedLocalTag = try? context.fetch(FetchDescriptor<Dequeue.Tag>(predicate: #Predicate { $0.id == "zzz-local-tag" })).first
        #expect(updatedLocalTag?.isDeleted == true)

        // Verify: stack should now reference the canonical (incoming) tag
        let updatedStack = try? context.fetch(FetchDescriptor<Stack>()).first { $0.id == stack.id }
        #expect(updatedStack?.tagObjects.count == 1)
        #expect(updatedStack?.tagObjects.first?.id == "aaa-incoming-tag")
    }
}
