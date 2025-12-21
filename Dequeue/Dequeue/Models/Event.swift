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
    @Attribute(.unique) var id: UUID
    var type: String
    var payload: Data
    var timestamp: Date
    var metadata: Data?

    // Sync tracking
    var isSynced: Bool
    var syncedAt: Date?

    init(
        id: UUID = UUID(),
        type: String,
        payload: Data,
        timestamp: Date = Date(),
        metadata: Data? = nil,
        isSynced: Bool = false,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
        self.metadata = metadata
        self.isSynced = isSynced
        self.syncedAt = syncedAt
    }

    convenience init(
        id: UUID = UUID(),
        eventType: EventType,
        payload: Data,
        timestamp: Date = Date(),
        metadata: Data? = nil
    ) {
        self.init(
            id: id,
            type: eventType.rawValue,
            payload: payload,
            timestamp: timestamp,
            metadata: metadata
        )
    }
}

// MARK: - Convenience

extension Event {
    var eventType: EventType? {
        EventType(rawValue: type)
    }

    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: payload)
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
