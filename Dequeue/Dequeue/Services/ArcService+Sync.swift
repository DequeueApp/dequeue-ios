//
//  ArcService+Sync.swift
//  Dequeue
//
//  Sync support functionality for ArcService
//

import Foundation
import SwiftData

// MARK: - Sync Support

extension ArcService {
    /// Creates or updates an arc from a sync event (used by ProjectorService)
    func upsertFromSync( // swiftlint:disable:this function_parameter_count
        id: String,
        title: String,
        description: String?,
        status: ArcStatus,
        sortOrder: Int,
        colorHex: String?,
        startTime: Date?,
        dueTime: Date?,
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
            existing.startTime = startTime
            existing.dueTime = dueTime
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
                startTime: startTime,
                dueTime: dueTime,
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
    func fetchByIdIncludingDeleted(_ id: String) throws -> Arc? {
        let descriptor = FetchDescriptor<Arc>(
            predicate: #Predicate<Arc> { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }
}
