//
//  StackService+Tags.swift
//  Dequeue
//
//  Tag operations and history revert for StackService
//

import Foundation
import SwiftData

extension StackService {
    // MARK: - Tag Operations

    /// Adds a tag to a stack and records the update event for sync.
    ///
    /// - Parameters:
    ///   - tag: The tag to add
    ///   - stack: The stack to add the tag to
    func addTag(_ tag: Tag, to stack: Stack) async throws {
        guard !stack.tagObjects.contains(where: { $0.id == tag.id }) else { return }

        stack.tagObjects.append(tag)
        stack.updatedAt = Date()
        stack.syncState = .pending

        try await eventService.recordStackUpdated(stack, changes: ["tagIds": stack.tagObjects.map { $0.id }])
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    /// Removes a tag from a stack and records the update event for sync.
    ///
    /// - Parameters:
    ///   - tag: The tag to remove
    ///   - stack: The stack to remove the tag from
    func removeTag(_ tag: Tag, from stack: Stack) async throws {
        guard stack.tagObjects.contains(where: { $0.id == tag.id }) else { return }

        stack.tagObjects.removeAll { $0.id == tag.id }
        stack.updatedAt = Date()
        stack.syncState = .pending

        try await eventService.recordStackUpdated(stack, changes: ["tagIds": stack.tagObjects.map { $0.id }])
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
    func revertToHistoricalState(_ stack: Stack, from event: Event) async throws {
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
        try await eventService.recordStackUpdated(stack)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }
}
