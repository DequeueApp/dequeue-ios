//
//  TagServiceTests.swift
//  DequeueTests
//
//  Tests for TagService - tag creation and management
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container for TagService tests
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Tag.self,
        Event.self,
        configurations: config
    )
}

@Suite("TagService Tests", .serialized)
@MainActor
struct TagServiceTests {
    // MARK: - Create Tag Tests

    @Test("createTag creates a new tag with name")
    func createTagWithName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "Work")

        #expect(tag.name == "Work")
        #expect(tag.isDeleted == false)
        #expect(tag.syncState == .pending)
    }

    @Test("createTag trims whitespace from name")
    func createTagTrimsWhitespace() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "  Work  ")

        #expect(tag.name == "Work")
    }

    @Test("createTag creates tag with color")
    func createTagWithColor() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "Urgent", colorHex: "#FF5733")

        #expect(tag.name == "Urgent")
        #expect(tag.colorHex == "#FF5733")
    }

    @Test("createTag throws on empty name")
    func createTagThrowsOnEmptyName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        await #expect(throws: TagServiceError.emptyTagName) {
            _ = try await tagService.createTag(name: "")
        }
    }

    @Test("createTag throws on whitespace-only name")
    func createTagThrowsOnWhitespaceOnlyName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")

        await #expect(throws: TagServiceError.emptyTagName) {
            _ = try await tagService.createTag(name: "   ")
        }
    }

    @Test("createTag throws on name too long")
    func createTagThrowsOnNameTooLong() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let longName = String(repeating: "a", count: TagService.maxTagNameLength + 1)

        await #expect(throws: TagServiceError.tagNameTooLong(maxLength: TagService.maxTagNameLength)) {
            _ = try await tagService.createTag(name: longName)
        }
    }

    @Test("createTag throws on duplicate name (case-insensitive)")
    func createTagThrowsOnDuplicateName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        _ = try await tagService.createTag(name: "Work")

        await #expect(throws: TagServiceError.duplicateTagName(existingName: "Work")) {
            _ = try await tagService.createTag(name: "WORK")
        }
    }

    // MARK: - Find or Create Tests

    @Test("findOrCreateTag returns existing tag")
    func findOrCreateTagReturnsExisting() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let original = try await tagService.createTag(name: "Personal")
        let found = try await tagService.findOrCreateTag(name: "personal")

        #expect(found.id == original.id)
        #expect(found.name == "Personal")
    }

    @Test("findOrCreateTag creates new tag when not found")
    func findOrCreateTagCreatesWhenNotFound() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.findOrCreateTag(name: "NewTag")

        #expect(tag.name == "NewTag")
        #expect(tag.isDeleted == false)
    }

    // MARK: - Read Tests

    @Test("getAllTags returns all non-deleted tags sorted by name")
    func getAllTagsReturnsSorted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        _ = try await tagService.createTag(name: "Zebra")
        _ = try await tagService.createTag(name: "Apple")
        _ = try await tagService.createTag(name: "Mango")

        let tags = try tagService.getAllTags()

        #expect(tags.count == 3)
        #expect(tags[0].name == "Apple")
        #expect(tags[1].name == "Mango")
        #expect(tags[2].name == "Zebra")
    }

    @Test("getAllTags excludes deleted tags")
    func getAllTagsExcludesDeleted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag1 = try await tagService.createTag(name: "Keep")
        let tag2 = try await tagService.createTag(name: "Delete")
        try await tagService.deleteTag(tag2)

        let tags = try tagService.getAllTags()

        #expect(tags.count == 1)
        #expect(tags[0].id == tag1.id)
    }

    @Test("searchTags finds tags by partial match")
    func searchTagsFindsPartialMatch() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        _ = try await tagService.createTag(name: "Work")
        _ = try await tagService.createTag(name: "Workout")
        _ = try await tagService.createTag(name: "Personal")

        let results = try tagService.searchTags(query: "work")

        #expect(results.count == 2)
        #expect(results.contains { $0.name == "Work" })
        #expect(results.contains { $0.name == "Workout" })
    }

    @Test("searchTags with empty query returns all tags")
    func searchTagsWithEmptyQueryReturnsAll() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        _ = try await tagService.createTag(name: "Tag1")
        _ = try await tagService.createTag(name: "Tag2")

        let results = try tagService.searchTags(query: "")

        #expect(results.count == 2)
    }

    @Test("findTagById returns correct tag")
    func findTagByIdReturnsCorrectTag() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "FindMe")

        let found = try tagService.findTagById(tag.id)

        #expect(found?.id == tag.id)
        #expect(found?.name == "FindMe")
    }

    @Test("findTagById returns nil for non-existent tag")
    func findTagByIdReturnsNilForNonExistent() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let found = try tagService.findTagById("non-existent-id")

        #expect(found == nil)
    }

    // MARK: - Update Tests

    @Test("updateTag updates tag name")
    func updateTagUpdatesName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "OldName")

        try await tagService.updateTag(tag, name: "NewName")

        #expect(tag.name == "NewName")
        #expect(tag.syncState == .pending)
    }

    @Test("updateTag updates tag color")
    func updateTagUpdatesColor() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "ColorTag")

        try await tagService.updateTag(tag, colorHex: "#00FF00")

        #expect(tag.colorHex == "#00FF00")
        #expect(tag.syncState == .pending)
    }

    @Test("updateTag throws on empty name")
    func updateTagThrowsOnEmptyName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "Original")

        await #expect(throws: TagServiceError.emptyTagName) {
            try await tagService.updateTag(tag, name: "")
        }
    }

    @Test("updateTag throws on duplicate name")
    func updateTagThrowsOnDuplicateName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        _ = try await tagService.createTag(name: "Existing")
        let tag = try await tagService.createTag(name: "Original")

        await #expect(throws: TagServiceError.duplicateTagName(existingName: "Existing")) {
            try await tagService.updateTag(tag, name: "existing")
        }
    }

    @Test("updateTag allows same name (no change)")
    func updateTagAllowsSameName() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "SameName")
        let originalRevision = tag.revision

        try await tagService.updateTag(tag, name: "SameName")

        // No changes should be recorded
        #expect(tag.name == "SameName")
        #expect(tag.revision == originalRevision)
    }

    // MARK: - Delete Tests

    @Test("deleteTag soft-deletes tag")
    func deleteTagSoftDeletes() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "DeleteMe")

        try await tagService.deleteTag(tag)

        #expect(tag.isDeleted == true)
        #expect(tag.syncState == .pending)
    }

    @Test("deleteTag excludes tag from getAllTags")
    func deleteTagExcludesFromGetAll() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let tagService = TagService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let tag = try await tagService.createTag(name: "DeleteMe")

        try await tagService.deleteTag(tag)

        let tags = try tagService.getAllTags()
        #expect(tags.isEmpty)
    }
}
