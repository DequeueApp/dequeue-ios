//
//  Tag.swift
//  Dequeue
//
//  Global tag model for categorizing Stacks
//

import Foundation
import SwiftData

/// A global tag model for categorizing and organizing Stacks.
///
/// Tags enable users to categorize stacks for filtering and organization.
/// Tag names are case-insensitive (normalized for matching) and unique per user.
///
/// **Threading**: This model is @MainActor-isolated via SwiftData's @Model macro.
/// All property access and relationship queries must occur on the main actor.
@Model
final class Tag {
    /// Unique identifier for the tag (CUID format)
    @Attribute(.unique) var id: String

    /// Display name of the tag (preserves user's original casing)
    var name: String

    /// Optional color for visual distinction (hex format, e.g., "#FF5733")
    var colorHex: String?

    // MARK: - Metadata

    /// Timestamp when the tag was created
    var createdAt: Date = Date() // swiftlint:disable:this redundant_type_annotation

    /// Timestamp when the tag was last modified
    var updatedAt: Date = Date() // swiftlint:disable:this redundant_type_annotation

    /// Soft deletion flag for sync-compatible deletion
    var isDeleted: Bool = false

    // MARK: - Sync Fields

    /// User ID who owns this tag (for multi-user support)
    var userId: String?

    /// Device ID that created this tag
    var deviceId: String?

    /// Current sync state with backend
    var syncState: SyncState = SyncState.pending // swiftlint:disable:this redundant_type_annotation

    /// Timestamp of last successful sync with backend
    var lastSyncedAt: Date?

    /// Server-assigned ID after successful sync
    var serverId: String?

    /// Revision counter for conflict resolution (incremented on each update)
    var revision: Int = 1

    // MARK: - Relationships

    /// Stacks that use this tag (many-to-many relationship)
    @Relationship(inverse: \Stack.tagObjects)
    var stacks: [Stack] = []

    /// Normalized name for case-insensitive matching and deduplication.
    ///
    /// This computed property automatically normalizes the `name` to lowercase
    /// and trims whitespace, ensuring consistent matching across the app.
    ///
    /// **Note**: SwiftData does not support uniqueness constraints on computed
    /// properties. Uniqueness must be enforced at the service layer during
    /// tag creation and rename operations.
    var normalizedName: String {
        name.lowercased().trimmingCharacters(in: .whitespaces)
    }

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
    /// Count of non-deleted active Stacks using this tag.
    ///
    /// This property queries the `stacks` relationship to count active stacks.
    ///
    /// **Threading**: Must be accessed on @MainActor since it queries SwiftData relationships.
    /// SwiftData relationships are not thread-safe and must be accessed from the main actor.
    ///
    /// **Performance**: This performs a filter operation on the entire stacks array.
    /// For large tag-to-stack relationships, consider caching or alternative approaches.
    var activeStackCount: Int {
        stacks.filter { !$0.isDeleted && $0.status == .active }.count
    }
}
