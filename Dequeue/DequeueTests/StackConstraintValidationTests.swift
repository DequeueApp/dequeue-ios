//
//  StackConstraintValidationTests.swift
//  DequeueTests
//
//  Tests for stack constraint validation (DEQ-25)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Stack Constraint Validation Tests")
struct StackConstraintValidationTests {
    // MARK: - Test Helpers

    private func createTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self,
            QueueTask.self,
            Reminder.self,
            Event.self,
            configurations: config
        )
    }

    // MARK: - Pre-condition Validation Tests

    @Test("setAsActive throws error for draft stack")
    @MainActor
    func setAsActiveThrowsForDraftStack() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let draft = try service.createStack(title: "Draft Stack", isDraft: true)

        #expect(throws: StackServiceError.cannotActivateDraftStack) {
            try service.setAsActive(draft)
        }
    }

    // MARK: - Post-condition Validation Tests

    @Test("validateSingleActiveConstraint passes with zero active stacks")
    @MainActor
    func validateConstraintPassesWithZeroActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        // Only create drafts - no active stacks
        _ = try service.createStack(title: "Draft 1", isDraft: true)
        _ = try service.createStack(title: "Draft 2", isDraft: true)

        // Should not throw
        try service.validateSingleActiveConstraint()
    }

    @Test("validateSingleActiveConstraint passes with one active stack")
    @MainActor
    func validateConstraintPassesWithOneActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        _ = try service.createStack(title: "Active Stack")

        // Should not throw
        try service.validateSingleActiveConstraint()
    }

    @Test("validateSingleActiveConstraint throws with multiple active stacks")
    @MainActor
    func validateConstraintThrowsWithMultipleActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        // Create stacks normally
        let stack1 = try service.createStack(title: "Stack 1")
        let stack2 = try service.createStack(title: "Stack 2")

        // Manually corrupt state to simulate constraint violation
        stack1.isActive = true
        stack2.isActive = true
        try context.save()

        #expect(throws: StackServiceError.multipleActiveStacksDetected(count: 2)) {
            try service.validateSingleActiveConstraint()
        }
    }

    // MARK: - Atomicity Tests

    @Test("setAsActive ensures only one stack is active after operation")
    @MainActor
    func setAsActiveEnsuresSingleActive() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let stack1 = try service.createStack(title: "Stack 1")
        let stack2 = try service.createStack(title: "Stack 2")
        let stack3 = try service.createStack(title: "Stack 3")

        // Manually set all to active to simulate corrupted state
        stack1.isActive = true
        stack2.isActive = true
        stack3.isActive = true
        try context.save()

        // setAsActive should fix the corruption
        try service.setAsActive(stack2)

        let activeCount = [stack1, stack2, stack3].filter { $0.isActive }.count
        #expect(activeCount == 1)
        #expect(stack2.isActive == true)
        #expect(stack1.isActive == false)
        #expect(stack3.isActive == false)
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

        #expect(first.isActive == true)
        #expect(second.isActive == false)
        #expect(third.isActive == false)

        try service.setAsActive(second)

        #expect(first.isActive == false)
        #expect(second.isActive == true)
        #expect(third.isActive == false)

        try service.setAsActive(third)

        #expect(first.isActive == false)
        #expect(second.isActive == false)
        #expect(third.isActive == true)
    }

    @Test("Rapid activation switching maintains constraint")
    @MainActor
    func rapidActivationMaintainsConstraint() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let stack1 = try service.createStack(title: "Stack 1")
        let stack2 = try service.createStack(title: "Stack 2")
        let stack3 = try service.createStack(title: "Stack 3")

        // Rapidly switch between stacks
        for _ in 0..<10 {
            try service.setAsActive(stack1)
            try service.setAsActive(stack2)
            try service.setAsActive(stack3)
        }

        // Constraint should still hold
        try service.validateSingleActiveConstraint()

        let activeCount = [stack1, stack2, stack3].filter { $0.isActive }.count
        #expect(activeCount == 1)
        #expect(stack3.isActive == true)
    }

    // MARK: - Error Message Tests

    @Test("StackServiceError provides clear error descriptions")
    func errorDescriptionsAreClear() {
        let deletedError = StackServiceError.cannotActivateDeletedStack
        #expect(deletedError.errorDescription?.contains("deleted") == true)

        let draftError = StackServiceError.cannotActivateDraftStack
        #expect(draftError.errorDescription?.contains("draft") == true)

        let constraintError = StackServiceError.multipleActiveStacksDetected(count: 3)
        #expect(constraintError.errorDescription?.contains("3") == true)
        #expect(constraintError.errorDescription?.contains("active stacks") == true)

        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "test error"])
        let operationError = StackServiceError.operationFailed(underlying: underlying)
        #expect(operationError.errorDescription?.contains("test error") == true)
    }

    // MARK: - Edge Case Tests

    @Test("Activating already active stack is idempotent")
    @MainActor
    func activatingActiveStackIsIdempotent() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let stack = try service.createStack(title: "Test Stack")
        #expect(stack.isActive == true)

        // Activating the same stack should not throw
        try service.setAsActive(stack)
        #expect(stack.isActive == true)

        // Constraint should still hold
        try service.validateSingleActiveConstraint()
    }

    @Test("Constraint validation ignores deleted stacks")
    @MainActor
    func constraintIgnoresDeletedStacks() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let stack1 = try service.createStack(title: "Stack 1")
        let stack2 = try service.createStack(title: "Stack 2")

        // Make stack2 active
        try service.setAsActive(stack2)

        // Delete stack1 but leave isActive = true (simulating corrupted deleted state)
        stack1.isDeleted = true
        stack1.isActive = true
        try context.save()

        // Constraint should still pass because deleted stacks are ignored
        try service.validateSingleActiveConstraint()
    }

    @Test("Constraint validation ignores draft stacks")
    @MainActor
    func constraintIgnoresDraftStacks() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        let service = StackService(modelContext: context)

        let stack = try service.createStack(title: "Active Stack")
        let draft = try service.createStack(title: "Draft Stack", isDraft: true)

        // Manually set draft as active (should be ignored)
        draft.isActive = true
        try context.save()

        // Constraint should pass because drafts are ignored
        try service.validateSingleActiveConstraint()
    }
}
