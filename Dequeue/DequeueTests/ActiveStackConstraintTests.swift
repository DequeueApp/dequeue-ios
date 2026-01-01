//
//  ActiveStackConstraintTests.swift
//  DequeueTests
//
//  Tests for the single-active-stack constraint (DEQ-23)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Active Stack Constraint Tests")
struct ActiveStackConstraintTests {

    // MARK: - Test Helpers

    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            configurations: config
        )
    }

    // MARK: - Stack Model Tests

    @Test("Stack initializes with isActive = false by default")
    func stackInitializesWithIsActiveFalse() {
        let stack = Stack(title: "Test Stack")
        #expect(stack.isActive == false)
    }

    @Test("Stack can be initialized with isActive = true")
    func stackInitializesWithIsActiveTrue() {
        let stack = Stack(title: "Test Stack", isActive: true)
        #expect(stack.isActive == true)
    }

    // MARK: - StackService.createStack Tests

    @Test("First non-draft stack becomes active automatically")
    @MainActor
    func firstStackBecomesActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let stack = try service.createStack(title: "First Stack")

        #expect(stack.isActive == true)
    }

    @Test("Draft stacks do not become active")
    @MainActor
    func draftStacksNotActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let draft = try service.createStack(title: "Draft Stack", isDraft: true)

        #expect(draft.isActive == false)
    }

    @Test("Second stack is not active when first exists")
    @MainActor
    func secondStackNotActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        #expect(first.isActive == true)
        #expect(second.isActive == false)
    }

    // MARK: - StackService.setAsActive Tests

    @Test("setAsActive activates target stack")
    @MainActor
    func setAsActiveActivatesTarget() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")

        #expect(first.isActive == true)
        #expect(second.isActive == false)

        try service.setAsActive(second)

        #expect(first.isActive == false)
        #expect(second.isActive == true)
    }

    @Test("setAsActive deactivates all other stacks")
    @MainActor
    func setAsActiveDeactivatesOthers() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")
        let third = try service.createStack(title: "Third Stack")

        // Manually set all to active to test deactivation
        first.isActive = true
        second.isActive = true
        third.isActive = true
        try context.save()

        try service.setAsActive(third)

        #expect(first.isActive == false)
        #expect(second.isActive == false)
        #expect(third.isActive == true)
    }

    @Test("Only one stack is active after multiple setAsActive calls")
    @MainActor
    func onlyOneActiveAfterMultipleCalls() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let first = try service.createStack(title: "First Stack")
        let second = try service.createStack(title: "Second Stack")
        let third = try service.createStack(title: "Third Stack")

        try service.setAsActive(second)
        try service.setAsActive(first)
        try service.setAsActive(third)
        try service.setAsActive(second)

        let activeCount = [first, second, third].filter { $0.isActive }.count
        #expect(activeCount == 1)
        #expect(second.isActive == true)
    }

    // MARK: - getCurrentActiveStack Tests

    @Test("getCurrentActiveStack returns the active stack")
    @MainActor
    func getCurrentActiveStackReturnsActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let first = try service.createStack(title: "First Stack")
        _ = try service.createStack(title: "Second Stack")

        let active = try service.getCurrentActiveStack()
        #expect(active?.id == first.id)
    }

    @Test("getCurrentActiveStack returns nil when no active stack")
    @MainActor
    func getCurrentActiveStackReturnsNilWhenNone() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        // Create only drafts
        _ = try service.createStack(title: "Draft 1", isDraft: true)
        _ = try service.createStack(title: "Draft 2", isDraft: true)

        let active = try service.getCurrentActiveStack()
        #expect(active == nil)
    }

    // MARK: - Migration Tests

    @Test("Migration activates first stack when none are active")
    @MainActor
    func migrationActivatesFirstStack() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        // Manually create stacks without isActive set (simulates pre-migration data)
        let stack1 = Stack(title: "Stack 1", sortOrder: 1, isActive: false)
        let stack2 = Stack(title: "Stack 2", sortOrder: 0, isActive: false)
        let stack3 = Stack(title: "Stack 3", sortOrder: 2, isActive: false)

        context.insert(stack1)
        context.insert(stack2)
        context.insert(stack3)
        try context.save()

        let service = StackService(modelContext: context)
        try service.migrateActiveStackState()

        // Stack with sortOrder 0 should become active
        #expect(stack2.isActive == true)
        #expect(stack1.isActive == false)
        #expect(stack3.isActive == false)
    }

    @Test("Migration keeps single active stack unchanged")
    @MainActor
    func migrationKeepsSingleActiveUnchanged() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1 = Stack(title: "Stack 1", sortOrder: 0, isActive: false)
        let stack2 = Stack(title: "Stack 2", sortOrder: 1, isActive: true)

        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        let service = StackService(modelContext: context)
        try service.migrateActiveStackState()

        #expect(stack1.isActive == false)
        #expect(stack2.isActive == true)
    }

    @Test("Migration resolves multiple active stacks")
    @MainActor
    func migrationResolvesMultipleActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)

        let stack1 = Stack(title: "Stack 1", sortOrder: 2, isActive: true)
        let stack2 = Stack(title: "Stack 2", sortOrder: 0, isActive: true)
        let stack3 = Stack(title: "Stack 3", sortOrder: 1, isActive: true)

        context.insert(stack1)
        context.insert(stack2)
        context.insert(stack3)
        try context.save()

        let service = StackService(modelContext: context)
        try service.migrateActiveStackState()

        // Only stack with lowest sortOrder should remain active
        let activeCount = [stack1, stack2, stack3].filter { $0.isActive }.count
        #expect(activeCount == 1)
        #expect(stack2.isActive == true)
    }

    // MARK: - Persistence Tests

    @Test("isActive state persists across fetch")
    @MainActor
    func isActiveStatePersists() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let stack = try service.createStack(title: "Test Stack")
        let stackId = stack.id

        #expect(stack.isActive == true)

        // Fetch the stack again
        let predicate = #Predicate<Stack> { $0.id == stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let fetched = try context.fetch(descriptor).first

        #expect(fetched?.isActive == true)
    }
}
