//
//  ProjectorService.swift
//  Dequeue
//
//  Applies incoming sync events to local SwiftData models
//

// swiftlint:disable file_length

import Foundation
import SwiftData

// MARK: - Thread-Safe Pending Tag Associations

/// Actor to safely manage pending tag-to-stack associations across concurrent sync operations.
/// Handles race condition where stack.updated arrives before tag.created.
actor PendingTagAssociationsActor {
    /// Stores pending tag-to-stack associations
    /// Key: tagId that hasn't been created yet
    /// Value: Set of stackIds waiting for that tag
    private var associations: [String: Set<String>] = [:]

    /// Adds a pending association between a tag and a stack
    func addPending(tagId: String, stackId: String) {
        associations[tagId, default: []].insert(stackId)
    }

    /// Resolves pending associations for a tag and returns the stack IDs
    /// Removes the tag from pending after resolution
    func resolvePending(tagId: String) -> Set<String> {
        defer { associations.removeValue(forKey: tagId) }
        return associations[tagId] ?? []
    }

    /// Clears all pending associations
    func clear() {
        associations.removeAll()
    }
}

// MARK: - Tag ID Remapping (DEQ-197)

/// Actor to manage mappings from duplicate tag IDs to canonical tag IDs.
/// When a cross-device duplicate tag is detected, we store a mapping so that
/// any future references to the duplicate ID are resolved to the canonical tag.
actor TagIdRemappingActor {
    /// Stores tag ID remappings
    /// Key: duplicate tag ID (from another device)
    /// Value: canonical tag ID (the one we kept)
    private var mappings: [String: String] = [:]

    /// Adds a mapping from a duplicate tag ID to the canonical tag ID
    func addMapping(from duplicateId: String, to canonicalId: String) {
        mappings[duplicateId] = canonicalId
    }

    /// Resolves a tag ID, returning the canonical ID if a mapping exists
    func resolve(_ tagId: String) -> String {
        mappings[tagId] ?? tagId
    }

    /// Resolves multiple tag IDs, returning canonical IDs where mappings exist
    func resolveAll(_ tagIds: [String]) -> [String] {
        tagIds.map { resolve($0) }
    }

    /// Clears all mappings
    func clear() {
        mappings.removeAll()
    }
}

// MARK: - Entity Lookup Cache (DEQ-143: N+1 Query Fix)

/// Cache for batch-prefetched entities to avoid N+1 queries during event processing.
/// Prefetch all needed entities once, then lookup by ID in O(1) time.
struct EntityLookupCache {
    var stacks: [String: Stack] = [:]
    var tasks: [String: QueueTask] = [:]
    var reminders: [String: Reminder] = [:]
    var tags: [String: Tag] = [:]
    var arcs: [String: Arc] = [:]
    var attachments: [String: Attachment] = [:]

    /// Creates an empty cache
    init() {}

    /// Creates a cache by batch-fetching all entities referenced by the given events
    init(prefetchingFor events: [Event], context: ModelContext) throws {
        // Extract all entity IDs from events using helper methods
        var collector = EntityIdCollector()
        for event in events {
            collector.collectIds(from: event)
        }

        // Batch fetch all entities
        if !collector.stackIds.isEmpty {
            stacks = try Self.batchFetchStacks(ids: collector.stackIds, context: context)
        }
        if !collector.taskIds.isEmpty {
            tasks = try Self.batchFetchTasks(ids: collector.taskIds, context: context)
        }
        if !collector.reminderIds.isEmpty {
            reminders = try Self.batchFetchReminders(ids: collector.reminderIds, context: context)
        }
        if !collector.tagIds.isEmpty {
            tags = try Self.batchFetchTags(ids: collector.tagIds, context: context)
        }
        if !collector.arcIds.isEmpty {
            arcs = try Self.batchFetchArcs(ids: collector.arcIds, context: context)
        }
        if !collector.attachmentIds.isEmpty {
            attachments = try Self.batchFetchAttachments(ids: collector.attachmentIds, context: context)
        }
    }

    /// Helper struct to collect entity IDs from events, reducing cyclomatic complexity
    private struct EntityIdCollector {
        var stackIds = Set<String>()
        var taskIds = Set<String>()
        var reminderIds = Set<String>()
        var tagIds = Set<String>()
        var arcIds = Set<String>()
        var attachmentIds = Set<String>()

        mutating func collectIds(from event: Event) {
            guard let eventType = event.eventType else { return }

            switch eventType {
            case .stackCreated, .stackUpdated, .stackDeleted, .stackDiscarded,
                 .stackCompleted, .stackActivated, .stackDeactivated, .stackClosed,
                 .stackReordered, .stackAssignedToArc, .stackRemovedFromArc:
                collectStackEventIds(from: event, eventType: eventType)

            case .taskCreated, .taskUpdated, .taskDeleted, .taskCompleted,
                 .taskActivated, .taskClosed, .taskReordered:
                collectTaskEventIds(from: event, eventType: eventType)

            case .reminderCreated, .reminderUpdated, .reminderSnoozed, .reminderDeleted:
                collectReminderEventIds(from: event, eventType: eventType)

            case .tagCreated, .tagUpdated, .tagDeleted:
                collectTagEventIds(from: event, eventType: eventType)

            case .arcCreated, .arcUpdated, .arcDeleted, .arcCompleted,
                 .arcActivated, .arcDeactivated, .arcPaused, .arcReordered:
                collectArcEventIds(from: event, eventType: eventType)

            case .attachmentAdded, .attachmentRemoved:
                collectAttachmentEventIds(from: event, eventType: eventType)

            case .deviceDiscovered:
                break  // Device events don't need prefetching
            }
        }

        private mutating func collectStackEventIds(from event: Event, eventType: EventType) {
            switch eventType {
            case .stackCreated, .stackUpdated:
                if let payload = try? event.decodePayload(StackEventPayload.self) {
                    stackIds.insert(payload.id)
                    tagIds.formUnion(payload.tagIds)
                }
            case .stackDeleted, .stackDiscarded, .stackCompleted, .stackActivated,
                 .stackDeactivated, .stackClosed:
                if let payload = try? event.decodePayload(EntityStatusPayload.self) {
                    stackIds.insert(payload.id)
                } else if let payload = try? event.decodePayload(EntityDeletedPayload.self) {
                    stackIds.insert(payload.id)
                }
            case .stackReordered:
                if let payload = try? event.decodePayload(ReorderPayload.self) {
                    stackIds.formUnion(payload.ids)
                }
            case .stackAssignedToArc, .stackRemovedFromArc:
                if let payload = try? event.decodePayload(StackArcAssignmentPayload.self) {
                    stackIds.insert(payload.stackId)
                    arcIds.insert(payload.arcId)
                }
            default:
                break
            }
        }

