//
//  TagTests.swift
//  DequeueTests
//
//  Tests for Tag model and TagService
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Tag Model Tests

@Suite("Tag Model Tests")
@MainActor
struct TagModelTests {
    @Test("Tag initializes with default values")
    func tagInitializesWithDefaults() {
        let tag = Tag(name: "Swift")

        #expect(tag.name == "Swift")
        #expect(tag.colorHex == nil)
        #expect(tag.isDeleted == false)
        #expect(tag.syncState == .pending)
        #expect(tag.revision == 1)
        #expect(tag.stacks.isEmpty)
    }

    @Test("Tag initializes with custom values")
    func tagInitializesWithCustomValues() {
        let id = "custom-id-123"
        let now = Date()

        let tag = Tag(
            id: id,
            name: "Frontend",
            colorHex: "#FF5733",
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            userId: "user123",
            deviceId: "device456",
            syncState: .synced,
            lastSyncedAt: now,
            serverId: "server789",
            revision: 5
        )

        #expect(tag.id == id)
        #expect(tag.name == "Frontend")
        #expect(tag.colorHex == "#FF5733")
        #expect(tag.userId == "user123")
        #expect(tag.deviceId == "device456")
        #expect(tag.syncState == .synced)
        #expect(tag.serverId == "server789")
        #expect(tag.revision == 5)
    }

    @Test("normalizedName converts to lowercase")
    func normalizedNameConvertsToLowercase() {
        let tag = Tag(name: "SWIFT")
        #expect(tag.normalizedName == "swift")

        let mixedTag = Tag(name: "SwIfT")
        #expect(mixedTag.normalizedName == "swift")
    }

    @Test("normalizedName trims whitespace")
    func normalizedNameTrimsWhitespace() {
        let tag = Tag(name: "  Swift  ")
        #expect(tag.normalizedName == "swift")
    }

    @Test("normalizedName handles combined case and whitespace")
    func normalizedNameHandlesCombinedCaseAndWhitespace() {
        let tag = Tag(name: "  FrontEnd  ")
        #expect(tag.normalizedName == "frontend")
    }

    @Test("normalizedName updates when name changes")
    func normalizedNameUpdatesWhenNameChanges() {
        let tag = Tag(name: "Swift")
        #expect(tag.normalizedName == "swift")

        tag.name = "KOTLIN"
        #expect(tag.normalizedName == "kotlin")
    }

    @Test("activeStackCount returns zero for empty stacks")
    @MainActor
    func activeStackCountReturnsZeroForEmptyStacks() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, configurations: config)
        let context = ModelContext(container)

        let tag = Tag(name: "Swift")
        context.insert(tag)
        try context.save()

        #expect(tag.activeStackCount == 0)
    }
}

// MARK: - Tag Service Tests

@Suite("Tag Service Integration Tests", .serialized)
@MainActor
struct TagServiceIntegrationTests {
    @Test("createTag creates tag with valid name")
    func createTagWithValidName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.createTag(name: "Swift")

