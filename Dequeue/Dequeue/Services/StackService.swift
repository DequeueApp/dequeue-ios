//
//  StackService.swift
//  Dequeue
//
//  Business logic for Stack operations
//

import Foundation
import SwiftData

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
    private let modelContext: ModelContext
    private let eventService: EventService
    private let syncManager: SyncManager?

    init(modelContext: ModelContext, syncManager: SyncManager? = nil) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext)
        self.syncManager = syncManager
    }

    // MARK: - Create

    func createStack(
        title: String,
        description: String? = nil,
        isDraft: Bool = false
    ) throws -> Stack {
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
        try eventService.recordStackCreated(stack)

        if shouldBeActive {
            try eventService.recordStackActivated(stack)
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()
        return stack
    }

    /// Updates a draft stack and records the update event
    func updateDraft(_ stack: Stack, title: String, description: String?) throws {
        guard stack.isDraft else { return }

        stack.title = title
        stack.stackDescription = description
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackUpdated(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    /// Discards a draft stack - fires stack.discarded event
    func discardDraft(_ stack: Stack) throws {
        guard stack.isDraft else { return }

        stack.isDeleted = true
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackDiscarded(stack)
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
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == true
        }
        let descriptor = FetchDescriptor<Stack>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Update

    func updateStack(_ stack: Stack, title: String, description: String?) throws {
        stack.title = title
        stack.stackDescription = description
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackUpdated(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func publishDraft(_ stack: Stack) throws {
        guard stack.isDraft else { return }

        stack.isDraft = false
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackCreated(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Status Changes

    func markAsCompleted(_ stack: Stack, completeAllTasks: Bool = true) throws {
        // If this was the active stack, deactivate it first
        // A completed stack cannot be the "active" stack
        let wasActive = stack.isActive
        if wasActive {
            try eventService.recordStackDeactivated(stack)
            stack.isActive = false
        }

        stack.status = .completed
        stack.updatedAt = Date()
        stack.syncState = .pending

        if completeAllTasks {
            let taskService = TaskService(modelContext: modelContext)
            for task in stack.tasks where task.status == .pending && !task.isDeleted {
                try taskService.markAsCompleted(task)
            }
        }

        try eventService.recordStackCompleted(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func setAsActive(_ stack: Stack) throws {
        // MARK: Pre-condition validation
        guard !stack.isDeleted else {
            throw StackServiceError.cannotActivateDeletedStack
        }
        guard !stack.isDraft else {
            throw StackServiceError.cannotActivateDraftStack
        }

        // Get ALL stacks with isActive = true (not just those with status == .active)
        // This handles synced stacks that may have isActive = true but different status
        let allCurrentlyActiveStacks = try getAllStacksWithIsActiveTrue()

        // Find stacks to deactivate (any stack with isActive = true except the target)
        let stacksToDeactivate = allCurrentlyActiveStacks.filter { $0.id != stack.id }

        // Record deactivation events BEFORE changing state
        for stackToDeactivate in stacksToDeactivate {
            try eventService.recordStackDeactivated(stackToDeactivate)
            stackToDeactivate.isActive = false
            stackToDeactivate.updatedAt = Date()
            stackToDeactivate.syncState = .pending
        }

        // Get stacks with status == .active for sort order management
        let activeStacks = try getActiveStacks()

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

        try eventService.recordStackActivated(stack)
        try eventService.recordStackReordered(activeStacks)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        // MARK: Post-condition validation (fix rather than throw)
        try validateAndFixSingleActiveConstraint(keeping: stack.id)
    }

    func closeStack(_ stack: Stack, reason: String? = nil) throws {
        stack.status = .closed
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackUpdated(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Delete

    func deleteStack(_ stack: Stack) throws {
        stack.isDeleted = true
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackDeleted(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Reorder

    func updateSortOrders(_ stacks: [Stack]) throws {
        for (index, stack) in stacks.enumerated() {
            stack.sortOrder = index
            stack.updatedAt = Date()
            stack.syncState = .pending
        }

        try eventService.recordStackReordered(stacks)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - History Revert

    /// Reverts a stack to a historical state captured in an event.
    /// Creates a NEW update event (preserves immutable history).
    ///
    /// Example timeline after revert:
    /// ```
    /// 10:00 - Created "Get Bread"
    /// 10:05 - Updated "Get French Bread"
    /// 10:10 - Updated "Get Sourdough Bread"
    /// 10:15 - Updated "Get French Bread"  ← Revert creates NEW event
    /// ```
    ///
    /// - Parameters:
    ///   - stack: The stack to revert
    ///   - event: The historical event containing the desired state
    func revertToHistoricalState(_ stack: Stack, from event: Event) throws {
        let historicalPayload = try event.decodePayload(StackEventPayload.self)

        // Apply historical values
        stack.title = historicalPayload.title
        stack.stackDescription = historicalPayload.description
        stack.status = historicalPayload.status
        stack.priority = historicalPayload.priority
        stack.sortOrder = historicalPayload.sortOrder
        stack.isDraft = historicalPayload.isDraft
        stack.isActive = historicalPayload.isActive
        stack.activeTaskId = historicalPayload.activeTaskId
        stack.updatedAt = Date()  // Current time - this IS a new edit
        stack.syncState = .pending

        // Record as a NEW update event (preserves immutable history)
        try eventService.recordStackUpdated(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Migration

    /// Migrates existing data to ensure exactly one stack has isActive = true.
    /// Call this on app startup to handle the schema migration from sortOrder-based
    /// active tracking to explicit isActive field.
    ///
    /// Migration logic:
    /// 1. If no stack has isActive = true, set the stack with sortOrder = 0 as active
    /// 2. If multiple stacks have isActive = true, keep only the one with lowest sortOrder
    func migrateActiveStackState() throws {
        let activeStacks = try getActiveStacks()
        guard !activeStacks.isEmpty else { return }

        // Find ALL stacks that have isActive = true (regardless of status)
        let allWithIsActiveTrue = try getAllStacksWithIsActiveTrue()

        if allWithIsActiveTrue.isEmpty {
            // No stack is marked active - activate the one with lowest sortOrder
            if let firstStack = activeStacks.min(by: { $0.sortOrder < $1.sortOrder }) {
                firstStack.isActive = true
                firstStack.syncState = .pending
                try modelContext.save()
            }
        } else if allWithIsActiveTrue.count > 1 {
            // Multiple stacks marked active - keep only the one with lowest sortOrder
            // Prefer stacks with status == .active
            let activeStatusStacks = allWithIsActiveTrue.filter { $0.status == .active }
            let stackToKeepActive: Stack?

            if !activeStatusStacks.isEmpty {
                stackToKeepActive = activeStatusStacks.min(by: { $0.sortOrder < $1.sortOrder })
            } else {
                stackToKeepActive = allWithIsActiveTrue.min(by: { $0.sortOrder < $1.sortOrder })
            }

            for stack in allWithIsActiveTrue {
                if stack.id == stackToKeepActive?.id {
                    stack.isActive = true
                } else {
                    stack.isActive = false
                }
                stack.syncState = .pending
            }
            try modelContext.save()
        }
        // If exactly one is active, no migration needed
    }

    /// Migrates existing data to populate activeTaskId from computed value.
    /// Call this on app startup after migrateActiveStackState().
    ///
    /// Migration logic:
    /// For each stack without activeTaskId, set it to the first pending task (if any)
    func migrateActiveTaskId() throws {
        let activeStacks = try getActiveStacks()

        var needsSave = false
        for stack in activeStacks {
            // Skip if already has activeTaskId set
            guard stack.activeTaskId == nil else { continue }

            // Set activeTaskId to first pending task (matches previous computed behavior)
            if let firstPendingTask = stack.pendingTasks.first {
                stack.activeTaskId = firstPendingTask.id
                stack.syncState = .pending
                needsSave = true
            }
        }

        if needsSave {
            try modelContext.save()
        }
    }
}
