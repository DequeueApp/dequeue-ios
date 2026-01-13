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
        // Fetch all stacks (including deleted ones for complete migration)
        let stackDescriptor = FetchDescriptor<Stack>()
        let allStacks = try modelContext.fetch(stackDescriptor)

        // Filter to stacks with legacy tags that need migration
        let stacksToMigrate = allStacks.filter { !$0.tags.isEmpty }

        guard !stacksToMigrate.isEmpty else {
            return 0
        }

        // Collect all unique tag names for efficient batch creation
        var uniqueTagNames = Set<String>()
        for stack in stacksToMigrate {
            for tagName in stack.tags {
                let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                uniqueTagNames.insert(trimmed.lowercased())
            }
        }

        // Fetch existing tags to avoid duplicates
        let tagDescriptor = FetchDescriptor<Tag>()
        let existingTags = try modelContext.fetch(tagDescriptor)
        var tagsByNormalizedName: [String: Tag] = [:]
        for tag in existingTags where !tag.isDeleted {
            tagsByNormalizedName[tag.normalizedName] = tag
        }

        // Create missing tags
        for tagName in uniqueTagNames {
            guard tagsByNormalizedName[tagName] == nil else { continue }

            // Find original casing from any stack's tags array
            var displayName = tagName
            outer: for stack in stacksToMigrate {
                for stackTagName in stack.tags {
                    if stackTagName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == tagName {
                        displayName = stackTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                        break outer
                    }
                }
            }

            let tag = Tag(
                name: displayName,
                syncState: .pending
            )
            modelContext.insert(tag)
            tagsByNormalizedName[tagName] = tag
        }

        // Associate tags with stacks
        for stack in stacksToMigrate {
            for tagName in stack.tags {
                let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let normalizedName = trimmed.lowercased()
                if let tag = tagsByNormalizedName[normalizedName] {
                    // Add tag to stack if not already present
                    if !stack.tagObjects.contains(where: { $0.id == tag.id }) {
                        stack.tagObjects.append(tag)
                    }
                }
            }

            // Clear legacy tags array to mark as migrated
            stack.tags = []
            stack.syncState = .pending
        }

        try modelContext.save()

        return stacksToMigrate.count
    }
}
