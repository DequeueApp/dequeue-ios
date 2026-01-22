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
import os

private let logger = Logger(subsystem: "com.dequeue", category: "EventService")

// MARK: - Event Context

/// Context required for creating events, capturing who/what created the event.
/// This ensures every event is properly attributed to a user, device, and app.
struct EventContext {
    let userId: String
    let deviceId: String
    let appId: String

    /// Creates context from the current authenticated user and device.
    /// - Parameters:
    ///   - userId: The authenticated user's ID (from AuthService.currentUserId)
    ///   - deviceId: The current device's ID (from DeviceService.getDeviceId())
    ///   - appId: The app bundle identifier (defaults to current app's bundle ID)
    init(userId: String, deviceId: String, appId: String = Bundle.main.bundleIdentifier ?? "com.dequeue.app") {
        self.userId = userId
        self.deviceId = deviceId
        self.appId = appId
    }
}

// swiftlint:disable type_body_length
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

    func recordStackCreated(_ stack: Stack) async throws {
        let payload = StackCreatedPayload(
            stackId: stack.id,
            state: StackState.from(stack)
        )
        try await recordEvent(type: .stackCreated, payload: payload, entityId: stack.id)
    }

    func recordStackUpdated(_ stack: Stack, changes: [String: Any] = [:]) async throws {
        logger.info("recordStackUpdated: stack.id='\(stack.id)', stack.title='\(stack.title)'")
        let state = StackState.from(stack)
        logger.info("recordStackUpdated: StackState.title='\(state.title)'")
        let payload = StackUpdatedPayload(
            stackId: stack.id,
            changes: changes,
            fullState: state
        )
        try await recordEvent(type: .stackUpdated, payload: payload, entityId: stack.id)
        logger.info("recordStackUpdated: event recorded with title='\(state.title)'")
    }

    func recordStackDeleted(_ stack: Stack) async throws {
        let payload = StackDeletedPayload(stackId: stack.id)
        try await recordEvent(type: .stackDeleted, payload: payload, entityId: stack.id)
    }

    func recordStackDiscarded(_ stack: Stack) async throws {
        let payload = StackDeletedPayload(stackId: stack.id)
        try await recordEvent(type: .stackDiscarded, payload: payload, entityId: stack.id)
    }

    func recordStackCompleted(_ stack: Stack) async throws {
        let payload = StackStatusPayload(
            stackId: stack.id,
            status: StackStatus.completed.rawValue,
            fullState: StackState.from(stack)
        )
        try await recordEvent(type: .stackCompleted, payload: payload, entityId: stack.id)
    }

    func recordStackActivated(_ stack: Stack) async throws {
        let payload = StackStatusPayload(
            stackId: stack.id,
            status: StackStatus.active.rawValue,
            fullState: StackState.from(stack)
        )
        try await recordEvent(type: .stackActivated, payload: payload, entityId: stack.id)
    }

    func recordStackDeactivated(_ stack: Stack) async throws {
        let payload = StackStatusPayload(
            stackId: stack.id,
            status: StackStatus.active.rawValue,  // Captures state before deactivation
            fullState: StackState.from(stack)
        )
        try await recordEvent(type: .stackDeactivated, payload: payload, entityId: stack.id)
    }

    func recordStackReordered(_ stacks: [Stack]) async throws {
        let payload = StackReorderedPayload(
            stackIds: stacks.map { $0.id },
            sortOrders: stacks.map { $0.sortOrder }
        )
        try await recordEvent(type: .stackReordered, payload: payload)
    }

    // MARK: - Task Events

    func recordTaskCreated(_ task: QueueTask) async throws {
        let payload = TaskCreatedPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            state: TaskState.from(task)
        )
        try await recordEvent(type: .taskCreated, payload: payload, entityId: task.id)
    }

    func recordTaskUpdated(_ task: QueueTask, changes: [String: Any] = [:]) async throws {
        let payload = TaskUpdatedPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            changes: changes,
            fullState: TaskState.from(task)
        )
        try await recordEvent(type: .taskUpdated, payload: payload, entityId: task.id)
    }

    func recordTaskDeleted(_ task: QueueTask) async throws {
        let payload = TaskDeletedPayload(taskId: task.id, stackId: task.stack?.id ?? "")
        try await recordEvent(type: .taskDeleted, payload: payload, entityId: task.id)
    }

    func recordTaskCompleted(_ task: QueueTask) async throws {
        let payload = TaskStatusPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            status: TaskStatus.completed.rawValue,
            fullState: TaskState.from(task)
        )
        try await recordEvent(type: .taskCompleted, payload: payload, entityId: task.id)
    }

    func recordTaskActivated(_ task: QueueTask) async throws {
        let payload = TaskStatusPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            status: TaskStatus.pending.rawValue,
            fullState: TaskState.from(task)
        )
        try await recordEvent(type: .taskActivated, payload: payload, entityId: task.id)
    }

    func recordTaskReordered(_ tasks: [QueueTask]) async throws {
        let payload = TaskReorderedPayload(
            taskIds: tasks.map { $0.id },
            sortOrders: tasks.map { $0.sortOrder }
        )
        try await recordEvent(type: .taskReordered, payload: payload)
    }

    // MARK: - Reminder Events

    func recordReminderCreated(_ reminder: Reminder) async throws {
        let payload = ReminderCreatedPayload(
            reminderId: reminder.id,
            parentId: reminder.parentId,
            parentType: reminder.parentType.rawValue,
            state: ReminderState.from(reminder)
        )
        try await recordEvent(type: .reminderCreated, payload: payload, entityId: reminder.id)
    }

    func recordReminderUpdated(_ reminder: Reminder) async throws {
        let payload = ReminderUpdatedPayload(
            reminderId: reminder.id,
            parentId: reminder.parentId,
            parentType: reminder.parentType.rawValue,
            fullState: ReminderState.from(reminder)
        )
        try await recordEvent(type: .reminderUpdated, payload: payload, entityId: reminder.id)
    }

    func recordReminderDeleted(_ reminder: Reminder) async throws {
        let payload = ReminderDeletedPayload(reminderId: reminder.id)
        try await recordEvent(type: .reminderDeleted, payload: payload, entityId: reminder.id)
    }

    func recordReminderSnoozed(_ reminder: Reminder) async throws {
        let payload = ReminderSnoozedPayload(
            reminderId: reminder.id,
            parentId: reminder.parentId,
            parentType: reminder.parentType.rawValue,
            snoozedFrom: reminder.snoozedFrom.map { Int64($0.timeIntervalSince1970 * 1_000) },
            snoozedUntil: Int64(reminder.remindAt.timeIntervalSince1970 * 1_000),
            fullState: ReminderState.from(reminder)
        )
        try await recordEvent(type: .reminderSnoozed, payload: payload, entityId: reminder.id)
    }

    // MARK: - Tag Events

    func recordTagCreated(_ tag: Tag) async throws {
        let payload = TagCreatedPayload(
            tagId: tag.id,
            state: TagState.from(tag)
        )
        try await recordEvent(type: .tagCreated, payload: payload, entityId: tag.id)
    }

    func recordTagUpdated(_ tag: Tag, changes: [String: Any] = [:]) async throws {
        let payload = TagUpdatedPayload(
            tagId: tag.id,
            changes: changes,
            fullState: TagState.from(tag)
        )
        try await recordEvent(type: .tagUpdated, payload: payload, entityId: tag.id)
    }

    func recordTagDeleted(_ tag: Tag) async throws {
        let payload = TagDeletedPayload(tagId: tag.id)
        try await recordEvent(type: .tagDeleted, payload: payload, entityId: tag.id)
    }

    // MARK: - Device Events

    func recordDeviceDiscovered(_ device: Device) async throws {
        let payload = DeviceDiscoveredPayload(
            deviceId: device.deviceId,
            state: DeviceState.from(device)
        )
        try await recordEvent(type: .deviceDiscovered, payload: payload, entityId: device.id)
    }

    // MARK: - Attachment Events

    func recordAttachmentAdded(_ attachment: Attachment) async throws {
        let payload = AttachmentAddedPayload(
            attachmentId: attachment.id,
            parentId: attachment.parentId,
            parentType: attachment.parentType.rawValue,
            state: AttachmentState.from(attachment)
        )
        try await recordEvent(type: .attachmentAdded, payload: payload, entityId: attachment.id)
    }

    func recordAttachmentRemoved(_ attachment: Attachment) async throws {
        let payload = AttachmentRemovedPayload(
            attachmentId: attachment.id,
            parentId: attachment.parentId,
            parentType: attachment.parentType.rawValue
        )
        try await recordEvent(type: .attachmentRemoved, payload: payload, entityId: attachment.id)
    }

    // MARK: - Arc Events

    func recordArcCreated(_ arc: Arc) async throws {
        let payload = ArcCreatedPayload(
            arcId: arc.id,
            state: ArcState.from(arc)
        )
        try await recordEvent(type: .arcCreated, payload: payload, entityId: arc.id)
    }

    func recordArcUpdated(_ arc: Arc, changes: [String: Any] = [:]) async throws {
        let payload = ArcUpdatedPayload(
            arcId: arc.id,
            changes: changes,
            fullState: ArcState.from(arc)
        )
        try await recordEvent(type: .arcUpdated, payload: payload, entityId: arc.id)
    }

    func recordArcDeleted(_ arc: Arc) async throws {
        let payload = ArcDeletedPayload(arcId: arc.id)
        try await recordEvent(type: .arcDeleted, payload: payload, entityId: arc.id)
    }

    func recordArcCompleted(_ arc: Arc) async throws {
        let payload = ArcStatusPayload(
            arcId: arc.id,
            status: ArcStatus.completed.rawValue,
            fullState: ArcState.from(arc)
        )
        try await recordEvent(type: .arcCompleted, payload: payload, entityId: arc.id)
    }

    func recordArcPaused(_ arc: Arc) async throws {
        let payload = ArcStatusPayload(
            arcId: arc.id,
            status: ArcStatus.paused.rawValue,
            fullState: ArcState.from(arc)
        )
        try await recordEvent(type: .arcPaused, payload: payload, entityId: arc.id)
    }

    func recordArcActivated(_ arc: Arc) async throws {
        let payload = ArcStatusPayload(
            arcId: arc.id,
            status: ArcStatus.active.rawValue,
            fullState: ArcState.from(arc)
        )
        try await recordEvent(type: .arcActivated, payload: payload, entityId: arc.id)
    }

    func recordArcDeactivated(_ arc: Arc) async throws {
        let payload = ArcStatusPayload(
            arcId: arc.id,
            status: ArcStatus.archived.rawValue,
            fullState: ArcState.from(arc)
        )
        try await recordEvent(type: .arcDeactivated, payload: payload, entityId: arc.id)
    }

    func recordArcReordered(_ arcs: [Arc]) async throws {
        let payload = ArcReorderedPayload(
            arcIds: arcs.map { $0.id },
            sortOrders: arcs.map { $0.sortOrder }
        )
        try await recordEvent(type: .arcReordered, payload: payload)
    }

    func recordStackAssignedToArc(stack: Stack, arc: Arc) async throws {
        let payload = StackArcAssignmentPayload(
            stackId: stack.id,
            arcId: arc.id
        )
        try await recordEvent(type: .stackAssignedToArc, payload: payload, entityId: stack.id)
    }

    func recordStackRemovedFromArc(stack: Stack, arcId: String) async throws {
        let payload = StackArcAssignmentPayload(
            stackId: stack.id,
            arcId: arcId
        )
        try await recordEvent(type: .stackRemovedFromArc, payload: payload, entityId: stack.id)
    }

    // MARK: - Query

    func fetchPendingEvents() throws -> [Event] {
        let predicate = #Predicate<Event> { event in
            event.isSynced == false && event.payloadVersion >= 2
        }
        let descriptor = FetchDescriptor<Event>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchEventsByIds(_ ids: [String]) throws -> [Event] {
        let predicate = #Predicate<Event> { event in
            ids.contains(event.id)
        }
        let descriptor = FetchDescriptor<Event>(predicate: predicate)
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

    /// Fetches all events related to a stack, including events for its tasks, reminders, and attachments
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

        // Convert to array for predicate (predicates work with arrays)
        let entityIdArray = Array(entityIds)

        // Fetch events by entityId using database predicate
        // Note: SwiftData predicates have limitations with optional contains,
        // so we use flatMap to unwrap and check, returning nil (false) for nil entityId
        let entityPredicate = #Predicate<Event> { event in
            event.entityId.flatMap { entityIdArray.contains($0) } ?? false
        }
        let entityDescriptor = FetchDescriptor<Event>(
            predicate: entityPredicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        var result = try modelContext.fetch(entityDescriptor)

        // Separately fetch attachment events (by type) and filter by parentId in memory
        // This is more efficient than fetching ALL events
        let attachmentPredicate = #Predicate<Event> { event in
            event.type == "attachment.added" || event.type == "attachment.removed"
        }
        let attachmentDescriptor = FetchDescriptor<Event>(
            predicate: attachmentPredicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let attachmentEvents = try modelContext.fetch(attachmentDescriptor)

        // Filter attachment events by parentId matching stack or task IDs
        let stackAndTaskIds = entityIds
        for event in attachmentEvents {
            if let payload = try? event.decodePayload(AttachmentEventPayload.self),
               stackAndTaskIds.contains(payload.parentId) {
                result.append(event)
            }
        }

        // Sort combined results by timestamp descending
        return result.sorted { $0.timestamp > $1.timestamp }
    }

    /// Fetches all events related to a task, including reminders and attachments
    func fetchTaskHistoryWithRelated(for task: QueueTask) throws -> [Event] {
        var entityIds: Set<String> = [task.id]

        // Add reminder IDs for this task
        for reminder in task.reminders {
            entityIds.insert(reminder.id)
        }

        // Convert to array for predicate
        let entityIdArray = Array(entityIds)

        // Fetch events by entityId using database predicate
        let entityPredicate = #Predicate<Event> { event in
            event.entityId.flatMap { entityIdArray.contains($0) } ?? false
        }
        let entityDescriptor = FetchDescriptor<Event>(
            predicate: entityPredicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        var result = try modelContext.fetch(entityDescriptor)

        // Separately fetch attachment events and filter by parentId
        let attachmentPredicate = #Predicate<Event> { event in
            event.type == "attachment.added" || event.type == "attachment.removed"
        }
        let attachmentDescriptor = FetchDescriptor<Event>(
            predicate: attachmentPredicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let attachmentEvents = try modelContext.fetch(attachmentDescriptor)

        // Filter attachment events by parentId matching task ID
        let taskId = task.id
        for event in attachmentEvents {
            if let payload = try? event.decodePayload(AttachmentEventPayload.self),
               payload.parentId == taskId {
                result.append(event)
            }
        }

        // Sort combined results by timestamp descending
        return result.sorted { $0.timestamp > $1.timestamp }
    }

    /// Fetches all events related to an arc and its direct children (stacks, reminders, attachments).
    /// Returns events sorted by timestamp (newest first).
    func fetchArcHistoryWithRelated(for arc: Arc) throws -> [Event] {
        // Collect all entity IDs we need to query
        var entityIds: Set<String> = [arc.id]

        // Add stack IDs (direct children)
        for stack in arc.stacks where !stack.isDeleted {
            entityIds.insert(stack.id)
        }

        // Add reminder IDs (arc reminders)
        for reminder in arc.reminders where !reminder.isDeleted {
            entityIds.insert(reminder.id)
        }

        // Add attachment IDs (arc attachments)
        // Query attachments by parentId since Arc doesn't have a direct relationship
        let arcId = arc.id
        let arcParentType = ParentType.arc.rawValue
        let attachmentDescriptor = FetchDescriptor<Attachment>(
            predicate: #Predicate<Attachment> { attachment in
                attachment.parentId == arcId &&
                attachment.parentTypeRawValue == arcParentType &&
                attachment.isDeleted == false
            }
        )
        let attachments = try modelContext.fetch(attachmentDescriptor)
        for attachment in attachments {
            entityIds.insert(attachment.id)
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
    ///
    /// JSON encoding is performed off the main thread to prevent UI blocking.
    /// The modelContext.insert() still happens on @MainActor as required by SwiftData.
    private func recordEvent<T: Encodable>(type: EventType, payload: T, entityId: String? = nil) async throws {
        // Encode JSON on main thread first (payload may not be Sendable due to [String: Any])
        // then the heavy work is already done. For truly large payloads, consider
        // converting to a Sendable representation first.
        let payloadData = try JSONEncoder().encode(payload)

        // Insert event on main thread (required by SwiftData @MainActor)
        let event = Event(
            eventType: type,
            payload: payloadData,
            entityId: entityId,
            userId: context.userId,
            deviceId: context.deviceId,
            appId: context.appId
        )
        modelContext.insert(event)
        // Note: Caller must call modelContext.save() to persist changes.
        // This allows batching multiple events into a single disk write.
    }
}
// swiftlint:enable type_body_length

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
    let tagIds: [String]

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
            activeTaskId: stack.activeTaskId,
            tagIds: stack.tagObjects.filter { !$0.isDeleted }.map { $0.id }
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

