//
//  SyncStatusViewModel.swift
//  Dequeue
//
//  Tracks sync status for UI display
//

import Foundation
import SwiftData
import Observation

/// ViewModel that tracks sync status for UI display.
///
/// Uses @MainActor isolation because:
/// - SwiftData's ModelContext is MainActor-isolated
/// - EventService (used for fetching pending events) is @MainActor
/// - All properties are observed by SwiftUI views which run on MainActor
/// - This is an exception per CLAUDE.md: "@MainActor unless truly needed" - this qualifies
@MainActor
@Observable
internal final class SyncStatusViewModel {
    // MARK: - Constants

    private static let statusUpdateInterval: Duration = .seconds(3)

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Properties

    private(set) var pendingEventCount: Int = 0
    private(set) var isSyncing: Bool = false
    private(set) var lastSyncTime: Date?
    private(set) var connectionStatus: ConnectionStatus = .disconnected

    /// Whether an initial sync is currently in progress (fresh device downloading events)
    private(set) var isInitialSyncInProgress: Bool = false

    /// Number of events processed during initial sync
    private(set) var initialSyncEventsProcessed: Int = 0

    /// Total number of events during initial sync (DEQ-240)
    private(set) var initialSyncTotalEvents: Int = 0

    private let modelContext: ModelContext
    private let eventService: EventService
    private var syncManager: SyncManager?
    // nonisolated(unsafe) allows access from deinit for cleanup with @Observable.
    // nonisolated(unsafe) needed for mutable property accessed in deinit
    nonisolated(unsafe) private var updateTask: Task<Void, Never>?
    private var previousPendingCount: Int = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.eventService = EventService.readOnly(modelContext: modelContext)
        startMonitoring()
    }

    deinit {
        updateTask?.cancel()
    }

    func stopMonitoring() {
        updateTask?.cancel()
        updateTask = nil
    }

    func setSyncManager(_ syncManager: SyncManager) {
        self.syncManager = syncManager
    }

    /// Forces an immediate status update. Useful for tests or when sync state changes.
    func updateStatusNow() async {
        await updateStatus()
    }

    private func startMonitoring() {
        // Cancel any existing task to prevent accumulation if view appears/disappears rapidly
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                await self.updateStatus()
                try? await Task.sleep(for: Self.statusUpdateInterval)
            }
        }
    }

    private func updateStatus() async {
        // Update connection status from SyncManager first
        if let syncManager = syncManager {
            let status = await syncManager.connectionStatus

            // Fetch initial sync state (DEQ-240)
            let initialSyncActive = await syncManager.isInitialSyncInProgress
            let eventsProcessed = await syncManager.initialSyncEventsProcessed
            let totalEvents = await syncManager.initialSyncTotalEvents

            // Fetch pending event count - do this AFTER connection status to minimize race window.
            // Note: There's an inherent race between status and count fetches, but this is
            // acceptable for a non-critical UI indicator that updates every few seconds.
            let currentCount: Int
            do {
                let pendingEvents = try eventService.fetchPendingEvents()
                currentCount = pendingEvents.count
            } catch {
                // Log error but don't crash - status indicator is non-critical.
                // Keep previous count instead of resetting to avoid misleading "Synced" UI
                // when there's actually a database error.
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "sync_status_fetch_pending"]
                )
                currentCount = pendingEventCount
            }

            let previousCount = previousPendingCount

            // Update connection status
            connectionStatus = status

            // Update initial sync state (DEQ-240)
            isInitialSyncInProgress = initialSyncActive
            initialSyncEventsProcessed = eventsProcessed
            initialSyncTotalEvents = totalEvents

            // Update pending count
            pendingEventCount = currentCount

            // Consider "syncing" when connected and has pending events
            isSyncing = status == .connected && currentCount > 0

            // Update last sync time only when transitioning from pending → synced
            if previousCount > 0 && currentCount == 0 && status == .connected {
                lastSyncTime = Date()
            }

            // Track for next comparison
            previousPendingCount = currentCount
        } else {
            // No sync manager - just update pending count
            do {
                let pendingEvents = try eventService.fetchPendingEvents()
                pendingEventCount = pendingEvents.count
            } catch {
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "sync_status_fetch_pending"]
                )
            }
        }
    }

    /// Format last sync time for display
    var lastSyncTimeFormatted: String {
        guard let lastSyncTime = lastSyncTime else {
            return "Never"
        }

        let now = Date()
        let interval = now.timeIntervalSince(lastSyncTime)

        if interval < 60 {
            return "Just now"
        } else if interval < 3_600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86_400 {
            let hours = Int(interval / 3_600)
            return "\(hours)h ago"
        } else {
            return Self.dateTimeFormatter.string(from: lastSyncTime)
        }
    }

    /// Status message for display
    var statusMessage: String {
        switch connectionStatus {
        case .connected:
            if isSyncing {
                return "Syncing \(pendingEventCount) events..."
            } else if pendingEventCount > 0 {
                return "\(pendingEventCount) pending"
            } else {
                return "Synced"
            }
        case .connecting:
            return "Connecting..."
        case .disconnected:
            if pendingEventCount > 0 {
                return "\(pendingEventCount) offline"
            } else {
                return "Offline"
            }
        }
    }
}
