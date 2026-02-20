//
//  Device.swift
//  Dequeue
//
//  Tracks connected devices for multi-device sync
//

import Foundation
import SwiftData

@Model
final class Device {
    @Attribute(.unique) var id: String
    var deviceId: String
    var stableDeviceId: String?
    var name: String
    var model: String?
    var osName: String
    var osVersion: String?
    var isDevice: Bool
    var isCurrentDevice: Bool
    var lastSeenAt: Date
    var firstSeenAt: Date
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    // Sync fields
    var userId: String?
    var syncState: SyncState
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int

    init(
        id: String = CUID.generate(),
        deviceId: String,
        stableDeviceId: String? = nil,
        name: String,
        model: String? = nil,
        osName: String,
        osVersion: String? = nil,
        isDevice: Bool = true,
        isCurrentDevice: Bool = false,
        lastSeenAt: Date = Date(),
        firstSeenAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        userId: String? = nil,
        syncState: SyncState = .pending,
        lastSyncedAt: Date? = nil,
        serverId: String? = nil,
        revision: Int = 1
    ) {
        self.id = id
        self.deviceId = deviceId
        self.stableDeviceId = stableDeviceId
        self.name = name
        self.model = model
        self.osName = osName
        self.osVersion = osVersion
        self.isDevice = isDevice
        self.isCurrentDevice = isCurrentDevice
        self.lastSeenAt = lastSeenAt
        self.firstSeenAt = firstSeenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.userId = userId
        self.syncState = syncState
        self.lastSyncedAt = lastSyncedAt
        self.serverId = serverId
        self.revision = revision
    }
}

// MARK: - Current Device Helper

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Device {
    @MainActor
    static func createCurrentDevice() -> Device {
        #if os(iOS)
        let device = UIDevice.current
        return Device(
            deviceId: device.identifierForVendor?.uuidString ?? UUID().uuidString,
            name: device.name,
            model: device.model,
            osName: device.systemName,
            osVersion: device.systemVersion,
            isDevice: !isSimulator,
            isCurrentDevice: true
        )
        #elseif os(macOS)
        return Device(
            deviceId: getMacDeviceId(),
            name: Host.current().localizedName ?? "Mac",
            model: getMacModel(),
            osName: "macOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            isDevice: true,
            isCurrentDevice: true
        )
        #else
        return Device(
            deviceId: UUID().uuidString,
            name: "Unknown Device",
            osName: "Unknown",
            isCurrentDevice: true
        )
        #endif
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    #if os(macOS)
    private static func getMacDeviceId() -> String {
        // Use IOKit to get hardware UUID
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        guard platformExpert != 0 else {
            return UUID().uuidString
        }

        defer { IOObjectRelease(platformExpert) }

        if let serialNumber = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String {
            return serialNumber
        }

        return UUID().uuidString
    }

    private static func getMacModel() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let bytes = model.prefix(while: { $0 != 0 }).map { UInt8($0) }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }
    #endif
}