/// Full tag state snapshot - matches React Native TagState interface
struct TagState: Codable {
    let id: String
    let name: String
    let normalizedName: String
    let colorHex: String?
    let createdAt: Int64  // Unix timestamp in milliseconds
    let updatedAt: Int64
    let deleted: Bool

    static func from(_ tag: Tag) -> TagState {
        TagState(
            id: tag.id,
            name: tag.name,
            normalizedName: tag.normalizedName,
            colorHex: tag.colorHex,
            createdAt: Int64(tag.createdAt.timeIntervalSince1970 * 1_000),
            updatedAt: Int64(tag.updatedAt.timeIntervalSince1970 * 1_000),
            deleted: tag.isDeleted
        )
    }
}

/// Full attachment state snapshot - matches backend attachment event payload
struct AttachmentState: Codable {
    let id: String
    let parentId: String
    let parentType: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int64
    let url: String?
    let createdAt: Int64  // Unix timestamp in milliseconds
    let updatedAt: Int64
    let deleted: Bool

    static func from(_ attachment: Attachment) -> AttachmentState {
        AttachmentState(
            id: attachment.id,
            parentId: attachment.parentId,
            parentType: attachment.parentType.rawValue,
            filename: attachment.filename,
            mimeType: attachment.mimeType,
            sizeBytes: attachment.sizeBytes,
            url: attachment.remoteUrl,
            createdAt: Int64(attachment.createdAt.timeIntervalSince1970 * 1_000),
            updatedAt: Int64(attachment.updatedAt.timeIntervalSince1970 * 1_000),
            deleted: attachment.isDeleted
        )
    }
}