        private mutating func collectTaskEventIds(from event: Event, eventType: EventType) {
            switch eventType {
            case .taskCreated, .taskUpdated:
                if let payload = try? event.decodePayload(TaskEventPayload.self) {
                    taskIds.insert(payload.id)
                    if let stackId = payload.stackId {
                        stackIds.insert(stackId)
                    }
                }
            case .taskDeleted, .taskCompleted, .taskActivated, .taskClosed:
                if let payload = try? event.decodePayload(EntityStatusPayload.self) {
                    taskIds.insert(payload.id)
                } else if let payload = try? event.decodePayload(EntityDeletedPayload.self) {
                    taskIds.insert(payload.id)
                }
            case .taskReordered:
                if let payload = try? event.decodePayload(ReorderPayload.self) {
                    taskIds.formUnion(payload.ids)
                }
            default:
                break
            }
        }

        private mutating func collectReminderEventIds(from event: Event, eventType: EventType) {
            switch eventType {
            case .reminderCreated, .reminderUpdated, .reminderSnoozed:
                if let payload = try? event.decodePayload(ReminderEventPayload.self) {
                    reminderIds.insert(payload.id)
                    switch payload.parentType {
                    case .stack: stackIds.insert(payload.parentId)
                    case .task: taskIds.insert(payload.parentId)
                    case .arc: arcIds.insert(payload.parentId)
                    }
                }
            case .reminderDeleted:
                if let payload = try? event.decodePayload(EntityDeletedPayload.self) {
                    reminderIds.insert(payload.id)
                }
            default:
                break
            }
        }

        private mutating func collectTagEventIds(from event: Event, eventType: EventType) {
            switch eventType {
            case .tagCreated, .tagUpdated:
                if let payload = try? event.decodePayload(TagEventPayload.self) {
                    tagIds.insert(payload.id)
                }
            case .tagDeleted:
                if let payload = try? event.decodePayload(EntityDeletedPayload.self) {
                    tagIds.insert(payload.id)
                }
            default:
                break
            }
        }

        private mutating func collectArcEventIds(from event: Event, eventType: EventType) {
            switch eventType {
            case .arcCreated, .arcUpdated:
                if let payload = try? event.decodePayload(ArcEventPayload.self) {
                    arcIds.insert(payload.id)
                }
            case .arcDeleted, .arcCompleted, .arcActivated, .arcDeactivated, .arcPaused:
                if let payload = try? event.decodePayload(EntityStatusPayload.self) {
                    arcIds.insert(payload.id)
                } else if let payload = try? event.decodePayload(EntityDeletedPayload.self) {
                    arcIds.insert(payload.id)
                }
            case .arcReordered:
                if let payload = try? event.decodePayload(ReorderPayload.self) {
                    arcIds.formUnion(payload.ids)
                }
            default:
                break
            }
        }

        private mutating func collectAttachmentEventIds(from event: Event, eventType: EventType) {
            switch eventType {
            case .attachmentAdded:
                if let payload = try? event.decodePayload(AttachmentEventPayload.self) {
                    attachmentIds.insert(payload.id)
                }
            case .attachmentRemoved:
                if let payload = try? event.decodePayload(EntityDeletedPayload.self) {
                    attachmentIds.insert(payload.id)
                }
            default:
                break
            }
        }
    }

    // MARK: - Batch Fetch Methods
    //
    // DEQ-143: These methods fetch only the needed entities using predicates.
    // SwiftData's #Predicate supports `contains()` for IN-style queries.
    // This ensures O(n) database work where n = number of requested IDs,
    // rather than O(N) where N = total entities in database.

    private static func batchFetchStacks(ids: Set<String>, context: ModelContext) throws -> [String: Stack] {
        guard !ids.isEmpty else { return [:] }
        let idArray = Array(ids)
        let predicate = #Predicate<Stack> { stack in
            idArray.contains(stack.id)
        }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        let stacks = try context.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: stacks.map { ($0.id, $0) })
    }

    private static func batchFetchTasks(ids: Set<String>, context: ModelContext) throws -> [String: QueueTask] {
        guard !ids.isEmpty else { return [:] }
        let idArray = Array(ids)
        let predicate = #Predicate<QueueTask> { task in
            idArray.contains(task.id)
        }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
        let tasks = try context.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }

    private static func batchFetchReminders(ids: Set<String>, context: ModelContext) throws -> [String: Reminder] {
        guard !ids.isEmpty else { return [:] }
        let idArray = Array(ids)
        let predicate = #Predicate<Reminder> { reminder in
            idArray.contains(reminder.id)
        }
        let descriptor = FetchDescriptor<Reminder>(predicate: predicate)
        let reminders = try context.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })
    }

    private static func batchFetchTags(ids: Set<String>, context: ModelContext) throws -> [String: Tag] {
        guard !ids.isEmpty else { return [:] }
        let idArray = Array(ids)
        let predicate = #Predicate<Tag> { tag in
            idArray.contains(tag.id)
        }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        let tags = try context.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    }

    private static func batchFetchArcs(ids: Set<String>, context: ModelContext) throws -> [String: Arc] {
        guard !ids.isEmpty else { return [:] }
        let idArray = Array(ids)
        let predicate = #Predicate<Arc> { arc in
            idArray.contains(arc.id)
        }
        let descriptor = FetchDescriptor<Arc>(predicate: predicate)
        let arcs = try context.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: arcs.map { ($0.id, $0) })
    }

    private static func batchFetchAttachments(ids: Set<String>, context: ModelContext) throws -> [String: Attachment] {
        guard !ids.isEmpty else { return [:] }
        let idArray = Array(ids)
        let predicate = #Predicate<Attachment> { attachment in
            idArray.contains(attachment.id)
        }
        let descriptor = FetchDescriptor<Attachment>(predicate: predicate)
        let attachments = try context.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0) })
    }

    /// Refreshes the cache after an entity is inserted during batch processing.
    /// Call this when creating new entities so subsequent events can find them.
    mutating func insert(stack: Stack) {
        stacks[stack.id] = stack
    }

    mutating func insert(task: QueueTask) {
        tasks[task.id] = task
    }

    mutating func insert(reminder: Reminder) {
        reminders[reminder.id] = reminder
    }

    mutating func insert(tag: Tag) {
        tags[tag.id] = tag
    }

    mutating func insert(arc: Arc) {
        arcs[arc.id] = arc
    }

    mutating func insert(attachment: Attachment) {
        attachments[attachment.id] = attachment
    }
}

// swiftlint:disable:next type_body_length
enum ProjectorService {
    // MARK: - Pending Tag Associations

    /// Thread-safe actor for managing pending tag associations
    private static let pendingTagAssociations = PendingTagAssociationsActor()

    /// Thread-safe actor for managing tag ID remappings (DEQ-197: cross-device deduplication)
    private static let tagIdRemapping = TagIdRemappingActor()

