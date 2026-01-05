//
//  EventService.swift
//  Dequeue
//
//  Records events for sync and audit trail
//  Payload format matches React Native stacks-app for full compatibility
//

// swiftlint:disable file_length

import Foundation
import SwiftData

// MARK: - Event Context

/// Context required for creating events, capturing who/what created the event.
/// This ensures every event is properly attributed to a user and device.
struct EventContext {
    let userId: String
    let deviceId: String

    /// Creates context from the current authenticated user and device.
    /// - Parameters:
    ///   - userId: The authenticated user's ID (from AuthService.currentUserId)
    ///   - deviceId: The current device's ID (from DeviceService.getDeviceId())
    init(userId: String, deviceId: String) {
        self.userId = userId
        self.deviceId = deviceId
    }
}

@MainActor
final class EventService {
    private let modelContext: ModelContext
    private let context: EventContext

    init(modelContext: ModelContext, context: EventContext) {
        self.modelContext = modelContext
        self.context = context
    }

    /// Convenience initializer that fetches context from shared services.
    /// Requires user to be authenticated (will use empty string if not).
    init(modelContext: ModelContext, userId: String, deviceId: String) {
        self.modelContext = modelContext
        self.context = EventContext(userId: userId, deviceId: deviceId)
    }

    /// Read-only initializer for query operations that don't create new events.
    /// Use this for fetching history, pending events, etc.
    /// - Important: Do NOT use this initializer if you intend to record new events.
    static func readOnly(modelContext: ModelContext) -> EventService {
        EventService(
            modelContext: modelContext,
            context: EventContext(userId: "", deviceId: "")
        )
    }

    // MARK: - Stack Events

    func recordStackCreated(_ stack: Stack) throws {
        let payload = StackCreatedPayload(
            stackId: stack.id,
            state: StackState.from(stack)
        )
        try recordEvent(type: .stackCreated, payload: payload, entityId: stack.id)
    }

    func recordStackUpdated(_ stack: Stack, changes: [String: Any] = [:]) throws {
        let payload = StackUpdatedPayload(
            stackId: stack.id,
            changes: changes,
            fullState: StackState.from(stack)
        )
        try recordEvent(type: .stackUpdated, payload: payload, entityId: stack.id)
    }

    func recordStackDeleted(_ stack: Stack) throws {
        let payload = StackDeletedPayload(stackId: stack.id)
        try recordEvent(type: .stackDeleted, payload: payload, entityId: stack.id)
    }

    func recordStackDiscarded(_ stack: Stack) throws {
        let payload = StackDeletedPayload(stackId: stack.id)
        try recordEvent(type: .stackDiscarded, payload: payload, entityId: stack.id)
    }

    func recordStackCompleted(_ stack: Stack) throws {
        let payload = StackStatusPayload(
            stackId: stack.id,
            status: StackStatus.completed.rawValue,
            fullState: StackState.from(stack)
        )
        try recordEvent(type: .stackCompleted, payload: payload, entityId: stack.id)
    }

    func recordStackActivated(_ stack: Stack) throws {
        let payload = StackStatusPayload(
            stackId: stack.id,
            status: StackStatus.active.rawValue,
            fullState: StackState.from(stack)
        )
        try recordEvent(type: .stackActivated, payload: payload, entityId: stack.id)
    }

    func recordStackDeactivated(_ stack: Stack) throws {
        let payload = StackStatusPayload(
            stackId: stack.id,
            status: StackStatus.active.rawValue,  // Captures state before deactivation
            fullState: StackState.from(stack)
        )
        try recordEvent(type: .stackDeactivated, payload: payload, entityId: stack.id)
    }

    func recordStackReordered(_ stacks: [Stack]) throws {
        let payload = StackReorderedPayload(
            stackIds: stacks.map { $0.id },
            sortOrders: stacks.map { $0.sortOrder }
        )
        try recordEvent(type: .stackReordered, payload: payload)
    }

    // MARK: - Task Events

