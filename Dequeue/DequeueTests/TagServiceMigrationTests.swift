//
//  TagServiceMigrationTests.swift
//  DequeueTests
//
//  Tests for TagService+Migration — duplicate merging and legacy string tag migration
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Tag.self,
        Arc.self,
        Attachment.self,
        Device.self,
        SyncConflict.self,
        configurations: config
    )
}

/// Checks if a tag is soft-deleted using a FetchDescriptor predicate.
/// This avoids PersistentModel.isDeleted shadowing the stored property.
private func isTagSoftDeleted(_ tag: Dequeue.Tag, in context: ModelContext) throws -> Bool {
    let tagId = tag.id
    let descriptor = FetchDescriptor<Dequeue.Tag>(
        predicate: #Predicate<Dequeue.Tag> { $0.id == tagId && $0.isDeleted == true }
    )
    return try !context.fetch(descriptor).isEmpty
}

/// Checks if a tag is NOT soft-deleted using a FetchDescriptor predicate.
private func isTagActive(_ tag: Dequeue.Tag, in context: ModelContext) throws -> Bool {
    let tagId = tag.id
    let descriptor = FetchDescriptor<Dequeue.Tag>(
        predicate: #Predicate<Dequeue.Tag> { $0.id == tagId && $0.isDeleted == false }
    )
    return try !context.fetch(descriptor).isEmpty
}

// MARK: - Merge Duplicate Tags Tests

@Suite("TagService mergeDuplicateTags", .serialized)
@MainActor
struct MergeDuplicateTagsTests {

    @Test("no duplicates returns zero counts")
    func noDuplicates() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tag1 = Tag(name: "work")
        let tag2 = Tag(name: "personal")
        let tag3 = Tag(name: "urgent")
        context.insert(tag1)
        context.insert(tag2)
        context.insert(tag3)
        try context.save()

        let result = try TagService.mergeDuplicateTags(modelContext: context)

