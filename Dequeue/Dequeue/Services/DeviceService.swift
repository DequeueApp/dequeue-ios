//
//  DeviceService.swift
//  Dequeue
//
//  Manages device identification and discovery for sync
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "DeviceService")

actor DeviceService {
    static let shared = DeviceService()

    private let deviceIdKey = "com.dequeue.deviceId"
    private let deviceDiscoveredKey = "com.dequeue.deviceDiscovered"
    private var cachedDeviceId: String?

    private init() {}

    // MARK: - Device ID

    func getDeviceId() async -> String {
        if let cached = cachedDeviceId {
            return cached
        }

        if let stored = UserDefaults.standard.string(forKey: deviceIdKey) {
            cachedDeviceId = stored
            return stored
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        cachedDeviceId = newId
        return newId
    }

    func resetDeviceId() async -> String {
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        cachedDeviceId = newId
        // Reset discovery flag so device will be re-registered
        UserDefaults.standard.set(false, forKey: deviceDiscoveredKey)
        return newId
    }

    // MARK: - Device Discovery

    /// Ensures the current device is registered in the database and device.discovered event is recorded.
    /// Should be called once after successful authentication.
    @MainActor
    func ensureCurrentDeviceDiscovered(modelContext: ModelContext, userId: String) async throws {
        let deviceId = await getDeviceId()

        // Check if device already exists in database
        let predicate = #Predicate<Device> { device in
            device.deviceId == deviceId && device.isDeleted == false
        }
        let descriptor = FetchDescriptor<Device>(predicate: predicate)
        let existingDevices = try modelContext.fetch(descriptor)

        if let existingDevice = existingDevices.first {
            // Device exists - update lastSeenAt
            existingDevice.lastSeenAt = Date()
            existingDevice.userId = userId
            try modelContext.save()
            logger.info("Device already registered, updated lastSeenAt: \(deviceId)")
            return
        }

        // Device not found - create it and emit discovery event
        let device = Device.createCurrentDevice()
        device.deviceId = deviceId  // Use our consistent device ID
        device.userId = userId
        device.isCurrentDevice = true

        modelContext.insert(device)

        // Record the discovery event
        let eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        try eventService.recordDeviceDiscovered(device)

        logger.info("Device discovered and registered: \(deviceId) - \(device.name)")
    }

    /// Get all known devices for the current user
    @MainActor
    func getDevices(modelContext: ModelContext) throws -> [Device] {
        let predicate = #Predicate<Device> { device in
            device.isDeleted == false
        }
        let descriptor = FetchDescriptor<Device>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Get only the current device
    @MainActor
    func getCurrentDevice(modelContext: ModelContext) async throws -> Device? {
        let deviceId = await getDeviceId()
        let predicate = #Predicate<Device> { device in
            device.deviceId == deviceId && device.isDeleted == false
        }
        let descriptor = FetchDescriptor<Device>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Device Activity

    /// Minimum interval between activity updates to avoid excessive events
    private static let activityUpdateThreshold: TimeInterval = 60  // 1 minute

    /// Updates the current device's lastSeenAt and emits a device.discovered event
    /// so other devices learn about the activity. Throttled to avoid excessive events.
    @MainActor
    func updateDeviceActivity(modelContext: ModelContext) async throws {
        guard let device = try await getCurrentDevice(modelContext: modelContext) else {
            logger.warning("Cannot update device activity: device not found")
            return
        }

        // Throttle: only update if more than 1 minute has passed
        let timeSinceLastSeen = Date().timeIntervalSince(device.lastSeenAt)
        guard timeSinceLastSeen >= Self.activityUpdateThreshold else {
            logger.debug("Skipping activity update: only \(Int(timeSinceLastSeen))s since last update")
            return
        }

        // Update lastSeenAt
        device.lastSeenAt = Date()
        device.syncState = .pending

        // Emit device.discovered event so other devices learn about the activity
        let eventService = EventService(
            modelContext: modelContext,
            userId: device.userId ?? "",
            deviceId: device.deviceId
        )
        try eventService.recordDeviceDiscovered(device)

        try modelContext.save()
        logger.info("Device activity updated: \(device.deviceId)")
    }
}
