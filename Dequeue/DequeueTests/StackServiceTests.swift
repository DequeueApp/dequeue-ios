//
//  StackServiceTests.swift
//  DequeueTests
//
//  Comprehensive tests for StackService - stack creation, activation, and lifecycle
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container for StackService tests
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )
}

@Suite("StackService Tests", .serialized)
@MainActor
struct StackServiceTests {
    // MARK: - Create Stack Tests

    @Test("createStack creates a new stack with title")
    func createStackWithTitle() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Test Stack")

        #expect(stack.title == "Test Stack")
        #expect(stack.status == .active)
        #expect(stack.isDraft == false)
        #expect(stack.isActive == true) // First stack is auto-activated
        #expect(stack.sortOrder == 0)
    }

    @Test("createStack creates stack with description")
    func createStackWithDescription() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(
            title: "Stack with Description",
            description: "This is a test description"
        )

        #expect(stack.title == "Stack with Description")
        #expect(stack.stackDescription == "This is a test description")
    }

    @Test("createStack first stack is automatically active")
    func firstStackIsAutomaticallyActive() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "First Stack")

        #expect(stack.isActive == true)
        let activeStack = try stackService.getCurrentActiveStack()
        #expect(activeStack?.id == stack.id)
    }

    @Test("createStack second stack is inactive by default")
    func secondStackIsInactiveByDefault() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack1 = try await stackService.createStack(title: "First Stack")
        let stack2 = try await stackService.createStack(title: "Second Stack")

        #expect(stack1.isActive == true)
        #expect(stack2.isActive == false)
        #expect(stack2.sortOrder == 1)
    }

    @Test("createStack with setAsActive deactivates previous active stack")
    func createStackWithSetAsActiveDeactivatesPrevious() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack1 = try await stackService.createStack(title: "First Stack")
        let stack2 = try await stackService.createStack(title: "Second Stack", setAsActive: true)

        #expect(stack1.isActive == false)
        #expect(stack2.isActive == true)
        let activeStack = try stackService.getCurrentActiveStack()
        #expect(activeStack?.id == stack2.id)
    }

    @Test("createStack draft is not active")
    func createDraftStackIsNotActive() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await stackService.createStack(title: "Draft Stack", isDraft: true)

        #expect(draft.isDraft == true)
        #expect(draft.isActive == false)
        #expect(try stackService.getCurrentActiveStack() == nil)
    }

    @Test("createStack draft after active stack does not affect active stack")
    func createDraftAfterActiveStackDoesNotAffectActive() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let activeStack = try await stackService.createStack(title: "Active Stack")
        let draft = try await stackService.createStack(title: "Draft", isDraft: true)

        #expect(activeStack.isActive == true)
        #expect(draft.isActive == false)
        #expect(draft.isDraft == true)
        let currentActive = try stackService.getCurrentActiveStack()
        #expect(currentActive?.id == activeStack.id)
    }

    // MARK: - Draft Operations Tests

    @Test("updateDraft updates title and description")
    func updateDraftUpdatesTitleAndDescription() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await stackService.createStack(title: "Original", description: "Old desc", isDraft: true)
        try await stackService.updateDraft(draft, title: "Updated", description: "New desc")

        #expect(draft.title == "Updated")
        #expect(draft.stackDescription == "New desc")
        #expect(draft.isDraft == true)
    }

    @Test("updateDraft does nothing for non-draft stacks")
    func updateDraftDoesNothingForNonDrafts() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Not a draft")
        let originalTitle = stack.title

        try await stackService.updateDraft(stack, title: "Should not change", description: nil)

        #expect(stack.title == originalTitle) // Title should not change
    }

    @Test("discardDraft marks draft as deleted")
    func discardDraftMarksAsDeleted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await stackService.createStack(title: "Draft to discard", isDraft: true)
        try await stackService.discardDraft(draft)

        #expect(draft.isDeleted == true)
    }

    @Test("publishDraft converts draft to active stack")
    func publishDraftConvertsToActiveStack() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await stackService.createStack(title: "Draft to publish", isDraft: true)
        try await stackService.publishDraft(draft)

        #expect(draft.isDraft == false)
        #expect(draft.isActive == true)
        let activeStack = try stackService.getCurrentActiveStack()
        #expect(activeStack?.id == draft.id)
    }

    // MARK: - Read/Query Tests

    @Test("getCurrentActiveStack returns nil when no active stack")
    func getCurrentActiveStackReturnsNilWhenNone() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let activeStack = try stackService.getCurrentActiveStack()

        #expect(activeStack == nil)
    }

    @Test("getCurrentActiveStack returns the active stack")
    func getCurrentActiveStackReturnsActiveStack() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Active Stack")

        let activeStack = try stackService.getCurrentActiveStack()

        #expect(activeStack?.id == stack.id)
    }

    @Test("getActiveStacks returns only active status stacks")
    func getActiveStacksReturnsOnlyActiveStatus() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack1 = try await stackService.createStack(title: "Active 1")
        let stack2 = try await stackService.createStack(title: "Active 2")
        let stack3 = try await stackService.createStack(title: "Will be completed")

        try await stackService.markAsCompleted(stack3)

        let activeStacks = try stackService.getActiveStacks()

        #expect(activeStacks.count == 2)
        #expect(activeStacks.contains { $0.id == stack1.id })
        #expect(activeStacks.contains { $0.id == stack2.id })
        #expect(!activeStacks.contains { $0.id == stack3.id })
    }

    @Test("getDrafts returns only draft stacks")
    func getDraftsReturnsOnlyDrafts() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft1 = try await stackService.createStack(title: "Draft 1", isDraft: true)
        let draft2 = try await stackService.createStack(title: "Draft 2", isDraft: true)
        let notDraft = try await stackService.createStack(title: "Not a draft")

        let drafts = try stackService.getDrafts()

        #expect(drafts.count == 2)
        #expect(drafts.contains { $0.id == draft1.id })
        #expect(drafts.contains { $0.id == draft2.id })
        #expect(!drafts.contains { $0.id == notDraft.id })
    }

    // MARK: - Update Tests

    @Test("updateStack updates title and description")
    func updateStackUpdatesTitleAndDescription() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Original", description: "Old desc")
        try await stackService.updateStack(stack, title: "Updated", description: "New desc")

        #expect(stack.title == "Updated")
        #expect(stack.stackDescription == "New desc")
    }

    // MARK: - Activation Tests

    @Test("setAsActive activates stack and deactivates previous")
    func setAsActiveActivatesAndDeactivatesPrevious() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack1 = try await stackService.createStack(title: "First")
        let stack2 = try await stackService.createStack(title: "Second")

        try await stackService.setAsActive(stack2)

        #expect(stack1.isActive == false)
        #expect(stack2.isActive == true)
        let activeStack = try stackService.getCurrentActiveStack()
        #expect(activeStack?.id == stack2.id)
    }

    @Test("setAsActive throws for deleted stack")
    func setAsActiveThrowsForDeletedStack() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "To be deleted")
        try await stackService.deleteStack(stack)

        await #expect(throws: StackServiceError.cannotActivateDeletedStack) {
            try await stackService.setAsActive(stack)
        }
    }

    @Test("setAsActive throws for draft stack")
    func setAsActiveThrowsForDraftStack() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let draft = try await stackService.createStack(title: "Draft", isDraft: true)

        await #expect(throws: StackServiceError.cannotActivateDraftStack) {
            try await stackService.setAsActive(draft)
        }
    }

    @Test("deactivateStack removes active flag")
    func deactivateStackRemovesActiveFlag() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Active Stack")
        try await stackService.deactivateStack(stack)

        #expect(stack.isActive == false)
        #expect(try stackService.getCurrentActiveStack() == nil)
    }

    // MARK: - Completion Tests

    @Test("markAsCompleted changes status to completed")
    func markAsCompletedChangesStatus() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack to complete")
        try await stackService.markAsCompleted(stack)

        #expect(stack.status == .completed)
        #expect(stack.isActive == false)
    }

    @Test("markAsCompleted with tasks completes all tasks")
    func markAsCompletedCompletesAllTasks() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let taskService = TaskService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack with tasks")
        let task1 = try await taskService.createTask(title: "Task 1", stack: stack)
        let task2 = try await taskService.createTask(title: "Task 2", stack: stack)

        try await stackService.markAsCompleted(stack, completeAllTasks: true)

        #expect(task1.status == .completed)
        #expect(task2.status == .completed)
        #expect(stack.status == .completed)
    }

    @Test("markAsCompleted without completeAllTasks leaves tasks unchanged")
    func markAsCompletedWithoutTasksLeavesTasksUnchanged() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let taskService = TaskService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack with tasks")
        let task = try await taskService.createTask(title: "Task 1", stack: stack)

        try await stackService.markAsCompleted(stack, completeAllTasks: false)

        #expect(task.status == .pending)
        #expect(stack.status == .completed)
    }

    @Test("getCompletedStacks returns only completed stacks")
    func getCompletedStacksReturnsOnlyCompleted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let active = try await stackService.createStack(title: "Active")
        let toComplete = try await stackService.createStack(title: "To complete")
        try await stackService.markAsCompleted(toComplete)

        let completedStacks = try stackService.getCompletedStacks()

        #expect(completedStacks.count == 1)
        #expect(completedStacks.first?.id == toComplete.id)
    }

    // MARK: - Close Tests

    @Test("closeStack changes status to closed")
    func closeStackChangesStatusToClosed() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack to close")
        try await stackService.closeStack(stack, reason: "No longer needed")

        #expect(stack.status == .closed)
        #expect(stack.isActive == false)
    }

    // MARK: - Delete Tests

    @Test("deleteStack marks stack as deleted")
    func deleteStackMarksAsDeleted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Stack to delete")
        try await stackService.deleteStack(stack)

        #expect(stack.isDeleted == true)
        #expect(stack.isActive == false)
    }

    // MARK: - Sort Order Tests

    @Test("updateSortOrders updates stack sort orders")
    func updateSortOrdersUpdatesStackSortOrders() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack1 = try await stackService.createStack(title: "Stack 1")
        let stack2 = try await stackService.createStack(title: "Stack 2")
        let stack3 = try await stackService.createStack(title: "Stack 3")

        // Reorder: [stack3, stack1, stack2]
        try await stackService.updateSortOrders([stack3, stack1, stack2])

        #expect(stack3.sortOrder == 0)
        #expect(stack1.sortOrder == 1)
        #expect(stack2.sortOrder == 2)
    }

    // MARK: - Constraint Validation Tests

    @Test("validateAndFixSingleActiveConstraint returns true when valid")
    func validateAndFixSingleActiveConstraintReturnsTrueWhenValid() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack = try await stackService.createStack(title: "Only active")

        let isValid = try stackService.validateAndFixSingleActiveConstraint()

        #expect(isValid == true)
    }

    @Test("validateAndFixSingleActiveConstraint fixes multiple active stacks")
    func validateAndFixSingleActiveConstraintFixesMultiple() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stackService = StackService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let stack1 = try await stackService.createStack(title: "Stack 1")
        let stack2 = try await stackService.createStack(title: "Stack 2")

        // Manually create a constraint violation for testing
        stack1.isActive = true
        stack2.isActive = true
        try context.save()

        let fixed = try stackService.validateAndFixSingleActiveConstraint(keeping: stack2.id)

        #expect(fixed == true)
        #expect(stack1.isActive == false)
        #expect(stack2.isActive == true)
    }
}
