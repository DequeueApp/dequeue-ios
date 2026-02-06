//
//  EventServiceTests.swift
//  DequeueTests
//
//  Tests for EventService - event storage and retrieval
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container for EventService tests
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Event.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        Attachment.self,
        configurations: config
    )
}

/// Creates a test attachment event payload
@MainActor
private func makeAttachmentPayload(
    attachmentId: String,
    parentId: String,
    parentType: ParentType = .stack,
    filename: String = "test.pdf"
) throws -> Data {
    let payload = AttachmentAddedPayload(
        attachmentId: attachmentId,
        parentId: parentId,
        parentType: parentType.rawValue,
        state: AttachmentState(
            id: attachmentId,
            parentId: parentId,
            parentType: parentType.rawValue,
            filename: filename,
            mimeType: "application/pdf",
            sizeBytes: 1_024,
            url: nil,
            createdAt: Int64(Date().timeIntervalSince1970 * 1_000),
            updatedAt: Int64(Date().timeIntervalSince1970 * 1_000),
            deleted: false
        )
    )
    return try JSONEncoder().encode(payload)
}

@Suite("EventService FetchByIds Tests", .serialized)
@MainActor
struct EventServiceFetchByIdsTests {
    @Test("fetchEventsByIds returns events matching provided IDs")
    @MainActor
    func fetchEventsByIdsReturnsMatchingEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create test events with specific IDs
        let event1 = Event(
            id: "event-1",
            type: "stack.created",
            payload: try JSONEncoder().encode(["stackId": "123"]),
            timestamp: Date(),
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        let event2 = Event(
            id: "event-2",
            type: "task.created",
            payload: try JSONEncoder().encode(["taskId": "456"]),
            timestamp: Date(),
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        let event3 = Event(
            id: "event-3",
            type: "stack.updated",
            payload: try JSONEncoder().encode(["stackId": "123"]),
            timestamp: Date(),
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )

        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        let eventService = EventService.readOnly(modelContext: context)

        // Fetch events by specific IDs
        let requestedIds = ["event-1", "event-3"]
        let fetchedEvents = try eventService.fetchEventsByIds(requestedIds)

        #expect(fetchedEvents.count == 2)
        let fetchedIds = Set(fetchedEvents.map { $0.id })
        #expect(fetchedIds.contains("event-1"))
        #expect(fetchedIds.contains("event-3"))
        #expect(!fetchedIds.contains("event-2"))
    }

    @Test("fetchEventsByIds returns empty array when no matching events")
    @MainActor
    func fetchEventsByIdsReturnsEmptyArrayWhenNoMatches() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create test event
        let event = Event(
            id: "event-1",
            type: "stack.created",
            payload: try JSONEncoder().encode(["stackId": "123"]),
            timestamp: Date(),
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)
        try context.save()

        let eventService = EventService.readOnly(modelContext: context)

        // Try to fetch non-existent events
        let fetchedEvents = try eventService.fetchEventsByIds(["non-existent-1", "non-existent-2"])

        #expect(fetchedEvents.isEmpty)
    }

    @Test("fetchEventsByIds returns all matching events from large set")
    @MainActor
    func fetchEventsByIdsHandlesLargeSet() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create 100 test events
        for index in 1...100 {
            let event = Event(
                id: "event-\(index)",
                type: "stack.created",
                payload: try JSONEncoder().encode(["index": index]),
                timestamp: Date(),
                userId: "test-user",
                deviceId: "test-device",
                appId: "test-app"
            )
            context.insert(event)
        }
        try context.save()

        let eventService = EventService.readOnly(modelContext: context)

        // Fetch specific subset
        let requestedIds = (1...10).map { "event-\($0)" }
        let fetchedEvents = try eventService.fetchEventsByIds(requestedIds)

        #expect(fetchedEvents.count == 10)

        let fetchedIds = Set(fetchedEvents.map { $0.id })
        for id in requestedIds {
            #expect(fetchedIds.contains(id))
        }
    }
}

// MARK: - Stack History Tests

