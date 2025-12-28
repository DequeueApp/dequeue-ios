//
//  DeviceTests.swift
//  DequeueTests
//
//  Tests for Device model and ProjectorService device event handling
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Device Model Tests")
struct DeviceTests {

    @Test("Device initializes with required fields")
    func deviceInitializesWithRequiredFields() {
        let device = Device(
            deviceId: "test-device-id",
            name: "Test Device",
            osName: "iOS"
        )

        #expect(device.deviceId == "test-device-id")
        #expect(device.name == "Test Device")
        #expect(device.osName == "iOS")
        #expect(device.isDevice == true)
        #expect(device.isCurrentDevice == false)
        #expect(device.isDeleted == false)
        #expect(device.syncState == .pending)
    }

    @Test("Device initializes with all fields")
    func deviceInitializesWithAllFields() {
        let now = Date()
        let device = Device(
            deviceId: "device-123",
            stableDeviceId: "stable-123",
            name: "iPhone 15 Pro",
            model: "iPhone16,1",
            osName: "iOS",
            osVersion: "18.0",
            isDevice: true,
            isCurrentDevice: true,
            lastSeenAt: now,
            firstSeenAt: now,
            userId: "user-123",
            syncState: .synced,
            revision: 2
        )

        #expect(device.deviceId == "device-123")
        #expect(device.stableDeviceId == "stable-123")
        #expect(device.model == "iPhone16,1")
        #expect(device.osVersion == "18.0")
        #expect(device.isCurrentDevice == true)
        #expect(device.userId == "user-123")
        #expect(device.syncState == .synced)
        #expect(device.revision == 2)
    }

    @Test("Device can be persisted")
    func deviceCanBePersisted() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Device.self, configurations: config)
        let context = ModelContext(container)

        let device = Device(
            deviceId: "persist-test",
            name: "Test Device",
            osName: "iOS"
        )
        context.insert(device)

        try context.save()

        let fetchDescriptor = FetchDescriptor<Device>()
        let devices = try context.fetch(fetchDescriptor)

        #expect(devices.count == 1)
        #expect(devices.first?.deviceId == "persist-test")
    }

    @Test("createCurrentDevice returns valid device")
    func createCurrentDeviceReturnsValidDevice() {
        let device = Device.createCurrentDevice()

        #expect(!device.deviceId.isEmpty)
        #expect(!device.name.isEmpty)
        #expect(!device.osName.isEmpty)
        #expect(device.isCurrentDevice == true)
    }
}

// MARK: - ProjectorService Device Event Tests

@Suite("Device Event Rehydration Tests")
struct DeviceEventRehydrationTests {