    /// Clears all pending tag associations. Call at the start of a full sync to reset state.
    static func clearPendingTagAssociations() async {
        await pendingTagAssociations.clear()
        await tagIdRemapping.clear()
    }

    // MARK: - Batch Event Processing (DEQ-143)

    /// Applies multiple events efficiently using batch prefetching.
    /// This eliminates N+1 queries by prefetching all needed entities upfront.
    /// - Parameters:
    ///   - events: Array of events to process
    ///   - context: The SwiftData model context
    /// - Returns: Number of events successfully processed
    @discardableResult
    static func applyBatch(events: [Event], context: ModelContext) async throws -> Int {
        guard !events.isEmpty else { return 0 }

        logBatchStart(events: events)
        var cache = try EntityLookupCache(prefetchingFor: events, context: context)
        logCacheStats(cache: cache)

        var processedCount = 0
        var failedEvents: [(event: Event, error: Error)] = []

        for event in events {
            do {
                try await apply(event: event, context: context, cache: &cache)
                processedCount += 1
            } catch {
                failedEvents.append((event, error))
                logEventFailure(event: event, error: error, processedCount: processedCount, totalEvents: events.count)
            }
        }

        if !failedEvents.isEmpty {
            logBatchComplete(totalEvents: events.count, processedCount: processedCount, failedEvents: failedEvents)
        }

        return processedCount
    }

    // MARK: - Batch Logging Helpers

    private static func logBatchStart(events: [Event]) {
        ErrorReportingService.addBreadcrumb(
            category: "sync_batch",
            message: "Starting batch processing",
            data: [
                "event_count": events.count,
                "event_types": Dictionary(grouping: events, by: { $0.type }).mapValues { $0.count }.description
            ]
        )
    }

    private static func logCacheStats(cache: EntityLookupCache) {
        ErrorReportingService.addBreadcrumb(
            category: "sync_batch_cache",
            message: "Entity cache prefetched",
            data: [
                "stacks_cached": cache.stacks.count,
                "tasks_cached": cache.tasks.count,
                "reminders_cached": cache.reminders.count,
                "tags_cached": cache.tags.count,
                "arcs_cached": cache.arcs.count,
                "attachments_cached": cache.attachments.count
            ]
        )
    }

    private static func logEventFailure(event: Event, error: Error, processedCount: Int, totalEvents: Int) {
        ErrorReportingService.addBreadcrumb(
            category: "sync_batch_error",
            message: "Failed to apply event in batch",
            data: [
                "event_type": event.type,
                "event_id": event.id,
                "entity_id": event.entityId ?? "unknown",
                "error": error.localizedDescription,
                "error_type": String(describing: type(of: error)),
                "processed_so_far": processedCount,
                "remaining": totalEvents - processedCount - 1
            ]
        )
    }

    private static func logBatchComplete(
        totalEvents: Int,
        processedCount: Int,
        failedEvents: [(event: Event, error: Error)]
    ) {
        ErrorReportingService.addBreadcrumb(
            category: "sync_batch_complete",
            message: "Batch processing completed with errors",
            data: [
                "total_events": totalEvents,
                "processed_count": processedCount,
                "failed_count": failedEvents.count,
                "failed_types": failedEvents.map { $0.event.type }.joined(separator: ",")
            ]
        )
    }

    // MARK: - Single Event Processing

    /// Applies a single event (backward compatible - performs individual queries)
    static func apply(event: Event, context: ModelContext) async throws {
        // Create empty cache - will fall back to individual queries
        var cache = EntityLookupCache()
        try await apply(event: event, context: context, cache: &cache)
    }

    /// Internal apply with cache support - dispatches to category-specific handlers
    private static func apply(event: Event, context: ModelContext, cache: inout EntityLookupCache) async throws {
        guard let eventType = event.eventType else { return }

        // DEQ-236: Update device lastSeenAt for ALL events from other devices
        // This ensures "last seen" reflects actual device activity, not just foreground events
        try updateDeviceLastSeenFromEvent(event: event, context: context)

        switch eventType {
        // Stack events
        case .stackCreated, .stackUpdated, .stackDeleted, .stackDiscarded,
             .stackCompleted, .stackActivated, .stackDeactivated, .stackClosed, .stackReordered:
            try await applyStackEvent(event: event, eventType: eventType, context: context, cache: &cache)

        // Task events
        case .taskCreated, .taskUpdated, .taskDeleted, .taskCompleted,
             .taskActivated, .taskClosed, .taskReordered:
            try applyTaskEvent(event: event, eventType: eventType, context: context, cache: &cache)

        // Reminder events
        case .reminderCreated, .reminderUpdated, .reminderDeleted, .reminderSnoozed:
            try applyReminderEvent(event: event, eventType: eventType, context: context, cache: &cache)

        // Device events
        case .deviceDiscovered:
            try applyDeviceDiscovered(event: event, context: context)

        // Tag events
        case .tagCreated, .tagUpdated, .tagDeleted:
            try await applyTagEvent(event: event, eventType: eventType, context: context, cache: &cache)

        // Attachment events
        case .attachmentAdded, .attachmentRemoved:
            try applyAttachmentEvent(event: event, eventType: eventType, context: context, cache: &cache)

        // Arc events (including stack-arc assignments)
        case .arcCreated, .arcUpdated, .arcDeleted, .arcCompleted,
             .arcActivated, .arcDeactivated, .arcPaused, .arcReordered,
             .stackAssignedToArc, .stackRemovedFromArc:
            try applyArcEvent(event: event, eventType: eventType, context: context, cache: &cache)
        }
    }

    // MARK: - Category Event Dispatchers

    private static func applyStackEvent(
        event: Event,
        eventType: EventType,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) async throws {
        switch eventType {
        case .stackCreated:
            try await applyStackCreated(event: event, context: context, cache: &cache)
        case .stackUpdated:
            try await applyStackUpdated(event: event, context: context, cache: &cache)
        case .stackDeleted:
            try applyStackDeleted(event: event, context: context, cache: cache)
        case .stackDiscarded:
            try applyStackDiscarded(event: event, context: context, cache: cache)
        case .stackCompleted:
            try applyStackCompleted(event: event, context: context, cache: cache)
        case .stackActivated:
            try applyStackActivated(event: event, context: context, cache: cache)
        case .stackDeactivated:
            try applyStackDeactivated(event: event, context: context, cache: cache)
        case .stackClosed:
            try applyStackClosed(event: event, context: context, cache: cache)
        case .stackReordered:
            try applyStackReordered(event: event, context: context, cache: cache)
        default:
            break
        }
    }

