//
//  StackServiceTagTests.swift
//  DequeueTests
//
//  Tests for StackService+Tags extension — tag operations and history revert
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

@Suite("StackService Tag Operations", .serialized)
@MainActor
struct StackServiceTagTests {

    // MARK: - Add Tag

    @Test("addTag adds a tag to a stack")
    func addTagToStack() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Tagged Stack")
        let tag = Tag(name: "urgent", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        try await stackService.addTag(tag, to: stack)

        #expect(stack.tagObjects.count == 1)
        #expect(stack.tagObjects.first?.id == tag.id)
        #expect(stack.tagObjects.first?.name == "urgent")
        #expect(stack.syncState == .pending)
    }

    @Test("addTag updates stack updatedAt timestamp")
    func addTagUpdatesTimestamp() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let originalUpdatedAt = stack.updatedAt

        // Small delay to ensure different timestamp
        try await Task.sleep(for: .milliseconds(10))

        let tag = Tag(name: "work", userId: "test-user", deviceId: "test-device")
        context.insert(tag)

        try await stackService.addTag(tag, to: stack)

        #expect(stack.updatedAt > originalUpdatedAt)
    }

    @Test("addTag is idempotent — adding same tag twice does nothing")
    func addTagIdempotent() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let tag = Tag(name: "work", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        try await stackService.addTag(tag, to: stack)
        let countAfterFirst = stack.tagObjects.count

        try await stackService.addTag(tag, to: stack)
        let countAfterSecond = stack.tagObjects.count

        #expect(countAfterFirst == 1)
        #expect(countAfterSecond == 1)
    }

    @Test("addTag supports multiple tags on same stack")
    func addMultipleTagsToStack() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Multi-tag Stack")

        let tag1 = Tag(name: "urgent", userId: "test-user", deviceId: "test-device")
        let tag2 = Tag(name: "work", userId: "test-user", deviceId: "test-device")
        let tag3 = Tag(name: "personal", userId: "test-user", deviceId: "test-device")
        context.insert(tag1)
        context.insert(tag2)
        context.insert(tag3)
        try context.save()

        try await stackService.addTag(tag1, to: stack)
        try await stackService.addTag(tag2, to: stack)
        try await stackService.addTag(tag3, to: stack)

        #expect(stack.tagObjects.count == 3)
        let tagNames = Set(stack.tagObjects.map(\.name))
        #expect(tagNames == Set(["urgent", "work", "personal"]))
    }

    @Test("addTag records an update event")
    func addTagRecordsEvent() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let tag = Tag(name: "important", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        try await stackService.addTag(tag, to: stack)

        // Verify an event was recorded (the create event + the update from addTag)
        let stackId = stack.id
        let eventType = "stack.updated"
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate<Event> { $0.entityId == stackId && $0.type == eventType }
        )
        let events = try context.fetch(descriptor)
        #expect(events.count >= 1)
    }

    // MARK: - Remove Tag

    @Test("removeTag removes a tag from a stack")
    func removeTagFromStack() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let tag = Tag(name: "remove-me", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        try await stackService.addTag(tag, to: stack)
        #expect(stack.tagObjects.count == 1)

        try await stackService.removeTag(tag, from: stack)
        #expect(stack.tagObjects.count == 0)
    }

    @Test("removeTag updates stack updatedAt timestamp")
    func removeTagUpdatesTimestamp() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let tag = Tag(name: "temp", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        try await stackService.addTag(tag, to: stack)

        try await Task.sleep(for: .milliseconds(10))
        let beforeRemove = stack.updatedAt

        try await stackService.removeTag(tag, from: stack)

        #expect(stack.updatedAt > beforeRemove)
    }

    @Test("removeTag is idempotent — removing absent tag does nothing")
    func removeTagIdempotent() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let tag = Tag(name: "not-added", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        // Removing a tag that was never added should be a no-op
        try await stackService.removeTag(tag, from: stack)
        #expect(stack.tagObjects.count == 0)
    }

    @Test("removeTag removes only the specified tag, leaving others")
    func removeTagLeavesOthers() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let tag1 = Tag(name: "keep", userId: "test-user", deviceId: "test-device")
        let tag2 = Tag(name: "remove", userId: "test-user", deviceId: "test-device")
        let tag3 = Tag(name: "also-keep", userId: "test-user", deviceId: "test-device")
        context.insert(tag1)
        context.insert(tag2)
        context.insert(tag3)
        try context.save()

        try await stackService.addTag(tag1, to: stack)
        try await stackService.addTag(tag2, to: stack)
        try await stackService.addTag(tag3, to: stack)
        #expect(stack.tagObjects.count == 3)

        try await stackService.removeTag(tag2, from: stack)

        #expect(stack.tagObjects.count == 2)
        let remainingNames = Set(stack.tagObjects.map(\.name))
        #expect(remainingNames == Set(["keep", "also-keep"]))
    }

    @Test("removeTag records an update event")
    func removeTagRecordsEvent() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let tag = Tag(name: "doomed", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        try await stackService.addTag(tag, to: stack)

        // Count events before removal
        let stackId = stack.id
        let eventType = "stack.updated"
        let beforeDescriptor = FetchDescriptor<Event>(
            predicate: #Predicate<Event> { $0.entityId == stackId && $0.type == eventType }
        )
        let eventsBefore = try context.fetch(beforeDescriptor).count

        try await stackService.removeTag(tag, from: stack)

        let eventsAfter = try context.fetch(beforeDescriptor).count
        #expect(eventsAfter > eventsBefore)
    }

    @Test("removeTag sets syncState to pending")
    func removeTagSetsSyncPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let tag = Tag(name: "temp", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        try await stackService.addTag(tag, to: stack)

        // Simulate synced state
        stack.syncState = .synced

        try await stackService.removeTag(tag, from: stack)

        #expect(stack.syncState == .pending)
    }

    // MARK: - Tag-Stack Relationship Integrity

    @Test("adding tag to stack updates tag's stacks relationship")
    func addTagUpdatesRelationship() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack")
        let tag = Tag(name: "shared", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        try await stackService.addTag(tag, to: stack)

        // The inverse relationship should also be set
        #expect(tag.stacks.count == 1)
        #expect(tag.stacks.first?.id == stack.id)
    }

    @Test("same tag can be added to multiple stacks")
    func sameTagOnMultipleStacks() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack1 = try await stackService.createStack(title: "Stack 1")
        let stack2 = try await stackService.createStack(title: "Stack 2", setAsActive: true)
        let tag = Tag(name: "shared-tag", userId: "test-user", deviceId: "test-device")
        context.insert(tag)
        try context.save()

        try await stackService.addTag(tag, to: stack1)
        try await stackService.addTag(tag, to: stack2)

        #expect(stack1.tagObjects.count == 1)
        #expect(stack2.tagObjects.count == 1)
        #expect(tag.stacks.count == 2)
    }
}
