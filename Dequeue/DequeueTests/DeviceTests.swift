//
//  DeviceTests.swift
//  DequeueTests
//
//  Tests for Device model
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
    @MainActor
    func createCurrentDeviceReturnsValidDevice() {
        let device = Device.createCurrentDevice()

        #expect(!device.deviceId.isEmpty)
        #expect(!device.name.isEmpty)
        #expect(!device.osName.isEmpty)
        #expect(device.isCurrentDevice == true)
    }
}