    private static func applyTaskEvent(
        event: Event,
        eventType: EventType,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) throws {
        switch eventType {
        case .taskCreated:
            try applyTaskCreated(event: event, context: context, cache: &cache)
        case .taskUpdated:
            try applyTaskUpdated(event: event, context: context, cache: cache)
        case .taskDeleted:
            try applyTaskDeleted(event: event, context: context, cache: cache)
        case .taskCompleted:
            try applyTaskCompleted(event: event, context: context, cache: cache)
        case .taskActivated:
            try applyTaskActivated(event: event, context: context, cache: cache)
        case .taskClosed:
            try applyTaskClosed(event: event, context: context, cache: cache)
        case .taskReordered:
            try applyTaskReordered(event: event, context: context, cache: cache)
        default:
            break
        }
    }

    private static func applyReminderEvent(
        event: Event,
        eventType: EventType,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) throws {
        switch eventType {
        case .reminderCreated:
            try applyReminderCreated(event: event, context: context, cache: &cache)
        case .reminderUpdated:
            try applyReminderUpdated(event: event, context: context, cache: cache)
        case .reminderDeleted:
            try applyReminderDeleted(event: event, context: context, cache: cache)
        case .reminderSnoozed:
            try applyReminderSnoozed(event: event, context: context, cache: cache)
        default:
            break
        }
    }

    private static func applyTagEvent(
        event: Event,
        eventType: EventType,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) async throws {
        switch eventType {
        case .tagCreated:
            try await applyTagCreated(event: event, context: context, cache: &cache)
        case .tagUpdated:
            try applyTagUpdated(event: event, context: context, cache: cache)
        case .tagDeleted:
            try applyTagDeleted(event: event, context: context, cache: cache)
        default:
            break
        }
    }

    private static func applyAttachmentEvent(
        event: Event,
        eventType: EventType,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) throws {
        switch eventType {
        case .attachmentAdded:
            try applyAttachmentAdded(event: event, context: context, cache: &cache)
        case .attachmentRemoved:
            try applyAttachmentRemoved(event: event, context: context, cache: cache)
        default:
            break
        }
    }

    private static func applyArcEvent(
        event: Event,
        eventType: EventType,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) throws {
        switch eventType {
        case .arcCreated:
            try applyArcCreated(event: event, context: context, cache: &cache)
        case .arcUpdated:
            try applyArcUpdated(event: event, context: context, cache: cache)
        case .arcDeleted:
            try applyArcDeleted(event: event, context: context, cache: cache)
        case .arcCompleted:
            try applyArcCompleted(event: event, context: context, cache: cache)
        case .arcActivated:
            try applyArcActivated(event: event, context: context, cache: cache)
        case .arcDeactivated:
            try applyArcDeactivated(event: event, context: context, cache: cache)
        case .arcPaused:
            try applyArcPaused(event: event, context: context, cache: cache)
        case .arcReordered:
            try applyArcReordered(event: event, context: context, cache: cache)
        case .stackAssignedToArc:
            try applyStackAssignedToArc(event: event, context: context, cache: cache)
        case .stackRemovedFromArc:
            try applyStackRemovedFromArc(event: event, context: context, cache: cache)
        default:
            break
        }
    }

    // MARK: - Device Events

    /// DEQ-236: Updates device lastSeenAt whenever we process any event from that device.
    /// This ensures other devices see accurate "last seen" timestamps reflecting actual activity,
    /// not just when the device.discovered event fired (which only happens on foreground).
    ///
    /// - Parameters:
    ///   - event: The event being processed (contains deviceId of originating device)
    ///   - context: The model context for database operations
    private static func updateDeviceLastSeenFromEvent(event: Event, context: ModelContext) throws {
        let eventDeviceId = event.deviceId

        // Skip if this is the current device - we track our own activity locally
        // (ensureCurrentDeviceDiscovered and updateDeviceActivity handle the current device)
        // Note: We can't easily check isCurrentDevice here without async, so we rely on
        // the fact that we only receive sync events from OTHER devices anyway.

        // Find device by deviceId
        let predicate = #Predicate<Device> { device in
            device.deviceId == eventDeviceId && device.isDeleted == false
        }
        let descriptor = FetchDescriptor<Device>(predicate: predicate)
        guard let device = try context.fetch(descriptor).first else {
            // Device not yet known - will be created when device.discovered event is processed
            return
        }

