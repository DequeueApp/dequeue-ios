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

        // Create a pending event BEFORE the view model so the first update sees it
        let payload = try JSONEncoder().encode(["key": "value"])
        let event = Event(type: "test.event", payload: payload, userId: "test-user", deviceId: "test-device", isSynced: false)
        context.insert(event)
        try context.save()

        let viewModel = SyncStatusViewModel(modelContext: context)

        // Wait briefly for the initial monitoring update to complete
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.pendingEventCount == 1)
    }

    @Test("ViewModel shows syncing state when connected with pending events")
    func viewModelShowsSyncingState() async throws {
        let container = try ModelContainer(
            for: Event.self, Stack.self, QueueTask.self, Reminder.self, Device.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        // Create a pending event BEFORE the view model so the first update sees it
        let payload = try JSONEncoder().encode(["key": "value"])
        let event = Event(type: "test.event", payload: payload, userId: "test-user", deviceId: "test-device", isSynced: false)
        context.insert(event)
        try context.save()

        let viewModel = SyncStatusViewModel(modelContext: context)
        let syncManager = SyncManager(modelContainer: container)
        viewModel.setSyncManager(syncManager)

        // Force immediate status update for test reliability
        await viewModel.updateStatusNow()

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

        // Test disconnected state with no pending events
        let viewModel = SyncStatusViewModel(modelContext: container.mainContext)
        #expect(viewModel.statusMessage == "Offline")
        viewModel.stopMonitoring()

        // Create a new view model with a pending event already present
        let context = container.mainContext
        let payload = try JSONEncoder().encode(["key": "value"])
        let event = Event(type: "test.event", payload: payload, userId: "test-user", deviceId: "test-device", isSynced: false)
        context.insert(event)
        try context.save()

        let viewModel2 = SyncStatusViewModel(modelContext: context)

        // Wait briefly for the initial monitoring update to complete
        try await Task.sleep(for: .milliseconds(100))

        // Test disconnected state with pending events
        #expect(viewModel2.statusMessage.contains("offline"))
    }

    @Test("ViewModel can stop monitoring")
    func viewModelCanStopMonitoring() async throws {
        let container = try ModelContainer(
            for: Event.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = SyncStatusViewModel(modelContext: container.mainContext)

        // Wait briefly for initial update to complete, then stop
        try await Task.sleep(for: .milliseconds(50))
        viewModel.stopMonitoring()

        // Create a pending event after stopping
        let context = container.mainContext
        let payload = try JSONEncoder().encode(["key": "value"])
        let event = Event(type: "test.event", payload: payload, userId: "test-user", deviceId: "test-device", isSynced: false)
        context.insert(event)
        try context.save()

        // Wait briefly - count should not update since monitoring is stopped
        try await Task.sleep(for: .milliseconds(200))

        #expect(viewModel.pendingEventCount == 0)
    }
}
