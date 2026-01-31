//
//  StackService.swift
//  Dequeue
//
//  Business logic for Stack operations
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "StackService")

// MARK: - Stack Service Errors

/// Errors that can occur during stack operations
enum StackServiceError: LocalizedError, Equatable {
    /// Attempted to activate a stack that is deleted
    case cannotActivateDeletedStack
    /// Attempted to activate a draft stack (must publish first)
    case cannotActivateDraftStack
    /// Constraint violation: multiple stacks marked as active after operation
    case multipleActiveStacksDetected(count: Int)
    /// Operation failed and changes were not saved
    case operationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .cannotActivateDeletedStack:
            return "Cannot activate a deleted stack"
        case .cannotActivateDraftStack:
            return "Cannot activate a draft stack. Publish it first."
        case .multipleActiveStacksDetected(let count):
            return "Constraint violation: found \(count) active stacks (expected 1)"
        case .operationFailed(let underlying):
            return "Stack operation failed: \(underlying.localizedDescription)"
        }
    }

    static func == (lhs: StackServiceError, rhs: StackServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.cannotActivateDeletedStack, .cannotActivateDeletedStack):
            return true
        case (.cannotActivateDraftStack, .cannotActivateDraftStack):
            return true
        case let (.multipleActiveStacksDetected(lhsCount), .multipleActiveStacksDetected(rhsCount)):
            return lhsCount == rhsCount
        case let (.operationFailed(lhsError), .operationFailed(rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

@MainActor
final class StackService {
    let modelContext: ModelContext
    let eventService: EventService
    private let userId: String
    private let deviceId: String
    let syncManager: SyncManager?

    init(modelContext: ModelContext, userId: String, deviceId: String, syncManager: SyncManager? = nil) {
        self.modelContext = modelContext
        self.userId = userId
        self.deviceId = deviceId
        self.eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        self.syncManager = syncManager
    }

    // MARK: - Create

    func createStack(
        title: String,
        description: String? = nil,
        isDraft: Bool = false
    ) async throws -> Stack {
        // Check if this will be the first non-draft active stack
        let existingActiveStacks = try getActiveStacks()
        let shouldBeActive = !isDraft && existingActiveStacks.isEmpty

        // Determine sortOrder: active stack gets 0, inactive stacks get next available
        // Query ALL non-deleted stacks (not just active) to prevent sortOrder collisions
        let sortOrder: Int
        if shouldBeActive {
            sortOrder = 0
        } else {
            // Find the max sortOrder from ALL stacks (including drafts, completed, closed)
            let allStacks = try getAllNonDeletedStacks()
            let maxSortOrder = allStacks.map(\.sortOrder).max() ?? -1
            sortOrder = maxSortOrder + 1
        }

        let stack = Stack(
            title: title,
            stackDescription: description,
            status: .active,
            sortOrder: sortOrder,
            isDraft: isDraft,
            isActive: shouldBeActive,
            syncState: .pending
        )

        modelContext.insert(stack)

        // Always record events - drafts are synced for offline-first behavior
        try await eventService.recordStackCreated(stack)

        if shouldBeActive {
            try await eventService.recordStackActivated(stack)
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()
        return stack
    }

    /// Updates a draft stack and records the update event
    func updateDraft(_ stack: Stack, title: String, description: String?) async throws {
        guard stack.isDraft else { return }

        stack.title = title
        stack.stackDescription = description
        stack.updatedAt = Date()
        stack.syncState = .pending

        try await eventService.recordStackUpdated(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    /// Discards a draft stack - fires stack.discarded event
    func discardDraft(_ stack: Stack) async throws {
        guard stack.isDraft else { return }

        stack.isDeleted = true
        stack.updatedAt = Date()
        stack.syncState = .pending

        try await eventService.recordStackDiscarded(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Read

    /// Returns the single currently active stack, or nil if none is active.
    func getCurrentActiveStack() throws -> Stack? {
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == false && stack.isActive == true
        }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let results = try modelContext.fetch(descriptor)
        return results.first
    }

    /// Validates that at most one stack has isActive = true.
    /// If multiple stacks have isActive = true (e.g., from sync), silently fixes by keeping only the target stack active.
    /// - Parameter targetStackId: The ID of the stack that should remain active (pass nil to just check without fixing)
    /// - Returns: True if constraint was valid or was fixed, false if no target provided and multiple found
    @discardableResult
    func validateAndFixSingleActiveConstraint(keeping targetStackId: String? = nil) throws -> Bool {
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == false && stack.isActive == true
        }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let activeStacks = try modelContext.fetch(descriptor)

        if activeStacks.count <= 1 {
            return true
        }

        // Multiple stacks have isActive = true - fix it
        if let targetId = targetStackId {
            // Deactivate all except the target
            for stack in activeStacks where stack.id != targetId {
                stack.isActive = false
                stack.updatedAt = Date()
                stack.syncState = .pending
            }
            return true
        }

        // No target specified and multiple found - can't auto-fix
        return false
    }

    /// Returns ALL stacks with isActive = true, regardless of status.
    /// Use this to ensure we deactivate all stacks before activating a new one,
    /// including stacks that may have been synced with isActive = true but different status.
    func getAllStacksWithIsActiveTrue() throws -> [Stack] {
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == false && stack.isActive == true
        }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }

    func getActiveStacks() throws -> [Stack] {
        // Use rawValue for SwiftData predicate compatibility
        let activeRaw = StackStatus.active.rawValue
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == false && stack.statusRawValue == activeRaw
        }
        let descriptor = FetchDescriptor<Stack>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Returns all non-deleted stacks regardless of status, draft state, or isActive flag.
    /// Used for calculating max sortOrder to prevent collisions.
    func getAllNonDeletedStacks() throws -> [Stack] {
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false
        }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }

    func getCompletedStacks() throws -> [Stack] {
        // Use rawValue for SwiftData predicate compatibility
        let completedRaw = StackStatus.completed.rawValue
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.statusRawValue == completedRaw
        }
        let descriptor = FetchDescriptor<Stack>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func getDrafts() throws -> [Stack] {
        // Only return true drafts: not deleted, marked as draft, AND active status
        // A draft that was completed or closed should not appear as a draft
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false &&
            stack.isDraft == true &&
            stack.statusRawValue == "active"
        }
        let descriptor = FetchDescriptor<Stack>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Update

    func updateStack(_ stack: Stack, title: String, description: String?) async throws {
        logger.info("updateStack: input title='\(title)', stack.title before='\(stack.title)'")
        stack.title = title
        stack.stackDescription = description
        stack.updatedAt = Date()
        stack.syncState = .pending
        logger.info("updateStack: stack.title after set='\(stack.title)'")

        try await eventService.recordStackUpdated(stack)
        logger.info("updateStack: event recorded, about to save context")
        try modelContext.save()
        logger.info("updateStack: context saved")
        syncManager?.triggerImmediatePush()
    }

    func publishDraft(_ stack: Stack) async throws {
        guard stack.isDraft else { return }

        stack.isDraft = false
        stack.updatedAt = Date()
        stack.syncState = .pending

        // Record as update event, not created - the stack.created event was already
        // fired when the draft was created. Publishing just changes isDraft to false.
        try await eventService.recordStackUpdated(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Status Changes

    func markAsCompleted(_ stack: Stack, completeAllTasks: Bool = true) async throws {
        // If this was the active stack, deactivate it first
        // A completed stack cannot be the "active" stack
        let wasActive = stack.isActive
        if wasActive {
            try await eventService.recordStackDeactivated(stack)
            stack.isActive = false
        }

        stack.status = .completed
        stack.updatedAt = Date()
        stack.syncState = .pending

        if completeAllTasks {
            let taskService = TaskService(
                modelContext: modelContext,
                userId: userId,
                deviceId: deviceId
            )
            for task in stack.tasks where task.status == .pending && !task.isDeleted {
                try await taskService.markAsCompleted(task)
            }
        }

        // Auto-dismiss any active or snoozed reminders for this stack (DEQ-212)
        // When a stack is completed, its reminders should no longer appear as overdue/snoozed
        let notificationService = NotificationService(modelContext: modelContext)
        for reminder in stack.reminders where !reminder.isDeleted {
            if reminder.status == .active || reminder.status == .snoozed {
                reminder.status = .fired
                reminder.updatedAt = Date()
                reminder.syncState = .pending
                notificationService.cancelNotification(for: reminder)
            }
        }

        try await eventService.recordStackCompleted(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func setAsActive(_ stack: Stack) async throws {
        // MARK: Pre-condition validation
        guard !stack.isDeleted else {
            throw StackServiceError.cannotActivateDeletedStack
        }
        guard !stack.isDraft else {
            throw StackServiceError.cannotActivateDraftStack
        }

        // DEQ-144: Single fetch, filter in memory to avoid multiple database queries
        let allNonDeletedStacks = try getAllNonDeletedStacks()
        let nonDraftStacks = allNonDeletedStacks.filter { !$0.isDraft }

        // Get ALL stacks with isActive = true (not just those with status == .active)
        // This handles synced stacks that may have isActive = true but different status
        let allCurrentlyActiveStacks = nonDraftStacks.filter { $0.isActive }

        // Find stacks to deactivate (any stack with isActive = true except the target)
        let stacksToDeactivate = allCurrentlyActiveStacks.filter { $0.id != stack.id }

        // Record deactivation events BEFORE changing state
        for stackToDeactivate in stacksToDeactivate {
            try await eventService.recordStackDeactivated(stackToDeactivate)
            stackToDeactivate.isActive = false
            stackToDeactivate.updatedAt = Date()
            stackToDeactivate.syncState = .pending
        }

        // Get stacks with status == .active for sort order management (sorted by sortOrder)
        let activeStacks = nonDraftStacks.filter { $0.status == .active }.sorted { $0.sortOrder < $1.sortOrder }

        // Update sort orders for active stacks
        for (index, activeStack) in activeStacks.enumerated() {
            if activeStack.id == stack.id {
                activeStack.sortOrder = 0
            } else if activeStack.sortOrder <= stack.sortOrder {
                activeStack.sortOrder = index + 1
            }
            activeStack.updatedAt = Date()
            activeStack.syncState = .pending
        }

        // Ensure target stack is active
        stack.isActive = true
        stack.sortOrder = 0
        stack.updatedAt = Date()
        stack.syncState = .pending

        try await eventService.recordStackActivated(stack)
        try await eventService.recordStackReordered(activeStacks)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        // MARK: Post-condition validation (fix rather than throw)
        try validateAndFixSingleActiveConstraint(keeping: stack.id)
    }

    /// Deactivates the currently active stack, leaving no stack active.
    /// This allows the user to have zero active stacks.
    func deactivateStack(_ stack: Stack) async throws {
        guard stack.isActive else { return }

        try await eventService.recordStackDeactivated(stack)
        stack.isActive = false
        stack.updatedAt = Date()
        stack.syncState = .pending

        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func closeStack(_ stack: Stack, reason: String? = nil) async throws {
        stack.status = .closed
        stack.updatedAt = Date()
        stack.syncState = .pending

        try await eventService.recordStackUpdated(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Delete

    func deleteStack(_ stack: Stack) async throws {
        stack.isDeleted = true
        stack.updatedAt = Date()
        stack.syncState = .pending

        try await eventService.recordStackDeleted(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Reorder

    func updateSortOrders(_ stacks: [Stack]) async throws {
        for (index, stack) in stacks.enumerated() {
            stack.sortOrder = index
            stack.updatedAt = Date()
            stack.syncState = .pending
        }

        try await eventService.recordStackReordered(stacks)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

}