/// Full arc state snapshot - higher-level organizational container
struct ArcState: Codable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let sortOrder: Int
    let colorHex: String?
    let createdAt: Int64  // Unix timestamp in milliseconds
    let updatedAt: Int64
    let deleted: Bool
    let stackIds: [String]

    static func from(_ arc: Arc) -> ArcState {
        ArcState(
            id: arc.id,
            title: arc.title,
            description: arc.arcDescription,
            status: arc.status.rawValue,
            sortOrder: arc.sortOrder,
            colorHex: arc.colorHex,
            createdAt: Int64(arc.createdAt.timeIntervalSince1970 * 1_000),
            updatedAt: Int64(arc.updatedAt.timeIntervalSince1970 * 1_000),
            deleted: arc.isDeleted,
            stackIds: arc.stacks.filter { !$0.isDeleted }.map { $0.id }
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

// Tag payloads
struct TagCreatedPayload: Codable {
    let tagId: String
    let state: TagState
}

struct TagUpdatedPayload: Encodable {
    let tagId: String
    let changes: [String: Any]
    let fullState: TagState

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tagId, forKey: .tagId)
        try container.encode(fullState, forKey: .fullState)
        let changesData = try JSONSerialization.data(withJSONObject: changes)
        let changesDict = try JSONDecoder().decode([String: AnyCodable].self, from: changesData)
        try container.encode(changesDict, forKey: .changes)
    }

    enum CodingKeys: String, CodingKey {
        case tagId, changes, fullState
    }
}

