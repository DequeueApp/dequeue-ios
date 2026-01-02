//
//  ProjectorService.swift
//  Dequeue
//
//  Applies incoming sync events to local SwiftData models
//

// swiftlint:disable file_length

import Foundation
import SwiftData

// swiftlint:disable:next type_body_length
enum ProjectorService {
    // swiftlint:disable:next cyclomatic_complexity
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
        case .stackDiscarded:
            try applyStackDiscarded(event: event, context: context)
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
            try applyDeviceDiscovered(event: event, context: context)
        }
    }

    // MARK: - Device Events

    private static func applyDeviceDiscovered(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(DeviceEventPayload.self)

        // Check if device already exists
        let deviceId = payload.deviceId
        let predicate = #Predicate<Device> { device in
            device.deviceId == deviceId
        }
        let descriptor = FetchDescriptor<Device>(predicate: predicate)
        let existingDevices = try context.fetch(descriptor)

        if let existing = existingDevices.first {
            // Update existing device - use event timestamp for lastSeenAt
            existing.name = payload.name
            existing.model = payload.model
            existing.osName = payload.osName
            existing.osVersion = payload.osVersion
            existing.lastSeenAt = event.timestamp  // Use event timestamp, not current time
            existing.syncState = .synced
            existing.lastSyncedAt = Date()
        } else {
            // Create new device record for other device
            let device = Device(
                id: payload.id,
                deviceId: payload.deviceId,
                name: payload.name,
                model: payload.model,
                osName: payload.osName,
                osVersion: payload.osVersion,
                isDevice: payload.isDevice,
                isCurrentDevice: false,  // This is another device
                lastSeenAt: event.timestamp,  // Use event timestamp, not current time
                firstSeenAt: event.timestamp,  // Use event timestamp for first seen too
                syncState: .synced,
                lastSyncedAt: Date()
            )
            context.insert(device)
        }
    }

    // MARK: - Stack Events

    private static func applyStackCreated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(StackEventPayload.self)

        if let existing = try findStack(id: payload.id, context: context) {
            // LWW: Only update if this event is newer than current state
            guard event.timestamp > existing.updatedAt else { return }
            updateStack(existing, from: payload, eventTimestamp: event.timestamp)
        } else {
            let stack = Stack(
                id: payload.id,
                title: payload.title,
                stackDescription: payload.description,
                status: payload.status,
                priority: payload.priority,
                sortOrder: payload.sortOrder,
                isDraft: payload.isDraft,
                activeTaskId: payload.activeTaskId,
                syncState: .synced,
                lastSyncedAt: Date()
            )
            stack.updatedAt = event.timestamp  // LWW: Use event timestamp
            context.insert(stack)
        }
    }

    private static func applyStackUpdated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(StackEventPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !stack.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > stack.updatedAt else { return }

        updateStack(stack, from: payload, eventTimestamp: event.timestamp)
    }

    private static func applyStackDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > stack.updatedAt else { return }

        stack.isDeleted = true
        stack.updatedAt = event.timestamp  // LWW: Use event timestamp
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackDiscarded(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > stack.updatedAt else { return }

        // Discarded drafts are deleted
        stack.isDeleted = true
        stack.updatedAt = event.timestamp  // LWW: Use event timestamp
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackCompleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !stack.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > stack.updatedAt else { return }

        stack.status = .completed
        stack.updatedAt = event.timestamp  // LWW: Use event timestamp
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackActivated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !stack.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > stack.updatedAt else { return }

        stack.status = .active
        stack.updatedAt = event.timestamp  // LWW: Use event timestamp
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackDeactivated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !stack.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > stack.updatedAt else { return }

        stack.status = .archived
        stack.updatedAt = event.timestamp  // LWW: Use event timestamp
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackClosed(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !stack.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > stack.updatedAt else { return }

        stack.status = .closed
        stack.updatedAt = event.timestamp  // LWW: Use event timestamp
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackReordered(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(ReorderPayload.self)
        for (index, id) in payload.ids.enumerated() {
            guard let stack = try findStack(id: id, context: context) else { continue }

            // LWW: Skip updates to deleted entities
            guard !stack.isDeleted else { continue }

            // LWW: Only apply if this event is newer than current state (per entity)
            guard event.timestamp > stack.updatedAt else { continue }

            stack.sortOrder = payload.sortOrders[index]
            stack.updatedAt = event.timestamp  // LWW: Use event timestamp
            stack.syncState = .synced
            stack.lastSyncedAt = Date()
        }
    }

    // MARK: - Task Events

    private static func applyTaskCreated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(TaskEventPayload.self)

        if let existing = try findTask(id: payload.id, context: context) {
            // LWW: Only update if this event is newer than current state
            guard event.timestamp > existing.updatedAt else { return }
            updateTask(existing, from: payload, context: context, eventTimestamp: event.timestamp)
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
            task.updatedAt = event.timestamp  // LWW: Use event timestamp

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

        // LWW: Skip updates to deleted entities
        guard !task.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > task.updatedAt else { return }

        updateTask(task, from: payload, context: context, eventTimestamp: event.timestamp)
    }

    private static func applyTaskDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > task.updatedAt else { return }

        task.isDeleted = true
        task.updatedAt = event.timestamp  // LWW: Use event timestamp
        task.syncState = .synced
        task.lastSyncedAt = Date()
    }

    private static func applyTaskCompleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !task.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > task.updatedAt else { return }

        task.status = .completed
        task.updatedAt = event.timestamp  // LWW: Use event timestamp
        task.syncState = .synced
        task.lastSyncedAt = Date()
    }

    private static func applyTaskActivated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !task.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > task.updatedAt else { return }

        task.status = .pending
        task.sortOrder = 0
        task.updatedAt = event.timestamp  // LWW: Use event timestamp
        task.syncState = .synced
        task.lastSyncedAt = Date()

        // Update the stack's activeTaskId to match
        if let stack = task.stack {
            stack.activeTaskId = task.id
            stack.updatedAt = event.timestamp
            stack.syncState = .synced
            stack.lastSyncedAt = Date()
        }
    }

    private static func applyTaskClosed(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !task.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > task.updatedAt else { return }

        task.status = .closed
        task.updatedAt = event.timestamp  // LWW: Use event timestamp
        task.syncState = .synced
        task.lastSyncedAt = Date()
    }

    private static func applyTaskReordered(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(ReorderPayload.self)
        for (index, id) in payload.ids.enumerated() {
            guard let task = try findTask(id: id, context: context) else { continue }

            // LWW: Skip updates to deleted entities
            guard !task.isDeleted else { continue }

            // LWW: Only apply if this event is newer than current state (per entity)
            guard event.timestamp > task.updatedAt else { continue }

            task.sortOrder = payload.sortOrders[index]
            task.updatedAt = event.timestamp  // LWW: Use event timestamp
            task.syncState = .synced
            task.lastSyncedAt = Date()
        }
    }

    // MARK: - Reminder Events

    private static func applyReminderCreated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(ReminderEventPayload.self)

        if let existing = try findReminder(id: payload.id, context: context) {
            // LWW: Only update if this event is newer than current state
            guard event.timestamp > existing.updatedAt else { return }
            updateReminder(existing, from: payload, eventTimestamp: event.timestamp)
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
            reminder.updatedAt = event.timestamp  // LWW: Use event timestamp
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

        // LWW: Skip updates to deleted entities
        guard !reminder.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > reminder.updatedAt else { return }

        updateReminder(reminder, from: payload, eventTimestamp: event.timestamp)
    }

    private static func applyReminderDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let reminder = try findReminder(id: payload.id, context: context) else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > reminder.updatedAt else { return }

        reminder.isDeleted = true
        reminder.updatedAt = event.timestamp  // LWW: Use event timestamp
        reminder.syncState = .synced
        reminder.lastSyncedAt = Date()
    }

    private static func applyReminderSnoozed(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(ReminderEventPayload.self)
        guard let reminder = try findReminder(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !reminder.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard event.timestamp > reminder.updatedAt else { return }

        reminder.status = .snoozed
        reminder.remindAt = payload.remindAt
        reminder.updatedAt = event.timestamp  // LWW: Use event timestamp
        reminder.syncState = .synced
        reminder.lastSyncedAt = Date()
    }

    // MARK: - Helpers

    private static func findStack(id: String, context: ModelContext) throws -> Stack? {
        let predicate = #Predicate<Stack> { $0.id == id }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    private static func findTask(id: String, context: ModelContext) throws -> QueueTask? {
        let predicate = #Predicate<QueueTask> { $0.id == id }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    private static func findReminder(id: String, context: ModelContext) throws -> Reminder? {
        let predicate = #Predicate<Reminder> { $0.id == id }
        let descriptor = FetchDescriptor<Reminder>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    /// Updates stack fields from payload. Uses event timestamp for deterministic LWW.
    private static func updateStack(_ stack: Stack, from payload: StackEventPayload, eventTimestamp: Date) {
        stack.title = payload.title
        stack.stackDescription = payload.description
        stack.status = payload.status
        stack.priority = payload.priority
        stack.sortOrder = payload.sortOrder
        stack.isDraft = payload.isDraft
        stack.activeTaskId = payload.activeTaskId
        stack.updatedAt = eventTimestamp  // LWW: Use event timestamp for determinism
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    /// Updates task fields from payload. Uses event timestamp for deterministic LWW.
    private static func updateTask(
        _ task: QueueTask,
        from payload: TaskEventPayload,
        context: ModelContext,
        eventTimestamp: Date
    ) {
        task.title = payload.title
        task.taskDescription = payload.description
        task.status = payload.status
        task.priority = payload.priority
        task.sortOrder = payload.sortOrder
        task.updatedAt = eventTimestamp  // LWW: Use event timestamp for determinism
        task.syncState = .synced
        task.lastSyncedAt = Date()

        if let stackId = payload.stackId,
           task.stack?.id != stackId,
           let newStack = try? findStack(id: stackId, context: context) {
            task.stack = newStack
        }
    }

    /// Updates reminder fields from payload. Uses event timestamp for deterministic LWW.
    private static func updateReminder(_ reminder: Reminder, from payload: ReminderEventPayload, eventTimestamp: Date) {
        reminder.remindAt = payload.remindAt
        reminder.status = payload.status
        reminder.updatedAt = eventTimestamp  // LWW: Use event timestamp for determinism
        reminder.syncState = .synced
        reminder.lastSyncedAt = Date()
    }
}
