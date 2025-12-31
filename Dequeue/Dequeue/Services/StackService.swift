//
//  StackService.swift
//  Dequeue
//
//  Business logic for Stack operations
//

import Foundation
import SwiftData

@MainActor
final class StackService {
    private let modelContext: ModelContext
    private let eventService: EventService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext)
    }

    // MARK: - Create

    func createStack(
        title: String,
        description: String? = nil,
        isDraft: Bool = false
    ) throws -> Stack {
        let stack = Stack(
            title: title,
            stackDescription: description,
            status: .active,
            sortOrder: 0,
            isDraft: isDraft,
            syncState: .pending
        )

        modelContext.insert(stack)

        // Always record events - drafts are synced for offline-first behavior
        try eventService.recordStackCreated(stack)

        try modelContext.save()
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
    }

    /// Discards a draft stack - fires stack.discarded event
    func discardDraft(_ stack: Stack) throws {
        guard stack.isDraft else { return }

        stack.isDeleted = true
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackDiscarded(stack)
        try modelContext.save()
    }

    // MARK: - Read

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
    }

    func publishDraft(_ stack: Stack) throws {
        guard stack.isDraft else { return }

        stack.isDraft = false
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackCreated(stack)
        try modelContext.save()
    }

    // MARK: - Status Changes

    func markAsCompleted(_ stack: Stack, completeAllTasks: Bool = true) throws {
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
    }

    func setAsActive(_ stack: Stack) throws {
        let activeStacks = try getActiveStacks()

        for (index, activeStack) in activeStacks.enumerated() {
            if activeStack.id == stack.id {
                activeStack.sortOrder = 0
            } else if activeStack.sortOrder <= stack.sortOrder {
                activeStack.sortOrder = index + 1
            }
            activeStack.syncState = .pending
        }

        try eventService.recordStackActivated(stack)
        try eventService.recordStackReordered(activeStacks)
        try modelContext.save()
    }

    func closeStack(_ stack: Stack, reason: String? = nil) throws {
        stack.status = .closed
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackUpdated(stack)
        try modelContext.save()
    }

    // MARK: - Delete

    func deleteStack(_ stack: Stack) throws {
        stack.isDeleted = true
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackDeleted(stack)
        try modelContext.save()
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
        stack.updatedAt = Date()  // Current time - this IS a new edit
        stack.syncState = .pending

        // Record as a NEW update event (preserves immutable history)
        try eventService.recordStackUpdated(stack)
        try modelContext.save()
    }
}