        #expect(result.duplicateGroupsFound == 0)
        #expect(result.tagsMerged == 0)
        #expect(result.stacksUpdated == 0)
    }

    @Test("single group of duplicates merges correctly")
    func singleDuplicateGroup() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let oldest = Tag(name: "Work", createdAt: Date(timeIntervalSince1970: 1000))
        let newer = Tag(name: "work", createdAt: Date(timeIntervalSince1970: 2000))
        let newest = Tag(name: "WORK", createdAt: Date(timeIntervalSince1970: 3000))
        context.insert(oldest)
        context.insert(newer)
        context.insert(newest)
        try context.save()

        let result = try TagService.mergeDuplicateTags(modelContext: context)

        #expect(result.duplicateGroupsFound == 1)
        #expect(result.tagsMerged == 2)
        #expect(try isTagActive(oldest, in: context))
        #expect(try isTagSoftDeleted(newer, in: context))
        #expect(try isTagSoftDeleted(newest, in: context))
    }

    @Test("multiple duplicate groups all resolved")
    func multipleDuplicateGroups() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Group 1: "work" variants
        let work1 = Tag(name: "work", createdAt: Date(timeIntervalSince1970: 1000))
        let work2 = Tag(name: "Work", createdAt: Date(timeIntervalSince1970: 2000))
        // Group 2: "urgent" variants
        let urgent1 = Tag(name: "urgent", createdAt: Date(timeIntervalSince1970: 1500))
        let urgent2 = Tag(name: "Urgent", createdAt: Date(timeIntervalSince1970: 2500))
        let urgent3 = Tag(name: "URGENT", createdAt: Date(timeIntervalSince1970: 3500))
        // Unique tag (no duplicates)
        let unique = Tag(name: "personal")

        for tag in [work1, work2, urgent1, urgent2, urgent3, unique] {
            context.insert(tag)
        }
        try context.save()

        let result = try TagService.mergeDuplicateTags(modelContext: context)

        #expect(result.duplicateGroupsFound == 2)
        #expect(result.tagsMerged == 3) // 1 from work + 2 from urgent
        #expect(try isTagActive(work1, in: context))
        #expect(try isTagSoftDeleted(work2, in: context))
        #expect(try isTagActive(urgent1, in: context))
        #expect(try isTagSoftDeleted(urgent2, in: context))
        #expect(try isTagSoftDeleted(urgent3, in: context))
        #expect(try isTagActive(unique, in: context))
    }

    @Test("stack reassignment moves stacks from duplicates to canonical tag")
    func stackReassignment() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let canonical = Tag(name: "work", createdAt: Date(timeIntervalSince1970: 1000))
        let duplicate = Tag(name: "Work", createdAt: Date(timeIntervalSince1970: 2000))
        context.insert(canonical)
        context.insert(duplicate)

        let stack = Stack(title: "My Stack")
        context.insert(stack)
        stack.tagObjects.append(duplicate)
        try context.save()

        let result = try TagService.mergeDuplicateTags(modelContext: context)

        #expect(result.stacksUpdated == 1)
        // Stack should now reference canonical, not duplicate
        #expect(stack.tagObjects.contains { $0.id == canonical.id })
        #expect(!stack.tagObjects.contains { $0.id == duplicate.id })
        #expect(stack.syncState == .pending)
    }

    @Test("keeps oldest tag as canonical")
    func keepsOldestTag() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let newest = Tag(name: "Tag", createdAt: Date(timeIntervalSince1970: 3000))
        let oldest = Tag(name: "tag", createdAt: Date(timeIntervalSince1970: 1000))
        let middle = Tag(name: "TAG", createdAt: Date(timeIntervalSince1970: 2000))
        context.insert(newest)
        context.insert(oldest)
        context.insert(middle)
        try context.save()

        _ = try TagService.mergeDuplicateTags(modelContext: context)

        #expect(try isTagActive(oldest, in: context))
        #expect(try isTagSoftDeleted(middle, in: context))
        #expect(try isTagSoftDeleted(newest, in: context))
    }

    @Test("soft-deletes duplicates with pending sync state")
    func softDeletesSetsSync() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let keep = Tag(name: "work", createdAt: Date(timeIntervalSince1970: 1000))
        let dup = Tag(name: "Work", createdAt: Date(timeIntervalSince1970: 2000), syncState: .synced)
        context.insert(keep)
        context.insert(dup)
        try context.save()

        _ = try TagService.mergeDuplicateTags(modelContext: context)

        #expect(try isTagSoftDeleted(dup, in: context))
        #expect(dup.syncState == .pending)
    }

    @Test("idempotent — running twice produces same result")
    func idempotent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tag1 = Tag(name: "work", createdAt: Date(timeIntervalSince1970: 1000))
        let tag2 = Tag(name: "Work", createdAt: Date(timeIntervalSince1970: 2000))
        context.insert(tag1)
        context.insert(tag2)
        try context.save()

        let firstResult = try TagService.mergeDuplicateTags(modelContext: context)
        #expect(firstResult.tagsMerged == 1)

        // Second run should find no more duplicates (deleted tags excluded)
        let secondResult = try TagService.mergeDuplicateTags(modelContext: context)
        #expect(secondResult.duplicateGroupsFound == 0)
        #expect(secondResult.tagsMerged == 0)
    }

    @Test("stack already on canonical tag is not duplicated")
    func stackAlreadyOnCanonical() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let canonical = Tag(name: "work", createdAt: Date(timeIntervalSince1970: 1000))
        let duplicate = Tag(name: "Work", createdAt: Date(timeIntervalSince1970: 2000))
        context.insert(canonical)
        context.insert(duplicate)

        let stack = Stack(title: "My Stack")
        context.insert(stack)
        // Stack already has canonical AND duplicate
        stack.tagObjects.append(canonical)
        stack.tagObjects.append(duplicate)
        try context.save()

        _ = try TagService.mergeDuplicateTags(modelContext: context)

        // Should have only canonical, not a duplicate reference
        let canonicalRefs = stack.tagObjects.filter { $0.id == canonical.id }
        #expect(canonicalRefs.count == 1)
        #expect(!stack.tagObjects.contains { $0.id == duplicate.id })
    }

    @Test("merge with no stacks to reassign reports zero updates")
    func noStacksToReassign() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Duplicate tags with no stacks attached at all
        let canonical = Tag(name: "work", createdAt: Date(timeIntervalSince1970: 1000))
        let duplicate = Tag(name: "Work", createdAt: Date(timeIntervalSince1970: 2000))
        context.insert(canonical)
        context.insert(duplicate)
        try context.save()

        let result = try TagService.mergeDuplicateTags(modelContext: context)

        #expect(result.duplicateGroupsFound == 1)
        #expect(result.tagsMerged == 1)
        #expect(result.stacksUpdated == 0)
    }
}

