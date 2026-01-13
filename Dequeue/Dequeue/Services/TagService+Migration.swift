//
//  TagService+Migration.swift
//  Dequeue
//
//  Migration methods for TagService - called on app startup
//

import Foundation
import SwiftData

extension TagService {
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
