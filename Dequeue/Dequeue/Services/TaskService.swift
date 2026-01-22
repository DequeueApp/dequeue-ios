//
//  TaskService.swift
//  Dequeue
//
//  Business logic for Task operations
//

import Foundation
import SwiftData

@MainActor
final class TaskService {
    private let modelContext: ModelContext
    private let eventService: EventService
    private let syncManager: SyncManager?

    init(modelContext: ModelContext, userId: String, deviceId: String, syncManager: SyncManager? = nil) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        self.syncManager = syncManager
    }

    // MARK: - Create

    func createTask(
        title: String,
        description: String? = nil,
        stack: Stack,
        sortOrder: Int? = nil
    ) async throws -> QueueTask {
        let order = sortOrder ?? stack.pendingTasks.count

        let task = QueueTask(
            title: title,
            taskDescription: description,
            status: .pending,
            sortOrder: order,
            stack: stack
        )

        modelContext.insert(task)
        stack.tasks.append(task)

        try await eventService.recordTaskCreated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return task
    }

    // MARK: - Update

    func updateTask(_ task: QueueTask, title: String, description: String?) async throws {
        task.title = title
        task.taskDescription = description
        task.updatedAt = Date()
        task.syncState = .pending

        try await eventService.recordTaskUpdated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Status Changes

    func markAsCompleted(_ task: QueueTask) async throws {
        task.status = .completed
        task.updatedAt = Date()
        task.syncState = .pending

        try await eventService.recordTaskCompleted(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func markAsBlocked(_ task: QueueTask, reason: String?) async throws {
        task.status = .blocked
        task.blockedReason = reason
        task.updatedAt = Date()
        task.syncState = .pending

        try await eventService.recordTaskUpdated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func unblock(_ task: QueueTask) async throws {
        task.status = .pending
        task.blockedReason = nil
        task.updatedAt = Date()
        task.syncState = .pending

        try await eventService.recordTaskUpdated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func closeTask(_ task: QueueTask) async throws {
        task.status = .closed
        task.updatedAt = Date()
        task.syncState = .pending

        try await eventService.recordTaskUpdated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Delete

    func deleteTask(_ task: QueueTask) async throws {
        task.isDeleted = true
        task.updatedAt = Date()
        task.syncState = .pending

        try await eventService.recordTaskDeleted(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Reorder

    func updateSortOrders(_ tasks: [QueueTask]) async throws {
        for (index, task) in tasks.enumerated() {
            task.sortOrder = index
            task.updatedAt = Date()
            task.syncState = .pending
        }

        try await eventService.recordTaskReordered(tasks)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Activate (move to top)

    func activateTask(_ task: QueueTask) async throws {
        guard let stack = task.stack else { return }

        // Set explicit active task tracking
        stack.activeTaskId = task.id
        stack.updatedAt = Date()
        stack.syncState = .pending

        // Track when this task was last activated
        task.lastActiveTime = Date()

        // Reorder tasks to maintain sort order consistency
        let pendingTasks = stack.pendingTasks
        var reorderedTasks = pendingTasks.filter { $0.id != task.id }
        reorderedTasks.insert(task, at: 0)

        for (index, reorderedTask) in reorderedTasks.enumerated() {
            reorderedTask.sortOrder = index
            reorderedTask.updatedAt = Date()
            reorderedTask.syncState = .pending
        }

        // Record events
        try await eventService.recordTaskActivated(task)
        try await eventService.recordTaskReordered(reorderedTasks)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }
}
