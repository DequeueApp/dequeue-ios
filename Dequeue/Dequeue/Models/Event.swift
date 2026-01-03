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
        isSynced: Bool = false,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
        self.metadata = metadata
        self.entityId = entityId
        self.isSynced = isSynced
        self.syncedAt = syncedAt
    }

    convenience init(
        id: String = CUID.generate(),
        eventType: EventType,
        payload: Data,
        timestamp: Date = Date(),
        metadata: Data? = nil,
        entityId: String? = nil
    ) {
        self.init(
            id: id,
            type: eventType.rawValue,
            payload: payload,
            timestamp: timestamp,
            metadata: metadata,
            entityId: entityId
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
