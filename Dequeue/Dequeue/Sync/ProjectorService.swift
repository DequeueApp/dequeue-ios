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
    // swiftlint:disable:next cyclomatic_complexity function_body_length
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

        // Tag events
        case .tagCreated:
            try applyTagCreated(event: event, context: context)
        case .tagUpdated:
            try applyTagUpdated(event: event, context: context)
        case .tagDeleted:
            try applyTagDeleted(event: event, context: context)
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
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: existing.updatedAt,
                entityType: .stack,
                entityId: payload.id,
                conflictType: .update,
                context: context
            ) else { return }
            updateStack(existing, from: payload, context: context, eventTimestamp: event.timestamp)
        } else {
            let stack = Stack(
                id: payload.id,
                title: payload.title,
                stackDescription: payload.description,
                status: payload.status,
                priority: payload.priority,
                sortOrder: payload.sortOrder,
                isDraft: payload.isDraft,
                isActive: payload.isActive,
                activeTaskId: payload.activeTaskId,
                syncState: .synced,
                lastSyncedAt: Date()
            )
            stack.updatedAt = event.timestamp  // LWW: Use event timestamp
            context.insert(stack)

            // Apply tagIds - find and link the tags
            if let tags = try? findTags(ids: payload.tagIds, context: context) {
                stack.tagObjects = tags
            }
        }
    }

    private static func applyStackUpdated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(StackEventPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !stack.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: stack.updatedAt,
            entityType: .stack,
            entityId: payload.id,
            conflictType: .update,
            context: context
        ) else { return }

        updateStack(stack, from: payload, context: context, eventTimestamp: event.timestamp)
    }

    private static func applyStackDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: stack.updatedAt,
            entityType: .stack,
            entityId: payload.id,
            conflictType: .delete,
            context: context
        ) else { return }

        stack.isDeleted = true
        stack.isActive = false  // DEQ-136: Deleted stacks cannot be active
        stack.updatedAt = event.timestamp  // LWW: Use event timestamp
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackDiscarded(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let stack = try findStack(id: payload.id, context: context) else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: stack.updatedAt,
            entityType: .stack,
            entityId: payload.id,
            conflictType: .delete,
            context: context
        ) else { return }

        // Discarded drafts are deleted
        stack.isDeleted = true
        stack.isActive = false  // DEQ-136: Deleted stacks cannot be active
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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: stack.updatedAt,
            entityType: .stack,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

        stack.status = .completed
        // A completed stack cannot be active - ensure this invariant holds even if
        // the stackDeactivated event was rejected by LWW due to timestamp ordering
        stack.isActive = false
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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: stack.updatedAt,
            entityType: .stack,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

        // DEQ-136: Enforce single active stack constraint
        // Deactivate all other stacks before activating this one to ensure invariant holds.
        // Event ordering: The LWW check above (shouldApplyEvent) ensures we only apply events
        // newer than current state, preventing out-of-order activation from corrupting state.
        // We update updatedAt on implicitly-deactivated stacks to ensure proper LWW resolution
        // across devices - they need to know when deactivation occurred for sync consistency.
        let stackId = payload.id
        let predicate = #Predicate<Stack> { $0.isActive == true && $0.id != stackId }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let otherActiveStacks = try context.fetch(descriptor)
        for otherStack in otherActiveStacks {
            otherStack.isActive = false
            otherStack.updatedAt = event.timestamp  // LWW: Sync timestamp for implicit deactivation
        }

        // Set as the active stack (isActive is the "active stack" indicator, not workflow status)
        stack.isActive = true
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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: stack.updatedAt,
            entityType: .stack,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

        // Remove active stack designation (isActive is the "active stack" indicator, not workflow status)
        stack.isActive = false
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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: stack.updatedAt,
            entityType: .stack,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

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
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: stack.updatedAt,
                entityType: .stack,
                entityId: id,
                conflictType: .reorder,
                context: context
            ) else { continue }

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
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: existing.updatedAt,
                entityType: .task,
                entityId: payload.id,
                conflictType: .update,
                context: context
            ) else { return }
            updateTask(existing, from: payload, context: context, eventTimestamp: event.timestamp)
        } else {
            let task = QueueTask(
                id: payload.id,
                title: payload.title,
                taskDescription: payload.description,
                status: payload.status,
                priority: payload.priority,
                sortOrder: payload.sortOrder,
                lastActiveTime: payload.lastActiveTime,
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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: task.updatedAt,
            entityType: .task,
            entityId: payload.id,
            conflictType: .update,
            context: context
        ) else { return }

        updateTask(task, from: payload, context: context, eventTimestamp: event.timestamp)
    }

    private static func applyTaskDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let task = try findTask(id: payload.id, context: context) else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: task.updatedAt,
            entityType: .task,
            entityId: payload.id,
            conflictType: .delete,
            context: context
        ) else { return }

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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: task.updatedAt,
            entityType: .task,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: task.updatedAt,
            entityType: .task,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

        task.status = .pending
        task.sortOrder = 0
        task.lastActiveTime = event.timestamp  // Track when task was activated
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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: task.updatedAt,
            entityType: .task,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

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
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: task.updatedAt,
                entityType: .task,
                entityId: id,
                conflictType: .reorder,
                context: context
            ) else { continue }

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
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: existing.updatedAt,
                entityType: .reminder,
                entityId: payload.id,
                conflictType: .update,
                context: context
            ) else { return }
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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: reminder.updatedAt,
            entityType: .reminder,
            entityId: payload.id,
            conflictType: .update,
            context: context
        ) else { return }

        updateReminder(reminder, from: payload, eventTimestamp: event.timestamp)
    }

    private static func applyReminderDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let reminder = try findReminder(id: payload.id, context: context) else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: reminder.updatedAt,
            entityType: .reminder,
            entityId: payload.id,
            conflictType: .delete,
            context: context
        ) else { return }

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
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: reminder.updatedAt,
            entityType: .reminder,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

        reminder.status = .snoozed
        reminder.remindAt = payload.remindAt
        reminder.updatedAt = event.timestamp  // LWW: Use event timestamp
        reminder.syncState = .synced
        reminder.lastSyncedAt = Date()
    }

    // MARK: - Tag Events

    private static func applyTagCreated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(TagEventPayload.self)

        if let existing = try findTag(id: payload.id, context: context) {
            // LWW: Only update if this event is newer than current state
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: existing.updatedAt,
                entityType: .tag,
                entityId: payload.id,
                conflictType: .update,
                context: context
            ) else { return }
            updateTag(existing, from: payload, eventTimestamp: event.timestamp)
        } else {
            let tag = Tag(
                id: payload.id,
                name: payload.name,
                colorHex: payload.colorHex,
                syncState: .synced,
                lastSyncedAt: Date()
            )
            tag.updatedAt = event.timestamp  // LWW: Use event timestamp
            context.insert(tag)
        }
    }

    private static func applyTagUpdated(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(TagEventPayload.self)
        guard let tag = try findTag(id: payload.id, context: context) else { return }

        // LWW: Skip updates to deleted entities
        guard !tag.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: tag.updatedAt,
            entityType: .tag,
            entityId: payload.id,
            conflictType: .update,
            context: context
        ) else { return }

        updateTag(tag, from: payload, eventTimestamp: event.timestamp)
    }

    private static func applyTagDeleted(event: Event, context: ModelContext) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let tag = try findTag(id: payload.id, context: context) else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: tag.updatedAt,
            entityType: .tag,
            entityId: payload.id,
            conflictType: .delete,
            context: context
        ) else { return }

        tag.isDeleted = true
        tag.updatedAt = event.timestamp  // LWW: Use event timestamp
        tag.syncState = .synced
        tag.lastSyncedAt = Date()
    }

    /// Updates tag fields from payload. Uses event timestamp for deterministic LWW.
    private static func updateTag(_ tag: Tag, from payload: TagEventPayload, eventTimestamp: Date) {
        tag.name = payload.name
        tag.colorHex = payload.colorHex
        tag.updatedAt = eventTimestamp  // LWW: Use event timestamp for determinism
        tag.syncState = .synced
        tag.lastSyncedAt = Date()
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

    private static func findTag(id: String, context: ModelContext) throws -> Tag? {
        let predicate = #Predicate<Tag> { $0.id == id }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    private static func findTags(ids: [String], context: ModelContext) throws -> [Tag] {
        let descriptor = FetchDescriptor<Tag>()
        let allTags = try context.fetch(descriptor)
        return allTags.filter { ids.contains($0.id) && !$0.isDeleted }
    }

    /// Updates stack fields from payload. Uses event timestamp for deterministic LWW.
    private static func updateStack(
        _ stack: Stack,
        from payload: StackEventPayload,
        context: ModelContext,
        eventTimestamp: Date
    ) {
        stack.title = payload.title
        stack.stackDescription = payload.description
        stack.status = payload.status
        stack.priority = payload.priority
        stack.sortOrder = payload.sortOrder
        stack.isDraft = payload.isDraft
        stack.isActive = payload.isActive
        stack.activeTaskId = payload.activeTaskId
        stack.updatedAt = eventTimestamp  // LWW: Use event timestamp for determinism
        stack.syncState = .synced
        stack.lastSyncedAt = Date()

        // Apply tagIds - find and link the tags
        if let tags = try? findTags(ids: payload.tagIds, context: context) {
            stack.tagObjects = tags
        }
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
        task.lastActiveTime = payload.lastActiveTime
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

    // MARK: - LWW Conflict Resolution

    /// Checks if event should be applied using LWW (Last-Write-Wins).
    /// Returns true if the event is newer and should be applied.
    /// If older, logs a conflict and returns false.
    private static func shouldApplyEvent(
        eventTimestamp: Date,
        localTimestamp: Date,
        entityType: SyncConflictEntityType,
        entityId: String,
        conflictType: SyncConflictType,
        context: ModelContext
    ) -> Bool {
        guard eventTimestamp > localTimestamp else {
            recordConflict(
                entityType: entityType,
                entityId: entityId,
                localTimestamp: localTimestamp,
                remoteTimestamp: eventTimestamp,
                conflictType: conflictType,
                context: context
            )
            return false
        }
        return true
    }

    /// Records a sync conflict when LWW resolution skips an incoming event
    private static func recordConflict(
        entityType: SyncConflictEntityType,
        entityId: String,
        localTimestamp: Date,
        remoteTimestamp: Date,
        conflictType: SyncConflictType,
        context: ModelContext
    ) {
        let conflict = SyncConflict(
            entityType: entityType,
            entityId: entityId,
            localTimestamp: localTimestamp,
            remoteTimestamp: remoteTimestamp,
            conflictType: conflictType,
            resolution: .keptLocal,  // LWW kept local because it was newer
            detectedAt: Date(),
            isResolved: true  // Auto-resolved by LWW
        )

        context.insert(conflict)

        // Log for debugging
        let timeDiff = abs(localTimestamp.timeIntervalSince(remoteTimestamp))
        ErrorReportingService.addBreadcrumb(
            category: "sync_conflict",
            message: "LWW conflict detected",
            data: [
                "entity_type": entityType.rawValue,
                "entity_id": entityId,
                "conflict_type": conflictType.rawValue,
                "time_diff_seconds": Int(timeDiff),
                "resolution": SyncConflictResolution.keptLocal.rawValue
            ]
        )
    }
}
