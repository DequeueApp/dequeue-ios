//
//  DequeueAppIntents.swift
//  Dequeue
//
//  App Intents for Siri and Shortcuts integration
//

import AppIntents
import SwiftData
import os.log

// MARK: - App Entity: StackEntity

/// Lightweight representation of a Stack for App Intents
struct StackEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stack"

    static let defaultQuery = StackEntityQuery()

    var id: String
    var title: String
    var taskCount: Int
    var pendingTaskCount: Int
    var isActive: Bool
    var status: String

    var displayRepresentation: DisplayRepresentation {
        if isActive {
            return DisplayRepresentation(
                title: "⚡ \(title)",
                subtitle: "\(pendingTaskCount) of \(taskCount) tasks remaining"
            )
        } else {
            return DisplayRepresentation(
                title: "\(title)",
                subtitle: "\(pendingTaskCount) of \(taskCount) tasks remaining"
            )
        }
    }
}

// MARK: - App Entity: TaskEntity

/// Lightweight representation of a QueueTask for App Intents
struct TaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"

    static let defaultQuery = TaskEntityQuery()

    var id: String
    var title: String
    var stackTitle: String?
    var status: String
    var priority: Int?
    var hasDueDate: Bool

    var displayRepresentation: DisplayRepresentation {
        let subtitle = stackTitle.map { "in \($0)" } ?? "No stack"
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)"
        )
    }
}

// MARK: - Entity Queries

struct StackEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [StackEntity] {
        let container = try IntentsModelContainer.shared
        let context = ModelContext(container)

        var results: [StackEntity] = []
        for identifier in identifiers {
            let predicate = #Predicate<Stack> {
                $0.id == identifier && !$0.isDeleted
            }
            let descriptor = FetchDescriptor<Stack>(predicate: predicate)
            if let stack = try context.fetch(descriptor).first {
                results.append(stack.toEntity())
            }
        }
        return results
    }

    @MainActor
    func suggestedEntities() async throws -> [StackEntity] {
        let container = try IntentsModelContainer.shared
        let context = ModelContext(container)

        let predicate = #Predicate<Stack> {
            !$0.isDeleted && !$0.isDraft && $0.statusRawValue == "active"
        }
        var descriptor = FetchDescriptor<Stack>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.sortOrder)]
        descriptor.fetchLimit = 20

        let stacks = try context.fetch(descriptor)
        return stacks.map { $0.toEntity() }
    }
}

struct TaskEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TaskEntity] {
        let container = try IntentsModelContainer.shared
        let context = ModelContext(container)

        var results: [TaskEntity] = []
        for identifier in identifiers {
            let predicate = #Predicate<QueueTask> {
                $0.id == identifier && !$0.isDeleted
            }
            let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
            if let task = try context.fetch(descriptor).first {
                results.append(task.toEntity())
            }
        }
        return results
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskEntity] {
        let container = try IntentsModelContainer.shared
        let context = ModelContext(container)

        // Fetch non-deleted tasks and filter pending in-memory
        // (SwiftData predicates on Codable enums can be unreliable)
        let predicate = #Predicate<QueueTask> { !$0.isDeleted }
        var descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.sortOrder)]

        let allTasks = try context.fetch(descriptor)
        return allTasks
            .filter { $0.status == .pending }
            .prefix(20)
            .map { $0.toEntity() }
    }
}

// MARK: - Model Extensions for Entity Conversion

extension Stack {
    func toEntity() -> StackEntity {
        let allTasks = tasks.filter { !$0.isDeleted }
        let pending = allTasks.filter { $0.status == .pending }
        return StackEntity(
            id: id,
            title: title,
            taskCount: allTasks.count,
            pendingTaskCount: pending.count,
            isActive: isActive,
            status: statusRawValue
        )
    }
}

extension QueueTask {
    func toEntity() -> TaskEntity {
        TaskEntity(
            id: id,
            title: title,
            stackTitle: stack?.title,
            status: String(describing: status),
            priority: priority,
            hasDueDate: dueTime != nil
        )
    }
}

// MARK: - Shared Model Container for Intents

/// Provides a shared ModelContainer for App Intents.
/// Uses nonisolated(unsafe) because ModelContainer is thread-safe once created,
/// and App Intents may run from various actor contexts.
enum IntentsModelContainer {
    nonisolated(unsafe) private static var _container: ModelContainer?

    @MainActor
    static var shared: ModelContainer {
        get throws {
            if let existing = _container { return existing }
            let schema = Schema([
                Stack.self,
                QueueTask.self,
                Reminder.self,
                Event.self,
                Device.self,
                SyncConflict.self,
                Attachment.self,
                Tag.self,
                Arc.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            _container = container
            return container
        }
    }
}
