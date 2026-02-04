//
//  DeviceServiceTests.swift
//  DequeueTests
//
//  Tests for DeviceService
//

import XCTest
import SwiftData
@testable import Dequeue

@MainActor
final class DeviceServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var service: DeviceService!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory container for testing
        let schema = Schema([
            Device.self,
            Stack.self,
            QueueTask.self,
            Tag.self,
            Arc.self,
            Reminder.self,
            Attachment.self,
            Event.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        service = DeviceService.shared

        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: "com.dequeue.deviceId")
        UserDefaults.standard.removeObject(forKey: "com.dequeue.deviceDiscovered")
    }

    override func tearDown() async throws {
        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: "com.dequeue.deviceId")
        UserDefaults.standard.removeObject(forKey: "com.dequeue.deviceDiscovered")

        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Device ID Tests

    func testGetDeviceIdGeneratesNewIdWhenNoneExists() async throws {
        let deviceId = await service.getDeviceId()

        XCTAssertFalse(deviceId.isEmpty, "Device ID should not be empty")
        XCTAssertNotNil(UUID(uuidString: deviceId), "Device ID should be a valid UUID")
    }

    func testGetDeviceIdReturnsSameIdOnSubsequentCalls() async throws {
        let firstId = await service.getDeviceId()
        let secondId = await service.getDeviceId()

        XCTAssertEqual(firstId, secondId, "Device ID should be consistent across calls")
    }

    func testGetDeviceIdReturnsStoredIdFromUserDefaults() async throws {
        let storedId = UUID().uuidString
        UserDefaults.standard.set(storedId, forKey: "com.dequeue.deviceId")

        let deviceId = await service.getDeviceId()

        XCTAssertEqual(deviceId, storedId, "Should return stored device ID")
    }

    func testResetDeviceIdGeneratesNewId() async throws {
        let originalId = await service.getDeviceId()
        let newId = await service.resetDeviceId()

        XCTAssertNotEqual(originalId, newId, "Reset should generate a new device ID")
        XCTAssertNotNil(UUID(uuidString: newId), "New ID should be a valid UUID")

        let retrievedId = await service.getDeviceId()
        XCTAssertEqual(newId, retrievedId, "New ID should persist")
    }

    func testResetDeviceIdClearsDiscoveryFlag() async throws {
        UserDefaults.standard.set(true, forKey: "com.dequeue.deviceDiscovered")

        _ = await service.resetDeviceId()

        let discoveryFlag = UserDefaults.standard.bool(forKey: "com.dequeue.deviceDiscovered")
        XCTAssertFalse(discoveryFlag, "Discovery flag should be reset")
    }

    // MARK: - Device Discovery Tests

    func testEnsureCurrentDeviceDiscoveredCreatesNewDevice() async throws {
        let userId = "test-user-123"

        try await service.ensureCurrentDeviceDiscovered(modelContext: context, userId: userId)

        let devices = try service.getDevices(modelContext: context)
        XCTAssertEqual(devices.count, 1, "Should create exactly one device")

        let device = devices[0]
        XCTAssertEqual(device.userId, userId, "Device should have correct user ID")
        XCTAssertTrue(device.isCurrentDevice, "Device should be marked as current device")
        XCTAssertFalse(device.isDeleted, "Device should not be deleted")
    }

    func testEnsureCurrentDeviceDiscoveredUpdatesExistingDevice() async throws {
        let userId = "test-user-123"
        let deviceId = await service.getDeviceId()

        // Create existing device
        let existingDevice = Device.createCurrentDevice()
        existingDevice.deviceId = deviceId
        existingDevice.userId = userId
        existingDevice.lastSeenAt = Date().addingTimeInterval(-3600) // 1 hour ago
        context.insert(existingDevice)
        try context.save()

        let oldLastSeen = existingDevice.lastSeenAt

        // Wait a moment to ensure time difference
        try await Task.sleep(for: .milliseconds(10))

        try await service.ensureCurrentDeviceDiscovered(modelContext: context, userId: userId)

        let devices = try service.getDevices(modelContext: context)
        XCTAssertEqual(devices.count, 1, "Should still have only one device")

        let device = devices[0]
        XCTAssertGreaterThan(device.lastSeenAt, oldLastSeen, "lastSeenAt should be updated")
    }

    // MARK: - Get Devices Tests

    func testGetDevicesReturnsOnlyNonDeletedDevices() async throws {
        let userId = "test-user-123"

        // Create active device
        let activeDevice = Device.createCurrentDevice()
        activeDevice.deviceId = UUID().uuidString
        activeDevice.userId = userId
        activeDevice.lastSeenAt = Date()
        context.insert(activeDevice)

        // Create deleted device
        let deletedDevice = Device.createCurrentDevice()
        deletedDevice.deviceId = UUID().uuidString
        deletedDevice.userId = userId
        deletedDevice.isDeleted = true
        context.insert(deletedDevice)

        try context.save()

        let devices = try service.getDevices(modelContext: context)

        XCTAssertEqual(devices.count, 1, "Should only return non-deleted devices")
        XCTAssertEqual(devices[0].deviceId, activeDevice.deviceId)
    }

    func testGetDevicesSortsByLastSeenDescending() async throws {
        let userId = "test-user-123"
        let now = Date()

        // Create devices with different lastSeenAt times
        let device1 = Device.createCurrentDevice()
        device1.deviceId = UUID().uuidString
        device1.userId = userId
        device1.lastSeenAt = now.addingTimeInterval(-3600) // 1 hour ago
        context.insert(device1)

        let device2 = Device.createCurrentDevice()
        device2.deviceId = UUID().uuidString
        device2.userId = userId
        device2.lastSeenAt = now // now (most recent)
        context.insert(device2)

        let device3 = Device.createCurrentDevice()
        device3.deviceId = UUID().uuidString
        device3.userId = userId
        device3.lastSeenAt = now.addingTimeInterval(-7200) // 2 hours ago
        context.insert(device3)

        try context.save()

        let devices = try service.getDevices(modelContext: context)

        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices[0].deviceId, device2.deviceId, "Most recent device should be first")
        XCTAssertEqual(devices[1].deviceId, device1.deviceId, "Second most recent should be second")
        XCTAssertEqual(devices[2].deviceId, device3.deviceId, "Oldest device should be last")
    }

    // MARK: - Get Current Device Tests

    func testGetCurrentDeviceReturnsNilWhenDeviceNotFound() async throws {
        let device = try await service.getCurrentDevice(modelContext: context)

        XCTAssertNil(device, "Should return nil when device doesn't exist")
    }

    func testGetCurrentDeviceReturnsMatchingDevice() async throws {
        let userId = "test-user-123"
        let deviceId = await service.getDeviceId()

        let currentDevice = Device.createCurrentDevice()
        currentDevice.deviceId = deviceId
        currentDevice.userId = userId
        context.insert(currentDevice)
        try context.save()

        let device = try await service.getCurrentDevice(modelContext: context)

        XCTAssertNotNil(device, "Should find current device")
        XCTAssertEqual(device?.deviceId, deviceId)
    }

    func testGetCurrentDeviceIgnoresDeletedDevice() async throws {
        let userId = "test-user-123"
        let deviceId = await service.getDeviceId()

        let deletedDevice = Device.createCurrentDevice()
        deletedDevice.deviceId = deviceId
        deletedDevice.userId = userId
        deletedDevice.isDeleted = true
        context.insert(deletedDevice)
        try context.save()

        let device = try await service.getCurrentDevice(modelContext: context)

        XCTAssertNil(device, "Should not return deleted device")
    }

    // MARK: - Device Activity Tests

    func testUpdateDeviceActivityUpdatesLastSeenAt() async throws {
        let userId = "test-user-123"
        let deviceId = await service.getDeviceId()

        // Create current device with old lastSeenAt
        let device = Device.createCurrentDevice()
        device.deviceId = deviceId
        device.userId = userId
        device.lastSeenAt = Date().addingTimeInterval(-3600) // 1 hour ago
        context.insert(device)
        try context.save()

        let oldLastSeen = device.lastSeenAt

        // Wait enough time to pass the throttle threshold
        try await Task.sleep(for: .milliseconds(10))

        try await service.updateDeviceActivity(modelContext: context)

        XCTAssertGreaterThan(device.lastSeenAt, oldLastSeen, "lastSeenAt should be updated")
        XCTAssertEqual(device.syncState, .pending, "Sync state should be pending")
    }

    func testUpdateDeviceActivityThrottlesFrequentUpdates() async throws {
        let userId = "test-user-123"
        let deviceId = await service.getDeviceId()

        // Create current device with recent lastSeenAt (within throttle window)
        let device = Device.createCurrentDevice()
        device.deviceId = deviceId
        device.userId = userId
        device.lastSeenAt = Date().addingTimeInterval(-30) // 30 seconds ago (< 1 min threshold)
        context.insert(device)
        try context.save()

        let oldLastSeen = device.lastSeenAt

        try await service.updateDeviceActivity(modelContext: context)

        XCTAssertEqual(device.lastSeenAt, oldLastSeen, "lastSeenAt should not be updated due to throttling")
    }

    func testUpdateDeviceActivityDoesNothingWhenDeviceNotFound() async throws {
        // No device exists, should not throw
        try await service.updateDeviceActivity(modelContext: context)

        // No assertion needed - test passes if no exception thrown
    }
}