    func recordTaskCreated(_ task: QueueTask) throws {
        let payload = TaskCreatedPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            state: TaskState.from(task)
        )
        try recordEvent(type: .taskCreated, payload: payload, entityId: task.id)
    }

    func recordTaskUpdated(_ task: QueueTask, changes: [String: Any] = [:]) throws {
        let payload = TaskUpdatedPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            changes: changes,
            fullState: TaskState.from(task)
        )
        try recordEvent(type: .taskUpdated, payload: payload, entityId: task.id)
    }

    func recordTaskDeleted(_ task: QueueTask) throws {
        let payload = TaskDeletedPayload(taskId: task.id, stackId: task.stack?.id ?? "")
        try recordEvent(type: .taskDeleted, payload: payload, entityId: task.id)
    }

    func recordTaskCompleted(_ task: QueueTask) throws {
        let payload = TaskStatusPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            status: TaskStatus.completed.rawValue,
            fullState: TaskState.from(task)
        )
        try recordEvent(type: .taskCompleted, payload: payload, entityId: task.id)
    }

    func recordTaskActivated(_ task: QueueTask) throws {
        let payload = TaskStatusPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            status: TaskStatus.pending.rawValue,
            fullState: TaskState.from(task)
        )
        try recordEvent(type: .taskActivated, payload: payload, entityId: task.id)
    }

    func recordTaskReordered(_ tasks: [QueueTask]) throws {
        let payload = TaskReorderedPayload(
            taskIds: tasks.map { $0.id },
            sortOrders: tasks.map { $0.sortOrder }
        )
        try recordEvent(type: .taskReordered, payload: payload)
    }

    // MARK: - Reminder Events

    func recordReminderCreated(_ reminder: Reminder) throws {
        let payload = ReminderCreatedPayload(
            reminderId: reminder.id,
            parentId: reminder.parentId,
            parentType: reminder.parentType.rawValue,
            state: ReminderState.from(reminder)
        )
        try recordEvent(type: .reminderCreated, payload: payload, entityId: reminder.id)
    }

    func recordReminderUpdated(_ reminder: Reminder) throws {
        let payload = ReminderUpdatedPayload(
            reminderId: reminder.id,
            parentId: reminder.parentId,
            parentType: reminder.parentType.rawValue,
            fullState: ReminderState.from(reminder)
        )
        try recordEvent(type: .reminderUpdated, payload: payload, entityId: reminder.id)
    }

    func recordReminderDeleted(_ reminder: Reminder) throws {
        let payload = ReminderDeletedPayload(reminderId: reminder.id)
        try recordEvent(type: .reminderDeleted, payload: payload, entityId: reminder.id)
    }

    func recordReminderSnoozed(_ reminder: Reminder) throws {
        let payload = ReminderSnoozedPayload(
            reminderId: reminder.id,
            parentId: reminder.parentId,
            parentType: reminder.parentType.rawValue,
            snoozedFrom: reminder.snoozedFrom.map { Int64($0.timeIntervalSince1970 * 1_000) },
            snoozedUntil: Int64(reminder.remindAt.timeIntervalSince1970 * 1_000),
            fullState: ReminderState.from(reminder)
        )
        try recordEvent(type: .reminderSnoozed, payload: payload, entityId: reminder.id)
    }

    // MARK: - Device Events

    func recordDeviceDiscovered(_ device: Device) throws {
        let payload = DeviceDiscoveredPayload(
            deviceId: device.deviceId,
            state: DeviceState.from(device)
        )
        try recordEvent(type: .deviceDiscovered, payload: payload, entityId: device.id)
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

    // MARK: - History Queries

    func fetchHistory(for entityId: String) throws -> [Event] {
        let predicate = #Predicate<Event> { event in
            event.entityId == entityId
        }
        let descriptor = FetchDescriptor<Event>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchHistoryReversed(for entityId: String) throws -> [Event] {
        let predicate = #Predicate<Event> { event in
            event.entityId == entityId
        }
        let descriptor = FetchDescriptor<Event>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches all events related to a stack, including events for its tasks and reminders
    func fetchStackHistoryWithRelated(for stack: Stack) throws -> [Event] {
        // Collect all entity IDs we need to query
        var entityIds: Set<String> = [stack.id]

        // Add task IDs
        for task in stack.tasks {
            entityIds.insert(task.id)
        }

        // Add reminder IDs (both stack reminders and task reminders)
        for reminder in stack.reminders {
            entityIds.insert(reminder.id)
        }

        // Fetch all events (SwiftData predicates don't support complex contains with optionals)
        // We'll filter in memory after fetching
        let descriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allEvents = try modelContext.fetch(descriptor)

        // Filter to only events for our entity IDs
        return allEvents.filter { event in
            guard let eventEntityId = event.entityId else { return false }
            return entityIds.contains(eventEntityId)
        }
    }

    // MARK: - Private

    /// Records an event without saving - caller is responsible for batching saves.
    /// This improves performance by avoiding multiple disk writes per operation.
    private func recordEvent<T: Encodable>(type: EventType, payload: T, entityId: String? = nil) throws {
        let payloadData = try JSONEncoder().encode(payload)
        let event = Event(
            eventType: type,
            payload: payloadData,
            entityId: entityId,
            userId: context.userId,
            deviceId: context.deviceId
        )
        modelContext.insert(event)
        // Note: Caller must call modelContext.save() to persist changes.
        // This allows batching multiple events into a single disk write.
    }
}