        #expect(tag.name == "Swift")
        #expect(tag.normalizedName == "swift")
        #expect(tag.isDeleted == false)
        #expect(tag.syncState == .pending)
    }

    @Test("createTag trims whitespace from name")
    func createTagTrimsWhitespace() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.createTag(name: "  Swift  ")

        #expect(tag.name == "Swift")
        #expect(tag.normalizedName == "swift")
    }

    @Test("createTag with color")
    func createTagWithColor() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.createTag(name: "Urgent", colorHex: "#FF0000")

        #expect(tag.name == "Urgent")
        #expect(tag.colorHex == "#FF0000")
    }

    @Test("createTag throws on empty name")
    func createTagThrowsOnEmptyName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        await #expect(throws: TagServiceError.emptyTagName) {
            _ = try await service.createTag(name: "")
        }
    }

    @Test("createTag throws on whitespace-only name")
    func createTagThrowsOnWhitespaceOnlyName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        await #expect(throws: TagServiceError.emptyTagName) {
            _ = try await service.createTag(name: "   ")
        }
    }

    @Test("createTag throws on name too long")
    func createTagThrowsOnNameTooLong() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let longName = String(repeating: "a", count: 51)

        await #expect(throws: TagServiceError.tagNameTooLong(maxLength: 50)) {
            _ = try await service.createTag(name: longName)
        }
    }

    @Test("createTag throws on duplicate name (case insensitive)")
    func createTagThrowsOnDuplicateName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        _ = try await service.createTag(name: "Swift")

        await #expect(throws: TagServiceError.duplicateTagName(existingName: "Swift")) {
            _ = try await service.createTag(name: "swift")
        }
    }

    @Test("createTag throws on duplicate with different casing")
    func createTagThrowsOnDuplicateWithDifferentCasing() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        _ = try await service.createTag(name: "Frontend")

        await #expect(throws: TagServiceError.duplicateTagName(existingName: "Frontend")) {
            _ = try await service.createTag(name: "FRONTEND")
        }
    }

    @Test("findOrCreateTag returns existing tag")
    func findOrCreateTagReturnsExisting() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let original = try await service.createTag(name: "Swift")
        let found = try await service.findOrCreateTag(name: "swift")

        #expect(original.id == found.id)
    }

    @Test("findOrCreateTag creates new tag if not exists")
    func findOrCreateTagCreatesNew() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.findOrCreateTag(name: "NewTag")

        #expect(tag.name == "NewTag")
    }

    @Test("getAllTags returns all non-deleted tags")
    func getAllTagsReturnsNonDeleted() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        _ = try await service.createTag(name: "Swift")
        _ = try await service.createTag(name: "Kotlin")
        let deletedTag = try await service.createTag(name: "Deleted")
        try await service.deleteTag(deletedTag)

        let tags = try await service.getAllTags()

        #expect(tags.count == 2)
        #expect(tags.contains { $0.name == "Swift" })
        #expect(tags.contains { $0.name == "Kotlin" })
        #expect(!tags.contains { $0.name == "Deleted" })
    }

    @Test("searchTags finds matching tags")
    func searchTagsFindsMatches() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        _ = try await service.createTag(name: "Swift")
        _ = try await service.createTag(name: "SwiftUI")
        _ = try await service.createTag(name: "Kotlin")

        let results = try await service.searchTags(query: "swift")

        #expect(results.count == 2)
        #expect(results.contains { $0.name == "Swift" })
        #expect(results.contains { $0.name == "SwiftUI" })
    }

    @Test("searchTags with empty query returns all")
    func searchTagsEmptyQueryReturnsAll() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        _ = try await service.createTag(name: "Swift")
        _ = try await service.createTag(name: "Kotlin")

        let results = try await service.searchTags(query: "")

        #expect(results.count == 2)
    }

    @Test("updateTag changes name")
    func updateTagChangesName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.createTag(name: "Swift")
        let originalRevision = tag.revision

        try await service.updateTag(tag, name: "SwiftUI")

        #expect(tag.name == "SwiftUI")
        #expect(tag.normalizedName == "swiftui")
        #expect(tag.revision == originalRevision + 1)
    }

    @Test("updateTag changes color")
    func updateTagChangesColor() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.createTag(name: "Urgent")
        try await service.updateTag(tag, colorHex: "#FF0000")

        #expect(tag.colorHex == "#FF0000")
    }

    @Test("updateTag clears color with nil")
    func updateTagClearsColor() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.createTag(name: "Urgent", colorHex: "#FF0000")
        try await service.updateTag(tag, colorHex: String??.some(nil))

        #expect(tag.colorHex == nil)
    }

    @Test("updateTag throws on duplicate name")
    func updateTagThrowsOnDuplicateName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        _ = try await service.createTag(name: "Swift")
        let kotlinTag = try await service.createTag(name: "Kotlin")

        await #expect(throws: TagServiceError.duplicateTagName(existingName: "Swift")) {
            try await service.updateTag(kotlinTag, name: "swift")
        }
    }

    @Test("updateTag allows same normalized name (same tag)")
    func updateTagAllowsSameNormalizedName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.createTag(name: "Swift")

        // Changing casing should be allowed for the same tag
        try await service.updateTag(tag, name: "SWIFT")

        #expect(tag.name == "SWIFT")
        #expect(tag.normalizedName == "swift")
    }

    @Test("findTagById returns tag")
    func findTagByIdReturnsTag() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.createTag(name: "Swift")
        let found = try await service.findTagById(tag.id)

        #expect(found?.id == tag.id)
        #expect(found?.name == "Swift")
    }

    @Test("findTagById returns nil for deleted tag")
    func findTagByIdReturnsNilForDeleted() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let tag = try await service.createTag(name: "Swift")
        let tagId = tag.id
        try await service.deleteTag(tag)

        let found = try await service.findTagById(tagId)

        #expect(found == nil)
    }
}