struct TagDeletedPayload: Codable {
    let tagId: String
}

// Attachment payloads
struct AttachmentAddedPayload: Codable {
    let attachmentId: String
    let parentId: String
    let parentType: String
    let state: AttachmentState
}

struct AttachmentRemovedPayload: Codable {
    let attachmentId: String
    let parentId: String
    let parentType: String
}

// Arc payloads
struct ArcCreatedPayload: Codable {
    let arcId: String
    let state: ArcState
}

struct ArcUpdatedPayload: Encodable {
    let arcId: String
    let changes: [String: Any]
    let fullState: ArcState

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(arcId, forKey: .arcId)
        try container.encode(fullState, forKey: .fullState)
        let changesData = try JSONSerialization.data(withJSONObject: changes)
        let changesDict = try JSONDecoder().decode([String: AnyCodable].self, from: changesData)
        try container.encode(changesDict, forKey: .changes)
    }

    enum CodingKeys: String, CodingKey {
        case arcId, changes, fullState
    }
}

struct ArcDeletedPayload: Codable {
    let arcId: String
}

struct ArcStatusPayload: Codable {
    let arcId: String
    let status: String
    let fullState: ArcState
}

struct ArcReorderedPayload: Codable {
    let arcIds: [String]
    let sortOrders: [Int]
}

