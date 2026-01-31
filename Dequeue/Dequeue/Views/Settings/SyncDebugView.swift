//
//  SyncDebugView.swift
//  Dequeue
//
//  Debug view for sync status and operations
//

import SwiftUI
import SwiftData

struct SyncDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Query(filter: #Predicate<Event> { !$0.isSynced })
    private var pendingEvents: [Event]

    @State private var lastSyncCheckpoint: String = "Loading..."
    @State private var currentDeviceId: String = "Loading..."
    @State private var isSyncing = false
    @State private var syncResult: String?
    @State private var isPulling = false
    @State private var isPushing = false

    private let lastSyncCheckpointKey = "com.dequeue.lastSyncCheckpoint"

    var body: some View {
        List {
            Section("Sync Status") {
                LabeledContent("Pending Events", value: "\(pendingEvents.count)")
                LabeledContent("Last Checkpoint", value: lastSyncCheckpoint)
                LabeledContent("Device ID", value: currentDeviceId)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Pending Events Preview") {
                if pendingEvents.isEmpty {
                    Text("No pending events")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pendingEvents.prefix(10)) { event in
                        HStack {
                            Text(event.type)
                                .font(.caption)
                            Spacer()
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if pendingEvents.count > 10 {
                        Text("... and \(pendingEvents.count - 10) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Manual Sync") {
                Button {
                    Task { await manualPull() }
                } label: {
                    HStack {
                        Label("Pull from Server", systemImage: "arrow.down.circle")
                        if isPulling {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isPulling || syncManager == nil)

                Button {
                    Task { await manualPush() }
                } label: {
                    HStack {
                        Label("Push to Server", systemImage: "arrow.up.circle")
                        if isPushing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isPushing || syncManager == nil)

                if syncManager == nil {
                    Text("Sync manager not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Actions") {
                Button {
                    resetSyncCheckpoint()
                } label: {
                    Label("Reset Sync Checkpoint", systemImage: "arrow.counterclockwise")
                }

                Button(role: .destructive) {
                    clearAllEvents()
                } label: {
                    Label("Clear All Events", systemImage: "trash")
                }
            }

            if let result = syncResult {
                Section("Last Operation") {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sync Debug")
        .task {
            await loadDebugInfo()
        }
        .refreshable {
            await loadDebugInfo()
        }
    }

    private func loadDebugInfo() async {
        currentDeviceId = await DeviceService.shared.getDeviceId()

        if let checkpoint = UserDefaults.standard.string(forKey: lastSyncCheckpointKey) {
            lastSyncCheckpoint = checkpoint
        } else {
            lastSyncCheckpoint = "Not set (will pull all)"
        }
    }

    private func resetSyncCheckpoint() {
        UserDefaults.standard.removeObject(forKey: lastSyncCheckpointKey)
        lastSyncCheckpoint = "Reset - will pull all events"
        syncResult = "Checkpoint reset at \(Date().formatted())"
    }

    private func clearAllEvents() {
        do {
            try modelContext.delete(model: Event.self)
            try modelContext.save()
            syncResult = "All events cleared at \(Date().formatted())"
        } catch {
            syncResult = "Error clearing events: \(error.localizedDescription)"
        }
    }

    private func manualPull() async {
        guard let syncManager = syncManager else {
            syncResult = "Sync manager not available"
            return
        }

        isPulling = true
        do {
            try await syncManager.manualPull()
            syncResult = "Pull completed at \(Date().formatted())"
        } catch {
            syncResult = "Pull failed: \(error.localizedDescription)"
        }
        isPulling = false
        await loadDebugInfo()
    }

    private func manualPush() async {
        guard let syncManager = syncManager else {
            syncResult = "Sync manager not available"
            return
        }

        isPushing = true
        do {
            try await syncManager.manualPush()
            syncResult = "Push completed at \(Date().formatted())"
        } catch {
            syncResult = "Push failed: \(error.localizedDescription)"
        }
        isPushing = false
        await loadDebugInfo()
    }
}

#Preview {
    NavigationStack {
        SyncDebugView()
    }
    .modelContainer(for: [Event.self], inMemory: true)
}
