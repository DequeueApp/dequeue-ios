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
    private(set) var pendingEventCount: Int = 0
    private(set) var isSyncing: Bool = false
    private(set) var lastSyncTime: Date?
    private(set) var connectionStatus: ConnectionStatus = .disconnected

    private let modelContext: ModelContext
    private var syncManager: SyncManager?
    private var updateTask: Task<Void, Never>?

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
                try? await Task.sleep(for: .seconds(1))
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
            // Silently fail - don't crash the app
            pendingEventCount = 0
        }

        // Update connection status from SyncManager
        if let syncManager = syncManager {
            connectionStatus = await syncManager.connectionStatus

            // Consider "syncing" when connected and has pending events
            isSyncing = connectionStatus == .connected && pendingEventCount > 0
        }

        // Update last sync time when we transition from having pending events to none
        if pendingEventCount == 0 && connectionStatus == .connected {
            lastSyncTime = Date()
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
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: lastSyncTime)
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
