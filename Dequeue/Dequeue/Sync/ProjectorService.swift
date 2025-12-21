//
//  ProjectorService.swift
//  Dequeue
//
//  Applies incoming sync events to local SwiftData models
//

import Foundation
import SwiftData

enum ProjectorService {
    static func apply(event: Event, context: ModelContext) throws {
        guard let eventType = event.eventType else { return }

        switch eventType {
        // Stack events
        case .stackCreated:
            try applyStackCreated(event: event, context: context)
        case .stackUpdated:
            try applyStackUpdated(event: event, context: context)
        case .stackDeleted:
            try applyStackDeleted(event: event, context: context)
        case .stackCompleted:
            try applyStackCompleted(event: event, context: context)
        case .stackActivated:
            try applyStackActivated(event: event, context: context)
        case .stackDeactivated:
            try applyStackDeactivated(event: event, context: context)
        case .stackClosed:
            try applyStackClosed(event: event, context: context)
        case .stackReordered:
            try applyStackReordered(event: event, context: context)

        // Task events
        case .taskCreated:
            try applyTaskCreated(event: event, context: context)
        case .taskUpdated:
            try applyTaskUpdated(event: event, context: context)
        case .taskDeleted:
            try applyTaskDeleted(event: event, context: context)
        case .taskCompleted:
            try applyTaskCompleted(event: event, context: context)
        case .taskActivated:
            try applyTaskActivated(event: event, context: context)
        case .taskClosed:
            try applyTaskClosed(event: event, context: context)
        case .taskReordered:
            try applyTaskReordered(event: event, context: context)

        // Reminder events
        case .reminderCreated:
            try applyReminderCreated(event: event, context: context)
        case .reminderUpdated:
            try applyReminderUpdated(event: event, context: context)
        case .reminderDeleted:
            try applyReminderDeleted(event: event, context: context)
        case .reminderSnoozed:
            try applyReminderSnoozed(event: event, context: context)

        case .deviceDiscovered:
            break
        }
    }

    // MARK: - Stack Events

    private static func applyStackCreated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(StackEventPayload.self)