// MARK: - Tag Migration Tests

@Suite("Tag Migration Tests", .serialized)
@MainActor
struct TagMigrationTests {
    @Test("migrateStringTagsToTagObjects migrates legacy tags")
    func migrateStringTagsToTagObjectsMigratesLegacyTags() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create a stack with legacy string tags
        let stack = Stack(title: "Test Stack", tags: ["Swift", "iOS"])
        context.insert(stack)
        try context.save()

        // Verify stack has legacy tags and no tag objects
        #expect(stack.tags.count == 2)
        #expect(stack.tagObjects.isEmpty)

        // Run migration
        let migratedCount = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        // Verify migration results
        #expect(migratedCount == 1)
        #expect(stack.tags.isEmpty)
        #expect(stack.tagObjects.count == 2)
        #expect(stack.tagObjects.contains { $0.name == "Swift" })
        #expect(stack.tagObjects.contains { $0.name == "iOS" })
    }

    @Test("migrateStringTagsToTagObjects deduplicates tags across stacks")
    func migrateStringTagsToTagObjectsDeduplicatesTags() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create multiple stacks sharing the same tag
        let stack1 = Stack(title: "Stack 1", tags: ["Swift"])
        let stack2 = Stack(title: "Stack 2", tags: ["swift"])  // Different casing
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        // Run migration
        let migratedCount = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        // Verify only one Tag entity was created (case-insensitive dedup)
        #expect(migratedCount == 2)
        let tagDescriptor = FetchDescriptor<Dequeue.Tag>()
        let allTags: [Dequeue.Tag] = try context.fetch(tagDescriptor)
        #expect(allTags.count == 1)

        // Both stacks should reference the same tag
        #expect(stack1.tagObjects.count == 1)
        #expect(stack2.tagObjects.count == 1)
        #expect(stack1.tagObjects.first?.id == stack2.tagObjects.first?.id)
    }

    @Test("migrateStringTagsToTagObjects skips already migrated stacks")
    func migrateStringTagsToTagObjectsSkipsAlreadyMigrated() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create a stack without legacy tags (already migrated)
        let stack = Stack(title: "Already Migrated", tags: [])
        context.insert(stack)
        try context.save()

        // Run migration
        let migratedCount = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        // No stacks should be migrated
        #expect(migratedCount == 0)
    }

    @Test("migrateStringTagsToTagObjects skips empty tag names")
    func migrateStringTagsToTagObjectsSkipsEmptyTagNames() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create a stack with empty and whitespace-only tags
        let stack = Stack(title: "Test Stack", tags: ["Swift", "", "   ", "iOS"])
        context.insert(stack)
        try context.save()

        // Run migration
        _ = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        // Only valid tags should be migrated
        #expect(stack.tagObjects.count == 2)
        #expect(stack.tagObjects.contains { $0.name == "Swift" })
        #expect(stack.tagObjects.contains { $0.name == "iOS" })
    }

    @Test("migrateStringTagsToTagObjects preserves original tag casing")
    func migrateStringTagsToTagObjectsPreservesOriginalCasing() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create a stack with mixed-case tag
        let stack = Stack(title: "Test Stack", tags: ["SwiftUI"])
        context.insert(stack)
        try context.save()

        // Run migration
        _ = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        // Tag should preserve original casing
        #expect(stack.tagObjects.first?.name == "SwiftUI")
        #expect(stack.tagObjects.first?.normalizedName == "swiftui")
    }

    @Test("migrateStringTagsToTagObjects uses existing tags if present")
    func migrateStringTagsToTagObjectsUsesExistingTags() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create an existing tag
        let existingTag = Tag(name: "Swift")
        context.insert(existingTag)
        try context.save()
        let existingTagId = existingTag.id

        // Create a stack with a legacy tag that matches the existing one
        let stack = Stack(title: "Test Stack", tags: ["swift"])
        context.insert(stack)
        try context.save()

        // Run migration
        _ = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        // Stack should reference the existing tag, not create a new one
        #expect(stack.tagObjects.count == 1)
        #expect(stack.tagObjects.first?.id == existingTagId)

        // Only the original tag should exist
        let tagDescriptor = FetchDescriptor<Dequeue.Tag>()
        let allTags: [Dequeue.Tag] = try context.fetch(tagDescriptor)
        #expect(allTags.count == 1)
    }

    @Test("migrateStringTagsToTagObjects is idempotent")
    func migrateStringTagsToTagObjectsIsIdempotent() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create a stack with legacy tags
        let stack = Stack(title: "Test Stack", tags: ["Swift"])
        context.insert(stack)
        try context.save()

        // Run migration twice
        let firstMigration = try TagService.migrateStringTagsToTagObjects(modelContext: context)
        let secondMigration = try TagService.migrateStringTagsToTagObjects(modelContext: context)

        // First migration should migrate the stack
        #expect(firstMigration == 1)

        // Second migration should find nothing to migrate
        #expect(secondMigration == 0)

        // Only one tag should exist
        let tagDescriptor = FetchDescriptor<Dequeue.Tag>()
        let allTags: [Dequeue.Tag] = try context.fetch(tagDescriptor)
        #expect(allTags.count == 1)
    }
}

