//
//  SyncTypes.swift
//  Dequeue
//
//  Type declarations for sync: projection models, WebSocket messages, and errors.
//  Extracted from SyncManager.swift for file-length compliance.
//

import Foundation

// MARK: - Internal Sync Types

/// Sendable representation of Event data for cross-actor communication
struct EventData: Sendable {
    let id: String
    let timestamp: Date
    let type: String
    let payload: Data
    let metadata: Data?  // DEQ-55: Actor metadata (actorType, actorId)
    let userId: String
    let deviceId: String
    let appId: String
    let payloadVersion: Int
}

/// Result of processing a pull response, used for pagination
struct PullResult {
    let eventsProcessed: Int
    let nextCheckpoint: String?
    let hasMore: Bool
}

// MARK: - Projection Sync Types (DEQ-230)

/// Generic response wrapper for projection API endpoints
/// Requires Sendable to safely cross actor boundaries during concurrent fetch.
/// Uses @preconcurrency Decodable to allow decoding in actor-isolated contexts (Swift 6 concurrency).
struct ProjectionResponse<T: Decodable & Sendable>: @preconcurrency Decodable, Sendable {
    let data: [T]
    let pagination: PaginationMeta?

    struct PaginationMeta: @preconcurrency Decodable, Sendable {
        let nextCursor: String?
        let hasMore: Bool
        let limit: Int
    }
}

/// Projection data structures matching dequeue-api responses
/// All projection types are Sendable (simple value types with only Sendable properties)
/// to allow safe transfer across actor isolation boundaries during concurrent fetch.
/// Uses @preconcurrency Decodable for Swift 6 actor isolation compatibility.
struct StackProjection: @preconcurrency Decodable, Sendable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let isActive: Bool
    let isDeleted: Bool
    let arcId: String?
    let tags: [String]?
    let sortOrder: Int
    let activeTaskId: String?
    let startTime: Int64?
    let dueTime: Int64?
    let createdAt: Int64
    let updatedAt: Int64
    // Note: tasks are fetched separately via GET /v1/tasks (not nested in stacks response)

    // API returns startAt/dueAt but iOS models use startTime/dueTime
    private enum CodingKeys: String, CodingKey {
        case id, title, description, status, isActive, isDeleted, arcId, tags
        case sortOrder, activeTaskId
        case startTime = "startAt"
        case dueTime = "dueAt"
        case createdAt, updatedAt
    }

    // Custom init: isDeleted defaults to false when API omits it
    // (API list endpoints filter WHERE is_deleted = false and don't include the field)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decode(String.self, forKey: .status)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        arcId = try container.decodeIfPresent(String.self, forKey: .arcId)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        activeTaskId = try container.decodeIfPresent(String.self, forKey: .activeTaskId)
        startTime = try container.decodeIfPresent(Int64.self, forKey: .startTime)
        dueTime = try container.decodeIfPresent(Int64.self, forKey: .dueTime)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
    }
}

struct TaskProjection: @preconcurrency Decodable, Sendable {
    let id: String
    let stackId: String
    let title: String
    let notes: String?
    let sortOrder: Int
    let status: String
    let isActive: Bool
    let priority: Int?
    let blockedReason: String?
    let parentTaskId: String?
    let startTime: Int64?
    let dueTime: Int64?
    let completedAt: Int64?
    let createdAt: Int64
    let updatedAt: Int64

    // API returns startAt/dueAt but iOS models use startTime/dueTime
    private enum CodingKeys: String, CodingKey {
        case id, stackId, title, notes, sortOrder, status, isActive
        case priority, blockedReason, parentTaskId, completedAt
        case startTime = "startAt"
        case dueTime = "dueAt"
        case createdAt, updatedAt
    }
}

struct ArcProjection: @preconcurrency Decodable, Sendable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let color: String?
    let isDeleted: Bool
    let sortOrder: Int
    let startTime: Int64?
    let dueTime: Int64?
    let createdAt: Int64
    let updatedAt: Int64

    // API returns colorHex/startAt/dueAt but iOS models use different names
    private enum CodingKeys: String, CodingKey {
        case id, title, description, status, isDeleted, sortOrder
        case color = "colorHex"
        case startTime = "startAt"
        case dueTime = "dueAt"
        case createdAt, updatedAt
    }

    // Custom init: isDeleted/sortOrder default when API omits them
    // (API list endpoints filter WHERE is_deleted = false and don't include the field)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        color = try container.decodeIfPresent(String.self, forKey: .color)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        startTime = try container.decodeIfPresent(Int64.self, forKey: .startTime)
        dueTime = try container.decodeIfPresent(Int64.self, forKey: .dueTime)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
    }
}

struct TagProjection: @preconcurrency Decodable, Sendable {
    let id: String
    let name: String
    let color: String?
    let createdAt: Int64
    let updatedAt: Int64

    // API returns colorHex but we use color internally
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt
        case color = "colorHex"
    }
}

struct ReminderProjection: @preconcurrency Decodable, Sendable {
    let id: String
    let parentType: String
    let parentId: String
    let remindAt: Int64
    let snoozedFrom: Int64?
    let status: String
    let createdAt: Int64
    let updatedAt: Int64

    // Derived properties for backward compatibility with populateReminders()
    var stackId: String? { parentType == "stack" ? parentId : nil }
    var arcId: String? { parentType == "arc" ? parentId : nil }
    var taskId: String? { parentType == "task" ? parentId : nil }
    var triggerTime: Int64 { remindAt }
    var isDeleted: Bool { status == "deleted" }
}

// MARK: - WebSocket Stream Messages (DEQ-243)

/// Client request to start streaming events
struct SyncStreamRequest: Codable, Sendable {
    let type: String // "sync.stream.request"
    let since: String? // RFC3339 timestamp, optional
}

/// Server response indicating stream start with total event count
struct SyncStreamStart: Codable, Sendable {
    let type: String // "sync.stream.start"
    let totalEvents: Int64
}

/// Server response containing a batch of events
/// Note: events are parsed separately using JSONSerialization to match REST API handling
struct SyncStreamBatch: Codable, Sendable {
    let type: String // "sync.stream.batch"
    // events field handled separately via JSONSerialization
    let batchIndex: Int
    let isLast: Bool
}

/// Server response indicating stream completion
struct SyncStreamComplete: Codable, Sendable {
    let type: String // "sync.stream.complete"
    let processedEvents: Int64
    let newCheckpoint: String
}

/// Server response indicating an error occurred during streaming
struct SyncStreamError: Codable, Sendable {
    let type: String // "sync.stream.error"
    let error: String
    let code: String?
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case pushFailed
    case pullFailed
    case connectionLost

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated for sync"
        case .invalidURL:
            return "Invalid sync URL"
        case .pushFailed:
            return "Failed to push events to server"
        case .pullFailed:
            return "Failed to pull events from server"
        case .connectionLost:
            return "Sync connection lost"
        }
    }
}

enum ConnectionStatus {
    case connected
    case connecting
    case disconnected
}
