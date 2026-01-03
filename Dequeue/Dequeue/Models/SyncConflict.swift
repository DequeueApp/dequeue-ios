//
//  SyncConflict.swift
//  Dequeue
//
//  Tracks sync conflicts when Last-Write-Wins resolution occurs
//

import Foundation
import SwiftData

@Model
final class SyncConflict {
    var id: String
    var entityType: String  // "stack", "task", "reminder"
    var entityId: String
    var localTimestamp: Date
    var remoteTimestamp: Date
    var conflictType: String  // "update", "delete", "status_change"
    var localState: Data?  // JSON snapshot of local state
    var remoteState: Data?  // JSON snapshot of remote state
    var resolution: String  // "kept_local" or "kept_remote"
    var detectedAt: Date
    var isResolved: Bool

    init(
        id: String = UUID().uuidString,
        entityType: String,
        entityId: String,
        localTimestamp: Date,
        remoteTimestamp: Date,
        conflictType: String,
        localState: Data? = nil,
        remoteState: Data? = nil,
        resolution: String,
        detectedAt: Date = Date(),
        isResolved: Bool = false
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.localTimestamp = localTimestamp
        self.remoteTimestamp = remoteTimestamp
        self.conflictType = conflictType
        self.localState = localState
        self.remoteState = remoteState
        self.resolution = resolution
        self.detectedAt = detectedAt
        self.isResolved = isResolved
    }

    /// Returns a human-readable description of the conflict
    var conflictDescription: String {
        let timeDiff = abs(localTimestamp.timeIntervalSince(remoteTimestamp))
        let direction = resolution == "kept_local" ? "kept local changes" : "applied remote changes"
        return "\(entityType.capitalized) conflict: \(direction) (\(Int(timeDiff))s apart)"
    }
}
