//
//  ProjectorServiceDeviceTests.swift
//  DequeueTests
//
//  Tests for ProjectorService device event projection:
//  - deviceDiscovered: creates/updates Device entities
//  - updateDeviceLastSeenFromEvent: updates lastSeenAt for all events from known devices
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("ProjectorService Device Events", .serialized)
@MainActor
struct ProjectorServiceDeviceTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self,
            SyncConflict.self, Tag.self, Device.self, Arc.self, Attachment.self,
            configurations: config
        )
    }

    private func makeDevicePayload(
        id: String,
        deviceId: String,
        name: String,
        model: String? = "iPhone 15",
        osName: String = "iOS",
        osVersion: String? = "18.0",
        isDevice: Bool = true,
        isCurrentDevice: Bool = false
    ) throws -> Data {
        var dict: [String: Any] = [
            "id": id,
            "deviceId": deviceId,
            "name": name,
            "osName": osName,
            "isDevice": isDevice,
            "isCurrentDevice": isCurrentDevice,
            "lastSeenAt": Int64(Date().timeIntervalSince1970 * 1000),
            "firstSeenAt": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let model { dict["model"] = model }
        if let osVersion { dict["osVersion"] = osVersion }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func makeTaskPayload(id: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": id,
            "title": "Test Task",
            "status": "pending",
            "sortOrder": 0,
            "deleted": false,
            "isRecurring": false
        ] as [String: Any])
    }

    // MARK: - deviceDiscovered: Creates New Device

    @Test("deviceDiscovered: creates new Device entity with correct fields")
    func createsNewDevice() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let deviceId = CUID.generate()
        let entityId = CUID.generate()
        let eventTime = Date(timeIntervalSince1970: 1_700_000_000)

        let payload = try makeDevicePayload(
            id: entityId,
            deviceId: deviceId,
            name: "Victor's iPhone",
            model: "iPhone 15 Pro",
            osName: "iOS",
            osVersion: "18.1"
        )
        let event = Event(
            eventType: .deviceDiscovered,
            payload: payload,
            timestamp: eventTime,
            entityId: entityId,
            userId: "u", deviceId: deviceId, appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Device> { $0.deviceId == deviceId }
        let devices = try context.fetch(FetchDescriptor<Device>(predicate: predicate))
        #expect(devices.count == 1)

        let device = try #require(devices.first)
        #expect(device.id == entityId)
        #expect(device.deviceId == deviceId)
        #expect(device.name == "Victor's iPhone")
        #expect(device.model == "iPhone 15 Pro")
        #expect(device.osName == "iOS")
        #expect(device.osVersion == "18.1")
        #expect(device.isDevice == true)
    }

    @Test("deviceDiscovered: uses event.timestamp for lastSeenAt and firstSeenAt")
    func usesEventTimestampForDates() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let deviceId = CUID.generate()
        let entityId = CUID.generate()
        let eventTime = Date(timeIntervalSince1970: 1_700_000_000)

        let payload = try makeDevicePayload(id: entityId, deviceId: deviceId, name: "Test Device")
        let event = Event(
            eventType: .deviceDiscovered,
            payload: payload,
            timestamp: eventTime,
            entityId: entityId,
            userId: "u", deviceId: deviceId, appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Device> { $0.deviceId == deviceId }
        let device = try #require(
            try context.fetch(FetchDescriptor<Device>(predicate: predicate)).first
        )
        #expect(device.lastSeenAt == eventTime)
        #expect(device.firstSeenAt == eventTime)
    }

    @Test("deviceDiscovered: sets isCurrentDevice to false (other device)")
    func setsIsCurrentDeviceFalse() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let deviceId = CUID.generate()
        let entityId = CUID.generate()
        let payload = try makeDevicePayload(
            id: entityId, deviceId: deviceId, name: "Other iPhone",
            isCurrentDevice: true  // payload says true, but projector should override to false
        )
        let event = Event(
            eventType: .deviceDiscovered, payload: payload,
            entityId: entityId, userId: "u", deviceId: deviceId, appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Device> { $0.deviceId == deviceId }
        let device = try #require(
            try context.fetch(FetchDescriptor<Device>(predicate: predicate)).first
        )
        // ProjectorService always sets isCurrentDevice = false — this is another device
        #expect(device.isCurrentDevice == false)
    }

    @Test("deviceDiscovered: sets syncState to .synced on new device")
    func setsSyncStateSynced() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let deviceId = CUID.generate()
        let entityId = CUID.generate()
        let payload = try makeDevicePayload(id: entityId, deviceId: deviceId, name: "Device A")
        let event = Event(
            eventType: .deviceDiscovered, payload: payload,
            entityId: entityId, userId: "u", deviceId: deviceId, appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Device> { $0.deviceId == deviceId }
        let device = try #require(
            try context.fetch(FetchDescriptor<Device>(predicate: predicate)).first
        )
        #expect(device.syncState == .synced)
    }

    // MARK: - deviceDiscovered: Updates Existing Device

    @Test("deviceDiscovered: updates existing device name, model, and OS fields")
    func updatesExistingDevice() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let deviceId = CUID.generate()
        let entityId = CUID.generate()

        // Pre-insert device with old data
        let existing = Device(
            id: entityId,
            deviceId: deviceId,
            name: "Old Name",
            model: "iPhone 13",
            osName: "iOS",
            osVersion: "16.0",
            syncState: .pending
        )
        context.insert(existing)
        try context.save()

        // Now process a deviceDiscovered with updated info
        let eventTime = Date(timeIntervalSince1970: 1_710_000_000)
        let payload = try makeDevicePayload(
            id: entityId,
            deviceId: deviceId,
            name: "New Name",
            model: "iPhone 15",
            osName: "iOS",
            osVersion: "18.1"
        )
        let event = Event(
            eventType: .deviceDiscovered, payload: payload,
            timestamp: eventTime,
            entityId: entityId, userId: "u", deviceId: deviceId, appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        // Should still be only one device entity
        let predicate = #Predicate<Device> { $0.deviceId == deviceId }
        let devices = try context.fetch(FetchDescriptor<Device>(predicate: predicate))
        #expect(devices.count == 1)

        let device = try #require(devices.first)
        #expect(device.name == "New Name")
        #expect(device.model == "iPhone 15")
        #expect(device.osVersion == "18.1")
    }

    @Test("deviceDiscovered: updates lastSeenAt to event.timestamp on existing device")
    func updatesLastSeenAtOnExisting() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let deviceId = CUID.generate()
        let entityId = CUID.generate()
        let oldTime = Date(timeIntervalSince1970: 1_700_000_000)
        let newTime = Date(timeIntervalSince1970: 1_710_000_000)

        let existing = Device(
            id: entityId, deviceId: deviceId, name: "My Device",
            osName: "iOS", lastSeenAt: oldTime
        )
        context.insert(existing)
        try context.save()

        let payload = try makeDevicePayload(id: entityId, deviceId: deviceId, name: "My Device")
        let event = Event(
            eventType: .deviceDiscovered, payload: payload,
            timestamp: newTime,
            entityId: entityId, userId: "u", deviceId: deviceId, appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Device> { $0.deviceId == deviceId }
        let device = try #require(
            try context.fetch(FetchDescriptor<Device>(predicate: predicate)).first
        )
        #expect(device.lastSeenAt == newTime)
    }

    @Test("deviceDiscovered: sets syncState to .synced on existing device")
    func setsSyncSyncedOnExisting() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let deviceId = CUID.generate()
        let entityId = CUID.generate()
        let existing = Device(
            id: entityId, deviceId: deviceId, name: "My Device",
            osName: "iOS", syncState: .pending
        )
        context.insert(existing)
        try context.save()

        let payload = try makeDevicePayload(id: entityId, deviceId: deviceId, name: "My Device")
        let event = Event(
            eventType: .deviceDiscovered, payload: payload,
            entityId: entityId, userId: "u", deviceId: deviceId, appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Device> { $0.deviceId == deviceId }
        let device = try #require(
            try context.fetch(FetchDescriptor<Device>(predicate: predicate)).first
        )
        #expect(device.syncState == .synced)
    }

    @Test("deviceDiscovered: duplicate events do not create duplicate Device entities")
    func noDuplicateDevices() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let deviceId = CUID.generate()
        let entityId = CUID.generate()
        let payload = try makeDevicePayload(id: entityId, deviceId: deviceId, name: "Phone")

        // Apply the same event twice
        let event1 = Event(
            eventType: .deviceDiscovered, payload: payload,
            entityId: entityId, userId: "u", deviceId: deviceId, appId: "a"
        )
        context.insert(event1)
        try await ProjectorService.apply(event: event1, context: context)

        let event2 = Event(
            eventType: .deviceDiscovered, payload: payload,
            entityId: entityId, userId: "u", deviceId: deviceId, appId: "a"
        )
        context.insert(event2)
        try await ProjectorService.apply(event: event2, context: context)

        let predicate = #Predicate<Device> { $0.deviceId == deviceId }
        let devices = try context.fetch(FetchDescriptor<Device>(predicate: predicate))
        #expect(devices.count == 1)
    }

    // MARK: - updateDeviceLastSeenFromEvent (DEQ-236)

    @Test("DEQ-236: non-device events update lastSeenAt for known device")
    func nonDeviceEventsUpdateLastSeen() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let otherDeviceId = "device-other-123"
        let deviceEntityId = CUID.generate()
        let oldTime = Date(timeIntervalSince1970: 1_700_000_000)
        let newTime = Date(timeIntervalSince1970: 1_710_000_000)

        // Register the device in the database
        let device = Device(
            id: deviceEntityId, deviceId: otherDeviceId, name: "Other Device",
            osName: "iOS", lastSeenAt: oldTime
        )
        context.insert(device)
        try context.save()

        // Process a task event from that device with a newer timestamp
        let taskId = CUID.generate()
        let taskPayload = try makeTaskPayload(id: taskId)
        let event = Event(
            eventType: .taskCreated,
            payload: taskPayload,
            timestamp: newTime,
            entityId: taskId,
            userId: "u", deviceId: otherDeviceId, appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Device> { $0.deviceId == otherDeviceId }
        let updatedDevice = try #require(
            try context.fetch(FetchDescriptor<Device>(predicate: predicate)).first
        )
        #expect(updatedDevice.lastSeenAt == newTime)
    }

    @Test("DEQ-236: lastSeenAt is not updated when event is older than current lastSeenAt")
    func noUpdateWhenEventIsOlder() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let otherDeviceId = "device-older-456"
        let deviceEntityId = CUID.generate()
        let recentTime = Date(timeIntervalSince1970: 1_710_000_000)
        let olderTime = Date(timeIntervalSince1970: 1_700_000_000)

        // Register device with recent lastSeenAt
        let device = Device(
            id: deviceEntityId, deviceId: otherDeviceId, name: "Device",
            osName: "iOS", lastSeenAt: recentTime
        )
        context.insert(device)
        try context.save()

        // Process an older event from the same device
        let taskId = CUID.generate()
        let taskPayload = try makeTaskPayload(id: taskId)
        let event = Event(
            eventType: .taskCreated,
            payload: taskPayload,
            timestamp: olderTime,  // older than device.lastSeenAt
            entityId: taskId,
            userId: "u", deviceId: otherDeviceId, appId: "a"
        )
        context.insert(event)

        try await ProjectorService.apply(event: event, context: context)

        let predicate = #Predicate<Device> { $0.deviceId == otherDeviceId }
        let updatedDevice = try #require(
            try context.fetch(FetchDescriptor<Device>(predicate: predicate)).first
        )
        // lastSeenAt should remain unchanged — event was older
        #expect(updatedDevice.lastSeenAt == recentTime)
    }

    @Test("DEQ-236: no-op when event originates from unknown device")
    func noOpForUnknownDevice() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Don't register any device — the function should silently skip
        let taskId = CUID.generate()
        let taskPayload = try makeTaskPayload(id: taskId)
        let event = Event(
            eventType: .taskCreated,
            payload: taskPayload,
            entityId: taskId,
            userId: "u", deviceId: "unknown-device-xyz", appId: "a"
        )
        context.insert(event)

        // Should not throw or create any Device entities
        try await ProjectorService.apply(event: event, context: context)

        let allDevices = try context.fetch(FetchDescriptor<Device>())
        #expect(allDevices.isEmpty)
    }
}