        // Only update if this event is newer than the current lastSeenAt
        // This handles out-of-order event processing
        if event.timestamp > device.lastSeenAt {
            device.lastSeenAt = event.timestamp
            // Don't change syncState - this is a local-only update based on received events
        }
    }

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

    private static func applyStackCreated(
        event: Event,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) async throws {
        let payload = try event.decodePayload(StackEventPayload.self)

        if let existing = try findStack(id: payload.id, context: context, cache: cache) {
            // LWW: Only update if this event is newer than current state
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: existing.updatedAt,
                entityType: .stack,
                entityId: payload.id,
                conflictType: .update,
                context: context
            ) else { return }
            await updateStack(existing, from: payload, context: context, cache: cache, eventTimestamp: event.timestamp)
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
            // Use original createdAt from payload if available, otherwise fall back to event timestamp
            stack.createdAt = payload.createdAt ?? event.timestamp
            stack.updatedAt = event.timestamp  // LWW: Use event timestamp
            context.insert(stack)
            cache.insert(stack: stack)  // DEQ-143: Update cache for subsequent events

            // Apply tagIds - find and link tags, with proper error handling for race conditions
            await applyTagsToStack(stack, tagIds: payload.tagIds, context: context, cache: cache)
        }
    }

    private static func applyStackUpdated(
        event: Event,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) async throws {
        let payload = try event.decodePayload(StackEventPayload.self)
        guard let stack = try findStack(id: payload.id, context: context, cache: cache) else { return }

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

        await updateStack(stack, from: payload, context: context, cache: cache, eventTimestamp: event.timestamp)
    }

    private static func applyStackDeleted(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let stack = try findStack(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyStackDiscarded(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let stack = try findStack(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyStackCompleted(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyStackActivated(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyStackDeactivated(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyStackClosed(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let stack = try findStack(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyStackReordered(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(ReorderPayload.self)
        for (index, id) in payload.ids.enumerated() {
            guard let stack = try findStack(id: id, context: context, cache: cache) else { continue }

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

    private static func applyTaskCreated(
        event: Event,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) throws {
        let payload = try event.decodePayload(TaskEventPayload.self)

        if let existing = try findTask(id: payload.id, context: context, cache: cache) {
            // LWW: Only update if this event is newer than current state
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: existing.updatedAt,
                entityType: .task,
                entityId: payload.id,
                conflictType: .update,
                context: context
            ) else { return }
            updateTask(existing, from: payload, context: context, cache: cache, eventTimestamp: event.timestamp)
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
            // Use original createdAt from payload if available, otherwise fall back to event timestamp
            task.createdAt = payload.createdAt ?? event.timestamp
            task.updatedAt = event.timestamp  // LWW: Use event timestamp

            if let stackId = payload.stackId,
               let stack = try findStack(id: stackId, context: context, cache: cache) {
                task.stack = stack
                stack.tasks.append(task)
            }

            context.insert(task)
            cache.insert(task: task)  // DEQ-143: Update cache for subsequent events
        }
    }

    private static func applyTaskUpdated(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(TaskEventPayload.self)
        guard let task = try findTask(id: payload.id, context: context, cache: cache) else { return }

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

        updateTask(task, from: payload, context: context, cache: cache, eventTimestamp: event.timestamp)
    }

    private static func applyTaskDeleted(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let task = try findTask(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyTaskCompleted(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let task = try findTask(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyTaskActivated(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let task = try findTask(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyTaskClosed(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let task = try findTask(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyTaskReordered(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(ReorderPayload.self)
        for (index, id) in payload.ids.enumerated() {
            guard let task = try findTask(id: id, context: context, cache: cache) else { continue }

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

    private static func applyReminderCreated(
        event: Event,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) throws {
        let payload = try event.decodePayload(ReminderEventPayload.self)

        if let existing = try findReminder(id: payload.id, context: context, cache: cache) {
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
            cache.insert(reminder: reminder)  // DEQ-143: Update cache for subsequent events

            switch payload.parentType {
            case .stack:
                if let stack = try findStack(id: payload.parentId, context: context, cache: cache) {
                    stack.reminders.append(reminder)
                }
            case .task:
                if let task = try findTask(id: payload.parentId, context: context, cache: cache) {
                    task.reminders.append(reminder)
                }
            case .arc:
                if let arc = try findArc(id: payload.parentId, context: context, cache: cache) {
                    arc.reminders.append(reminder)
                }
            }
        }
    }

    private static func applyReminderUpdated(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(ReminderEventPayload.self)
        guard let reminder = try findReminder(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyReminderDeleted(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let reminder = try findReminder(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyReminderSnoozed(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(ReminderEventPayload.self)
        guard let reminder = try findReminder(id: payload.id, context: context, cache: cache) else { return }

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

    // swiftlint:disable:next function_body_length
    private static func applyTagCreated(
        event: Event,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) async throws {
        let payload = try event.decodePayload(TagEventPayload.self)

        // First check if tag with same ID already exists
        if let existing = try findTag(id: payload.id, context: context, cache: cache) {
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
            return
        }

        // DEQ-235: Check if tag with same normalized name already exists (cross-device duplicate)
        let normalizedName = payload.name.lowercased().trimmingCharacters(in: .whitespaces)
        if let existingByName = try findTagByNormalizedName(normalizedName, context: context, cache: cache) {
            // Determine which tag is canonical using createdAt (older wins)
            // If timestamps are equal, use lexicographically smaller ID as tie-breaker
            let incomingCreatedAt = payload.createdAt ?? event.timestamp
            let existingCreatedAt = existingByName.createdAt

            let incomingIsCanonical: Bool
            if incomingCreatedAt != existingCreatedAt {
                incomingIsCanonical = incomingCreatedAt < existingCreatedAt
            } else {
                // Tie-breaker: smaller ID wins for deterministic ordering across devices
                incomingIsCanonical = payload.id < existingByName.id
            }

            if incomingIsCanonical {
                // Incoming tag is canonical - create it and migrate stacks from local duplicate
                await handleIncomingTagIsCanonical(
                    payload: payload,
                    eventTimestamp: event.timestamp,
                    localDuplicate: existingByName,
                    normalizedName: normalizedName,
                    context: context,
                    cache: cache
                )
            } else {
                // Local tag is canonical - don't create incoming, just set up mapping
                await handleLocalTagIsCanonical(
                    incomingId: payload.id,
                    canonicalTag: existingByName,
                    tagName: payload.name,
                    normalizedName: normalizedName,
                    context: context,
                    cache: cache
                )
            }
            return
        }

        // No duplicate - create the new tag
        let tag = Tag(
            id: payload.id,
            name: payload.name,
            colorHex: payload.colorHex,
            syncState: .synced,
            lastSyncedAt: Date()
        )
        // Use original createdAt from payload if available
        if let createdAt = payload.createdAt {
            tag.createdAt = createdAt
        }
        tag.updatedAt = event.timestamp  // LWW: Use event timestamp
        context.insert(tag)
        cache.insert(tag: tag)  // DEQ-143: Update cache for subsequent events

        // Resolve any pending associations for this tag
        // This handles the race condition where stack.updated arrived before tag.created
        let pendingStackIds = await pendingTagAssociations.resolvePending(tagId: payload.id)
        if !pendingStackIds.isEmpty {
            for stackId in pendingStackIds {
                if let stack = try? findStack(id: stackId, context: context, cache: cache), !stack.isDeleted {
                    if !stack.tagObjects.contains(where: { $0.id == tag.id }) {
                        stack.tagObjects.append(tag)
                    }
                }
            }
        }
    }

    /// Finds a tag by normalized name (case-insensitive).
    /// Used for detecting cross-device duplicate tags during sync.
    private static func findTagByNormalizedName(
        _ normalizedName: String,
        context: ModelContext,
        cache: EntityLookupCache? = nil
    ) throws -> Tag? {
        // Use cache if available
        if let cache = cache, !cache.tags.isEmpty {
            return cache.tags.values.first { tag in
                !tag.isDeleted && tag.name.lowercased().trimmingCharacters(in: .whitespaces) == normalizedName
            }
        }

        let predicate = #Predicate<Tag> { tag in
            tag.isDeleted == false
        }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        let allTags = try context.fetch(descriptor)

        return allTags.first { tag in
            tag.name.lowercased().trimmingCharacters(in: .whitespaces) == normalizedName
        }
    }

    /// DEQ-235: Handles case where incoming synced tag is the canonical one (older createdAt).
    // swiftlint:disable:next function_body_length
    /// Creates the incoming tag and migrates all stacks from the local duplicate to it.
    private static func handleIncomingTagIsCanonical(
        payload: TagEventPayload,
        eventTimestamp: Date,
        localDuplicate: Tag,
        normalizedName: String,
        context: ModelContext,
        cache: EntityLookupCache
    ) async {
        ErrorReportingService.addBreadcrumb(
            category: "sync_tag_dedupe",
            message: "Cross-device tag duplicate: incoming is canonical, replacing local",
            data: [
                "incoming_tag_id": payload.id,
                "local_duplicate_id": localDuplicate.id,
                "tag_name": payload.name,
                "normalized_name": normalizedName,
                "incoming_created_at": payload.createdAt?.ISO8601Format() ?? "unknown",
                "local_created_at": localDuplicate.createdAt.ISO8601Format()
            ]
        )

        // Create the canonical tag from incoming event
        let canonicalTag = Tag(
            id: payload.id,
            name: payload.name,
            colorHex: payload.colorHex ?? localDuplicate.colorHex,  // Preserve color if incoming doesn't have one
            syncState: .synced,
            lastSyncedAt: Date()
        )
        if let createdAt = payload.createdAt {
            canonicalTag.createdAt = createdAt
        }
        canonicalTag.updatedAt = eventTimestamp
        context.insert(canonicalTag)

        // Migrate all stacks from the local duplicate to the canonical tag
        let stacksToMigrate = localDuplicate.stacks.filter { !$0.isDeleted }
        for stack in stacksToMigrate {
            // Add the canonical tag if not already present
            if !stack.tagObjects.contains(where: { $0.id == canonicalTag.id }) {
                stack.tagObjects.append(canonicalTag)
            }
            // Remove the local duplicate
            stack.tagObjects.removeAll { $0.id == localDuplicate.id }
            stack.syncState = .pending
        }

        // Resolve pending associations for the incoming tag ID
        let pendingStackIds = await pendingTagAssociations.resolvePending(tagId: payload.id)
        for stackId in pendingStackIds {
            if let stack = try? findStack(id: stackId, context: context, cache: cache), !stack.isDeleted {
                if !stack.tagObjects.contains(where: { $0.id == canonicalTag.id }) {
                    stack.tagObjects.append(canonicalTag)
                }
            }
        }

        // Also resolve any pending associations that referenced the local duplicate ID
        let pendingForLocalId = await pendingTagAssociations.resolvePending(tagId: localDuplicate.id)
        for stackId in pendingForLocalId {
            if let stack = try? findStack(id: stackId, context: context, cache: cache), !stack.isDeleted {
                if !stack.tagObjects.contains(where: { $0.id == canonicalTag.id }) {
                    stack.tagObjects.append(canonicalTag)
                }
            }
        }

        // Soft-delete the local duplicate
        localDuplicate.isDeleted = true
        localDuplicate.updatedAt = Date()
        localDuplicate.syncState = .pending

        // Register mapping from local duplicate ID to canonical tag ID
        // This ensures any future references to the old local ID resolve correctly
        await tagIdRemapping.addMapping(from: localDuplicate.id, to: canonicalTag.id)
    }

    /// DEQ-235: Handles case where local tag is the canonical one (older createdAt).
    /// Keeps the local tag and sets up mapping from incoming ID.
    private static func handleLocalTagIsCanonical(
        incomingId: String,
        canonicalTag: Tag,
        tagName: String,
        normalizedName: String,
        context: ModelContext,
        cache: EntityLookupCache
    ) async {
        ErrorReportingService.addBreadcrumb(
            category: "sync_tag_dedupe",
            message: "Cross-device tag duplicate: local is canonical, keeping local",
            data: [
                "incoming_tag_id": incomingId,
                "canonical_tag_id": canonicalTag.id,
                "tag_name": tagName,
                "normalized_name": normalizedName,
                "local_created_at": canonicalTag.createdAt.ISO8601Format()
            ]
        )

        // Resolve pending associations for the incoming tag ID to the canonical tag
        let pendingStackIds = await pendingTagAssociations.resolvePending(tagId: incomingId)
        for stackId in pendingStackIds {
            if let stack = try? findStack(id: stackId, context: context, cache: cache), !stack.isDeleted {
                if !stack.tagObjects.contains(where: { $0.id == canonicalTag.id }) {
                    stack.tagObjects.append(canonicalTag)
                }
            }
        }

        // Register mapping so future references to the incoming ID redirect to canonical tag
        await tagIdRemapping.addMapping(from: incomingId, to: canonicalTag.id)
    }

    private static func applyTagUpdated(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(TagEventPayload.self)
        guard let tag = try findTag(id: payload.id, context: context, cache: cache) else { return }

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

    private static func applyTagDeleted(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let tag = try findTag(id: payload.id, context: context, cache: cache) else { return }

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

    // MARK: - Attachment Events

    private static func applyAttachmentAdded(
        event: Event,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) throws {
        let payload = try event.decodePayload(AttachmentEventPayload.self)

        // Check if attachment already exists
        if let existing = try findAttachment(id: payload.id, context: context, cache: cache) {
            // LWW: Skip updates to deleted entities
            guard !existing.isDeleted else { return }

            // LWW: Only update if this event is newer than current state
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: existing.updatedAt,
                entityType: .attachment,
                entityId: payload.id,
                conflictType: .update,
                context: context
            ) else { return }
            updateAttachment(existing, from: payload, eventTimestamp: event.timestamp)
        } else {
            // Create new attachment from sync event
            // This happens when another device uploads an attachment and we receive the event
            let attachment = Attachment(
                id: payload.id,
                parentId: payload.parentId,
                parentType: payload.parentType,
                filename: payload.filename,
                mimeType: payload.mimeType,
                sizeBytes: payload.sizeBytes,
                remoteUrl: payload.url,
                localPath: nil,  // No local file - will be downloaded on demand
                syncState: .synced,
                uploadState: payload.url != nil ? .completed : .pending,
                lastSyncedAt: Date()
            )
            // Use original createdAt from payload if available, otherwise fall back to event timestamp
            attachment.createdAt = payload.createdAt ?? event.timestamp
            attachment.updatedAt = event.timestamp  // LWW: Use event timestamp
            attachment.isDeleted = payload.deleted
            context.insert(attachment)
            cache.insert(attachment: attachment)  // DEQ-143: Update cache for subsequent events
        }
    }

    private static func applyAttachmentRemoved(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let attachment = try findAttachment(id: payload.id, context: context, cache: cache) else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: attachment.updatedAt,
            entityType: .attachment,
            entityId: payload.id,
            conflictType: .delete,
            context: context
        ) else { return }

        attachment.isDeleted = true
        attachment.updatedAt = event.timestamp  // LWW: Use event timestamp
        attachment.syncState = .synced
        attachment.lastSyncedAt = Date()
    }

    /// Updates attachment fields from payload. Uses event timestamp for deterministic LWW.
    private static func updateAttachment(
        _ attachment: Attachment,
        from payload: AttachmentEventPayload,
        eventTimestamp: Date
    ) {
        attachment.filename = payload.filename
        attachment.mimeType = payload.mimeType
        attachment.sizeBytes = payload.sizeBytes
        if let url = payload.url {
            attachment.remoteUrl = url
            attachment.uploadState = .completed
        }
        attachment.isDeleted = payload.deleted
        attachment.updatedAt = eventTimestamp  // LWW: Use event timestamp for determinism
        attachment.syncState = .synced
        attachment.lastSyncedAt = Date()
    }

    /// Finds an attachment by ID, using cache if available (O(1)), falling back to query (O(n)).
    private static func findAttachment(
        id: String,
        context: ModelContext,
        cache: EntityLookupCache? = nil
    ) throws -> Attachment? {
        if let cached = cache?.attachments[id] {
            return cached
        }
        let predicate = #Predicate<Attachment> { $0.id == id }
        let descriptor = FetchDescriptor<Attachment>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    // MARK: - Arc Events

    private static func applyArcCreated(
        event: Event,
        context: ModelContext,
        cache: inout EntityLookupCache
    ) throws {
        let payload = try event.decodePayload(ArcEventPayload.self)

        if let existing = try findArc(id: payload.id, context: context, cache: cache) {
            // LWW: Only update if this event is newer than current state
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: existing.updatedAt,
                entityType: .arc,
                entityId: payload.id,
                conflictType: .update,
                context: context
            ) else { return }
            updateArc(existing, from: payload, eventTimestamp: event.timestamp)
        } else {
            let arc = Arc(
                id: payload.id,
                title: payload.title,
                arcDescription: payload.description,
                status: payload.status,
                sortOrder: payload.sortOrder,
                colorHex: payload.colorHex,
                syncState: .synced,
                lastSyncedAt: Date()
            )
            arc.updatedAt = event.timestamp  // LWW: Use event timestamp
            context.insert(arc)
            cache.insert(arc: arc)  // DEQ-143: Update cache for subsequent events
        }
    }

    private static func applyArcUpdated(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(ArcEventPayload.self)
        guard let arc = try findArc(id: payload.id, context: context, cache: cache) else { return }

        // LWW: Skip updates to deleted entities
        guard !arc.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: arc.updatedAt,
            entityType: .arc,
            entityId: payload.id,
            conflictType: .update,
            context: context
        ) else { return }

        updateArc(arc, from: payload, eventTimestamp: event.timestamp)
    }

    private static func applyArcDeleted(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityDeletedPayload.self)
        guard let arc = try findArc(id: payload.id, context: context, cache: cache) else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: arc.updatedAt,
            entityType: .arc,
            entityId: payload.id,
            conflictType: .delete,
            context: context
        ) else { return }

        // Remove all stacks from this arc before marking as deleted
        for stack in arc.stacks {
            stack.arc = nil
            stack.arcId = nil
            stack.updatedAt = event.timestamp
            stack.syncState = .synced
            stack.lastSyncedAt = Date()
        }

        arc.isDeleted = true
        arc.updatedAt = event.timestamp  // LWW: Use event timestamp
        arc.syncState = .synced
        arc.lastSyncedAt = Date()
    }

    private static func applyArcCompleted(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let arc = try findArc(id: payload.id, context: context, cache: cache) else { return }

        // LWW: Skip updates to deleted entities
        guard !arc.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: arc.updatedAt,
            entityType: .arc,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

        arc.status = .completed
        arc.updatedAt = event.timestamp  // LWW: Use event timestamp
        arc.syncState = .synced
        arc.lastSyncedAt = Date()
    }

    private static func applyArcActivated(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let arc = try findArc(id: payload.id, context: context, cache: cache) else { return }

        // LWW: Skip updates to deleted entities
        guard !arc.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: arc.updatedAt,
            entityType: .arc,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

        arc.status = .active
        arc.updatedAt = event.timestamp  // LWW: Use event timestamp
        arc.syncState = .synced
        arc.lastSyncedAt = Date()
    }

    private static func applyArcDeactivated(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let arc = try findArc(id: payload.id, context: context, cache: cache) else { return }

        // LWW: Skip updates to deleted entities
        guard !arc.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: arc.updatedAt,
            entityType: .arc,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

        arc.status = .archived
        arc.updatedAt = event.timestamp  // LWW: Use event timestamp
        arc.syncState = .synced
        arc.lastSyncedAt = Date()
    }

    private static func applyArcPaused(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(EntityStatusPayload.self)
        guard let arc = try findArc(id: payload.id, context: context, cache: cache) else { return }

        // LWW: Skip updates to deleted entities
        guard !arc.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: arc.updatedAt,
            entityType: .arc,
            entityId: payload.id,
            conflictType: .statusChange,
            context: context
        ) else { return }

        arc.status = .paused
        arc.updatedAt = event.timestamp  // LWW: Use event timestamp
        arc.syncState = .synced
        arc.lastSyncedAt = Date()
    }

    private static func applyArcReordered(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(ReorderPayload.self)

        for (index, id) in payload.ids.enumerated() {
            guard let arc = try findArc(id: id, context: context, cache: cache) else { continue }

            // LWW: Skip updates to deleted entities
            guard !arc.isDeleted else { continue }

            // LWW: Only apply if this event is newer than current state (per entity)
            guard shouldApplyEvent(
                eventTimestamp: event.timestamp,
                localTimestamp: arc.updatedAt,
                entityType: .arc,
                entityId: id,
                conflictType: .reorder,
                context: context
            ) else { continue }

            arc.sortOrder = payload.sortOrders[index]
            arc.updatedAt = event.timestamp  // LWW: Use event timestamp
            arc.syncState = .synced
            arc.lastSyncedAt = Date()
        }
    }

    private static func applyStackAssignedToArc(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(StackArcAssignmentPayload.self)

        guard let stack = try findStack(id: payload.stackId, context: context, cache: cache) else { return }
        guard let arc = try findArc(id: payload.arcId, context: context, cache: cache) else { return }

        // LWW: Skip updates to deleted entities
        guard !stack.isDeleted && !arc.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: stack.updatedAt,
            entityType: .stack,
            entityId: payload.stackId,
            conflictType: .update,
            context: context
        ) else { return }

        stack.arc = arc
        stack.arcId = arc.id
        stack.updatedAt = event.timestamp  // LWW: Use event timestamp
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    private static func applyStackRemovedFromArc(event: Event, context: ModelContext, cache: EntityLookupCache) throws {
        let payload = try event.decodePayload(StackArcAssignmentPayload.self)

        guard let stack = try findStack(id: payload.stackId, context: context, cache: cache) else { return }

        // LWW: Skip updates to deleted entities
        guard !stack.isDeleted else { return }

        // LWW: Only apply if this event is newer than current state
        guard shouldApplyEvent(
            eventTimestamp: event.timestamp,
            localTimestamp: stack.updatedAt,
            entityType: .stack,
            entityId: payload.stackId,
            conflictType: .update,
            context: context
        ) else { return }

        stack.arc = nil
        stack.arcId = nil
        stack.updatedAt = event.timestamp  // LWW: Use event timestamp
        stack.syncState = .synced
        stack.lastSyncedAt = Date()
    }

    /// Updates arc fields from payload. Uses event timestamp for deterministic LWW.
    private static func updateArc(_ arc: Arc, from payload: ArcEventPayload, eventTimestamp: Date) {
        arc.title = payload.title
        arc.arcDescription = payload.description
        arc.status = payload.status
        arc.sortOrder = payload.sortOrder
        arc.colorHex = payload.colorHex
        arc.updatedAt = eventTimestamp  // LWW: Use event timestamp for determinism
        arc.syncState = .synced
        arc.lastSyncedAt = Date()
    }

    // MARK: - Helpers (DEQ-143: Cache-aware lookups)

    /// Finds a stack by ID, using cache if available (O(1)), falling back to query (O(n)).
    private static func findStack(id: String, context: ModelContext, cache: EntityLookupCache? = nil) throws -> Stack? {
        // Check cache first for O(1) lookup
        if let cached = cache?.stacks[id] {
            return cached
        }
        // Fall back to database query
        let predicate = #Predicate<Stack> { $0.id == id }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    /// Finds a task by ID, using cache if available (O(1)), falling back to query (O(n)).
    private static func findTask(
        id: String,
        context: ModelContext,
        cache: EntityLookupCache? = nil
    ) throws -> QueueTask? {
        if let cached = cache?.tasks[id] {
            return cached
        }
        let predicate = #Predicate<QueueTask> { $0.id == id }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    /// Finds a reminder by ID, using cache if available (O(1)), falling back to query (O(n)).
    private static func findReminder(
        id: String,
        context: ModelContext,
        cache: EntityLookupCache? = nil
    ) throws -> Reminder? {
        if let cached = cache?.reminders[id] {
            return cached
        }
        let predicate = #Predicate<Reminder> { $0.id == id }
        let descriptor = FetchDescriptor<Reminder>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    /// Finds a tag by ID, using cache if available (O(1)), falling back to query (O(n)).
    private static func findTag(id: String, context: ModelContext, cache: EntityLookupCache? = nil) throws -> Tag? {
        if let cached = cache?.tags[id] {
            return cached
        }
        let predicate = #Predicate<Tag> { $0.id == id }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    /// Finds an arc by ID, using cache if available (O(1)), falling back to query (O(n)).
    private static func findArc(id: String, context: ModelContext, cache: EntityLookupCache? = nil) throws -> Arc? {
        if let cached = cache?.arcs[id] {
            return cached
        }
        let predicate = #Predicate<Arc> { $0.id == id }
        let descriptor = FetchDescriptor<Arc>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    /// Result of attempting to find tags by IDs
    struct TagLookupResult {
        let foundTags: [Tag]
        let missingTagIds: [String]

        var hasMissingTags: Bool { !missingTagIds.isEmpty }
    }

    /// Finds tags by IDs, returning both found tags and any missing IDs.
    /// This handles the race condition where stack_updated arrives before tag_created events.
    /// Uses cache if available for O(1) lookups.
    private static func findTagsWithMissing(
        ids: [String],
        context: ModelContext,
        cache: EntityLookupCache? = nil
    ) throws -> TagLookupResult {
        guard !ids.isEmpty else {
            return TagLookupResult(foundTags: [], missingTagIds: [])
        }

        // Build lookup - prefer cache, fall back to fetch
        let tagLookup: [String: Tag]
        if let cache = cache, !cache.tags.isEmpty {
            tagLookup = cache.tags
        } else {
            let descriptor = FetchDescriptor<Tag>()
            let allTags = try context.fetch(descriptor)
            tagLookup = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
        }

        var foundTags: [Tag] = []
        var missingTagIds: [String] = []

        for id in ids {
            if let tag = tagLookup[id], !tag.isDeleted {
                foundTags.append(tag)
            } else {
                missingTagIds.append(id)
            }
        }

        return TagLookupResult(foundTags: foundTags, missingTagIds: missingTagIds)
    }

    /// Updates stack fields from payload. Uses event timestamp for deterministic LWW.
    private static func updateStack(
        _ stack: Stack,
        from payload: StackEventPayload,
        context: ModelContext,
        cache: EntityLookupCache,
        eventTimestamp: Date
    ) async {
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

        // Apply tagIds - find and link tags, with proper error handling for race conditions
        await applyTagsToStack(stack, tagIds: payload.tagIds, context: context, cache: cache)
    }

    /// Applies tags to a stack with proper handling for missing tags (race condition).
    /// This handles the case where stack_updated arrives before tag_created events.
    /// - Logs warnings for missing tags
    /// - Still applies tags that ARE found (partial success)
    /// - DEQ-197: Resolves tag IDs through remapping to handle cross-device duplicates
    private static func applyTagsToStack(
        _ stack: Stack,
        tagIds: [String],
        context: ModelContext,
        cache: EntityLookupCache
    ) async {
        guard !tagIds.isEmpty else {
            // Explicitly clear tags if payload has empty tagIds
            stack.tagObjects = []
            return
        }

        // DEQ-197: Resolve tag IDs through remapping (handles cross-device duplicates)
        let resolvedTagIds = await tagIdRemapping.resolveAll(tagIds)

        do {
            let result = try findTagsWithMissing(ids: resolvedTagIds, context: context, cache: cache)

            // Always apply found tags (partial success is better than nothing)
            stack.tagObjects = result.foundTags

            // Log warning for missing tags - this is critical for debugging sync issues
            if result.hasMissingTags {
                ErrorReportingService.addBreadcrumb(
                    category: "sync_tag_race",
                    message: "Missing tags during stack sync - race condition detected",
                    data: [
                        "stack_id": stack.id,
                        "stack_title": stack.title,
                        "expected_tag_count": resolvedTagIds.count,
                        "found_tag_count": result.foundTags.count,
                        "missing_tag_ids": result.missingTagIds.joined(separator: ",")
                    ]
                )

                // Log each missing tag individually for easier debugging
                for missingId in result.missingTagIds {
                    ErrorReportingService.addBreadcrumb(
                        category: "sync_tag_missing",
                        message: "Tag not found locally during stack sync",
                        data: [
                            "stack_id": stack.id,
                            "missing_tag_id": missingId
                        ]
                    )
                }

                // Store pending associations for resolution when the tag is created
                // This handles the race condition where stack.updated arrives before tag.created
                for missingId in result.missingTagIds {
                    await pendingTagAssociations.addPending(tagId: missingId, stackId: stack.id)
                }
            }
        } catch {
            // Log the error but don't fail the entire sync
            ErrorReportingService.addBreadcrumb(
                category: "sync_tag_error",
                message: "Failed to apply tags to stack",
                data: [
                    "stack_id": stack.id,
                    "error": error.localizedDescription,
                    "tag_ids": tagIds.joined(separator: ",")
                ]
            )
        }
    }

    /// Updates task fields from payload. Uses event timestamp for deterministic LWW.
    private static func updateTask(
        _ task: QueueTask,
        from payload: TaskEventPayload,
        context: ModelContext,
        cache: EntityLookupCache,
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
           let newStack = try? findStack(id: stackId, context: context, cache: cache) {
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
