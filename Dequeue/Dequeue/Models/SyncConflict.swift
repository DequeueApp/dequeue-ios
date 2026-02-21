//
//  SyncConflict.swift
//  Dequeue
//
//  Tracks sync conflicts when Last-Write-Wins resolution occurs
//

import Foundation
import SwiftData

// MARK: - Type-Safe Enums

/// Types of entities that can have sync conflicts
enum SyncConflictEntityType: String, Codable {
    case stack
    case task
    case reminder
    case tag
    case attachment
    case arc
}

/// Types of operations that can cause conflicts
enum SyncConflictType: String, Codable {
    case update
    case delete
    case statusChange = "status_change"
    case reorder
}

/// How the conflict was resolved
enum SyncConflictResolution: String, Codable {
    case keptLocal = "kept_local"
    case keptRemote = "kept_remote"
}

// MARK: - SyncConflict Model

@Model
final class SyncConflict {
    // MARK: - Properties

    private(set) var id: String
    /// Raw string value for entityType enum (needed for SwiftData predicates)
    private(set) var entityTypeRaw: String
    private(set) var entityId: String
    private(set) var localTimestamp: Date
    private(set) var remoteTimestamp: Date
    /// Raw string value for conflictType enum (needed for SwiftData predicates)
    private(set) var conflictTypeRaw: String
    private(set) var localState: Data?
    private(set) var remoteState: Data?
    /// Raw string value for resolution enum (needed for SwiftData predicates)
    private(set) var resolutionRaw: String
    private(set) var detectedAt: Date
    var isResolved: Bool = false

    // MARK: - Type-Safe Accessors

    var entityType: SyncConflictEntityType {
        get { SyncConflictEntityType(rawValue: entityTypeRaw) ?? .stack }
        set { entityTypeRaw = newValue.rawValue }
    }

    var conflictType: SyncConflictType {
        get { SyncConflictType(rawValue: conflictTypeRaw) ?? .update }
        set { conflictTypeRaw = newValue.rawValue }
    }

    var resolution: SyncConflictResolution {
        get { SyncConflictResolution(rawValue: resolutionRaw) ?? .keptLocal }
        set { resolutionRaw = newValue.rawValue }
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        entityType: SyncConflictEntityType,
        entityId: String,
        localTimestamp: Date,
        remoteTimestamp: Date,
        conflictType: SyncConflictType,
        localState: Data? = nil,
        remoteState: Data? = nil,
        resolution: SyncConflictResolution,
        detectedAt: Date = Date(),
        isResolved: Bool = false
    ) {
        self.id = id
        self.entityTypeRaw = entityType.rawValue
        self.entityId = entityId
        self.localTimestamp = localTimestamp
        self.remoteTimestamp = remoteTimestamp
        self.conflictTypeRaw = conflictType.rawValue
        self.localState = localState
        self.remoteState = remoteState
        self.resolutionRaw = resolution.rawValue
        self.detectedAt = detectedAt
        self.isResolved = isResolved
    }

    // MARK: - Computed Properties

    /// Returns a human-readable description of the conflict
    var conflictDescription: String {
        let timeDiff = abs(localTimestamp.timeIntervalSince(remoteTimestamp))
        let direction = resolution == .keptLocal ? "kept local changes" : "applied remote changes"
        return "\(entityType.rawValue.capitalized) conflict: \(direction) (\(Int(timeDiff))s apart)"
    }
}