        if let existing = try findStack(id: payload.id, context: context) {
            updateStack(existing, from: payload)
        } else {
            let stack = Stack(
                id: payload.id,
                title: payload.title,
                stackDescription: payload.description,
                status: payload.status,
                priority: payload.priority,
                sortOrder: payload.sortOrder,
                isDraft: payload.isDraft,
                syncState: .synced,
                lastSyncedAt: Date()
            )
            context.insert(stack)
        }
    }

    private static func applyStackUpdated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(StackEventPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }
        updateStack(stack, from: payload)
    }

    private static func applyStackDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }
        stack.isDeleted = true
        stack.updatedAt = Date()
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackCompleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }
        stack.status = .completed
        stack.updatedAt = Date()
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackActivated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }
        stack.status = .active
        stack.updatedAt = Date()
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackDeactivated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }
        stack.status = .archived
        stack.updatedAt = Date()
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackClosed(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }
        stack.status = .closed
        stack.updatedAt = Date()
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackReordered(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(ReorderPayload.self)
        for (index, id) in payload.ids.enumerated() {
            guard let stack = try findStack(id: id, context: context) else { continue }
            stack.sortOrder = payload.sortOrders[index]
            stack.updatedAt = Date()
            stack.syncState = .synced
            stack.lastSyncedAt = Date()
        }
    }

    // MARK: - Task Events

    private static func applyTaskCreated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(TaskEventPayload.self)

        if let existing = try findTask(id: payload.id, context: context) {
            updateTask(existing, from: payload, context: context)
        } else {
            let task = QueueTask(
                id: payload.id,
                title: payload.title,
                taskDescription: payload.description,
                status: payload.status,
                priority: payload.priority,
                sortOrder: payload.sortOrder,
                syncState: .synced,
                lastSyncedAt: Date()
            )

            if let stackId = payload.stackId,
               let stack = try findStack(id: stackId, context: context) {
                task.stack = stack
                stack.tasks.append(task)
            }

            context.insert(task)
        }
    }

    private static func applyTaskUpdated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(TaskEventPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }
        updateTask(task, from: payload, context: context)
    }

    private static func applyTaskDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }
        task.isDeleted = true
        task.updatedAt = Date()
        task.syncState = .synced
        task.lastSyncedAt = Date()
    }

    private static func applyTaskCompleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }
        task.status = .completed
        task.updatedAt = Date()
        task.syncState = .synced
        task.lastSyncedAt = Date()
    }

    private static func applyTaskActivated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }
        task.status = .pending
        task.sortOrder = 0
        task.updatedAt = Date()
        task.syncState = .synced
        task.lastSyncedAt = Date()
    }

    private static func applyTaskClosed(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }
        task.status = .closed
        task.updatedAt = Date()
        task.syncState = .synced
        task.lastSyncedAt = Date()
    }

    private static func applyTaskReordered(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(ReorderPayload.self)
        for (index, id) in payload.ids.enumerated() {
            guard let task = try findTask(id: id, context: context) else { continue }
            task.sortOrder = payload.sortOrders[index]
            task.updatedAt = Date()
            task.syncState = .synced
            task.lastSyncedAt = Date()
        }
    }

    // MARK: - Reminder Events

    private static func applyReminderCreated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(ReminderEventPayload.self)

        if let existing = try findReminder(id: payload.id, context: context) {
            updateReminder(existing, from: payload, context: context)
        } else {
            let reminder = Reminder(
                id: payload.id,
                parentId: payload.parentId,
                parentType: payload.parentType,
                status: payload.status,
                remindAt: payload.remindAt,
                syncState: .synced,
                lastSyncedAt: Date()
            )
            context.insert(reminder)

            switch payload.parentType {
            case .stack:
                if let stack = try findStack(id: payload.parentId, context: context) {
                    stack.reminders.append(reminder)
                }
            case .task:
                if let task = try findTask(id: payload.parentId, context: context) {
                    task.reminders.append(reminder)
                }
            }
        }
    }

    private static func applyReminderUpdated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(ReminderEventPayload.self)
        guard let reminder = try findReminder(id: payload.id, context: context) else { return }
        updateReminder(reminder, from: payload, context: context)
    }

    private static func applyReminderDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let reminder = try findReminder(id: payload.id, context: context) else { return }
        reminder.isDeleted = true
        reminder.updatedAt = Date()
        reminder.syncState = .synced
        reminder.lastSyncedAt = Date()
    }

    private static func applyReminderSnoozed(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(ReminderEventPayload.self)
        guard let reminder = try findReminder(id: payload.id, context: context) else { return }
        reminder.status = .snoozed
        reminder.remindAt = payload.remindAt
        reminder.updatedAt = Date()
        reminder.syncState = .synced
        reminder.lastSyncedAt = Date()
    }

    // MARK: - Helpers

    private static func findStack(id: UUID, context: ModelContext) throws -> Stack? {
        let predicate = #Predicate<Stack> { $0.id == id }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    private static func findTask(id: UUID, context: ModelContext) throws -> QueueTask? {
        let predicate = #Predicate<QueueTask> { $0.id == id }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    private static func findReminder(id: UUID, context: ModelContext) throws -> Reminder? {
        let predicate = #Predicate<Reminder> { $0.id == id }
        let descriptor = FetchDescriptor<Reminder>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    private static func updateStack(_ stack: Stack, from payload: StackEventPayload) {
        stack.title = payload.title
        stack.stackDescription = payload.description
        stack.status = payload.status
        stack.priority = payload.priority
        stack.sortOrder = payload.sortOrder
        stack.isDraft = payload.isDraft
        stack.updatedAt = Date()
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func updateTask(_ task: QueueTask, from payload: TaskEventPayload, context: ModelContext) {
        task.title = payload.title
        task.taskDescription = payload.description
        task.status = payload.status
        task.priority = payload.priority
        task.sortOrder = payload.sortOrder
        task.updatedAt = Date()
        task.syncState = .synced
        task.lastSyncedAt = Date()

        if let stackId = payload.stackId,
           task.stack?.id != stackId,
           let newStack = try? findStack(id: stackId, context: context) {
            task.stack = newStack
        }
    }

    private static func updateReminder(_ reminder: Reminder, from payload: ReminderEventPayload, context: ModelContext) {
        reminder.remindAt = payload.remindAt
        reminder.status = payload.status
        reminder.updatedAt = Date()
        reminder.syncState = .synced
        reminder.lastSyncedAt = Date()
    }
}
