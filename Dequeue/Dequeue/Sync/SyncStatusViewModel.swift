//
//  SyncStatusViewModel.swift
//  Dequeue
//
//  Tracks sync status for UI display
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class SyncStatusViewModel {
    // MARK: - Static

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

    private let modelContext: ModelContext
    private var syncManager: SyncManager?
    // nonisolated(unsafe) allows access from deinit for cleanup
    nonisolated(unsafe) private var updateTask: Task<Void, Never>?
    private var previousPendingCount: Int = 0

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
                await self?.updateStatus()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func updateStatus() async {
        // Update pending event count
        let eventService = EventService(modelContext: modelContext)
        do {
            let pendingEvents = try eventService.fetchPendingEvents()
            pendingEventCount = pendingEvents.count
        } catch {
            // Log error but don't crash - status indicator is non-critical
            ErrorReportingService.capture(
                error: error,
                context: ["source": "sync_status_fetch_pending"]
            )
            pendingEventCount = 0
        }

        // Update connection status from SyncManager
        if let syncManager = syncManager {
            connectionStatus = await syncManager.connectionStatus

            // Consider "syncing" when connected and has pending events
            isSyncing = connectionStatus == .connected && pendingEventCount > 0
        }

        // Update last sync time only when transitioning from pending → synced
        if previousPendingCount > 0 && pendingEventCount == 0 && connectionStatus == .connected {
            lastSyncTime = Date()
        }
        previousPendingCount = pendingEventCount
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
