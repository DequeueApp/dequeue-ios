//
//  SyncTypesTests.swift
//  DequeueTests
//
//  Tests for SyncTypes: projection models, WebSocket messages, and errors.
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - EventData Tests

@Suite("EventData Tests")
@MainActor
struct EventDataTests {
    @Test("EventData initializes with all fields")
    func eventDataInitWithAllFields() {
        let now = Date()
        let payload = Data("{\"key\":\"value\"}".utf8)

        let event = EventData(
            id: "evt-123",
            timestamp: now,
            type: "stack.created",
            payload: payload,
            metadata: nil,
            userId: "user-456",
            deviceId: "device-789",
            appId: "app-001",
            payloadVersion: 2
        )

        #expect(event.id == "evt-123")
        #expect(event.timestamp == now)
        #expect(event.type == "stack.created")
        #expect(event.payload == payload)
        #expect(event.metadata == nil)
        #expect(event.userId == "user-456")
        #expect(event.deviceId == "device-789")
        #expect(event.appId == "app-001")
        #expect(event.payloadVersion == 2)
    }

    @Test("EventData stores empty payload")
    func eventDataEmptyPayload() {
        let event = EventData(
            id: "evt-empty",
            timestamp: Date(),
            type: "task.created",
            payload: Data(),
            metadata: nil,
            userId: "u",
            deviceId: "d",
            appId: "a",
            payloadVersion: 1
        )

        #expect(event.payload.isEmpty)
        #expect(event.id == "evt-empty")
    }

    @Test("EventData stores actor metadata (DEQ-55)")
    func eventDataWithActorMetadata() throws {
        let metadata = try JSONEncoder().encode(EventMetadata.ai(agentId: "ada"))

        let event = EventData(
            id: "evt-ai",
            timestamp: Date(),
            type: "task.completed",
            payload: Data("{\"taskId\":\"t1\"}".utf8),
            metadata: metadata,
            userId: "user-1",
            deviceId: "api-dequeue",
            appId: "app-1",
            payloadVersion: 2
        )

        #expect(event.metadata != nil)
        let decoded = try JSONDecoder().decode(EventMetadata.self, from: event.metadata!)
        #expect(decoded.actorType == .ai)
        #expect(decoded.actorId == "ada")
    }
}

// MARK: - PullResult Tests

@Suite("PullResult Tests")
@MainActor
struct PullResultTests {
    @Test("PullResult with all fields")
    func pullResultWithAllFields() {
        let result = PullResult(
            eventsProcessed: 42,
            nextCheckpoint: "2026-02-20T12:00:00Z",
            hasMore: true
        )

        #expect(result.eventsProcessed == 42)
        #expect(result.nextCheckpoint == "2026-02-20T12:00:00Z")
        #expect(result.hasMore == true)
    }

    @Test("PullResult with nil checkpoint")
    func pullResultWithNilCheckpoint() {
        let result = PullResult(
            eventsProcessed: 0,
            nextCheckpoint: nil,
            hasMore: false
        )

        #expect(result.eventsProcessed == 0)
        #expect(result.nextCheckpoint == nil)
        #expect(result.hasMore == false)
    }
}

// MARK: - ProjectionResponse Tests

