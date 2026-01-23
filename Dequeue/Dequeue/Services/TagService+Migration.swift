//
//  TagService+Migration.swift
//  Dequeue
//
//  Migration methods for TagService - called on app startup
//

import Foundation
import SwiftData

extension TagService {
    // MARK: - Duplicate Tag Merging (DEQ-197)

    /// Result of the duplicate tag merge operation
    struct MergeDuplicateTagsResult {
        /// Number of duplicate tag groups found
        let duplicateGroupsFound: Int
        /// Total number of duplicate tags merged (deleted)
        let tagsMerged: Int
        /// Number of stacks that had their tag references updated
        let stacksUpdated: Int
    }

    /// Merges duplicate tags that have the same normalized name.
    ///
    /// This handles the case where the same tag was created on multiple devices
    /// before sync detected the duplicate. For each group of duplicate tags:
    /// 1. Keeps the oldest tag (by createdAt)
    /// 2. Moves all stack associations from duplicates to the kept tag
    /// 3. Soft-deletes the duplicate tags
    ///
    /// Call this on app startup to clean up any existing duplicates.
    ///
    /// - Parameter modelContext: The model context to use for the migration
    /// - Returns: Statistics about the merge operation
    @discardableResult
    static func mergeDuplicateTags(modelContext: ModelContext) throws -> MergeDuplicateTagsResult {
        // Fetch all non-deleted tags
        let predicate = #Predicate<Tag> { tag in
            tag.isDeleted == false
        }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        let allTags = try modelContext.fetch(descriptor)

        // Group tags by normalized name
        var tagsByNormalizedName: [String: [Tag]] = [:]
        for tag in allTags {
            let normalizedName = tag.name.lowercased().trimmingCharacters(in: .whitespaces)
            tagsByNormalizedName[normalizedName, default: []].append(tag)
        }

        // Find groups with duplicates
        let duplicateGroups = tagsByNormalizedName.filter { $0.value.count > 1 }

        guard !duplicateGroups.isEmpty else {
            return MergeDuplicateTagsResult(duplicateGroupsFound: 0, tagsMerged: 0, stacksUpdated: 0)
        }

        var totalTagsMerged = 0
        var totalStacksUpdated = 0

        for (normalizedName, tags) in duplicateGroups {
            let (merged, updated) = mergeDuplicateTagGroup(
                normalizedName: normalizedName,
                tags: tags
            )
            totalTagsMerged += merged
            totalStacksUpdated += updated
        }

        try modelContext.save()

