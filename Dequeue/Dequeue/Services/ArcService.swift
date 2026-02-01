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

/// Service layer for managing Arc entities (higher-level organizational containers).
///
/// ArcService handles all CRUD operations, status transitions, and stack associations for Arcs.
/// Thread safety: All operations are serialized on the MainActor.
///
/// Business rules:
/// - Maximum of 5 active arcs allowed at any time
/// - Arcs can contain multiple stacks
/// - Deleting an arc removes stacks from it but doesn't delete them
@MainActor
final class ArcService {
    let modelContext: ModelContext
    let eventService: EventService
    private let userId: String?
    let deviceId: String
    private(set) weak var syncManager: SyncManager?

    /// Creates a new ArcService instance.
    /// - Parameters:
    ///   - modelContext: The SwiftData model context for database operations
    ///   - userId: Optional user ID for sync attribution
    ///   - deviceId: Device ID for sync attribution
    ///   - syncManager: Optional sync manager for triggering immediate pushes
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

    /// Creates a new arc with the specified properties.
    /// - Parameters:
    ///   - title: The arc's title (required)
    ///   - description: Optional description text
    ///   - colorHex: Optional hex color for visual accent (e.g., "FF6B6B")
    ///   - status: Initial status (defaults to .active)
    /// - Returns: The newly created Arc
    /// - Throws: `ArcServiceError.maxActiveArcsExceeded` if creating an active arc would exceed the 5-arc limit
    @discardableResult
    func createArc(
        title: String,
        description: String? = nil,
        colorHex: String? = nil,
        startTime: Date? = nil,
        dueTime: Date? = nil,
        status: ArcStatus = .active
    ) async throws -> Arc {
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
            startTime: startTime,
            dueTime: dueTime,
            userId: userId,
            deviceId: deviceId,
            syncState: .pending
        )

        modelContext.insert(arc)
        try await eventService.recordArcCreated(arc)
        try modelContext.save()

        logger.info("Created arc: \(arc.id) - \(title)")
        triggerSync()