struct StackArcAssignmentPayload: Codable {
    let stackId: String
    let arcId: String
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
    let tagIds: [String]

    // Handle status as string from server
    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority, sortOrder, isDraft, isActive, activeTaskId, deleted, tagIds
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
        tagIds = try container.decodeIfPresent([String].self, forKey: .tagIds) ?? []
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
        try container.encode(tagIds, forKey: .tagIds)
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

/// Payload for reading tag events - extracts data from state object
struct TagEventPayload: Codable {
    let id: String
    let name: String
    let normalizedName: String
    let colorHex: String?
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, normalizedName, colorHex, deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        normalizedName = try container.decodeIfPresent(String.self, forKey: .normalizedName)
            ?? name.lowercased().trimmingCharacters(in: .whitespaces)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(normalizedName, forKey: .normalizedName)
        try container.encodeIfPresent(colorHex, forKey: .colorHex)
        try container.encode(deleted, forKey: .deleted)
    }
}

/// Payload for reading attachment events - extracts data from state object
struct AttachmentEventPayload: Codable {
    let id: String
    let parentId: String
    let parentType: ParentType
    let filename: String
    let mimeType: String
    let sizeBytes: Int64
    let url: String?
    let createdAt: Date?  // Original creation timestamp from sync
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, parentId, parentType, filename, mimeType, sizeBytes, url, createdAt, deleted
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