// MARK: - State Objects (match React Native StackState, TaskState, etc.)

/// Full stack state snapshot - matches React Native StackState interface
struct StackState: Codable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let priority: Int?
    let sortOrder: Int
    let createdAt: Int64  // Unix timestamp in milliseconds
    let updatedAt: Int64
    let deleted: Bool
    let isDraft: Bool
    let isActive: Bool
    let activeTaskId: String?

    static func from(_ stack: Stack) -> StackState {
        StackState(
            id: stack.id,
            title: stack.title,
            description: stack.stackDescription,
            status: stack.status.rawValue,
            priority: stack.priority,
            sortOrder: stack.sortOrder,
            createdAt: Int64(stack.createdAt.timeIntervalSince1970 * 1_000),
            updatedAt: Int64(stack.updatedAt.timeIntervalSince1970 * 1_000),
            deleted: stack.isDeleted,
            isDraft: stack.isDraft,
            isActive: stack.isActive,
            activeTaskId: stack.activeTaskId
        )
    }
}

/// Full task state snapshot - matches React Native TaskState interface
struct TaskState: Codable {
    let id: String
    let stackId: String
    let title: String
    let description: String?
    let status: String
    let priority: Int?
    let sortOrder: Int
    let lastActiveTime: Int64?
    let createdAt: Int64
    let updatedAt: Int64
    let deleted: Bool

    static func from(_ task: QueueTask) -> TaskState {
        TaskState(
            id: task.id,
            stackId: task.stack?.id ?? "",
            title: task.title,
            description: task.taskDescription,
            status: task.status.rawValue,
            priority: task.priority,
            sortOrder: task.sortOrder,
            lastActiveTime: task.lastActiveTime.map { Int64($0.timeIntervalSince1970 * 1_000) },
            createdAt: Int64(task.createdAt.timeIntervalSince1970 * 1_000),
            updatedAt: Int64(task.updatedAt.timeIntervalSince1970 * 1_000),
            deleted: task.isDeleted
        )
    }
}

/// Full reminder state snapshot - matches React Native ReminderState interface
struct ReminderState: Codable {
    let id: String
    let parentId: String
    let parentType: String
    let remindAt: Int64
    let status: String
    let createdAt: Int64
    let updatedAt: Int64
    let deleted: Bool

    static func from(_ reminder: Reminder) -> ReminderState {
        ReminderState(
            id: reminder.id,
            parentId: reminder.parentId,
            parentType: reminder.parentType.rawValue,
            remindAt: Int64(reminder.remindAt.timeIntervalSince1970 * 1_000),
            status: reminder.status.rawValue,
            createdAt: Int64(reminder.createdAt.timeIntervalSince1970 * 1_000),
            updatedAt: Int64(reminder.updatedAt.timeIntervalSince1970 * 1_000),
            deleted: reminder.isDeleted
        )
    }
}

/// Full device state snapshot - matches React Native DeviceState interface
struct DeviceState: Codable {
    let id: String
    let deviceId: String
    let name: String
    let model: String?
    let osName: String
    let osVersion: String?
    let isDevice: Bool
    let isCurrentDevice: Bool
    let lastSeenAt: Int64
    let firstSeenAt: Int64

    static func from(_ device: Device) -> DeviceState {
        DeviceState(
            id: device.id,
            deviceId: device.deviceId,
            name: device.name,
            model: device.model,
            osName: device.osName,
            osVersion: device.osVersion,
            isDevice: device.isDevice,
            isCurrentDevice: device.isCurrentDevice,
            lastSeenAt: Int64(device.lastSeenAt.timeIntervalSince1970 * 1_000),
            firstSeenAt: Int64(device.firstSeenAt.timeIntervalSince1970 * 1_000)
        )
    }
}

// MARK: - Event Payloads (match React Native EventService payload interfaces)

// Stack payloads
struct StackCreatedPayload: Codable {
    let stackId: String
    let state: StackState
}

