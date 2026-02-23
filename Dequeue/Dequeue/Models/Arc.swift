//
//  Arc.swift
//  Dequeue
//
//  Higher-level organizational container that groups related Stacks
//  Similar to how Epics organize Stories in JIRA
//

import Foundation
import SwiftData

@Model
final class Arc {
    @Attribute(.unique) var id: String
    var title: String
    var arcDescription: String?
    /// Stored as raw value string for SwiftData predicate compatibility
    var statusRawValue: String = ArcStatus.active.rawValue
    var sortOrder: Int = 0
    /// Optional color hex for visual accent (e.g., "FF6B6B")
    var colorHex: String?
    // swiftlint:disable:next redundant_type_annotation
    var createdAt: Date = Date()
    // swiftlint:disable:next redundant_type_annotation
    var updatedAt: Date = Date()
    var isDeleted: Bool = false

    // Sync fields (standard pattern)
    /// Optional start date for the arc
    var startTime: Date?
    /// Optional due date for the arc
    var dueTime: Date?

    // Sync fields (standard pattern)
    var userId: String?
    var deviceId: String?
    var syncStateRawValue: String = SyncState.pending.rawValue
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int = 1

    // Relationship to Stacks (one Arc has many Stacks)
    @Relationship(deleteRule: .nullify, inverse: \Stack.arc)
    var stacks: [Stack] = []

    // Relationship to Reminders (Arc can have reminders)
    @Relationship(deleteRule: .cascade, inverse: \Reminder.arc)
    var reminders: [Reminder] = []

    // MARK: - Computed Properties

    /// Type-safe status access
    var status: ArcStatus {
        get { ArcStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    /// Type-safe sync state access
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRawValue) ?? .pending }
        set { syncStateRawValue = newValue.rawValue }
    }

    /// Whether this arc is active and visible in the main list
    var isActive: Bool {
        status == .active && !isDeleted
    }

    /// Count of non-deleted, active Stacks
    var activeStackCount: Int {
        stacks.filter { !$0.isDeleted && $0.status == .active }.count
    }

    /// Count of completed Stacks
    var completedStackCount: Int {
        stacks.filter { !$0.isDeleted && $0.status == .completed }.count
    }

    /// Total non-deleted Stacks
    var totalStackCount: Int {
        stacks.filter { !$0.isDeleted }.count
    }

    /// Progress as fraction (0.0 to 1.0)
    var progress: Double {
        guard totalStackCount > 0 else { return 0 }
        return Double(completedStackCount) / Double(totalStackCount)
    }

    /// Stacks sorted by sort order
    var sortedStacks: [Stack] {
        return stacks
            .filter { !$0.isDeleted }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Active (non-completed) stacks sorted by sort order
    var pendingStacks: [Stack] {
        return stacks
            .filter { !$0.isDeleted && $0.status == .active }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Active reminders (not deleted, not fired) sorted by remindAt
    var activeReminders: [Reminder] {
        return reminders
            .filter { !$0.isDeleted && $0.status == .active }
            .sorted { $0.remindAt < $1.remindAt }
    }

    // MARK: - Initializer

    init(
        id: String = CUID.generate(),
        title: String,
        arcDescription: String? = nil,
        status: ArcStatus = .active,
        sortOrder: Int = 0,
        colorHex: String? = nil,
        startTime: Date? = nil,
        dueTime: Date? = nil,
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
        self.title = title
        self.arcDescription = arcDescription
        self.statusRawValue = status.rawValue
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.startTime = startTime
        self.dueTime = dueTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.userId = userId
        self.deviceId = deviceId
        self.syncStateRawValue = syncState.rawValue
        self.lastSyncedAt = lastSyncedAt
        self.serverId = serverId
        self.revision = revision
    }
}
