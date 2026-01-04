//
//  SyncStatusViewModel.swift
//  Dequeue
//
//  Tracks sync status for UI display
//

import Foundation
import SwiftData
import Observation

@Observable
internal final class SyncStatusViewModel {
    // MARK: - Static

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Properties

    @MainActor private(set) var pendingEventCount: Int = 0
    @MainActor private(set) var isSyncing: Bool = false
    @MainActor private(set) var lastSyncTime: Date?
    @MainActor private(set) var connectionStatus: ConnectionStatus = .disconnected

    private let modelContext: ModelContext
    private var syncManager: SyncManager?
    // nonisolated(unsafe) allows access from deinit for cleanup with @Observable
    nonisolated(unsafe) private var updateTask: Task<Void, Never>?
    @MainActor private var previousPendingCount: Int = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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

    private func startMonitoring() {
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                await self.updateStatus()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func updateStatus() async {
        // Update connection status from SyncManager first
        if let syncManager = syncManager {
            let status = await syncManager.connectionStatus

            // Fetch pending event count - do this AFTER connection status to minimize race window
            let eventService = EventService(modelContext: modelContext)
            let currentCount: Int
            do {
                let pendingEvents = try eventService.fetchPendingEvents()
                currentCount = pendingEvents.count
            } catch {
                // Log error but don't crash - status indicator is non-critical
                // Keep previous count instead of resetting to avoid misleading UI
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "sync_status_fetch_pending"]
                )
                // Use Task to access MainActor property from background context
                currentCount = await MainActor.run { pendingEventCount }
            }

            // Update all state atomically on MainActor to avoid races
            await MainActor.run {
                let previousCount = previousPendingCount

                // Update connection status
                connectionStatus = status

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
            }
        } else {
            // No sync manager - just update pending count
            let eventService = EventService(modelContext: modelContext)
            do {
                let pendingEvents = try eventService.fetchPendingEvents()
                await MainActor.run {
                    pendingEventCount = pendingEvents.count
                }
            } catch {
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "sync_status_fetch_pending"]
                )
            }
        }
    }

    /// Format last sync time for display
    @MainActor
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
    @MainActor
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
