//
//  Tag.swift
//  Dequeue
//
//  Global tag model for categorizing Stacks
//

import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var id: String
    var name: String
    var normalizedName: String
    var colorHex: String?

    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    // Sync fields
    var userId: String?
    var deviceId: String?
    var syncState: SyncState
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int

    // Relationship to Stacks (many-to-many)
    @Relationship(inverse: \Stack.tagObjects)
    var stacks: [Stack] = []

    init(
        id: String = CUID.generate(),
        name: String,
        colorHex: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        userId: String? = nil,
        deviceId: String? = nil,
        syncState: SyncState = .pending,
        lastSyncedAt: Date? = nil,
        serverId: String? = nil,
        revision: Int = 1
    ) {
        self.id = id
        self.name = name
        self.normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.userId = userId
        self.deviceId = deviceId
        self.syncState = syncState
        self.lastSyncedAt = lastSyncedAt
        self.serverId = serverId
        self.revision = revision
    }
}

// MARK: - Convenience

extension Tag {
    /// Count of non-deleted active Stacks using this tag
    var activeStackCount: Int {
        stacks.filter { !$0.isDeleted && $0.status == .active }.count
    }
}