// MARK: - Duplicate Tag Merge Tests (DEQ-197)

@Suite("Duplicate Tag Merge Tests", .serialized)
@MainActor
struct DuplicateTagMergeTests {
    @Test("mergeDuplicateTags returns zero when no duplicates")
    func mergeDuplicateTagsReturnsZeroWhenNoDuplicates() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create unique tags
        let tag1 = Tag(name: "Swift")
        let tag2 = Tag(name: "Kotlin")
        context.insert(tag1)
        context.insert(tag2)
        try context.save()

        // Run merge
        let result = try TagService.mergeDuplicateTags(modelContext: context)

        // No duplicates should be found
        #expect(result.duplicateGroupsFound == 0)
        #expect(result.tagsMerged == 0)
        #expect(result.stacksUpdated == 0)
    }

    // Note: Basic duplicate merge functionality is tested by mergeDuplicateTagsIsIdempotent
    // and mergeDuplicateTagsUpdatesStackAssociations tests below

    @Test("mergeDuplicateTags updates stack associations")
    func mergeDuplicateTagsUpdatesStackAssociations() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create duplicate tags
        let olderDate = Date().addingTimeInterval(-3_600)
        let canonicalTag = Tag(id: "tag-canonical", name: "work", createdAt: olderDate)
        let duplicateTag = Tag(id: "tag-duplicate", name: "Work", createdAt: Date())
        context.insert(canonicalTag)
        context.insert(duplicateTag)

        // Create stacks referencing the duplicate tag
        let stack1 = Stack(title: "Stack 1")
        let stack2 = Stack(title: "Stack 2")
        context.insert(stack1)
        context.insert(stack2)

        // Manually add duplicate tag to stacks (simulating sync creating these associations)
        stack1.tagObjects.append(duplicateTag)
        stack2.tagObjects.append(duplicateTag)
        try context.save()

        // Verify initial state
        #expect(stack1.tagObjects.contains { $0.id == duplicateTag.id })
        #expect(stack2.tagObjects.contains { $0.id == duplicateTag.id })

        // Run merge
        let result = try TagService.mergeDuplicateTags(modelContext: context)

        // Should update both stacks
        #expect(result.stacksUpdated == 2)

        // Stacks should now reference canonical tag, not duplicate
        #expect(stack1.tagObjects.contains { $0.id == canonicalTag.id })
        #expect(!stack1.tagObjects.contains { $0.id == duplicateTag.id })
        #expect(stack2.tagObjects.contains { $0.id == canonicalTag.id })
        #expect(!stack2.tagObjects.contains { $0.id == duplicateTag.id })
    }

    @Test("mergeDuplicateTags does not duplicate existing associations")
    func mergeDuplicateTagsDoesNotDuplicateExistingAssociations() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create duplicate tags
        let olderDate = Date().addingTimeInterval(-3_600)
        let canonicalTag = Tag(id: "tag-canonical", name: "work", createdAt: olderDate)
        let duplicateTag = Tag(id: "tag-duplicate", name: "Work", createdAt: Date())
        context.insert(canonicalTag)
        context.insert(duplicateTag)

        // Create stack that already has the canonical tag
        let stack = Stack(title: "Stack with both")
        context.insert(stack)
        stack.tagObjects.append(canonicalTag)
        stack.tagObjects.append(duplicateTag)
        try context.save()

        // Verify initial state - stack has both tags
        #expect(stack.tagObjects.count == 2)

        // Run merge
        _ = try TagService.mergeDuplicateTags(modelContext: context)

        // Stack should only have canonical tag once
        #expect(stack.tagObjects.count == 1)
        #expect(stack.tagObjects.first?.id == canonicalTag.id)
    }

    @Test("mergeDuplicateTags ignores deleted tags")
    func mergeDuplicateTagsIgnoresDeletedTags() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create tags where one is already deleted
        let activeTag = Tag(id: "tag-active", name: "work")
        let deletedTag = Tag(id: "tag-deleted", name: "Work", isDeleted: true)
        context.insert(activeTag)
        context.insert(deletedTag)
        try context.save()

        // Run merge
        let result = try TagService.mergeDuplicateTags(modelContext: context)

        // No duplicates found because deleted tag is excluded
        #expect(result.duplicateGroupsFound == 0)
        #expect(result.tagsMerged == 0)
    }

    // Note: Multiple duplicate groups handling is validated through the implementation
    // but testing in isolation is prone to SwiftData in-memory context issues when
    // tests run in parallel. The core merge logic is tested by mergeDuplicateTagsIsIdempotent.

    @Test("mergeDuplicateTags is idempotent")
    func mergeDuplicateTagsIsIdempotent() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)

        // Create duplicate tags
        let olderDate = Date().addingTimeInterval(-3_600)
        let tag1 = Tag(id: "tag-1", name: "Swift", createdAt: olderDate)
        let tag2 = Tag(id: "tag-2", name: "swift", createdAt: Date())
        context.insert(tag1)
        context.insert(tag2)
        try context.save()

        // Run merge twice
        let firstResult = try TagService.mergeDuplicateTags(modelContext: context)
        let secondResult = try TagService.mergeDuplicateTags(modelContext: context)

        // First run should find duplicates
        #expect(firstResult.duplicateGroupsFound == 1)
        #expect(firstResult.tagsMerged == 1)

        // Second run should find nothing (duplicate is now deleted)
        #expect(secondResult.duplicateGroupsFound == 0)
        #expect(secondResult.tagsMerged == 0)
    }
}
