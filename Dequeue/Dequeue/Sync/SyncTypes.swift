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
    let startTime: Int64?
    let dueTime: Int64?
    let createdAt: Int64
    let updatedAt: Int64
    // Note: tasks are fetched separately via GET /v1/tasks (not nested in stacks response)
}

struct TaskProjection: @preconcurrency Decodable, Sendable {
    let id: String
    let stackId: String
    let title: String
    let description: String?
    let sortOrder: Int
    let status: String
    let isActive: Bool
    let startTime: Int64?
    let dueTime: Int64?
    let createdAt: Int64
    let updatedAt: Int64
}

struct ArcProjection: @preconcurrency Decodable, Sendable {
    let id: String
    let title: String
    let description: String?
    let color: String?
    let isDeleted: Bool
    let createdAt: Int64
    let updatedAt: Int64
}

struct TagProjection: @preconcurrency Decodable, Sendable {
    let id: String
    let name: String
    let color: String?
    let createdAt: Int64
}

struct ReminderProjection: @preconcurrency Decodable, Sendable {
    let id: String
    let stackId: String?
    let arcId: String?
    let taskId: String?
    let triggerTime: Int64
    let notificationSent: Bool
    let isDeleted: Bool
    let createdAt: Int64
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