@Suite("EventService StackHistory Tests", .serialized)
@MainActor
struct EventServiceStackHistoryTests {
    @Test("fetchStackHistoryWithRelated returns stack events")
    @MainActor
    func fetchStackHistoryWithRelatedReturnsStackEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack
        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        // Create events for this stack
        let stackEvent = Event(
            id: "stack-event-1",
            type: "stack.created",
            payload: try JSONEncoder().encode(["stackId": stack.id]),
            timestamp: Date(),
            entityId: stack.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(stackEvent)

        // Create an unrelated event
        let unrelatedEvent = Event(
            id: "unrelated-event",
            type: "stack.created",
            payload: try JSONEncoder().encode(["stackId": "other-stack"]),
            timestamp: Date(),
            entityId: "other-stack",
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(unrelatedEvent)

        try context.save()

        let eventService = EventService.readOnly(modelContext: context)
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        #expect(events.count == 1)
        #expect(events.first?.id == "stack-event-1")
    }

    @Test("fetchStackHistoryWithRelated includes task events")
    @MainActor
    func fetchStackHistoryWithRelatedIncludesTaskEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack with a task
        let stack = Stack(title: "Test Stack")
        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(stack)
        context.insert(task)

        // Create events for stack and task
        let stackEvent = Event(
            id: "stack-event",
            type: "stack.created",
            payload: try JSONEncoder().encode(["stackId": stack.id]),
            timestamp: Date().addingTimeInterval(-100),
            entityId: stack.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        let taskEvent = Event(
            id: "task-event",
            type: "task.created",
            payload: try JSONEncoder().encode(["taskId": task.id]),
            timestamp: Date(),
            entityId: task.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(stackEvent)
        context.insert(taskEvent)

        try context.save()

        let eventService = EventService.readOnly(modelContext: context)
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        #expect(events.count == 2)
        let eventIds = Set(events.map { $0.id })
        #expect(eventIds.contains("stack-event"))
        #expect(eventIds.contains("task-event"))
    }

    @Test("fetchStackHistoryWithRelated includes attachment events by parentId")
    @MainActor
    func fetchStackHistoryWithRelatedIncludesAttachmentEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack
        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        // Create an attachment event for this stack
        let attachmentEvent = Event(
            id: "attachment-event",
            type: "attachment.added",
            payload: try makeAttachmentPayload(
                attachmentId: "attach-1",
                parentId: stack.id,
                parentType: .stack
            ),
            timestamp: Date(),
            entityId: "attach-1",
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(attachmentEvent)

        // Create an attachment event for a different stack
        let unrelatedAttachment = Event(
            id: "unrelated-attachment",
            type: "attachment.added",
            payload: try makeAttachmentPayload(
                attachmentId: "attach-2",
                parentId: "other-stack",
                parentType: .stack
            ),
            timestamp: Date(),
            entityId: "attach-2",
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(unrelatedAttachment)

        try context.save()

        let eventService = EventService.readOnly(modelContext: context)
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        #expect(events.count == 1)
        #expect(events.first?.id == "attachment-event")
    }

    @Test("fetchStackHistoryWithRelated includes task attachment events")
    @MainActor
    func fetchStackHistoryWithRelatedIncludesTaskAttachments() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create a stack with a task
        let stack = Stack(title: "Test Stack")
        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(stack)
        context.insert(task)

        // Create an attachment event for the task (not directly for the stack)
        let taskAttachmentEvent = Event(
            id: "task-attachment-event",
            type: "attachment.added",
            payload: try makeAttachmentPayload(
                attachmentId: "attach-task",
                parentId: task.id,
                parentType: .task
            ),
            timestamp: Date(),
            entityId: "attach-task",
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(taskAttachmentEvent)

        try context.save()

        let eventService = EventService.readOnly(modelContext: context)
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        #expect(events.count == 1)
        #expect(events.first?.id == "task-attachment-event")
    }

    @Test("fetchStackHistoryWithRelated returns events sorted by timestamp descending")
    @MainActor
    func fetchStackHistoryWithRelatedReturnsSortedEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        // Create events at different timestamps
        let now = Date()
        let event1 = Event(
            id: "oldest",
            type: "stack.created",
            payload: Data(),
            timestamp: now.addingTimeInterval(-200),
            entityId: stack.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        let event2 = Event(
            id: "middle",
            type: "stack.updated",
            payload: Data(),
            timestamp: now.addingTimeInterval(-100),
            entityId: stack.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        let event3 = Event(
            id: "newest",
            type: "stack.updated",
            payload: Data(),
            timestamp: now,
            entityId: stack.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )

        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        let eventService = EventService.readOnly(modelContext: context)
        let events = try eventService.fetchStackHistoryWithRelated(for: stack)

        #expect(events.count == 3)
        #expect(events[0].id == "newest")
        #expect(events[1].id == "middle")
        #expect(events[2].id == "oldest")
    }
}

// MARK: - Task History Tests

@Suite("EventService TaskHistory Tests", .serialized)
@MainActor
struct EventServiceTaskHistoryTests {
    @Test("fetchTaskHistoryWithRelated returns task events")
    @MainActor
    func fetchTaskHistoryWithRelatedReturnsTaskEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack")
        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(stack)
        context.insert(task)

        let taskEvent = Event(
            id: "task-event",
            type: "task.created",
            payload: try JSONEncoder().encode(["taskId": task.id]),
            timestamp: Date(),
            entityId: task.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(taskEvent)

        // Unrelated task event
        let unrelatedEvent = Event(
            id: "unrelated-task-event",
            type: "task.created",
            payload: try JSONEncoder().encode(["taskId": "other-task"]),
            timestamp: Date(),
            entityId: "other-task",
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(unrelatedEvent)

        try context.save()

        let eventService = EventService.readOnly(modelContext: context)
        let events = try eventService.fetchTaskHistoryWithRelated(for: task)

        #expect(events.count == 1)
        #expect(events.first?.id == "task-event")
    }

    @Test("fetchTaskHistoryWithRelated includes attachment events")
    @MainActor
    func fetchTaskHistoryWithRelatedIncludesAttachmentEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack")
        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(stack)
        context.insert(task)

        // Attachment for this task
        let attachmentEvent = Event(
            id: "task-attachment",
            type: "attachment.added",
            payload: try makeAttachmentPayload(
                attachmentId: "attach-1",
                parentId: task.id,
                parentType: .task
            ),
            timestamp: Date(),
            entityId: "attach-1",
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(attachmentEvent)

        // Attachment for another task
        let unrelatedAttachment = Event(
            id: "other-attachment",
            type: "attachment.added",
            payload: try makeAttachmentPayload(
                attachmentId: "attach-2",
                parentId: "other-task",
                parentType: .task
            ),
            timestamp: Date(),
            entityId: "attach-2",
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(unrelatedAttachment)

        try context.save()

        let eventService = EventService.readOnly(modelContext: context)
        let events = try eventService.fetchTaskHistoryWithRelated(for: task)

        #expect(events.count == 1)
        #expect(events.first?.id == "task-attachment")
    }

    @Test("fetchTaskHistoryWithRelated excludes stack-level events")
    @MainActor
    func fetchTaskHistoryWithRelatedExcludesStackEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack")
        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(stack)
        context.insert(task)

        // Stack event (should NOT be included)
        let stackEvent = Event(
            id: "stack-event",
            type: "stack.updated",
            payload: Data(),
            timestamp: Date(),
            entityId: stack.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(stackEvent)

        // Task event (should be included)
        let taskEvent = Event(
            id: "task-event",
            type: "task.updated",
            payload: Data(),
            timestamp: Date(),
            entityId: task.id,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(taskEvent)

        try context.save()

        let eventService = EventService.readOnly(modelContext: context)
        let events = try eventService.fetchTaskHistoryWithRelated(for: task)

        #expect(events.count == 1)
        #expect(events.first?.id == "task-event")
    }
}

// MARK: - AI Task Completion Tests (DEQ-57)

@Suite("EventService AI Task Completion Tests", .serialized)
@MainActor
struct EventServiceAICompletionTests {
    @Test("recordTaskAICompleted creates task.aiCompleted event")
    @MainActor
    func recordTaskAICompletedCreatesEvent() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack")
        let task = QueueTask(title: "AI Task", stack: stack)
        context.insert(stack)
        context.insert(task)
        try context.save()

        let eventService = EventService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        try await eventService.recordTaskAICompleted(
            task,
            aiAgentId: "agent-007",
            aiAgentName: "TestBot",
            resultSummary: "Task completed successfully"
        )
        try context.save()

        let events = try eventService.fetchHistory(for: task.id)
        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.eventType == .taskAICompleted)
        #expect(event.entityId == task.id)
    }

    @Test("recordTaskAICompleted includes AI actor metadata")
    @MainActor
    func recordTaskAICompletedIncludesAIMetadata() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack")
        let task = QueueTask(title: "AI Task", stack: stack)
        context.insert(stack)
        context.insert(task)
        try context.save()

        let eventService = EventService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let agentId = "agent-123"
        try await eventService.recordTaskAICompleted(
            task,
            aiAgentId: agentId,
            aiAgentName: "Ada",
            resultSummary: "Completed via AI"
        )
        try context.save()

        let events = try eventService.fetchHistory(for: task.id)
        let event = try #require(events.first)

        // Check actor metadata
        let metadata = try event.actorMetadata()
        #expect(metadata?.actorType == .ai)
        #expect(metadata?.actorId == agentId)
        #expect(event.isFromAI == true)
        #expect(event.isFromHuman == false)
    }

    @Test("recordTaskAICompleted payload includes agent details and result")
    @MainActor
    func recordTaskAICompletedPayloadIncludesDetails() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Test Stack")
        let task = QueueTask(title: "AI Task", stack: stack)
        context.insert(stack)
        context.insert(task)
        try context.save()

        let eventService = EventService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let agentId = "agent-456"
        let agentName = "CodeBot"
        let summary = "Refactored code and added tests"

        try await eventService.recordTaskAICompleted(
            task,
            aiAgentId: agentId,
            aiAgentName: agentName,
            resultSummary: summary
        )
        try context.save()

        let events = try eventService.fetchHistory(for: task.id)
        let event = try #require(events.first)

        let payload = try event.decodePayload(TaskAICompletedPayload.self)
        #expect(payload.taskId == task.id)
        #expect(payload.stackId == stack.id)
        #expect(payload.aiAgentId == agentId)
        #expect(payload.aiAgentName == agentName)
        #expect(payload.resultSummary == summary)
        #expect(payload.fullState.id == task.id)
    }
}