@Suite("ProjectionResponse Tests")
@MainActor
struct ProjectionResponseTests {
    @Test("ProjectionResponse decodes with pagination")
    func decodesWithPagination() throws {
        let json = """
        {
            "data": [
                {
                    "id": "stack-1",
                    "title": "My Stack",
                    "status": "active",
                    "isActive": true,
                    "isDeleted": false,
                    "tags": ["swift", "ios"],
                    "createdAt": 1708000000,
                    "updatedAt": 1708000100
                }
            ],
            "pagination": {
                "nextCursor": "cursor-abc",
                "hasMore": true,
                "limit": 50
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(
            ProjectionResponse<StackProjection>.self,
            from: json
        )

        #expect(response.data.count == 1)
        #expect(response.data[0].id == "stack-1")
        #expect(response.data[0].title == "My Stack")
        #expect(response.pagination?.nextCursor == "cursor-abc")
        #expect(response.pagination?.hasMore == true)
        #expect(response.pagination?.limit == 50)
    }

    @Test("ProjectionResponse decodes without pagination")
    func decodesWithoutPagination() throws {
        let json = """
        {
            "data": []
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(
            ProjectionResponse<TaskProjection>.self,
            from: json
        )

        #expect(response.data.isEmpty)
        #expect(response.pagination == nil)
    }
}

// MARK: - StackProjection Tests

@Suite("StackProjection Tests")
@MainActor
struct StackProjectionTests {
    @Test("StackProjection decodes with all fields using API field names")
    func decodesWithAllFields() throws {
        let json = """
        {
            "id": "stack-abc",
            "title": "Groceries",
            "description": "Weekly shopping list",
            "status": "active",
            "isActive": true,
            "isDeleted": false,
            "arcId": "arc-123",
            "tags": ["errands", "weekly"],
            "sortOrder": 3,
            "activeTaskId": "task-xyz",
            "startAt": 1708000000,
            "dueAt": 1708086400,
            "createdAt": 1707900000,
            "updatedAt": 1708000000
        }
        """.data(using: .utf8)!

        let stack = try JSONDecoder().decode(
            StackProjection.self, from: json
        )

        #expect(stack.id == "stack-abc")
        #expect(stack.title == "Groceries")
        #expect(stack.description == "Weekly shopping list")
        #expect(stack.status == "active")
        #expect(stack.isActive == true)
        #expect(stack.isDeleted == false)
        #expect(stack.arcId == "arc-123")
        #expect(stack.tags == ["errands", "weekly"])
        #expect(stack.sortOrder == 3)
        #expect(stack.activeTaskId == "task-xyz")
        // CodingKeys maps JSON "startAt"/"dueAt" → model "startTime"/"dueTime"
        #expect(stack.startTime == 1_708_000_000)
        #expect(stack.dueTime == 1_708_086_400)
        #expect(stack.createdAt == 1_707_900_000)
        #expect(stack.updatedAt == 1_708_000_000)
    }

    @Test("StackProjection decodes without isDeleted (API omits it)")
    func decodesWithoutIsDeleted() throws {
        // API list endpoints filter WHERE is_deleted = false and don't include the field
        let json = """
        {
            "id": "stack-api",
            "title": "From API",
            "status": "active",
            "isActive": true,
            "tags": [],
            "sortOrder": 1,
            "startAt": null,
            "dueAt": null,
            "createdAt": 1707900000,
            "updatedAt": 1707900000
        }
        """.data(using: .utf8)!

        let stack = try JSONDecoder().decode(
            StackProjection.self, from: json
        )

        #expect(stack.id == "stack-api")
        #expect(stack.isDeleted == false)
        #expect(stack.sortOrder == 1)
        #expect(stack.activeTaskId == nil)
        #expect(stack.arcId == nil)
        #expect(stack.description == nil)
    }