        filename = try container.decode(String.self, forKey: .filename)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        url = try container.decodeIfPresent(String.self, forKey: .url)

        // Decode createdAt - handle Int64 timestamp (milliseconds) or Date
        if let timestamp = try? container.decode(Int64.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: Double(timestamp) / 1_000.0)
        } else {
            createdAt = try? container.decode(Date.self, forKey: .createdAt)
        }

        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(parentId, forKey: .parentId)
        try container.encode(parentType.rawValue, forKey: .parentType)
        try container.encode(filename, forKey: .filename)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(url, forKey: .url)
        if let createdAt {
            try container.encode(Int64(createdAt.timeIntervalSince1970 * 1_000), forKey: .createdAt)
        }
        try container.encode(deleted, forKey: .deleted)
    }
}

/// Payload for reading arc events - extracts data from state object
struct ArcEventPayload: Codable {
    let id: String
    let title: String
    let description: String?
    let status: ArcStatus
    let sortOrder: Int
    let colorHex: String?
    let deleted: Bool
    let stackIds: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, sortOrder, colorHex, deleted, stackIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        // Decode status - try ArcStatus first, then String
        if let statusValue = try? container.decode(ArcStatus.self, forKey: .status) {
            status = statusValue
        } else {
            let statusString = try container.decode(String.self, forKey: .status)
            status = ArcStatus(rawValue: statusString) ?? .active
        }

        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        stackIds = try container.decodeIfPresent([String].self, forKey: .stackIds) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(colorHex, forKey: .colorHex)
        try container.encode(deleted, forKey: .deleted)
        try container.encode(stackIds, forKey: .stackIds)
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
        case tagId  // For tag.deleted
        case attachmentId  // For attachment.removed
        case arcId  // For arc.deleted
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
        } else if let tagId = try? container.decode(String.self, forKey: .tagId) {
            id = tagId
        } else if let attachmentId = try? container.decode(String.self, forKey: .attachmentId) {
            id = attachmentId
        } else if let arcId = try? container.decode(String.self, forKey: .arcId) {
            id = arcId
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
        case arcId    // For arc status events
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
        } else if let arcId = try? container.decode(String.self, forKey: .arcId) {
            id = arcId
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
        case arcIds    // For arc reorder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try different id array names
        if let stackIds = try? container.decode([String].self, forKey: .stackIds) {
            ids = stackIds
        } else if let taskIds = try? container.decode([String].self, forKey: .taskIds) {
            ids = taskIds
        } else if let arcIds = try? container.decode([String].self, forKey: .arcIds) {
            ids = arcIds
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
