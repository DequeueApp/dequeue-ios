//
//  TaskDependencyService.swift
//  Dequeue
//
//  Manages task dependency relationships ("blocked by" / "blocks")
//  Dependencies are stored as task IDs in the QueueTask model.
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "TaskDependencyService")

@MainActor
final class TaskDependencyService {
    private let modelContext: ModelContext
    private let eventService: EventService
    private let syncManager: SyncManager?

    init(modelContext: ModelContext, userId: String, deviceId: String, syncManager: SyncManager? = nil) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        self.syncManager = syncManager
    }

    // MARK: - Add/Remove Dependencies

    /// Adds a dependency: `task` is blocked by `blockerTask`
    /// Returns false if adding would create a circular dependency
    func addDependency(task: QueueTask, blockedBy blockerTask: QueueTask) async throws -> Bool {
        // Prevent self-dependency
        guard task.id != blockerTask.id else {
            logger.warning("Cannot add self-dependency")
            return false
        }

        // Check for circular dependency
        if wouldCreateCycle(adding: blockerTask.id, to: task) {
            logger.warning("Circular dependency detected: \(task.id) -> \(blockerTask.id)")
            return false
        }

        // Add the dependency
        var deps = task.dependencyIds
        guard !deps.contains(blockerTask.id) else {
            return true // Already exists
        }
        deps.append(blockerTask.id)
        task.dependencyIds = deps
        task.updatedAt = Date()
        task.syncState = .pending

        // Auto-block task if the blocker isn't completed
        if blockerTask.status != .completed {
            task.status = .blocked
            task.blockedReason = "Waiting on: \(blockerTask.title)"
        }

        try await eventService.recordTaskUpdated(task, changes: [
            "dependencyAdded": blockerTask.id
        ])
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        logger.info("Added dependency: \(task.id) blocked by \(blockerTask.id)")
        return true
    }

    /// Removes a dependency
    func removeDependency(task: QueueTask, blockerTaskId: String) async throws {
        var deps = task.dependencyIds
        deps.removeAll { $0 == blockerTaskId }
        task.dependencyIds = deps
        task.updatedAt = Date()
        task.syncState = .pending

        // If no more blocking dependencies, unblock the task
        if deps.isEmpty && task.status == .blocked {
            let allDepsCompleted = try areDependenciesSatisfied(for: task)
            if allDepsCompleted {
                task.status = .pending
                task.blockedReason = nil
            }
        }

        try await eventService.recordTaskUpdated(task, changes: [
            "dependencyRemoved": blockerTaskId
        ])
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        logger.info("Removed dependency: \(task.id) no longer blocked by \(blockerTaskId)")
    }

    // MARK: - Dependency Status

    /// Checks if all dependencies for a task are satisfied (completed)
    func areDependenciesSatisfied(for task: QueueTask) throws -> Bool {
        let deps = task.dependencyIds
        guard !deps.isEmpty else { return true }

        for depId in deps {
            if let depTask = try findTask(id: depId) {
                if depTask.status != .completed && !depTask.isDeleted {
                    return false
                }
            }
            // If dependency task not found, consider it satisfied (might have been deleted)
        }
        return true
    }

    /// Returns the actual task objects for all dependencies
    func getDependencyTasks(for task: QueueTask) throws -> [QueueTask] {
        try task.dependencyIds.compactMap { try findTask(id: $0) }
    }

    /// Returns tasks that depend on (are blocked by) the given task
    func getDependentTasks(for blockerTask: QueueTask) throws -> [QueueTask] {
        let blockerId = blockerTask.id
        let descriptor = FetchDescriptor<QueueTask>(
            predicate: #Predicate<QueueTask> { task in
                !task.isDeleted
            }
        )
        let allTasks = try modelContext.fetch(descriptor)
        return allTasks.filter { $0.dependencyIds.contains(blockerId) }
    }

    // MARK: - Auto-Unblock on Completion

    /// Called when a task is completed — checks if any dependent tasks should be unblocked
    func onTaskCompleted(_ completedTask: QueueTask) async throws {
        let dependents = try getDependentTasks(for: completedTask)

        for dependent in dependents {
            let allSatisfied = try areDependenciesSatisfied(for: dependent)
            if allSatisfied && dependent.status == .blocked {
                dependent.status = .pending
                dependent.blockedReason = nil
                dependent.updatedAt = Date()
                dependent.syncState = .pending

                try await eventService.recordTaskUpdated(dependent, changes: [
                    "autoUnblocked": "true",
                    "unblockTrigger": completedTask.id
                ])

                logger.info("Auto-unblocked task \(dependent.id) — all dependencies satisfied")
            }
        }

        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Cycle Detection

    /// Checks if adding `newDepId` as a dependency of `task` would create a cycle
    private func wouldCreateCycle(adding newDepId: String, to task: QueueTask) -> Bool {
        // DFS from newDepId to see if we can reach task.id
        var visited = Set<String>()
        return dfsReaches(from: newDepId, target: task.id, visited: &visited)
    }

    private func dfsReaches(from currentId: String, target: String, visited: inout Set<String>) -> Bool {
        if currentId == target { return true }
        if visited.contains(currentId) { return false }
        visited.insert(currentId)

        guard let currentTask = try? findTask(id: currentId) else { return false }
        for depId in currentTask.dependencyIds where dfsReaches(from: depId, target: target, visited: &visited) {
            return true
        }
        return false
    }

    // MARK: - Helpers

    private func findTask(id: String) throws -> QueueTask? {
        let descriptor = FetchDescriptor<QueueTask>(
            predicate: #Predicate<QueueTask> { task in
                task.id == id && !task.isDeleted
            }
        )
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - QueueTask Dependency Extensions

extension QueueTask {
    /// IDs of tasks this task depends on (is blocked by)
    /// Stored as JSON array in dependencyData
    var dependencyIds: [String] {
        get {
            guard let data = dependencyData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            dependencyData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Whether this task has any dependencies
    var hasDependencies: Bool {
        !dependencyIds.isEmpty
    }

    /// Count of dependencies
    var dependencyCount: Int {
        dependencyIds.count
    }
}