    @Test("StackProjection decodes with minimal fields")
    func decodesWithMinimalFields() throws {
        let json = """
        {
            "id": "stack-min",
            "title": "Minimal",
            "status": "active",
            "isActive": true,
            "createdAt": 1707900000,
            "updatedAt": 1707900000
        }
        """.data(using: .utf8)!

        let stack = try JSONDecoder().decode(
            StackProjection.self, from: json
        )

        #expect(stack.id == "stack-min")
        #expect(stack.isDeleted == false)
        #expect(stack.sortOrder == 0)
        #expect(stack.activeTaskId == nil)
        #expect(stack.description == nil)
        #expect(stack.arcId == nil)
        #expect(stack.tags == nil)
        #expect(stack.startTime == nil)
        #expect(stack.dueTime == nil)
    }
}

// MARK: - TaskProjection Tests

@Suite("TaskProjection Tests")
@MainActor
struct TaskProjectionTests {
    @Test("TaskProjection decodes correctly")
    func decodesCorrectly() throws {
        let json = """
        {
            "id": "task-001",
            "stackId": "stack-abc",
            "title": "Buy milk",
            "notes": "Organic whole milk",
            "sortOrder": 0,
            "status": "pending",
            "isActive": true,
            "priority": 2,
            "blockedReason": null,
            "parentTaskId": null,
            "startAt": 1708000000,
            "dueAt": 1708086400,
            "completedAt": null,
            "createdAt": 1707900000,
            "updatedAt": 1708000000
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(
            TaskProjection.self, from: json
        )

        #expect(task.id == "task-001")
        #expect(task.stackId == "stack-abc")
        #expect(task.title == "Buy milk")
        #expect(task.notes == "Organic whole milk")
        #expect(task.sortOrder == 0)
        #expect(task.status == "pending")
        #expect(task.isActive == true)
        #expect(task.priority == 2)
        // CodingKeys maps JSON "startAt"/"dueAt" → model "startTime"/"dueTime"
        #expect(task.startTime == 1_708_000_000)
        #expect(task.dueTime == 1_708_086_400)
    }

    @Test("TaskProjection decodes with nil optional fields")
    func decodesWithNilOptionals() throws {
        let json = """
        {
            "id": "task-002",
            "stackId": "stack-abc",
            "title": "Simple task",
            "sortOrder": 1,
            "status": "completed",
            "isActive": false,
            "createdAt": 1707900000,
            "updatedAt": 1707900000
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(
            TaskProjection.self, from: json
        )

        #expect(task.notes == nil)
        #expect(task.startTime == nil)
        #expect(task.dueTime == nil)
    }
}

// MARK: - ArcProjection Tests

@Suite("ArcProjection Tests")
@MainActor
struct ArcProjectionTests {
    @Test("ArcProjection decodes correctly with API field names")
    func decodesCorrectly() throws {
        let json = """
        {
            "id": "arc-100",
            "title": "Q1 Sprint",
            "description": "First quarter deliverables",
            "status": "active",
            "colorHex": "#3498DB",
            "isDeleted": false,
            "sortOrder": 2,
            "startAt": 1707500000,
            "dueAt": 1708500000,
            "createdAt": 1707000000,
            "updatedAt": 1708000000
        }
        """.data(using: .utf8)!

        let arc = try JSONDecoder().decode(
            ArcProjection.self, from: json
        )

        #expect(arc.id == "arc-100")
        #expect(arc.title == "Q1 Sprint")
        #expect(arc.description == "First quarter deliverables")
        #expect(arc.status == "active")
        #expect(arc.color == "#3498DB")
        #expect(arc.isDeleted == false)
        #expect(arc.sortOrder == 2)
        #expect(arc.startTime == 1_707_500_000)
        #expect(arc.dueTime == 1_708_500_000)
        #expect(arc.createdAt == 1_707_000_000)
        #expect(arc.updatedAt == 1_708_000_000)
    }

    @Test("ArcProjection decodes without isDeleted (API omits it)")
    func decodesWithoutIsDeleted() throws {
        // API list endpoints filter WHERE is_deleted = false and don't include the field
        let json = """
        {
            "id": "arc-api",
            "title": "From API",
            "status": "completed",
            "colorHex": "#FF0000",
            "sortOrder": 5,
            "startAt": null,
            "dueAt": null,
            "createdAt": 1707000000,
            "updatedAt": 1707000000
        }
        """.data(using: .utf8)!

        let arc = try JSONDecoder().decode(
            ArcProjection.self, from: json
        )

        #expect(arc.id == "arc-api")
        #expect(arc.isDeleted == false)
        #expect(arc.status == "completed")
        #expect(arc.color == "#FF0000")
        #expect(arc.sortOrder == 5)
        #expect(arc.description == nil)
    }

    @Test("ArcProjection decodes with nil optionals")
    func decodesWithNilOptionals() throws {
        let json = """
        {
            "id": "arc-101",
            "title": "No extras",
            "createdAt": 1707000000,
            "updatedAt": 1707000000
        }
        """.data(using: .utf8)!

        let arc = try JSONDecoder().decode(
            ArcProjection.self, from: json
        )

        #expect(arc.description == nil)
        #expect(arc.color == nil)
        #expect(arc.isDeleted == false)
        #expect(arc.status == "active")
        #expect(arc.sortOrder == 0)
        #expect(arc.startTime == nil)
        #expect(arc.dueTime == nil)
    }
}

// MARK: - TagProjection Tests

@Suite("TagProjection Tests")
@MainActor
struct TagProjectionTests {
    @Test("TagProjection decodes correctly with colorHex mapping")
    func decodesCorrectly() throws {
        let json = """
        {
            "id": "tag-50",
            "name": "urgent",
            "colorHex": "#E74C3C",
            "createdAt": 1707500000,
            "updatedAt": 1707600000
        }
        """.data(using: .utf8)!

        let tag = try JSONDecoder().decode(
            TagProjection.self, from: json
        )

        #expect(tag.id == "tag-50")
        #expect(tag.name == "urgent")
        #expect(tag.color == "#E74C3C")
        #expect(tag.createdAt == 1_707_500_000)
        #expect(tag.updatedAt == 1_707_600_000)
    }

