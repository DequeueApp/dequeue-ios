//
//  BatchOperationService.swift
//  Dequeue
//
//  Service for performing bulk operations on multiple tasks at once.
//  Supports batch complete, move, delete, set priority, and tag operations.
//

import Foundation
import SwiftData

/// Defines the types of batch operations that can be performed on selected tasks.
enum BatchOperation: String, CaseIterable, Identifiable, Sendable {
    case complete = "Complete"
    case close = "Close"
    case reopen = "Reopen"
    case delete = "Delete"
    case move = "Move to Stack"
    case setPriority = "Set Priority"
    case addTags = "Add Tags"
    case removeTags = "Remove Tags"
    case setDueDate = "Set Due Date"
    case clearDueDate = "Clear Due Date"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .complete: return "checkmark.circle"
        case .close: return "xmark.circle"
        case .reopen: return "arrow.uturn.backward.circle"
        case .delete: return "trash"
        case .move: return "arrow.right.square"
        case .setPriority: return "flag"
        case .addTags: return "tag"
        case .removeTags: return "tag.slash"
        case .setDueDate: return "calendar.badge.clock"
        case .clearDueDate: return "calendar.badge.minus"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .delete, .close: return true
        default: return false
        }
    }
}

/// Result of a batch operation, reporting successes and failures.
struct BatchOperationResult: Sendable {
    let operation: BatchOperation
    let totalSelected: Int
    let successCount: Int
    let failureCount: Int
    let errors: [String]

    var isFullSuccess: Bool { failureCount == 0 }

    var summary: String {
        if isFullSuccess {
            return "\(operation.rawValue): \(successCount) task\(successCount == 1 ? "" : "s") updated"
        } else {
            return "\(operation.rawValue): \(successCount) succeeded, \(failureCount) failed"
        }
    }
}

@MainActor
final class BatchOperationService {
    private let modelContext: ModelContext
    private let eventService: EventService
    private let syncManager: SyncManager?

