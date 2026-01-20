//
//  ArcService.swift
//  Dequeue
//
//  Service layer for Arc operations - higher-level organizational containers
//

import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.ardonos.dequeue", category: "ArcService")

/// Maximum number of active arcs allowed at any time
private let maxActiveArcs = 5

@MainActor
final class ArcService {
    private let modelContext: ModelContext
    private let eventService: EventService
    private let userId: String?
    private let deviceId: String
    private weak var syncManager: SyncManager?

    init(
        modelContext: ModelContext,
        userId: String? = nil,
        deviceId: String,
        syncManager: SyncManager? = nil
    ) {
        self.modelContext = modelContext
        self.userId = userId
        self.deviceId = deviceId
        self.eventService = EventService(modelContext: modelContext, userId: userId ?? "", deviceId: deviceId)
        self.syncManager = syncManager
    }

    // MARK: - Queries

    /// Fetches all non-deleted arcs sorted by sortOrder
    func fetchAll() throws -> [Arc] {
        let descriptor = FetchDescriptor<Arc>(
            predicate: #Predicate<Arc> { !$0.isDeleted },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches only active arcs (non-deleted, status = active)
    func fetchActive() throws -> [Arc] {
        let descriptor = FetchDescriptor<Arc>(
            predicate: #Predicate<Arc> { !$0.isDeleted && $0.statusRawValue == "active" },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetches an arc by ID
    func fetchById(_ id: String) throws -> Arc? {
        let descriptor = FetchDescriptor<Arc>(
            predicate: #Predicate<Arc> { $0.id == id && !$0.isDeleted }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Returns the count of active arcs
    func activeArcCount() throws -> Int {
        try fetchActive().count
    }

    /// Checks if a new arc can be created (< maxActiveArcs)
    func canCreateNewArc() throws -> Bool {
        try activeArcCount() < maxActiveArcs
    }

    // MARK: - CRUD Operations

    /// Creates a new arc
    /// - Throws: If the maximum number of active arcs would be exceeded
    @discardableResult
    func createArc(
        title: String,
        description: String? = nil,
        colorHex: String? = nil,
        status: ArcStatus = .active
    ) throws -> Arc {
        // Check constraint for active arcs
        if status == .active {
            guard try canCreateNewArc() else {
                throw ArcServiceError.maxActiveArcsExceeded(limit: maxActiveArcs)
            }
        }

        // Calculate next sort order
        let existingArcs = try fetchAll()
        let maxSortOrder = existingArcs.map(\.sortOrder).max() ?? -1
        let nextSortOrder = maxSortOrder + 1

        let arc = Arc(
            title: title,
            arcDescription: description,
            status: status,
            sortOrder: nextSortOrder,
            colorHex: colorHex,
            userId: userId,
            deviceId: deviceId,
            syncState: .pending
        )

        modelContext.insert(arc)
        try eventService.recordArcCreated(arc)
        try modelContext.save()

        logger.info("Created arc: \(arc.id) - \(title)")
        triggerSync()

        return arc
    }

    /// Updates an existing arc's basic properties
    func updateArc(
        _ arc: Arc,
        title: String? = nil,
        description: String? = nil,
        colorHex: String? = nil
    ) throws {
        var changes: [String: Any] = [:]

        if let title = title, title != arc.title {
            changes["title"] = ["from": arc.title, "to": title]
            arc.title = title
        }

        if let description = description, description != arc.arcDescription {
            changes["description"] = ["from": arc.arcDescription as Any, "to": description]
            arc.arcDescription = description
        }

        if let colorHex = colorHex, colorHex != arc.colorHex {
            changes["colorHex"] = ["from": arc.colorHex as Any, "to": colorHex]
            arc.colorHex = colorHex
        }

        guard !changes.isEmpty else { return }

        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try eventService.recordArcUpdated(arc, changes: changes)
        try modelContext.save()

        logger.info("Updated arc: \(arc.id)")
        triggerSync()
    }

    /// Soft-deletes an arc (sets isDeleted = true)
    func deleteArc(_ arc: Arc) throws {
        // Remove all stacks from this arc before deleting
        for stack in arc.stacks {
            stack.arc = nil
            stack.arcId = nil
            stack.updatedAt = Date()
            stack.syncState = .pending
            stack.revision += 1
        }

        arc.isDeleted = true
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try eventService.recordArcDeleted(arc)
        try modelContext.save()

        logger.info("Deleted arc: \(arc.id)")
        triggerSync()
    }

    // MARK: - Status Operations

    /// Marks an arc as completed
    func markAsCompleted(_ arc: Arc) throws {
        guard arc.status != .completed else { return }

        arc.status = .completed
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try eventService.recordArcCompleted(arc)
        try modelContext.save()

        logger.info("Completed arc: \(arc.id)")
        triggerSync()
    }

    /// Pauses an arc
    func pause(_ arc: Arc) throws {
        guard arc.status == .active else { return }

        arc.status = .paused
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try eventService.recordArcPaused(arc)
        try modelContext.save()

        logger.info("Paused arc: \(arc.id)")
        triggerSync()
    }

    /// Resumes a paused arc
    /// - Throws: If resuming would exceed the maximum active arcs
    func resume(_ arc: Arc) throws {
        guard arc.status == .paused else { return }

        // Check if we can have another active arc
        guard try canCreateNewArc() else {
            throw ArcServiceError.maxActiveArcsExceeded(limit: maxActiveArcs)
        }

        arc.status = .active
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try eventService.recordArcActivated(arc)
        try modelContext.save()

        logger.info("Resumed arc: \(arc.id)")
        triggerSync()
    }

    /// Archives an arc
    func archive(_ arc: Arc) throws {
        guard arc.status != .archived else { return }

        arc.status = .archived
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try eventService.recordArcDeactivated(arc)
        try modelContext.save()

        logger.info("Archived arc: \(arc.id)")
        triggerSync()
    }

    // MARK: - Stack Association

    /// Assigns a stack to an arc
    func assignStack(_ stack: Stack, to arc: Arc) throws {
        // If already assigned to this arc, do nothing
        guard stack.arc?.id != arc.id else { return }

        // If stack was in another arc, remove it first
        if let previousArc = stack.arc {
            try removeStack(stack, from: previousArc)
        }

        stack.arc = arc
        stack.arcId = arc.id
        stack.updatedAt = Date()
        stack.syncState = .pending
        stack.revision += 1

        try eventService.recordStackAssignedToArc(stack: stack, arc: arc)
        try modelContext.save()

        logger.info("Assigned stack \(stack.id) to arc \(arc.id)")
        triggerSync()
    }

    /// Removes a stack from an arc
    func removeStack(_ stack: Stack, from arc: Arc) throws {
        guard stack.arc?.id == arc.id else { return }

        let previousArcId = arc.id
        stack.arc = nil
        stack.arcId = nil
        stack.updatedAt = Date()
        stack.syncState = .pending
        stack.revision += 1

        try eventService.recordStackRemovedFromArc(stack: stack, arcId: previousArcId)
        try modelContext.save()

        logger.info("Removed stack \(stack.id) from arc \(previousArcId)")
        triggerSync()
    }

    // MARK: - Reordering

    /// Updates the sort order of arcs based on their position in the array
    func updateSortOrders(_ arcs: [Arc]) throws {
        for (index, arc) in arcs.enumerated() {
            if arc.sortOrder != index {
                arc.sortOrder = index
                arc.updatedAt = Date()
                arc.syncState = .pending
                arc.revision += 1
            }
        }

        try eventService.recordArcReordered(arcs)
        try modelContext.save()

        logger.info("Reordered \(arcs.count) arcs")
        triggerSync()
    }

    // MARK: - Sync Support

    /// Creates or updates an arc from a sync event (used by ProjectorService)
    func upsertFromSync(
        id: String,
        title: String,
        description: String?,
        status: ArcStatus,
        sortOrder: Int,
        colorHex: String?,
        createdAt: Date,
        updatedAt: Date,
        isDeleted: Bool,
        userId: String?,
        revision: Int,
        serverId: String?
    ) throws -> Arc {
        if let existing = try fetchByIdIncludingDeleted(id) {
            // Update existing arc
            existing.title = title
            existing.arcDescription = description
            existing.status = status
            existing.sortOrder = sortOrder
            existing.colorHex = colorHex
            existing.createdAt = createdAt
            existing.updatedAt = updatedAt
            existing.isDeleted = isDeleted
            existing.userId = userId
            existing.revision = revision
            existing.serverId = serverId
            existing.syncState = .synced
            existing.lastSyncedAt = Date()

            try modelContext.save()
            return existing
        } else {
            // Create new arc from sync
            let arc = Arc(
                id: id,
                title: title,
                arcDescription: description,
                status: status,
                sortOrder: sortOrder,
                colorHex: colorHex,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isDeleted: isDeleted,
                userId: userId,
                deviceId: deviceId,
                syncState: .synced,
                lastSyncedAt: Date(),
                serverId: serverId,
                revision: revision
            )

            modelContext.insert(arc)
            try modelContext.save()
            return arc
        }
    }

    /// Fetches an arc by ID including deleted ones (for sync)
    private func fetchByIdIncludingDeleted(_ id: String) throws -> Arc? {
        let descriptor = FetchDescriptor<Arc>(
            predicate: #Predicate<Arc> { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - History Revert

    /// Reverts an arc to a historical state from a previous event
    /// - Parameters:
    ///   - arc: The arc to revert
    ///   - event: The historical event containing the desired state
    func revertToHistoricalState(_ arc: Arc, from event: Event) throws {
        let historicalPayload = try event.decodePayload(ArcEventPayload.self)

        // Apply historical values
        arc.title = historicalPayload.title
        arc.arcDescription = historicalPayload.description
        arc.status = historicalPayload.status
        arc.sortOrder = historicalPayload.sortOrder
        arc.colorHex = historicalPayload.colorHex
        arc.updatedAt = Date()  // Current time - this IS a new edit
        arc.syncState = .pending
        arc.revision += 1

        // Record as a NEW update event (preserves immutable history)
        try eventService.recordArcUpdated(arc)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }

    // MARK: - Private Helpers

    private func triggerSync() {
        syncManager?.triggerImmediatePush()
    }
}

// MARK: - Errors

enum ArcServiceError: LocalizedError {
    case maxActiveArcsExceeded(limit: Int)
    case arcNotFound(id: String)

    var errorDescription: String? {
        switch self {
        case .maxActiveArcsExceeded(let limit):
            return "Maximum of \(limit) active arcs allowed. Complete or archive an existing arc first."
        case .arcNotFound(let id):
            return "Arc not found: \(id)"
        }
    }
}
