//
//  ArcService+History.swift
//  Dequeue
//
//  History revert functionality for ArcService
//

import Foundation
import SwiftData

// MARK: - History Revert

extension ArcService {
    /// Reverts an arc to a historical state from a previous event
    /// - Parameters:
    ///   - arc: The arc to revert
    ///   - event: The historical event containing the desired state
    func revertToHistoricalState(_ arc: Arc, from event: Event) async throws {
        let historicalPayload = try event.decodePayload(ArcEventPayload.self)

        // Apply historical values
        arc.title = historicalPayload.title
        arc.arcDescription = historicalPayload.description
        arc.status = historicalPayload.status
        arc.sortOrder = historicalPayload.sortOrder
        arc.colorHex = historicalPayload.colorHex
        arc.startTime = historicalPayload.startTime
        arc.dueTime = historicalPayload.dueTime
        arc.updatedAt = Date()  // Current time - this IS a new edit
        arc.syncState = .pending
        arc.revision += 1

        // Record as a NEW update event (preserves immutable history)
        try await eventService.recordArcUpdated(arc)
        try modelContext.save()
        syncManager?.triggerImmediatePush()
    }
}