    @Test("TagProjection decodes with nil color")
    func decodesWithNilColor() throws {
        let json = """
        {
            "id": "tag-51",
            "name": "misc",
            "createdAt": 1707500000,
            "updatedAt": 1707500000
        }
        """.data(using: .utf8)!

        let tag = try JSONDecoder().decode(
            TagProjection.self, from: json
        )

        #expect(tag.color == nil)
        #expect(tag.updatedAt == 1_707_500_000)
    }
}

// MARK: - ReminderProjection Tests

@Suite("ReminderProjection Tests")
@MainActor
struct ReminderProjectionTests {
    @Test("ReminderProjection decodes with stack parent")
    func decodesWithStackParent() throws {
        let json = """
        {
            "id": "rem-10",
            "parentType": "stack",
            "parentId": "stack-abc",
            "remindAt": 1708100000,
            "status": "active",
            "createdAt": 1708000000,
            "updatedAt": 1708000000
        }
        """.data(using: .utf8)!

        let reminder = try JSONDecoder().decode(
            ReminderProjection.self, from: json
        )

        #expect(reminder.id == "rem-10")
        #expect(reminder.stackId == "stack-abc")
        #expect(reminder.arcId == nil)
        #expect(reminder.taskId == nil)
        #expect(reminder.triggerTime == 1_708_100_000)
        #expect(reminder.isDeleted == false)
        #expect(reminder.snoozedFrom == nil)
    }

    @Test("ReminderProjection decodes with task parent")
    func decodesWithTaskParent() throws {
        let json = """
        {
            "id": "rem-11",
            "parentType": "task",
            "parentId": "task-001",
            "remindAt": 1708200000,
            "status": "active",
            "createdAt": 1708000000,
            "updatedAt": 1708000000
        }
        """.data(using: .utf8)!

        let reminder = try JSONDecoder().decode(
            ReminderProjection.self, from: json
        )

        #expect(reminder.taskId == "task-001")
        #expect(reminder.stackId == nil)
        #expect(reminder.arcId == nil)
        #expect(reminder.isDeleted == false)
        #expect(reminder.snoozedFrom == nil)
    }

    @Test("ReminderProjection decodes with arc parent")
    func decodesWithArcParent() throws {
        let json = """
        {
            "id": "rem-12",
            "parentType": "arc",
            "parentId": "arc-100",
            "remindAt": 1708300000,
            "status": "deleted",
            "createdAt": 1708000000,
            "updatedAt": 1708000000
        }
        """.data(using: .utf8)!

        let reminder = try JSONDecoder().decode(
            ReminderProjection.self, from: json
        )

        #expect(reminder.arcId == "arc-100")
        #expect(reminder.stackId == nil)
        #expect(reminder.taskId == nil)
        #expect(reminder.isDeleted == true)
        #expect(reminder.snoozedFrom == nil)
    }

