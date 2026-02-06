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

    nonisolated func decodeMetadata<T: Decodable>(_ type: T.Type) throws -> T? {
        guard let metadata else { return nil }
        // Decode directly - metadata is just Data, safe to access without synchronization
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

extension Event {
    /// Decode the event's metadata as EventMetadata (DEQ-55)
    nonisolated func actorMetadata() throws -> EventMetadata? {
        guard let metadata else { return nil }
        // Use manual JSON deserialization to avoid actor-isolated Codable conformance
        // This sidesteps Swift 6's conservative actor isolation on protocol conformances
        let json = try JSONSerialization.jsonObject(with: metadata) as? [String: Any]
        guard let json else { return nil }
        
        guard let actorTypeString = json["actorType"] as? String,
              let actorType = ActorType(rawValue: actorTypeString) else {
            return nil
        }
        
        let actorId = json["actorId"] as? String
        return EventMetadata.from(actorType: actorType, actorId: actorId)
    }

    /// Check if this event was created by an AI agent
    nonisolated var isFromAI: Bool {
        (try? actorMetadata()?.actorType == .ai) ?? false
    }

    /// Check if this event was created by a human user
    nonisolated var isFromHuman: Bool {
        !isFromAI
    }
}