// MARK: - Migrate String Tags to Tag Objects Tests

@Suite("TagService migrateStringTagsToTagObjects", .serialized)
@MainActor
struct MigrateStringTagsTests {

    @Test("no stacks to migrate returns zero")
    func noStacksToMigrate() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Stack with empty tags (already migrated or never had tags)
        let stack = Stack(title: "Clean Stack", tags: [])
        context.insert(stack)
        try context.save()

        let count = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        #expect(count == 0)
    }

    @Test("migrates stacks with string tags to Tag objects")
    func migratesStringTags() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Tagged Stack", tags: ["work", "urgent"])
        context.insert(stack)
        try context.save()

        let count = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        #expect(count == 1)
        #expect(stack.tags.isEmpty) // Legacy tags cleared
        #expect(stack.tagObjects.count == 2)

        let tagNames = Set(stack.tagObjects.map(\.name))
        #expect(tagNames.contains("work"))
        #expect(tagNames.contains("urgent"))
    }

    @Test("preserves original casing in Tag name")
    func preservesOriginalCasing() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Stack", tags: ["MyProject"])
        context.insert(stack)
        try context.save()

        _ = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        let tag = stack.tagObjects.first
        #expect(tag?.name == "MyProject")
    }

    @Test("handles empty tag strings by skipping them")
    func handlesEmptyTagStrings() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Stack", tags: ["valid", "", "  ", "also-valid"])
        context.insert(stack)
        try context.save()

        _ = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        #expect(stack.tagObjects.count == 2)
        let tagNames = Set(stack.tagObjects.map(\.name))
        #expect(tagNames.contains("valid"))
        #expect(tagNames.contains("also-valid"))
    }

    @Test("idempotent — already migrated stacks are skipped")
    func idempotent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Stack", tags: ["work"])
        context.insert(stack)
        try context.save()

        let firstCount = try TagService.migrateStringTagsToTagObjects(modelContext: context)
        #expect(firstCount == 1)
        #expect(stack.tags.isEmpty)

        // Second run: stack.tags is now empty, so it should be skipped
        let secondCount = try TagService.migrateStringTagsToTagObjects(modelContext: context)
        #expect(secondCount == 0)
        #expect(stack.tagObjects.count == 1) // Tag objects preserved
    }

    @Test("creates missing Tag entities for new tag names")
    func createsMissingTagEntities() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // No pre-existing Tag entities
        let stack = Stack(title: "Stack", tags: ["brand-new-tag"])
        context.insert(stack)
        try context.save()

        _ = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        // A Tag entity should have been created
        let descriptor = FetchDescriptor<Dequeue.Tag>()
        let allTags = try context.fetch(descriptor)
        #expect(allTags.count == 1)
        #expect(allTags.first?.name == "brand-new-tag")
    }

    @Test("reuses existing Tag entities instead of creating duplicates")
    func reusesExistingTags() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Pre-create a Tag entity
        let existingTag = Tag(name: "work")
        context.insert(existingTag)

        let stack = Stack(title: "Stack", tags: ["work"])
        context.insert(stack)
        try context.save()

        _ = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        // Should reuse existing tag, not create a new one
        let descriptor = FetchDescriptor<Dequeue.Tag>()
        let allTags = try context.fetch(descriptor)
        let nonDeletedTags = allTags.filter { !$0.isDeleted }
        #expect(nonDeletedTags.count == 1)
        #expect(stack.tagObjects.first?.id == existingTag.id)
    }

    @Test("sets syncState to pending on migrated stacks")
    func setsSyncPending() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack = Stack(title: "Stack", tags: ["work"], syncState: .synced)
        context.insert(stack)
        try context.save()

        _ = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        #expect(stack.syncState == .pending)
    }

    @Test("migrates multiple stacks sharing the same tag name")
    func multipleStacksSameTag() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let stack1 = Stack(title: "Stack 1", tags: ["shared"])
        let stack2 = Stack(title: "Stack 2", tags: ["shared"])
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        let count = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        #expect(count == 2)

        // Both stacks should reference the same Tag entity
        let tag1 = stack1.tagObjects.first
        let tag2 = stack2.tagObjects.first
        #expect(tag1 != nil)
        #expect(tag1?.id == tag2?.id)
    }
}
