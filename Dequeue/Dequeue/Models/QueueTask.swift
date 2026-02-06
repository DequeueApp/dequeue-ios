//
//  QueueTask.swift
//  Dequeue
//
//  Individual task within a Stack
//

import Foundation
import SwiftData

@Model
final class QueueTask {
    @Attribute(.unique) var id: String
    var title: String
    var taskDescription: String?
    var startTime: Date?
    var dueTime: Date?
    var locationAddress: String?
    var locationLatitude: Double?
    var locationLongitude: Double?
    var attachments: [String]
    var status: TaskStatus
    var priority: Int?
    var blockedReason: String?
    var sortOrder: Int
    var lastActiveTime: Date?
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    // AI delegation fields (DEQ-54)
    var delegatedToAI: Bool
    var aiAgentId: String?
    var aiDelegatedAt: Date?

    // Sync fields
    var userId: String?
    var deviceId: String?
    var syncState: SyncState
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int

    // Relationships
    var stack: Stack?

    @Relationship(deleteRule: .cascade, inverse: \Reminder.task)
    var reminders: [Reminder] = []

    init(
        id: String = CUID.generate(),
        title: String,
        taskDescription: String? = nil,
        startTime: Date? = nil,
        dueTime: Date? = nil,
        locationAddress: String? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        attachments: [String] = [],
        status: TaskStatus = .pending,
        priority: Int? = nil,
        blockedReason: String? = nil,
        sortOrder: Int = 0,
        lastActiveTime: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        delegatedToAI: Bool = false,
        aiAgentId: String? = nil,
        aiDelegatedAt: Date? = nil,
        userId: String? = nil,
        deviceId: String? = nil,
        syncState: SyncState = .pending,
        lastSyncedAt: Date? = nil,
        serverId: String? = nil,
        revision: Int = 1,
        stack: Stack? = nil
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.startTime = startTime
        self.dueTime = dueTime
        self.locationAddress = locationAddress
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.attachments = attachments
        self.status = status
        self.priority = priority
        self.blockedReason = blockedReason
        self.sortOrder = sortOrder
        self.lastActiveTime = lastActiveTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.delegatedToAI = delegatedToAI
        self.aiAgentId = aiAgentId
        self.aiDelegatedAt = aiDelegatedAt
        self.userId = userId
        self.deviceId = deviceId
        self.syncState = syncState
        self.lastSyncedAt = lastSyncedAt
        self.serverId = serverId
        self.revision = revision
        self.stack = stack
    }
}

// MARK: - Convenience

extension QueueTask {
    var activeReminders: [Reminder] {
        reminders.filter { !$0.isDeleted && $0.status == .active }
    }
}
