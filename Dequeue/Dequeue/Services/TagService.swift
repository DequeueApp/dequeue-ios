//
//  TagService.swift
//  Dequeue
//
//  Business logic for Tag operations
//

import Foundation
import SwiftData

// MARK: - Tag Service Errors

/// Errors that can occur during tag operations
enum TagServiceError: LocalizedError, Equatable {
    /// Tag name is empty or contains only whitespace
    case emptyTagName
    /// Tag name exceeds the maximum allowed length
    case tagNameTooLong(maxLength: Int)
    /// A tag with the same normalized name already exists
    case duplicateTagName(existingName: String)
    /// The tag was not found
    case tagNotFound
    /// Operation failed and changes were not saved
    case operationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .emptyTagName:
            return "Tag name cannot be empty"
        case .tagNameTooLong(let maxLength):
            return "Tag name exceeds maximum length of \(maxLength) characters"
        case .duplicateTagName(let existingName):
            return "A tag named '\(existingName)' already exists"
        case .tagNotFound:
            return "Tag not found"
        case .operationFailed(let underlying):
            return "Tag operation failed: \(underlying.localizedDescription)"
        }
    }

    static func == (lhs: TagServiceError, rhs: TagServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyTagName, .emptyTagName):
            return true
        case (.tagNameTooLong(let lhsMax), .tagNameTooLong(let rhsMax)):
            return lhsMax == rhsMax
        case (.duplicateTagName(let lhsName), .duplicateTagName(let rhsName)):
            return lhsName == rhsName
        case (.tagNotFound, .tagNotFound):
            return true
        case (.operationFailed(let lhsError), .operationFailed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Tag Service

@MainActor
final class TagService {
    /// Maximum allowed length for tag names
    static let maxTagNameLength = 50

    private let modelContext: ModelContext
    private let eventService: EventService
    private let syncManager: SyncManager?

    init(modelContext: ModelContext, syncManager: SyncManager? = nil) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext)
        self.syncManager = syncManager
    }

    // MARK: - Create

    /// Creates a new tag with the given name.
    ///
    /// - Parameters:
    ///   - name: The display name for the tag (will be trimmed)
    ///   - colorHex: Optional color in hex format (e.g., "#FF5733")
    /// - Returns: The newly created tag
    /// - Throws: `TagServiceError.emptyTagName` if name is empty after trimming
    /// - Throws: `TagServiceError.tagNameTooLong` if name exceeds max length
    /// - Throws: `TagServiceError.duplicateTagName` if a tag with same normalized name exists
    func createTag(name: String, colorHex: String? = nil) throws -> Tag {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate name is not empty
        guard !trimmedName.isEmpty else {
            throw TagServiceError.emptyTagName
        }

        // Validate name length
        guard trimmedName.count <= Self.maxTagNameLength else {
            throw TagServiceError.tagNameTooLong(maxLength: Self.maxTagNameLength)
        }

        // Check for duplicate (case-insensitive)
        let normalizedName = trimmedName.lowercased().trimmingCharacters(in: .whitespaces)
        if let existingTag = try findTagByNormalizedName(normalizedName) {
            throw TagServiceError.duplicateTagName(existingName: existingTag.name)
        }

        let tag = Tag(
            name: trimmedName,
            colorHex: colorHex,
            syncState: .pending
        )

        modelContext.insert(tag)
        try eventService.recordTagCreated(tag)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return tag
    }

    /// Finds or creates a tag with the given name.
    ///
    /// This is useful for ensuring a tag exists without throwing on duplicates.
    ///
    /// - Parameters:
    ///   - name: The display name for the tag
    ///   - colorHex: Optional color (only used if creating new tag)
    /// - Returns: The existing or newly created tag
    func findOrCreateTag(name: String, colorHex: String? = nil) throws -> Tag {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw TagServiceError.emptyTagName
        }

        guard trimmedName.count <= Self.maxTagNameLength else {
            throw TagServiceError.tagNameTooLong(maxLength: Self.maxTagNameLength)
        }

        let normalizedName = trimmedName.lowercased().trimmingCharacters(in: .whitespaces)

        // Return existing tag if found
        if let existingTag = try findTagByNormalizedName(normalizedName) {
            return existingTag
        }

        // Create new tag
        let tag = Tag(
            name: trimmedName,
            colorHex: colorHex,
            syncState: .pending
        )

        modelContext.insert(tag)
        try eventService.recordTagCreated(tag)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return tag
    }

    // MARK: - Read

    /// Returns all non-deleted tags sorted by name.
    func getAllTags() throws -> [Tag] {
        let predicate = #Predicate<Tag> { tag in
            tag.isDeleted == false
        }
        let descriptor = FetchDescriptor<Tag>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Searches for tags matching the query (case-insensitive).
    ///
    /// - Parameter query: The search query
    /// - Returns: Tags whose names contain the query
    func searchTags(query: String) throws -> [Tag] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedQuery.isEmpty else {
            return try getAllTags()
        }

        // Fetch all non-deleted tags and filter in memory
        // (SwiftData predicates have limited support for string contains with transformations)
        let allTags = try getAllTags()
        return allTags.filter { tag in
            tag.normalizedName.contains(trimmedQuery)
        }
    }

    /// Finds a tag by its normalized name (case-insensitive match).
    ///
    /// - Parameter normalizedName: The lowercased, trimmed name to search for
    /// - Returns: The matching tag, or nil if not found
    func findTagByNormalizedName(_ normalizedName: String) throws -> Tag? {
        // Fetch all non-deleted tags and filter by normalized name
        // (SwiftData predicates don't support computed properties directly)
        let predicate = #Predicate<Tag> { tag in
            tag.isDeleted == false
        }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        let allTags = try modelContext.fetch(descriptor)

        return allTags.first { tag in
            tag.normalizedName == normalizedName
        }
    }

    /// Finds a tag by its ID.
    ///
    /// - Parameter id: The tag ID
    /// - Returns: The matching tag, or nil if not found
    func findTagById(_ id: String) throws -> Tag? {
        let predicate = #Predicate<Tag> { tag in
            tag.id == id && tag.isDeleted == false
        }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        let results = try modelContext.fetch(descriptor)
        return results.first
    }

    // MARK: - Update

    /// Updates a tag's name and/or color.
    ///
    /// - Parameters:
    ///   - tag: The tag to update
    ///   - name: The new name (optional, will be trimmed if provided)
    ///   - colorHex: The new color hex (optional)
    /// - Throws: `TagServiceError.emptyTagName` if new name is empty after trimming
    /// - Throws: `TagServiceError.tagNameTooLong` if new name exceeds max length
    /// - Throws: `TagServiceError.duplicateTagName` if new name conflicts with existing tag
    func updateTag(_ tag: Tag, name: String? = nil, colorHex: String?? = nil) throws {
        var hasChanges = false

        // Update name if provided
        if let newName = name {
            let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedName.isEmpty else {
                throw TagServiceError.emptyTagName
            }

            guard trimmedName.count <= Self.maxTagNameLength else {
                throw TagServiceError.tagNameTooLong(maxLength: Self.maxTagNameLength)
            }

            // Check for duplicate only if name is changing
            let newNormalizedName = trimmedName.lowercased().trimmingCharacters(in: .whitespaces)
            if newNormalizedName != tag.normalizedName {
                if let existingTag = try findTagByNormalizedName(newNormalizedName) {
                    throw TagServiceError.duplicateTagName(existingName: existingTag.name)
                }
            }

            if tag.name != trimmedName {
                tag.name = trimmedName
                hasChanges = true
            }
        }

        // Update color if provided (use Optional<String?> to distinguish nil from not provided)
        if let newColorHex = colorHex {
            if tag.colorHex != newColorHex {
                tag.colorHex = newColorHex
                hasChanges = true
            }
        }

        if hasChanges {
            tag.updatedAt = Date()
            tag.syncState = .pending
            tag.revision += 1

            try eventService.recordTagUpdated(tag)
            try modelContext.save()
            syncManager?.triggerImmediatePush()
        }
    }

    // MARK: - Delete

    /// Soft-deletes a tag.
    ///
    /// The tag will be marked as deleted but retained for sync purposes.
    /// The tag will be automatically removed from all stack associations.
    ///
    /// - Parameter tag: The tag to delete
    func deleteTag(_ tag: Tag) throws {
        tag.isDeleted = true
        tag.updatedAt = Date()
        tag.syncState = .pending
        tag.revision += 1

        try eventService.recordTagDeleted(tag)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }
}
