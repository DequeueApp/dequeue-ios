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
    ) throws -> QueueTask {
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

        try eventService.recordTaskCreated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        return task
    }

    // MARK: - Update

    func updateTask(_ task: QueueTask, title: String, description: String?) throws {
        task.title = title
        task.taskDescription = description
        task.updatedAt = Date()
        task.syncState = .pending

        try eventService.recordTaskUpdated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Status Changes

    func markAsCompleted(_ task: QueueTask) throws {
        task.status = .completed
        task.updatedAt = Date()
        task.syncState = .pending

        try eventService.recordTaskCompleted(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func markAsBlocked(_ task: QueueTask, reason: String?) throws {
        task.status = .blocked
        task.blockedReason = reason
        task.updatedAt = Date()
        task.syncState = .pending

        try eventService.recordTaskUpdated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func unblock(_ task: QueueTask) throws {
        task.status = .pending
        task.blockedReason = nil
        task.updatedAt = Date()
        task.syncState = .pending

        try eventService.recordTaskUpdated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    func closeTask(_ task: QueueTask) throws {
        task.status = .closed
        task.updatedAt = Date()
        task.syncState = .pending

        try eventService.recordTaskUpdated(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Delete

    func deleteTask(_ task: QueueTask) throws {
        task.isDeleted = true
        task.updatedAt = Date()
        task.syncState = .pending

        try eventService.recordTaskDeleted(task)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Reorder

    func updateSortOrders(_ tasks: [QueueTask]) throws {
        for (index, task) in tasks.enumerated() {
            task.sortOrder = index
            task.updatedAt = Date()
            task.syncState = .pending
        }

        try eventService.recordTaskReordered(tasks)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Activate (move to top)

    func activateTask(_ task: QueueTask) throws {
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
        try eventService.recordTaskActivated(task)
        try eventService.recordTaskReordered(reorderedTasks)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }
}
