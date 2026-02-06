//
//  Event.swift
//  Dequeue
//
//  Immutable event log for audit trail and sync
//

import Foundation
import SwiftData

@Model
final class Event {
    @Attribute(.unique) var id: String
    var type: String
    var payload: Data
    var timestamp: Date
    var metadata: Data?

    /// The ID of the entity this event relates to (Stack, Task, Reminder, Device).
    /// Used for efficient history queries.
    var entityId: String?

    /// The user who created this event.
    /// Required for all events created after the DEQ-137 migration.
    var userId: String

    /// The device that created this event.
    /// Required for all events created after the DEQ-137 migration.
    var deviceId: String

    /// The app that created this event (bundle identifier).
    /// Required for all events created after the DEQ-137 migration.
    var appId: String

    /// Schema version for the event payload structure.
    /// Version 1: Legacy events (pre-DEQ-137, no userId/deviceId)
    /// Version 2: Current format with userId/deviceId (DEQ-137+)
    /// Events with payloadVersion < 2 are ignored during sync pull.
    static let currentPayloadVersion: Int = 2
    var payloadVersion: Int

    // Sync tracking
    var isSynced: Bool
    var syncedAt: Date?

    init(
        id: String = CUID.generate(),
        type: String,
        payload: Data,
        timestamp: Date = Date(),
        metadata: Data? = nil,
        entityId: String? = nil,
        userId: String,
        deviceId: String,
        appId: String,
        payloadVersion: Int = Event.currentPayloadVersion,
        isSynced: Bool = false,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
        self.metadata = metadata
        self.entityId = entityId
        self.userId = userId
        self.deviceId = deviceId
        self.appId = appId
        self.payloadVersion = payloadVersion
        self.isSynced = isSynced
        self.syncedAt = syncedAt
    }

    convenience init(
        id: String = CUID.generate(),
        eventType: EventType,
        payload: Data,
        timestamp: Date = Date(),
        metadata: Data? = nil,
        entityId: String? = nil,
        userId: String,
        deviceId: String,
        appId: String,
        payloadVersion: Int = Event.currentPayloadVersion
    ) {
        self.init(
            id: id,
            type: eventType.rawValue,
            payload: payload,
            timestamp: timestamp,
            metadata: metadata,
            entityId: entityId,
            userId: userId,
            deviceId: deviceId,
            appId: appId,
            payloadVersion: payloadVersion
        )
    }
}

// MARK: - Convenience

extension Event {
    var eventType: EventType? {
        EventType(rawValue: type)
    }

    /// Decodes payload supporting multiple wrapper formats.
    /// - Flat format: `{"id": "...", "name": "..."}`
    /// - State wrapper: `{"state": {"id": "...", "name": "..."}}`
    /// - FullState wrapper: `{"fullState": {"id": "...", "name": "..."}}`
    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()

        // First, try to decode directly (flat format)
        do {
            return try decoder.decode(type, from: payload)
        } catch {
            // If that fails, check for wrapped formats
            if let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                // Check for "fullState" wrapper (used by stack.updated, task.updated, etc.)
                if let fullStateObject = json["fullState"] {
                    let stateData = try JSONSerialization.data(withJSONObject: fullStateObject)
                    return try decoder.decode(type, from: stateData)
                }
                // Check for "state" wrapper (used by stack.created, task.created, etc.)
                if let stateObject = json["state"] {
                    let stateData = try JSONSerialization.data(withJSONObject: stateObject)
                    return try decoder.decode(type, from: stateData)
                }
            }

            // Neither format worked, throw the original error
            throw error
        }
    }

    func decodeMetadata<T: Decodable>(_ type: T.Type) throws -> T? {
        guard let metadata else { return nil }
        return try JSONDecoder().decode(type, from: metadata)
    }
}

// MARK: - Payload Helpers

extension Event {
    static func encodePayload<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}

// MARK: - Event Metadata (DEQ-55)

/// Metadata attached to events to track who/what created them.
/// Includes actor type (human vs AI) and optional AI agent identification.
struct EventMetadata: Codable, Sendable {
    /// Type of actor that created this event (human or AI)
    var actorType: ActorType

    /// AI agent identifier (required when actorType is .ai, nil otherwise)
    var actorId: String?

    init(actorType: ActorType = .human, actorId: String? = nil) {
        self.actorType = actorType
        self.actorId = actorId
    }

    /// Create metadata for a human actor
    static func human() -> EventMetadata {
        EventMetadata(actorType: .human, actorId: nil)
    }

    /// Create metadata for an AI actor
    static func ai(agentId: String) -> EventMetadata {
        EventMetadata(actorType: .ai, actorId: agentId)
    }
}

extension Event {
    /// Decode the event's metadata as EventMetadata (DEQ-55)
    func actorMetadata() throws -> EventMetadata? {
        try decodeMetadata(EventMetadata.self)
    }

    /// Check if this event was created by an AI agent
    var isFromAI: Bool {
        (try? actorMetadata()?.actorType == .ai) ?? false
    }

    /// Check if this event was created by a human user
    var isFromHuman: Bool {
        !isFromAI
    }
}
