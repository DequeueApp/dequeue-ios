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

@Suite("Tag Service Tests")
@MainActor
struct TagServiceTests {
    @Test("createTag creates tag with valid name")
    func createTagWithValidName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "Swift")

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
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "  Swift  ")

        #expect(tag.name == "Swift")
        #expect(tag.normalizedName == "swift")
    }

    @Test("createTag with color")
    func createTagWithColor() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "Urgent", colorHex: "#FF0000")

        #expect(tag.name == "Urgent")
        #expect(tag.colorHex == "#FF0000")
    }

    @Test("createTag throws on empty name")
    func createTagThrowsOnEmptyName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        #expect(throws: TagServiceError.emptyTagName) {
            _ = try service.createTag(name: "")
        }
    }

    @Test("createTag throws on whitespace-only name")
    func createTagThrowsOnWhitespaceOnlyName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        #expect(throws: TagServiceError.emptyTagName) {
            _ = try service.createTag(name: "   ")
        }
    }

    @Test("createTag throws on name too long")
    func createTagThrowsOnNameTooLong() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let longName = String(repeating: "a", count: 51)

        #expect(throws: TagServiceError.tagNameTooLong(maxLength: 50)) {
            _ = try service.createTag(name: longName)
        }
    }

    @Test("createTag throws on duplicate name (case insensitive)")
    func createTagThrowsOnDuplicateName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        _ = try service.createTag(name: "Swift")

        #expect(throws: TagServiceError.duplicateTagName(existingName: "Swift")) {
            _ = try service.createTag(name: "swift")
        }
    }

    @Test("createTag throws on duplicate with different casing")
    func createTagThrowsOnDuplicateWithDifferentCasing() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        _ = try service.createTag(name: "Frontend")

        #expect(throws: TagServiceError.duplicateTagName(existingName: "Frontend")) {
            _ = try service.createTag(name: "FRONTEND")
        }
    }

    @Test("findOrCreateTag returns existing tag")
    func findOrCreateTagReturnsExisting() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let original = try service.createTag(name: "Swift")
        let found = try service.findOrCreateTag(name: "swift")

        #expect(original.id == found.id)
    }

    @Test("findOrCreateTag creates new tag if not exists")
    func findOrCreateTagCreatesNew() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.findOrCreateTag(name: "NewTag")

        #expect(tag.name == "NewTag")
    }

    @Test("getAllTags returns all non-deleted tags")
    func getAllTagsReturnsNonDeleted() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        _ = try service.createTag(name: "Swift")
        _ = try service.createTag(name: "Kotlin")
        let deletedTag = try service.createTag(name: "Deleted")
        try service.deleteTag(deletedTag)

        let tags = try service.getAllTags()

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
        let service = TagService(modelContext: context)

        _ = try service.createTag(name: "Swift")
        _ = try service.createTag(name: "SwiftUI")
        _ = try service.createTag(name: "Kotlin")

        let results = try service.searchTags(query: "swift")

        #expect(results.count == 2)
        #expect(results.contains { $0.name == "Swift" })
        #expect(results.contains { $0.name == "SwiftUI" })
    }

    @Test("searchTags with empty query returns all")
    func searchTagsEmptyQueryReturnsAll() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        _ = try service.createTag(name: "Swift")
        _ = try service.createTag(name: "Kotlin")

        let results = try service.searchTags(query: "")

        #expect(results.count == 2)
    }

    @Test("updateTag changes name")
    func updateTagChangesName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "Swift")
        let originalRevision = tag.revision

        try service.updateTag(tag, name: "SwiftUI")

        #expect(tag.name == "SwiftUI")
        #expect(tag.normalizedName == "swiftui")
        #expect(tag.revision == originalRevision + 1)
    }

    @Test("updateTag changes color")
    func updateTagChangesColor() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "Urgent")
        try service.updateTag(tag, colorHex: "#FF0000")

        #expect(tag.colorHex == "#FF0000")
    }

    @Test("updateTag clears color with nil")
    func updateTagClearsColor() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "Urgent", colorHex: "#FF0000")
        try service.updateTag(tag, colorHex: Optional<String?>.some(nil))

        #expect(tag.colorHex == nil)
    }

    @Test("updateTag throws on duplicate name")
    func updateTagThrowsOnDuplicateName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        _ = try service.createTag(name: "Swift")
        let kotlinTag = try service.createTag(name: "Kotlin")

        #expect(throws: TagServiceError.duplicateTagName(existingName: "Swift")) {
            try service.updateTag(kotlinTag, name: "swift")
        }
    }

    @Test("updateTag allows same normalized name (same tag)")
    func updateTagAllowsSameNormalizedName() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "Swift")

        // Changing casing should be allowed for the same tag
        try service.updateTag(tag, name: "SWIFT")

        #expect(tag.name == "SWIFT")
        #expect(tag.normalizedName == "swift")
    }

    @Test("deleteTag soft deletes")
    func deleteTagSoftDeletes() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "Swift")
        let originalRevision = tag.revision

        try service.deleteTag(tag)

        #expect(tag.isDeleted == true)
        #expect(tag.syncState == .pending)
        #expect(tag.revision == originalRevision + 1)
    }

    @Test("findTagById returns tag")
    func findTagByIdReturnsTag() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "Swift")
        let found = try service.findTagById(tag.id)

        #expect(found?.id == tag.id)
        #expect(found?.name == "Swift")
    }

    @Test("findTagById returns nil for deleted tag")
    func findTagByIdReturnsNilForDeleted() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Tag.self, Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: config)
        let context = ModelContext(container)
        let service = TagService(modelContext: context)

        let tag = try service.createTag(name: "Swift")
        let tagId = tag.id
        try service.deleteTag(tag)

        let found = try service.findTagById(tagId)

        #expect(found == nil)
    }
}
