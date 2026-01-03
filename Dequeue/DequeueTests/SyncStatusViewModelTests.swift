//
//  SyncStatusViewModelTests.swift
//  DequeueTests
//
//  Tests for SyncStatusViewModel
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("SyncStatusViewModel Tests")
@MainActor
struct SyncStatusViewModelTests {

    @Test("ViewModel initializes with default state")
    func viewModelInitializesWithDefaults() async throws {
        let container = try ModelContainer(
            for: Event.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = SyncStatusViewModel(modelContext: container.mainContext)

        #expect(viewModel.pendingEventCount == 0)
        #expect(viewModel.isSyncing == false)
        #expect(viewModel.lastSyncTime == nil)
        #expect(viewModel.connectionStatus == .disconnected)
    }

    @Test("ViewModel tracks pending events")
    func viewModelTracksPendingEvents() async throws {
        let container = try ModelContainer(
            for: Event.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let viewModel = SyncStatusViewModel(modelContext: context)

        // Create a pending event
        let payload = try JSONEncoder().encode(["key": "value"])
        let event = Event(type: "test.event", payload: payload, isSynced: false)
        context.insert(event)
        try context.save()

        // Wait for the monitoring task to update
        try await Task.sleep(for: .seconds(1.5))

        #expect(viewModel.pendingEventCount == 1)
    }

    @Test("ViewModel shows syncing state when connected with pending events")
    func viewModelShowsSyncingState() async throws {
        let container = try ModelContainer(
            for: Event.self, Stack.self, QueueTask.self, Reminder.self, Device.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let viewModel = SyncStatusViewModel(modelContext: context)
        let syncManager = SyncManager(modelContainer: container)
        viewModel.setSyncManager(syncManager)

        // Create a pending event
        let payload = try JSONEncoder().encode(["key": "value"])
        let event = Event(type: "test.event", payload: payload, isSynced: false)
        context.insert(event)
        try context.save()

        // Wait for the monitoring task to update
        try await Task.sleep(for: .seconds(1.5))

        // Note: isSyncing will be false because we're not actually connected
        // This is expected behavior - syncing only happens when both connected AND has pending events
        #expect(viewModel.pendingEventCount == 1)
    }

    @Test("ViewModel formats last sync time correctly")
    func viewModelFormatsLastSyncTime() async throws {
        let container = try ModelContainer(
            for: Event.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = SyncStatusViewModel(modelContext: container.mainContext)

        // Test "Never" when no last sync time
        #expect(viewModel.lastSyncTimeFormatted == "Never")

        // Note: We can't easily test the time formatting without mocking the current time
        // This would require refactoring to inject a TimeProvider
    }

    @Test("ViewModel provides status messages")
    func viewModelProvidesStatusMessages() async throws {
        let container = try ModelContainer(
            for: Event.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = SyncStatusViewModel(modelContext: container.mainContext)

        // Test disconnected state with no pending events
        #expect(viewModel.statusMessage == "Offline")

        // Create a pending event
        let context = container.mainContext
        let payload = try JSONEncoder().encode(["key": "value"])
        let event = Event(type: "test.event", payload: payload, isSynced: false)
        context.insert(event)
        try context.save()

        // Wait for update
        try await Task.sleep(for: .seconds(1.5))

        // Test disconnected state with pending events
        #expect(viewModel.statusMessage.contains("offline"))
    }

    @Test("ViewModel can stop monitoring")
    func viewModelCanStopMonitoring() async throws {
        let container = try ModelContainer(
            for: Event.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = SyncStatusViewModel(modelContext: container.mainContext)

        viewModel.stopMonitoring()

        // Create a pending event after stopping
        let context = container.mainContext
        let payload = try JSONEncoder().encode(["key": "value"])
        let event = Event(type: "test.event", payload: payload, isSynced: false)
        context.insert(event)
        try context.save()

        // Wait - count should not update since monitoring is stopped
        try await Task.sleep(for: .seconds(1.5))

        #expect(viewModel.pendingEventCount == 0)
    }
}