    @Test("ReminderProjection decodes snoozed reminder with snoozedFrom")
    func decodesSnoozedReminder() throws {
        let json = """
        {
            "id": "rem-13",
            "parentType": "stack",
            "parentId": "stack-xyz",
            "remindAt": 1708400000,
            "snoozedFrom": 1708100000,
            "status": "snoozed",
            "createdAt": 1708000000,
            "updatedAt": 1708300000
        }
        """.data(using: .utf8)!

        let reminder = try JSONDecoder().decode(
            ReminderProjection.self, from: json
        )

        #expect(reminder.id == "rem-13")
        #expect(reminder.stackId == "stack-xyz")
        #expect(reminder.snoozedFrom == 1_708_100_000)
        #expect(reminder.triggerTime == 1_708_400_000)
        #expect(reminder.isDeleted == false)
    }
}

// MARK: - WebSocket Stream Message Tests

@Suite("SyncStream Message Tests")
@MainActor
struct SyncStreamMessageTests {
    @Test("SyncStreamRequest encodes and decodes")
    func syncStreamRequestRoundtrip() throws {
        let request = SyncStreamRequest(
            type: "sync.stream.request",
            since: "2026-02-20T00:00:00Z"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(
            SyncStreamRequest.self, from: data
        )

        #expect(decoded.type == "sync.stream.request")
        #expect(decoded.since == "2026-02-20T00:00:00Z")
    }

    @Test("SyncStreamRequest encodes with nil since")
    func syncStreamRequestNilSince() throws {
        let request = SyncStreamRequest(
            type: "sync.stream.request",
            since: nil
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(
            SyncStreamRequest.self, from: data
        )

        #expect(decoded.since == nil)
    }

    @Test("SyncStreamStart encodes and decodes")
    func syncStreamStartRoundtrip() throws {
        let msg = SyncStreamStart(
            type: "sync.stream.start",
            totalEvents: 1_500
        )

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(
            SyncStreamStart.self, from: data
        )

        #expect(decoded.type == "sync.stream.start")
        #expect(decoded.totalEvents == 1_500)
    }

    @Test("SyncStreamBatch encodes and decodes")
    func syncStreamBatchRoundtrip() throws {
        let msg = SyncStreamBatch(
            type: "sync.stream.batch",
            batchIndex: 3,
            isLast: false
        )

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(
            SyncStreamBatch.self, from: data
        )

        #expect(decoded.type == "sync.stream.batch")
        #expect(decoded.batchIndex == 3)
        #expect(decoded.isLast == false)
    }

    @Test("SyncStreamBatch last batch flag")
    func syncStreamBatchLastBatch() throws {
        let msg = SyncStreamBatch(
            type: "sync.stream.batch",
            batchIndex: 10,
            isLast: true
        )

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(
            SyncStreamBatch.self, from: data
        )

        #expect(decoded.isLast == true)
        #expect(decoded.batchIndex == 10)
    }

    @Test("SyncStreamComplete encodes and decodes")
    func syncStreamCompleteRoundtrip() throws {
        let msg = SyncStreamComplete(
            type: "sync.stream.complete",
            processedEvents: 42,
            newCheckpoint: "2026-02-20T12:00:00Z"
        )

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(
            SyncStreamComplete.self, from: data
        )

        #expect(decoded.type == "sync.stream.complete")
        #expect(decoded.processedEvents == 42)
        #expect(decoded.newCheckpoint == "2026-02-20T12:00:00Z")
    }

    @Test("SyncStreamError encodes and decodes")
    func syncStreamErrorRoundtrip() throws {
        let msg = SyncStreamError(
            type: "sync.stream.error",
            error: "Rate limit exceeded",
            code: "RATE_LIMIT"
        )

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(
            SyncStreamError.self, from: data
        )

        #expect(decoded.type == "sync.stream.error")
        #expect(decoded.error == "Rate limit exceeded")
        #expect(decoded.code == "RATE_LIMIT")
    }

    @Test("SyncStreamError with nil code")
    func syncStreamErrorNilCode() throws {
        let msg = SyncStreamError(
            type: "sync.stream.error",
            error: "Unknown error",
            code: nil
        )

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(
            SyncStreamError.self, from: data
        )

        #expect(decoded.code == nil)
    }
}

// MARK: - SyncError Tests

@Suite("SyncError Tests")
@MainActor
struct SyncErrorTests {
    @Test("notAuthenticated error description")
    func notAuthenticated() {
        let error = SyncError.notAuthenticated
        #expect(error.errorDescription == "Not authenticated for sync")
    }

    @Test("invalidURL error description")
    func invalidURL() {
        let error = SyncError.invalidURL
        #expect(error.errorDescription == "Invalid sync URL")
    }

    @Test("pushFailed error description")
    func pushFailed() {
        let error = SyncError.pushFailed
        #expect(
            error.errorDescription == "Failed to push events to server"
        )
    }

    @Test("pullFailed error description")
    func pullFailed() {
        let error = SyncError.pullFailed
        #expect(
            error.errorDescription == "Failed to pull events from server"
        )
    }

    @Test("connectionLost error description")
    func connectionLost() {
        let error = SyncError.connectionLost
        #expect(error.errorDescription == "Sync connection lost")
    }

    @Test("SyncError conforms to LocalizedError")
    func conformsToLocalizedError() {
        let error: LocalizedError = SyncError.notAuthenticated
        #expect(error.errorDescription != nil)
    }
}

// MARK: - ConnectionStatus Tests

@Suite("ConnectionStatus Tests")
@MainActor
struct ConnectionStatusTests {
    @Test("All ConnectionStatus cases exist")
    func allCasesExist() {
        let connected = ConnectionStatus.connected
        let connecting = ConnectionStatus.connecting
        let disconnected = ConnectionStatus.disconnected

        // Verify each case is distinct via pattern matching
        switch connected {
        case .connected: break
        case .connecting, .disconnected:
            Issue.record("Expected .connected")
        }

        switch connecting {
        case .connecting: break
        case .connected, .disconnected:
            Issue.record("Expected .connecting")
        }

        switch disconnected {
        case .disconnected: break
        case .connected, .connecting:
            Issue.record("Expected .disconnected")
        }
    }
}