    init(modelContext: ModelContext, userId: String, deviceId: String, syncManager: SyncManager? = nil) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        self.syncManager = syncManager
    }

    // MARK: - Batch Complete

    func batchComplete(_ tasks: [QueueTask]) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        for task in tasks {
            do {
                guard task.status == .pending || task.status == .blocked else {
                    errors.append("\(task.title): already \(task.status.rawValue)")
                    continue
                }
                task.status = .completed
                task.updatedAt = Date()
                task.syncState = .pending

                // Dismiss active reminders
                for reminder in task.reminders where !reminder.isDeleted {
                    if reminder.status == .active || reminder.status == .snoozed {
                        reminder.status = .fired
                        reminder.updatedAt = Date()
                        reminder.syncState = .pending
                    }
                }

                try await eventService.recordTaskCompleted(task)

                // Handle recurring tasks
                if task.isRecurring {
                    let userId = task.userId ?? ""
                    let deviceId = task.deviceId ?? ""
                    let recurringService = RecurringTaskService(
                        modelContext: modelContext,
                        userId: userId,
                        deviceId: deviceId,
                        syncManager: syncManager
                    )
                    try await recurringService.createNextOccurrence(for: task)
                }

                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .complete,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Batch Close

    func batchClose(_ tasks: [QueueTask]) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        for task in tasks {
            do {
                guard task.status != .closed else {
                    errors.append("\(task.title): already closed")
                    continue
                }
                task.status = .closed
                task.updatedAt = Date()
                task.syncState = .pending
                try await eventService.recordTaskUpdated(task)
                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .close,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Batch Reopen

    func batchReopen(_ tasks: [QueueTask]) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        for task in tasks {
            do {
                guard task.status == .completed || task.status == .closed else {
                    errors.append("\(task.title): not completed/closed")
                    continue
                }
                task.status = .pending
                task.blockedReason = nil
                task.updatedAt = Date()
                task.syncState = .pending
                try await eventService.recordTaskUpdated(task)
                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .reopen,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Batch Delete

    func batchDelete(_ tasks: [QueueTask]) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        for task in tasks {
            do {
                task.isDeleted = true
                task.updatedAt = Date()
                task.syncState = .pending
                try await eventService.recordTaskDeleted(task)
                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .delete,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Batch Move

    func batchMove(_ tasks: [QueueTask], to targetStack: Stack) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        let startOrder = targetStack.pendingTasks.count

        for (index, task) in tasks.enumerated() {
            do {
                guard task.stack?.id != targetStack.id else {
                    errors.append("\(task.title): already in target stack")
                    continue
                }
                let fromStackId = task.stack?.id ?? ""
                task.stack = targetStack
                task.sortOrder = startOrder + index
                task.updatedAt = Date()
                task.syncState = .pending
                try await eventService.recordTaskUpdated(task, changes: [
                    "stackId": targetStack.id,
                    "movedFrom": fromStackId
                ])
                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .move,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Batch Set Priority

    func batchSetPriority(_ tasks: [QueueTask], priority: Int?) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        for task in tasks {
            do {
                task.priority = priority
                task.updatedAt = Date()
                task.syncState = .pending
                try await eventService.recordTaskUpdated(task)
                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .setPriority,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Batch Add Tags

    func batchAddTags(_ tasks: [QueueTask], tags: [String]) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        for task in tasks {
            do {
                var currentTags = Set(task.tags)
                let newTags = Set(tags)
                let addedTags = newTags.subtracting(currentTags)
                guard !addedTags.isEmpty else {
                    errors.append("\(task.title): already has all specified tags")
                    continue
                }
                currentTags.formUnion(addedTags)
                task.tags = Array(currentTags).sorted()
                task.updatedAt = Date()
                task.syncState = .pending
                try await eventService.recordTaskUpdated(task)
                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .addTags,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Batch Remove Tags

    func batchRemoveTags(_ tasks: [QueueTask], tags: [String]) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        for task in tasks {
            do {
                var currentTags = Set(task.tags)
                let tagsToRemove = Set(tags)
                let removed = currentTags.intersection(tagsToRemove)
                guard !removed.isEmpty else {
                    errors.append("\(task.title): doesn't have specified tags")
                    continue
                }
                currentTags.subtract(tagsToRemove)
                task.tags = Array(currentTags).sorted()
                task.updatedAt = Date()
                task.syncState = .pending
                try await eventService.recordTaskUpdated(task)
                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .removeTags,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Batch Set Due Date

    func batchSetDueDate(_ tasks: [QueueTask], dueDate: Date) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        for task in tasks {
            do {
                task.dueTime = dueDate
                task.updatedAt = Date()
                task.syncState = .pending
                try await eventService.recordTaskUpdated(task)
                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .setDueDate,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Batch Clear Due Date

    func batchClearDueDate(_ tasks: [QueueTask]) async throws -> BatchOperationResult {
        var successCount = 0
        var errors: [String] = []

        for task in tasks {
            do {
                guard task.dueTime != nil else {
                    errors.append("\(task.title): no due date to clear")
                    continue
                }
                task.dueTime = nil
                task.updatedAt = Date()
                task.syncState = .pending
                try await eventService.recordTaskUpdated(task)
                successCount += 1
            } catch {
                errors.append("\(task.title): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return BatchOperationResult(
            operation: .clearDueDate,
            totalSelected: tasks.count,
            successCount: successCount,
            failureCount: tasks.count - successCount,
            errors: errors
        )
    }

    // MARK: - Available Operations

    /// Returns which batch operations are valid for the given selection of tasks.
    func availableOperations(for tasks: [QueueTask]) -> [BatchOperation] {
        guard !tasks.isEmpty else { return [] }

        var operations: [BatchOperation] = []

        let hasCompletable = tasks.contains { $0.status == .pending || $0.status == .blocked }
        let hasClosable = tasks.contains { $0.status != .closed }
        let hasReopenable = tasks.contains { $0.status == .completed || $0.status == .closed }
        let hasDueDate = tasks.contains { $0.dueTime != nil }

        if hasCompletable { operations.append(.complete) }
        if hasClosable { operations.append(.close) }
        if hasReopenable { operations.append(.reopen) }
        operations.append(.move)
        operations.append(.setPriority)
        operations.append(.addTags)
        operations.append(.removeTags)
        operations.append(.setDueDate)
        if hasDueDate { operations.append(.clearDueDate) }
        operations.append(.delete)

        return operations
    }
}
