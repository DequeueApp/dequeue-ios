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
            userId: "user-456",
            deviceId: "device-789",
            appId: "app-001",
            payloadVersion: 2
        )

        #expect(event.id == "evt-123")
        #expect(event.timestamp == now)
        #expect(event.type == "stack.created")
        #expect(event.payload == payload)
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
            userId: "u",
            deviceId: "d",
            appId: "a",
            payloadVersion: 1
        )

        #expect(event.payload.isEmpty)
        #expect(event.id == "evt-empty")
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
    @Test("StackProjection decodes with all fields")
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
            "startTime": 1708000000,
            "dueTime": 1708086400,
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
        #expect(stack.startTime == 1_708_000_000)
        #expect(stack.dueTime == 1_708_086_400)
        #expect(stack.createdAt == 1_707_900_000)
        #expect(stack.updatedAt == 1_708_000_000)
    }

    @Test("StackProjection decodes with minimal fields")
    func decodesWithMinimalFields() throws {
        let json = """
        {
            "id": "stack-min",
            "title": "Minimal",
            "status": "active",
            "isActive": true,
            "isDeleted": false,
            "createdAt": 1707900000,
            "updatedAt": 1707900000
        }
        """.data(using: .utf8)!

        let stack = try JSONDecoder().decode(
            StackProjection.self, from: json
        )

        #expect(stack.id == "stack-min")
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
            "description": "Organic whole milk",
            "sortOrder": 0,
            "status": "pending",
            "isActive": true,
            "startTime": 1708000000,
            "dueTime": 1708086400,
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
        #expect(task.description == "Organic whole milk")
        #expect(task.sortOrder == 0)
        #expect(task.status == "pending")
        #expect(task.isActive == true)
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

        #expect(task.description == nil)
        #expect(task.startTime == nil)
        #expect(task.dueTime == nil)
    }
}

// MARK: - ArcProjection Tests

@Suite("ArcProjection Tests")
@MainActor
struct ArcProjectionTests {
    @Test("ArcProjection decodes correctly")
    func decodesCorrectly() throws {
        let json = """
        {
            "id": "arc-100",
            "title": "Q1 Sprint",
            "description": "First quarter deliverables",
            "color": "#3498DB",
            "isDeleted": false,
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
        #expect(arc.color == "#3498DB")
        #expect(arc.isDeleted == false)
        #expect(arc.createdAt == 1_707_000_000)
        #expect(arc.updatedAt == 1_708_000_000)
    }

    @Test("ArcProjection decodes with nil optionals")
    func decodesWithNilOptionals() throws {
        let json = """
        {
            "id": "arc-101",
            "title": "No extras",
            "isDeleted": false,
            "createdAt": 1707000000,
            "updatedAt": 1707000000
        }
        """.data(using: .utf8)!

        let arc = try JSONDecoder().decode(
            ArcProjection.self, from: json
        )

        #expect(arc.description == nil)
        #expect(arc.color == nil)
    }
}

// MARK: - TagProjection Tests

@Suite("TagProjection Tests")
@MainActor
struct TagProjectionTests {
    @Test("TagProjection decodes correctly")
    func decodesCorrectly() throws {
        let json = """
        {
            "id": "tag-50",
            "name": "urgent",
            "color": "#E74C3C",
            "createdAt": 1707500000
        }
        """.data(using: .utf8)!

        let tag = try JSONDecoder().decode(
            TagProjection.self, from: json
        )

        #expect(tag.id == "tag-50")
        #expect(tag.name == "urgent")
        #expect(tag.color == "#E74C3C")
        #expect(tag.createdAt == 1_707_500_000)
    }

    @Test("TagProjection decodes with nil color")
    func decodesWithNilColor() throws {
        let json = """
        {
            "id": "tag-51",
            "name": "misc",
            "createdAt": 1707500000
        }
        """.data(using: .utf8)!

        let tag = try JSONDecoder().decode(
            TagProjection.self, from: json
        )

        #expect(tag.color == nil)
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
            "stackId": "stack-abc",
            "triggerTime": 1708100000,
            "notificationSent": false,
            "isDeleted": false,
            "createdAt": 1708000000
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
        #expect(reminder.notificationSent == false)
        #expect(reminder.isDeleted == false)
    }

    @Test("ReminderProjection decodes with task parent")
    func decodesWithTaskParent() throws {
        let json = """
        {
            "id": "rem-11",
            "taskId": "task-001",
            "triggerTime": 1708200000,
            "notificationSent": true,
            "isDeleted": false,
            "createdAt": 1708000000
        }
        """.data(using: .utf8)!

        let reminder = try JSONDecoder().decode(
            ReminderProjection.self, from: json
        )

        #expect(reminder.taskId == "task-001")
        #expect(reminder.notificationSent == true)
    }

    @Test("ReminderProjection decodes with arc parent")
    func decodesWithArcParent() throws {
        let json = """
        {
            "id": "rem-12",
            "arcId": "arc-100",
            "triggerTime": 1708300000,
            "notificationSent": false,
            "isDeleted": true,
            "createdAt": 1708000000
        }
        """.data(using: .utf8)!

        let reminder = try JSONDecoder().decode(
            ReminderProjection.self, from: json
        )

        #expect(reminder.arcId == "arc-100")
        #expect(reminder.isDeleted == true)
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
