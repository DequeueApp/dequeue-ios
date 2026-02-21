//
//  Reminder.swift
//  Dequeue
//
//  Scheduled notification for a Stack or Task
//

import Foundation
import SwiftData

@Model
final class Reminder {
    @Attribute(.unique) var id: String
    var parentId: String
    var parentType: ParentType
    var status: ReminderStatus = ReminderStatus.active
    var snoozedFrom: Date?
    var remindAt: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isDeleted: Bool = false

    // Sync fields
    var userId: String?
    var deviceId: String?
    var syncState: SyncState = SyncState.pending
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int = 1

    // Inverse relationships (only one should be set based on parentType)
    var stack: Stack?
    var task: QueueTask?
    var arc: Arc?

    init(
        id: String = CUID.generate(),
        parentId: String,
        parentType: ParentType,
        status: ReminderStatus = .active,
        snoozedFrom: Date? = nil,
        remindAt: Date,
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
        self.parentId = parentId
        self.parentType = parentType
        self.status = status
        self.snoozedFrom = snoozedFrom
        self.remindAt = remindAt
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

extension Reminder {
    var isPastDue: Bool {
        remindAt < Date()
    }

    var isUpcoming: Bool {
        status == .active && remindAt > Date()
    }
}