struct StackUpdatedPayload: Encodable {
    let stackId: String
    let changes: [String: Any]
    let fullState: StackState

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stackId, forKey: .stackId)
        try container.encode(fullState, forKey: .fullState)
        // Encode changes as a dictionary
        let changesData = try JSONSerialization.data(withJSONObject: changes)
        let changesDict = try JSONDecoder().decode([String: AnyCodable].self, from: changesData)
        try container.encode(changesDict, forKey: .changes)
    }

    enum CodingKeys: String, CodingKey {
        case stackId, changes, fullState
    }
}

struct StackDeletedPayload: Codable {
    let stackId: String
}

struct StackStatusPayload: Codable {
    let stackId: String
    let status: String
    let fullState: StackState
}

struct StackReorderedPayload: Codable {
    let stackIds: [String]
    let sortOrders: [Int]
}

// Task payloads
struct TaskCreatedPayload: Codable {
    let taskId: String
    let stackId: String
    let state: TaskState
}

struct TaskUpdatedPayload: Encodable {
    let taskId: String
    let stackId: String
    let changes: [String: Any]
    let fullState: TaskState

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(stackId, forKey: .stackId)
        try container.encode(fullState, forKey: .fullState)
        let changesData = try JSONSerialization.data(withJSONObject: changes)
        let changesDict = try JSONDecoder().decode([String: AnyCodable].self, from: changesData)
        try container.encode(changesDict, forKey: .changes)
    }

    enum CodingKeys: String, CodingKey {
        case taskId, stackId, changes, fullState
    }
}

struct TaskDeletedPayload: Codable {
    let taskId: String
    let stackId: String
}

struct TaskStatusPayload: Codable {
    let taskId: String
    let stackId: String
    let status: String
    let fullState: TaskState
}

struct TaskReorderedPayload: Codable {
    let taskIds: [String]
    let sortOrders: [Int]
}

// Reminder payloads
struct ReminderCreatedPayload: Codable {
    let reminderId: String
    let parentId: String
    let parentType: String
    let state: ReminderState
}

struct ReminderUpdatedPayload: Codable {
    let reminderId: String
    let parentId: String
    let parentType: String
    let fullState: ReminderState
}

struct ReminderDeletedPayload: Codable {
    let reminderId: String
}

struct ReminderSnoozedPayload: Codable {
    let reminderId: String
    let parentId: String
    let parentType: String
    let snoozedFrom: Int64?
    let snoozedUntil: Int64
    let fullState: ReminderState
}

// Device payloads
struct DeviceDiscoveredPayload: Codable {
    let deviceId: String
    let state: DeviceState
}

// MARK: - Reading Payloads (for ProjectorService to decode incoming events)

/// Payload for reading device events - extracts data from state object
struct DeviceEventPayload: Codable {
    let id: String
    let deviceId: String
    let name: String
    let model: String?
    let osName: String
    let osVersion: String?
    let isDevice: Bool
    let isCurrentDevice: Bool
    let lastSeenAt: Int64
    let firstSeenAt: Int64
}

/// Payload for reading stack events - extracts data from state object
struct StackEventPayload: Codable {
    let id: String
    let title: String
    let description: String?
    let status: StackStatus
    let priority: Int?
    let sortOrder: Int
    let isDraft: Bool
    let isActive: Bool
    let activeTaskId: String?
    let deleted: Bool

    // Handle status as string from server
    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority, sortOrder, isDraft, isActive, activeTaskId, deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        // Decode status - try StackStatus first, then String
        if let statusValue = try? container.decode(StackStatus.self, forKey: .status) {
            status = statusValue
        } else {
            let statusString = try container.decode(String.self, forKey: .status)
            status = StackStatus(rawValue: statusString) ?? .active
        }

        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        activeTaskId = try container.decodeIfPresent(String.self, forKey: .activeTaskId)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status.rawValue, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(isDraft, forKey: .isDraft)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(activeTaskId, forKey: .activeTaskId)
        try container.encode(deleted, forKey: .deleted)
    }
}