    /// Helper to create an in-memory model context for testing
    private func createTestContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Device.self, Event.self, configurations: config)
        return ModelContext(container)
    }

    /// Helper to create a device discovered event with specific timestamps
    private func createDeviceDiscoveredEvent(
        id: String = "event-1",
        deviceId: String,
        name: String,
        lastSeenAt: Date,
        firstSeenAt: Date,
        eventTimestamp: Date = Date()
    ) throws -> Event {
        let payload = DeviceEventPayload(
            id: "device-\(deviceId)",
            deviceId: deviceId,
            name: name,
            model: "TestModel",
            osName: "iOS",
            osVersion: "18.0",
            isDevice: true,
            isCurrentDevice: false,
            lastSeenAt: Int64(lastSeenAt.timeIntervalSince1970 * 1000),
            firstSeenAt: Int64(firstSeenAt.timeIntervalSince1970 * 1000)
        )
        let payloadData = try JSONEncoder().encode(payload)
        return Event(
            id: id,
            eventType: .deviceDiscovered,
            payload: payloadData,
            timestamp: eventTimestamp
        )
    }

    @Test("Device event uses payload timestamps for new device, not current date")
    func deviceEventUsesPayloadTimestampsForNewDevice() throws {
        let context = try createTestContext()

        // Create a timestamp 5 days in the past
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 24 * 60 * 60)
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)

        let event = try createDeviceDiscoveredEvent(
            deviceId: "test-device-123",
            name: "Test iPhone",
            lastSeenAt: fiveDaysAgo,
            firstSeenAt: tenDaysAgo
        )

        try ProjectorService.apply(event: event, context: context)

        // Fetch the created device
        let descriptor = FetchDescriptor<Device>()
        let devices = try context.fetch(descriptor)

        #expect(devices.count == 1)
        let device = devices.first!

        // The timestamps should match the payload, not the current time
        // Allow 1 second tolerance for floating point conversion
        #expect(abs(device.lastSeenAt.timeIntervalSince(fiveDaysAgo)) < 1)
        #expect(abs(device.firstSeenAt.timeIntervalSince(tenDaysAgo)) < 1)

        // Verify it's not close to "now" (should be at least 4 days old)
        let fourDaysAgo = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        #expect(device.lastSeenAt < fourDaysAgo)
    }

    @Test("Device event updates existing device with payload lastSeenAt")
    func deviceEventUpdatesExistingDeviceWithPayloadTimestamp() throws {
        let context = try createTestContext()

        // First, create an existing device with an old lastSeenAt
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let existingDevice = Device(
            deviceId: "existing-device-456",
            name: "Old Name",
            osName: "iOS",
            lastSeenAt: tenDaysAgo,
            firstSeenAt: tenDaysAgo
        )
        context.insert(existingDevice)
        try context.save()

        // Now apply an event with a newer lastSeenAt (5 days ago)
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 24 * 60 * 60)
        let event = try createDeviceDiscoveredEvent(
            deviceId: "existing-device-456",
            name: "Updated Name",
            lastSeenAt: fiveDaysAgo,
            firstSeenAt: tenDaysAgo
        )

        try ProjectorService.apply(event: event, context: context)

        // Fetch the device
        let descriptor = FetchDescriptor<Device>()
        let devices = try context.fetch(descriptor)

        #expect(devices.count == 1)
        let device = devices.first!

        // The lastSeenAt should be updated to the payload value (5 days ago)
        #expect(abs(device.lastSeenAt.timeIntervalSince(fiveDaysAgo)) < 1)
        #expect(device.name == "Updated Name")
    }

    @Test("Device event with older lastSeenAt does not overwrite newer (LWW)")
    func deviceEventOlderTimestampDoesNotOverwrite() throws {
        let context = try createTestContext()

        // Create a device that was already seen recently (2 days ago)
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let existingDevice = Device(
            deviceId: "lww-test-device",
            name: "Current Name",
            osName: "iOS",
            lastSeenAt: twoDaysAgo,
            firstSeenAt: tenDaysAgo
        )
        context.insert(existingDevice)
        try context.save()

        // Apply an event with an OLDER lastSeenAt (5 days ago - older than current)
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 24 * 60 * 60)
        let event = try createDeviceDiscoveredEvent(
            deviceId: "lww-test-device",
            name: "Old Name Should Not Apply",
            lastSeenAt: fiveDaysAgo,
            firstSeenAt: tenDaysAgo
        )

        try ProjectorService.apply(event: event, context: context)

        // Fetch the device
        let descriptor = FetchDescriptor<Device>()
        let devices = try context.fetch(descriptor)

        #expect(devices.count == 1)
        let device = devices.first!

        // The device should NOT be updated because the incoming event has older lastSeenAt
        #expect(abs(device.lastSeenAt.timeIntervalSince(twoDaysAgo)) < 1)
        #expect(device.name == "Current Name")
    }

    @Test("Multiple device events apply in correct chronological order")
    func multipleDeviceEventsApplyChronologically() throws {
        let context = try createTestContext()

        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 24 * 60 * 60)
        let oneDayAgo = Date().addingTimeInterval(-1 * 24 * 60 * 60)

        // Apply events out of order to simulate sync rehydration
        let event1 = try createDeviceDiscoveredEvent(
            id: "event-1",
            deviceId: "multi-event-device",
            name: "Name at 5 days ago",
            lastSeenAt: fiveDaysAgo,
            firstSeenAt: tenDaysAgo
        )

        let event2 = try createDeviceDiscoveredEvent(
            id: "event-2",
            deviceId: "multi-event-device",
            name: "Name at 10 days ago",
            lastSeenAt: tenDaysAgo,
            firstSeenAt: tenDaysAgo
        )

        let event3 = try createDeviceDiscoveredEvent(
            id: "event-3",
            deviceId: "multi-event-device",
            name: "Name at 1 day ago",
            lastSeenAt: oneDayAgo,
            firstSeenAt: tenDaysAgo
        )

        // Apply in random order (simulating out-of-order sync)
        try ProjectorService.apply(event: event2, context: context)  // oldest
        try ProjectorService.apply(event: event1, context: context)  // middle
        try ProjectorService.apply(event: event3, context: context)  // newest

        // Fetch the device
        let descriptor = FetchDescriptor<Device>()
        let devices = try context.fetch(descriptor)

        #expect(devices.count == 1)
        let device = devices.first!

        // Should have the most recent values
        #expect(abs(device.lastSeenAt.timeIntervalSince(oneDayAgo)) < 1)
        #expect(device.name == "Name at 1 day ago")
    }

    @Test("DeviceEventPayload correctly decodes timestamp milliseconds")
    func deviceEventPayloadDecodesTimestampMilliseconds() throws {
        // Test that the payload correctly handles millisecond timestamps
        let specificTime = Date(timeIntervalSince1970: 1703721600)  // 2023-12-28 00:00:00 UTC
        let timestampMs = Int64(specificTime.timeIntervalSince1970 * 1000)

        let payloadDict: [String: Any] = [
            "id": "test-id",
            "deviceId": "test-device",
            "name": "Test Device",
            "model": "TestModel",
            "osName": "iOS",
            "osVersion": "18.0",
            "isDevice": true,
            "isCurrentDevice": false,
            "lastSeenAt": timestampMs,
            "firstSeenAt": timestampMs
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict)
        let decoded = try JSONDecoder().decode(DeviceEventPayload.self, from: payloadData)

        #expect(decoded.lastSeenAt == timestampMs)
        #expect(decoded.firstSeenAt == timestampMs)

        // Convert back to Date and verify
        let convertedDate = Date(timeIntervalSince1970: Double(decoded.lastSeenAt) / 1000.0)
        #expect(abs(convertedDate.timeIntervalSince(specificTime)) < 1)
    }
}
