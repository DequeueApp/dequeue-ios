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
    var attachments: [String] = []
    var tags: [String] = []  // DEQ-31: Tag support for tasks
    var status: TaskStatus = TaskStatus.pending
    var priority: Int?
    var blockedReason: String?
    var sortOrder: Int = 0
    var lastActiveTime: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isDeleted: Bool = false

    // AI delegation fields (DEQ-54)
    var delegatedToAI: Bool = false
    var aiAgentId: String?
    var aiDelegatedAt: Date?

    // Sync fields
    var userId: String?
    var deviceId: String?
    var syncState: SyncState = SyncState.pending
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int = 1

    // Relationships
    var stack: Stack?

    @Relationship(deleteRule: .cascade, inverse: \Reminder.task)
    var reminders: [Reminder] = []

    // Parent-child task relationship (DEQ-29: Subtasks)
    var parentTaskId: String?

    // Task dependencies (blocked by)
    var dependencyData: Data?

    // Recurring task fields
    var recurrenceRuleData: Data?
    var recurrenceParentId: String?
    var isRecurrenceTemplate: Bool = false
    var completedOccurrences: Int = 0

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
        tags: [String] = [],  // DEQ-31
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
        stack: Stack? = nil,
        parentTaskId: String? = nil,  // DEQ-29: Subtasks
        dependencyData: Data? = nil,
        recurrenceRuleData: Data? = nil,
        recurrenceParentId: String? = nil,
        isRecurrenceTemplate: Bool = false,
        completedOccurrences: Int = 0
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
        self.tags = tags  // DEQ-31
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
        self.parentTaskId = parentTaskId  // DEQ-29
        self.dependencyData = dependencyData
        self.recurrenceRuleData = recurrenceRuleData
        self.recurrenceParentId = recurrenceParentId
        self.isRecurrenceTemplate = isRecurrenceTemplate
        self.completedOccurrences = completedOccurrences
    }
}

// MARK: - Convenience

extension QueueTask {
    var activeReminders: [Reminder] {
        reminders.filter { !$0.isDeleted && $0.status == .active }
    }

    // DEQ-29: Parent task relationship
    // Note: These computed properties require ModelContext access
    // For querying parent/subtasks, use helper methods in TaskService or similar
    var hasParent: Bool {
        parentTaskId != nil
    }

    /// Computed property for the recurrence rule (JSON-encoded in recurrenceRuleData)
    @MainActor
    var recurrenceRule: RecurrenceRule? {
        get {
            guard let data = recurrenceRuleData else { return nil }
            return try? JSONDecoder().decode(RecurrenceRule.self, from: data)
        }
        set {
            recurrenceRuleData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// Whether this task has a recurrence pattern
    var isRecurring: Bool {
        recurrenceRuleData != nil
    }
}
