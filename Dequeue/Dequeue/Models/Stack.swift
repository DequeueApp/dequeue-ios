//
//  Stack.swift
//  Dequeue
//
//  Top-level task container
//

import Foundation
import SwiftData

@Model
final class Stack {
    @Attribute(.unique) var id: String
    var title: String
    var stackDescription: String?
    var startTime: Date?
    var dueTime: Date?
    var locationAddress: String?
    var locationLatitude: Double?
    var locationLongitude: Double?
    var tags: [String]
    var attachments: [String]
    /// Stored as raw value string for SwiftData predicate compatibility
    var statusRawValue: String
    var priority: Int?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var isDraft: Bool

    // Sync fields
    var userId: String?
    var deviceId: String?
    var syncState: SyncState
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \QueueTask.stack)
    var tasks: [QueueTask] = []

    @Relationship(deleteRule: .cascade)
    var reminders: [Reminder] = []

    /// Computed property for type-safe status access
    var status: StackStatus {
        get { StackStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: String = CUID.generate(),
        title: String,
        stackDescription: String? = nil,
        startTime: Date? = nil,
        dueTime: Date? = nil,
        locationAddress: String? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        tags: [String] = [],
        attachments: [String] = [],
        status: StackStatus = .active,
        priority: Int? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        isDraft: Bool = false,
        userId: String? = nil,
        deviceId: String? = nil,
        syncState: SyncState = .pending,
        lastSyncedAt: Date? = nil,
        serverId: String? = nil,
        revision: Int = 1
    ) {
        self.id = id
        self.title = title
        self.stackDescription = stackDescription
        self.startTime = startTime
        self.dueTime = dueTime
        self.locationAddress = locationAddress
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.tags = tags
        self.attachments = attachments
        self.statusRawValue = status.rawValue
        self.priority = priority
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.isDraft = isDraft
        self.userId = userId
        self.deviceId = deviceId
        self.syncState = syncState
        self.lastSyncedAt = lastSyncedAt
        self.serverId = serverId
        self.revision = revision
    }
}

// MARK: - Convenience

extension Stack {
    var pendingTasks: [QueueTask] {
        tasks
            .filter { !$0.isDeleted && $0.status == .pending }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var completedTasks: [QueueTask] {
        tasks
            .filter { !$0.isDeleted && $0.status == .completed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeTask: QueueTask? {
        pendingTasks.first
    }

    var activeReminders: [Reminder] {
        reminders.filter { !$0.isDeleted && $0.status == .active }
    }
}
