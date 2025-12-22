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
    var status: ReminderStatus
    var snoozedFrom: Date?
    var remindAt: Date
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