        return arc
    }

    /// Updates an existing arc's basic properties.
    ///
    /// This method performs a **partial update**: only properties with non-nil values are modified.
    /// Pass `nil` to leave a property unchanged. The title is trimmed before being saved.
    ///
    /// Note: To clear optional fields (description, colorHex), pass an empty string rather than nil.
    ///
    /// - Parameters:
    ///   - arc: The arc to update
    ///   - title: New title (trimmed, must not be empty/whitespace-only), or nil to keep current
    ///   - description: New description, or nil to keep current
    ///   - colorHex: New color hex value, or nil to keep current
    /// - Throws: `ArcServiceError.invalidTitle` if title is provided but empty or whitespace-only
    /// Wrapper type to distinguish "set to nil" from "don't change" for optional Date fields.
    /// Use `.clear` to explicitly set the date to nil, `.set(date)` to update, or `nil` to leave unchanged.
    enum DateUpdate {
        case clear
        case set(Date)
    }

    func updateArc(
        _ arc: Arc,
        title: String? = nil,
        description: String? = nil,
        colorHex: String? = nil,
        startTime: DateUpdate? = nil,
        dueTime: DateUpdate? = nil
    ) async throws {
        // Validate and normalize title if provided
        var normalizedTitle: String?
        if let title = title {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else {
                throw ArcServiceError.invalidTitle
            }
            normalizedTitle = trimmedTitle
        }

        var changes: [String: Any] = [:]

        if let newTitle = normalizedTitle, newTitle != arc.title {
            changes["title"] = ["from": arc.title, "to": newTitle]
            arc.title = newTitle
        }

        if let description = description, description != arc.arcDescription {
            changes["description"] = ["from": arc.arcDescription as Any, "to": description]
            arc.arcDescription = description
        }

        if let colorHex = colorHex, colorHex != arc.colorHex {
            changes["colorHex"] = ["from": arc.colorHex as Any, "to": colorHex]
            arc.colorHex = colorHex
        }

        // Handle startTime updates
        if let startTimeUpdate = startTime {
            switch startTimeUpdate {
            case .clear:
                if arc.startTime != nil {
                    changes["startTime"] = ["from": arc.startTime as Any, "to": NSNull()]
                    arc.startTime = nil
                }
            case .set(let date):
                if arc.startTime != date {
                    changes["startTime"] = ["from": arc.startTime as Any, "to": date]
                    arc.startTime = date
                }
            }
        }

        // Handle dueTime updates
        if let dueTimeUpdate = dueTime {
            switch dueTimeUpdate {
            case .clear:
                if arc.dueTime != nil {
                    changes["dueTime"] = ["from": arc.dueTime as Any, "to": NSNull()]
                    arc.dueTime = nil
                }
            case .set(let date):
                if arc.dueTime != date {
                    changes["dueTime"] = ["from": arc.dueTime as Any, "to": date]
                    arc.dueTime = date
                }
            }
        }

        guard !changes.isEmpty else { return }

        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try await eventService.recordArcUpdated(arc, changes: changes)
        try modelContext.save()

        logger.info("Updated arc: \(arc.id)")
        triggerSync()
    }

    /// Soft-deletes an arc (sets isDeleted = true).
    ///
    /// This operation atomically removes all stacks from the arc and marks the arc as deleted.
    /// All changes are batched and committed in a single `modelContext.save()` call, ensuring
    /// that either all modifications succeed or none are persisted.
    ///
    /// Note: Stacks are removed from the arc but NOT deleted - this preserves user data
    /// while cleaning up the relationship.
    /// - Parameter arc: The arc to delete
    func deleteArc(_ arc: Arc) async throws {
        let arcId = arc.id
        let stacksToRemove = Array(arc.stacks)

        // Remove all stacks from this arc and record events for each
        for stack in stacksToRemove {
            stack.arc = nil
            stack.arcId = nil
            stack.updatedAt = Date()
            stack.syncState = .pending
            stack.revision += 1
            try await eventService.recordStackRemovedFromArc(stack: stack, arcId: arcId)
        }

        // Mark the arc as deleted
        arc.isDeleted = true
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try await eventService.recordArcDeleted(arc)

        // Save all changes atomically
        try modelContext.save()

        logger.info("Deleted arc: \(arc.id) (removed \(stacksToRemove.count) stacks)")
        triggerSync()
    }

    // MARK: - Status Operations

    /// Marks an arc as completed
    func markAsCompleted(_ arc: Arc) async throws {
        guard arc.status != .completed else { return }

        arc.status = .completed
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try await eventService.recordArcCompleted(arc)
        try modelContext.save()

        logger.info("Completed arc: \(arc.id)")
        triggerSync()
    }

    /// Pauses an arc
    func pause(_ arc: Arc) async throws {
        guard arc.status == .active else { return }

        arc.status = .paused
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try await eventService.recordArcPaused(arc)
        try modelContext.save()

        logger.info("Paused arc: \(arc.id)")
        triggerSync()
    }

    /// Resumes a paused or completed arc
    /// - Throws: If resuming would exceed the maximum active arcs
    func resume(_ arc: Arc) async throws {
        guard arc.status == .paused || arc.status == .completed else { return }

        // Check if we can have another active arc
        guard try canCreateNewArc() else {
            throw ArcServiceError.maxActiveArcsExceeded(limit: maxActiveArcs)
        }

        arc.status = .active
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try await eventService.recordArcActivated(arc)
        try modelContext.save()

        logger.info("Resumed arc: \(arc.id)")
        triggerSync()
    }

    /// Archives an arc
    func archive(_ arc: Arc) async throws {
        guard arc.status != .archived else { return }

        arc.status = .archived
        arc.updatedAt = Date()
        arc.syncState = .pending
        arc.revision += 1

        try await eventService.recordArcDeactivated(arc)
        try modelContext.save()

        logger.info("Archived arc: \(arc.id)")
        triggerSync()
    }

    // MARK: - Stack Association

    /// Assigns a stack to an arc
    func assignStack(_ stack: Stack, to arc: Arc) async throws {
        // If already assigned to this arc, do nothing
        guard stack.arc?.id != arc.id else { return }

        // If stack was in another arc, remove it first
        if let previousArc = stack.arc {
            try await removeStack(stack, from: previousArc)
        }

        stack.arc = arc
        stack.arcId = arc.id
        stack.updatedAt = Date()
        stack.syncState = .pending
        stack.revision += 1

        try await eventService.recordStackAssignedToArc(stack: stack, arc: arc)
        try modelContext.save()

        logger.info("Assigned stack \(stack.id) to arc \(arc.id)")
        triggerSync()
    }

    /// Removes a stack from an arc
    func removeStack(_ stack: Stack, from arc: Arc) async throws {
        guard stack.arc?.id == arc.id else { return }

        let previousArcId = arc.id
        stack.arc = nil
        stack.arcId = nil
        stack.updatedAt = Date()
        stack.syncState = .pending
        stack.revision += 1

        try await eventService.recordStackRemovedFromArc(stack: stack, arcId: previousArcId)
        try modelContext.save()

        logger.info("Removed stack \(stack.id) from arc \(previousArcId)")
        triggerSync()
    }

    // MARK: - Reordering

    /// Updates the sort order of arcs based on their position in the array
    func updateSortOrders(_ arcs: [Arc]) async throws {
        for (index, arc) in arcs.enumerated() where arc.sortOrder != index {
            arc.sortOrder = index
            arc.updatedAt = Date()
            arc.syncState = .pending
            arc.revision += 1
        }

        try await eventService.recordArcReordered(arcs)
        try modelContext.save()

        logger.info("Reordered \(arcs.count) arcs")
        triggerSync()
    }

    // MARK: - Private Helpers
    // Note: upsertFromSync and fetchByIdIncludingDeleted are defined in ArcService+Sync.swift
    // Note: revertToHistoricalState is defined in ArcService+History.swift

    private func triggerSync() {
        syncManager?.triggerImmediatePush()
    }
}

// MARK: - Errors

enum ArcServiceError: LocalizedError {
    case maxActiveArcsExceeded(limit: Int)
    case arcNotFound(id: String)
    case invalidTitle

    var errorDescription: String? {
        switch self {
        case .maxActiveArcsExceeded(let limit):
            return "Maximum of \(limit) active arcs allowed. Complete or archive an existing arc first."
        case .arcNotFound(let id):
            return "Arc not found: \(id)"
        case .invalidTitle:
            return "Title cannot be empty"
        }
    }
}
