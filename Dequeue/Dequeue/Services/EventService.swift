//
//  EventService.swift
//  Dequeue
//
//  Records events for sync and audit trail
//

import Foundation
import SwiftData

@MainActor
final class EventService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Stack Events

    func recordStackCreated(_ stack: Stack) throws {
        let payload = StackEventPayload(
            id: stack.id,
            title: stack.title,
            description: stack.stackDescription,
            status: stack.status,
            priority: stack.priority,
            sortOrder: stack.sortOrder,
            isDraft: stack.isDraft
        )
        try recordEvent(type: .stackCreated, payload: payload)
    }

    func recordStackUpdated(_ stack: Stack) throws {
        let payload = StackEventPayload(
            id: stack.id,
            title: stack.title,
            description: stack.stackDescription,
            status: stack.status,
            priority: stack.priority,
            sortOrder: stack.sortOrder,
            isDraft: stack.isDraft
        )
        try recordEvent(type: .stackUpdated, payload: payload)
    }

    func recordStackDeleted(_ stack: Stack) throws {
        let payload = EntityDeletedPayload(id: stack.id)
        try recordEvent(type: .stackDeleted, payload: payload)
    }

    func recordStackCompleted(_ stack: Stack) throws {
        let payload = EntityStatusPayload(id: stack.id, status: StackStatus.completed.rawValue)
        try recordEvent(type: .stackCompleted, payload: payload)
    }

    func recordStackActivated(_ stack: Stack) throws {
        let payload = EntityStatusPayload(id: stack.id, status: StackStatus.active.rawValue)
        try recordEvent(type: .stackActivated, payload: payload)
    }

    func recordStackReordered(_ stacks: [Stack]) throws {
        let payload = ReorderPayload(
            ids: stacks.map { $0.id },
            sortOrders: stacks.map { $0.sortOrder }
        )
        try recordEvent(type: .stackReordered, payload: payload)
    }

    // MARK: - Task Events

    func recordTaskCreated(_ task: QueueTask) throws {
        let payload = TaskEventPayload(
            id: task.id,
            stackId: task.stack?.id,
            title: task.title,
            description: task.taskDescription,
            status: task.status,
            priority: task.priority,
            sortOrder: task.sortOrder
        )
        try recordEvent(type: .taskCreated, payload: payload)
    }

    func recordTaskUpdated(_ task: QueueTask) throws {
        let payload = TaskEventPayload(
            id: task.id,
            stackId: task.stack?.id,
            title: task.title,
            description: task.taskDescription,
            status: task.status,
            priority: task.priority,
            sortOrder: task.sortOrder
        )
        try recordEvent(type: .taskUpdated, payload: payload)
    }

    func recordTaskDeleted(_ task: QueueTask) throws {
        let payload = EntityDeletedPayload(id: task.id)
        try recordEvent(type: .taskDeleted, payload: payload)
    }

    func recordTaskCompleted(_ task: QueueTask) throws {
        let payload = EntityStatusPayload(id: task.id, status: TaskStatus.completed.rawValue)
        try recordEvent(type: .taskCompleted, payload: payload)
    }

    func recordTaskReordered(_ tasks: [QueueTask]) throws {
        let payload = ReorderPayload(
            ids: tasks.map { $0.id },
            sortOrders: tasks.map { $0.sortOrder }
        )
        try recordEvent(type: .taskReordered, payload: payload)
    }

    // MARK: - Reminder Events

    func recordReminderCreated(_ reminder: Reminder) throws {
        let payload = ReminderEventPayload(
            id: reminder.id,
            parentId: reminder.parentId,
            parentType: reminder.parentType,
            remindAt: reminder.remindAt,
            status: reminder.status
        )
        try recordEvent(type: .reminderCreated, payload: payload)
    }

    func recordReminderUpdated(_ reminder: Reminder) throws {
        let payload = ReminderEventPayload(
            id: reminder.id,
            parentId: reminder.parentId,
            parentType: reminder.parentType,
            remindAt: reminder.remindAt,
            status: reminder.status
        )
        try recordEvent(type: .reminderUpdated, payload: payload)
    }

    func recordReminderDeleted(_ reminder: Reminder) throws {
        let payload = EntityDeletedPayload(id: reminder.id)
        try recordEvent(type: .reminderDeleted, payload: payload)
    }

    // MARK: - Query

    func fetchPendingEvents() throws -> [Event] {
        let predicate = #Predicate<Event> { event in
            event.isSynced == false
        }
        let descriptor = FetchDescriptor<Event>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    func markEventsSynced(_ events: [Event]) throws {
        let now = Date()
        for event in events {
            event.isSynced = true
            event.syncedAt = now
        }
        try modelContext.save()
    }

    // MARK: - Private

    private func recordEvent<T: Encodable>(type: EventType, payload: T) throws {
        let payloadData = try JSONEncoder().encode(payload)
        let event = Event(eventType: type, payload: payloadData)
        modelContext.insert(event)
        try modelContext.save()
    }
}

// MARK: - Event Payloads

struct StackEventPayload: Codable {
    let id: UUID
    let title: String
    let description: String?
    let status: StackStatus
    let priority: Int?
    let sortOrder: Int
    let isDraft: Bool
}

struct TaskEventPayload: Codable {
    let id: UUID
    let stackId: UUID?
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: Int?
    let sortOrder: Int
}

struct ReminderEventPayload: Codable {
    let id: UUID
    let parentId: UUID
    let parentType: ParentType
    let remindAt: Date
    let status: ReminderStatus
}

struct EntityDeletedPayload: Codable {
    let id: UUID
}

struct EntityStatusPayload: Codable {
    let id: UUID
    let status: String
}

struct ReorderPayload: Codable {
    let ids: [UUID]
    let sortOrders: [Int]
}