        return MergeDuplicateTagsResult(
            duplicateGroupsFound: duplicateGroups.count,
            tagsMerged: totalTagsMerged,
            stacksUpdated: totalStacksUpdated
        )
    }

    /// Merges a single group of duplicate tags into the canonical (oldest) tag
    private static func mergeDuplicateTagGroup(
        normalizedName: String,
        tags: [Tag]
    ) -> (tagsMerged: Int, stacksUpdated: Int) {
        let sortedTags = tags.sorted { $0.createdAt < $1.createdAt }
        guard let canonicalTag = sortedTags.first else { return (0, 0) }

        let duplicateTags = Array(sortedTags.dropFirst())

        ErrorReportingService.addBreadcrumb(
            category: "tag_merge",
            message: "Merging duplicate tags",
            data: [
                "normalized_name": normalizedName,
                "canonical_tag_id": canonicalTag.id,
                "duplicate_count": duplicateTags.count,
                "duplicate_ids": duplicateTags.map(\.id).joined(separator: ",")
            ]
        )

        var stacksUpdated = 0
        for duplicateTag in duplicateTags {
            for stack in duplicateTag.stacks where !stack.isDeleted {
                if !stack.tagObjects.contains(where: { $0.id == canonicalTag.id }) {
                    stack.tagObjects.append(canonicalTag)
                }
                stack.tagObjects.removeAll { $0.id == duplicateTag.id }
                stack.syncState = .pending
                stacksUpdated += 1
            }

            duplicateTag.isDeleted = true
            duplicateTag.updatedAt = Date()
            duplicateTag.syncState = .pending
        }

        return (duplicateTags.count, stacksUpdated)
    }

    // MARK: - Migration

    /// Migrates legacy string-based tags to the Tag model relationship.
    ///
    /// Call this on app startup to convert `Stack.tags: [String]` to `Stack.tagObjects: [Tag]`.
    ///
    /// Migration logic:
    /// 1. Find all stacks with non-empty `tags` arrays that haven't been migrated
    /// 2. For each tag string, find or create a corresponding Tag entity
    /// 3. Add the Tag to the stack's `tagObjects` relationship
    /// 4. Clear the legacy `tags` array to prevent re-migration
    ///
    /// **Important:** This migration is idempotent - stacks with empty `tags` arrays
    /// are assumed to have already been migrated.
    ///
    /// - Parameter modelContext: The model context to use for the migration
    /// - Returns: The number of stacks that were migrated
    @discardableResult
    static func migrateStringTagsToTagObjects(modelContext: ModelContext) throws -> Int {
        let stackDescriptor = FetchDescriptor<Stack>()
        let allStacks = try modelContext.fetch(stackDescriptor)
        let stacksToMigrate = allStacks.filter { !$0.tags.isEmpty }

        guard !stacksToMigrate.isEmpty else { return 0 }

        // Build tag lookup and create missing tags
        var tagsByNormalizedName = try buildTagLookup(modelContext: modelContext)
        try createMissingTags(
            stacksToMigrate: stacksToMigrate,
            tagsByNormalizedName: &tagsByNormalizedName,
            modelContext: modelContext
        )

        // Associate tags with stacks and clear legacy arrays
        for stack in stacksToMigrate {
            associateTagsWithStack(stack, tagsByNormalizedName: tagsByNormalizedName)
            stack.tags = []
            stack.syncState = .pending
        }

        try modelContext.save()
        return stacksToMigrate.count
    }

    // MARK: - Private Helpers

    private static func buildTagLookup(modelContext: ModelContext) throws -> [String: Tag] {
        let tagDescriptor = FetchDescriptor<Tag>()
        let existingTags = try modelContext.fetch(tagDescriptor)
        var lookup: [String: Tag] = [:]
        for tag in existingTags where !tag.isDeleted {
            lookup[tag.normalizedName] = tag
        }
        return lookup
    }

    private static func createMissingTags(
        stacksToMigrate: [Stack],
        tagsByNormalizedName: inout [String: Tag],
        modelContext: ModelContext
    ) throws {
        let uniqueTagNames = collectUniqueTagNames(from: stacksToMigrate)

        for tagName in uniqueTagNames where tagsByNormalizedName[tagName] == nil {
            let displayName = findOriginalCasing(for: tagName, in: stacksToMigrate)
            let tag = Tag(name: displayName, syncState: .pending)
            modelContext.insert(tag)
            tagsByNormalizedName[tagName] = tag
        }
    }

    private static func collectUniqueTagNames(from stacks: [Stack]) -> Set<String> {
        var uniqueNames = Set<String>()
        for stack in stacks {
            for tagName in stack.tags {
                let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    uniqueNames.insert(trimmed.lowercased())
                }
            }
        }
        return uniqueNames
    }

    private static func findOriginalCasing(for normalizedName: String, in stacks: [Stack]) -> String {
        for stack in stacks {
            for stackTagName in stack.tags
            where stackTagName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedName {
                return stackTagName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return normalizedName
    }

    private static func associateTagsWithStack(_ stack: Stack, tagsByNormalizedName: [String: Tag]) {
        for tagName in stack.tags {
            let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalizedName = trimmed.lowercased()
            if let tag = tagsByNormalizedName[normalizedName],
               !stack.tagObjects.contains(where: { $0.id == tag.id }) {
                stack.tagObjects.append(tag)
            }
        }
    }
}