/// Payload for reading task events - extracts data from state object
struct TaskEventPayload: Codable {
    let id: String
    let stackId: String?
    let title: String
    let description: String?
    let status: TaskStatus
    let priority: Int?
    let sortOrder: Int
    let lastActiveTime: Date?
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, stackId, title, description, status, priority, sortOrder, lastActiveTime, deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        stackId = try container.decodeIfPresent(String.self, forKey: .stackId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        // Decode status - try TaskStatus first, then String
        if let statusValue = try? container.decode(TaskStatus.self, forKey: .status) {
            status = statusValue
        } else {
            let statusString = try container.decode(String.self, forKey: .status)
            status = TaskStatus(rawValue: statusString) ?? .pending
        }

        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0

        // Decode lastActiveTime - handle both Int64 timestamp and Date
        if let timestamp = try container.decodeIfPresent(Int64.self, forKey: .lastActiveTime) {
            lastActiveTime = Date(timeIntervalSince1970: Double(timestamp) / 1_000.0)
        } else {
            lastActiveTime = try container.decodeIfPresent(Date.self, forKey: .lastActiveTime)
        }

        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(stackId, forKey: .stackId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status.rawValue, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encode(sortOrder, forKey: .sortOrder)
        if let lastActiveTime = lastActiveTime {
            try container.encode(Int64(lastActiveTime.timeIntervalSince1970 * 1_000), forKey: .lastActiveTime)
        }
        try container.encode(deleted, forKey: .deleted)
    }
}

/// Payload for reading reminder events - extracts data from state object
struct ReminderEventPayload: Codable {
    let id: String
    let parentId: String
    let parentType: ParentType
    let status: ReminderStatus
    let remindAt: Date
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, parentId, parentType, status, remindAt, deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        parentId = try container.decode(String.self, forKey: .parentId)

        // Decode parentType - try enum first, then String
        if let typeValue = try? container.decode(ParentType.self, forKey: .parentType) {
            parentType = typeValue
        } else {
            let typeString = try container.decode(String.self, forKey: .parentType)
            parentType = ParentType(rawValue: typeString) ?? .stack
        }

        // Decode status - try enum first, then String
        if let statusValue = try? container.decode(ReminderStatus.self, forKey: .status) {
            status = statusValue
        } else {
            let statusString = try container.decode(String.self, forKey: .status)
            status = ReminderStatus(rawValue: statusString) ?? .active
        }

        // Decode remindAt - handle both Int64 timestamp and Date
        if let timestamp = try? container.decode(Int64.self, forKey: .remindAt) {
            remindAt = Date(timeIntervalSince1970: Double(timestamp) / 1_000.0)
        } else {
            remindAt = try container.decode(Date.self, forKey: .remindAt)
        }

        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(parentId, forKey: .parentId)
        try container.encode(parentType.rawValue, forKey: .parentType)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(Int64(remindAt.timeIntervalSince1970 * 1_000), forKey: .remindAt)
        try container.encode(deleted, forKey: .deleted)
    }
}

/// Payload for entity deletion events
struct EntityDeletedPayload: Codable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id
        case stackId  // For stack.deleted
        case taskId   // For task.deleted
        case reminderId  // For reminder.deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try different id field names
        if let stackId = try? container.decode(String.self, forKey: .stackId) {
            id = stackId
        } else if let taskId = try? container.decode(String.self, forKey: .taskId) {
            id = taskId
        } else if let reminderId = try? container.decode(String.self, forKey: .reminderId) {
            id = reminderId
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }
}

/// Payload for entity status change events
struct EntityStatusPayload: Codable {
    let id: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case stackId  // For stack status events
        case taskId   // For task status events
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try different id field names
        // IMPORTANT: Check taskId BEFORE stackId because task events contain both,
        // and we need the task's ID, not the parent stack's ID (DEQ-139)
        if let taskId = try? container.decode(String.self, forKey: .taskId) {
            id = taskId
        } else if let stackId = try? container.decode(String.self, forKey: .stackId) {
            id = stackId
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
    }
}

/// Payload for reorder events
struct ReorderPayload: Codable {
    let ids: [String]
    let sortOrders: [Int]

    enum CodingKeys: String, CodingKey {
        case ids
        case sortOrders
        case stackIds  // For stack reorder
        case taskIds   // For task reorder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try different id array names
        if let stackIds = try? container.decode([String].self, forKey: .stackIds) {
            ids = stackIds
        } else if let taskIds = try? container.decode([String].self, forKey: .taskIds) {
            ids = taskIds
        } else {
            ids = try container.decode([String].self, forKey: .ids)
        }
        sortOrders = try container.decode([Int].self, forKey: .sortOrders)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ids, forKey: .ids)
        try container.encode(sortOrders, forKey: .sortOrders)
    }
}

// MARK: - Helper for encoding arbitrary dictionaries

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
