//
//  AttachmentSettingsTests.swift
//  DequeueTests
//
//  Tests for AttachmentSettings model
//

import Testing
import Foundation
@testable import Dequeue

/// Creates an isolated UserDefaults instance for testing
/// Each call returns a fresh UserDefaults with no persisted data
private func makeTestDefaults() -> UserDefaults {
    let suiteName = "com.dequeue.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    // Clean up any lingering data (belt and suspenders)
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@Suite("AttachmentSettings Tests", .serialized)
@MainActor
struct AttachmentSettingsTests {
    // MARK: - Initialization Tests

    @Test("Default values on first launch")
    func defaultValuesOnFirstLaunch() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)

        #expect(settings.downloadBehavior == .onDemand)
        #expect(settings.storageQuota == .fiveGB)
    }

    // MARK: - Download Behavior Tests

    @Test("Download behavior persists across instances")
    func downloadBehaviorPersistence() {
        let defaults = makeTestDefaults()

        let settings1 = AttachmentSettings(defaults: defaults)
        settings1.downloadBehavior = .always

        let settings2 = AttachmentSettings(defaults: defaults)
        #expect(settings2.downloadBehavior == .always)
    }

    @Test("shouldAutoDownload on WiFi - onDemand")
    func shouldAutoDownloadOnDemandWifi() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.downloadBehavior = .onDemand

        #expect(!settings.shouldAutoDownload(isOnWiFi: true))
    }

    @Test("shouldAutoDownload on cellular - onDemand")
    func shouldAutoDownloadOnDemandCellular() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.downloadBehavior = .onDemand

        #expect(!settings.shouldAutoDownload(isOnWiFi: false))
    }

    @Test("shouldAutoDownload on WiFi - wifiOnly")
    func shouldAutoDownloadWifiOnlyWifi() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.downloadBehavior = .wifiOnly

        #expect(settings.shouldAutoDownload(isOnWiFi: true))
    }

    @Test("shouldAutoDownload on cellular - wifiOnly")
    func shouldAutoDownloadWifiOnlyCellular() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.downloadBehavior = .wifiOnly

        #expect(!settings.shouldAutoDownload(isOnWiFi: false))
    }

    @Test("shouldAutoDownload on WiFi - always")
    func shouldAutoDownloadAlwaysWifi() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.downloadBehavior = .always

        #expect(settings.shouldAutoDownload(isOnWiFi: true))
    }

    @Test("shouldAutoDownload on cellular - always")
    func shouldAutoDownloadAlwaysCellular() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.downloadBehavior = .always

        #expect(settings.shouldAutoDownload(isOnWiFi: false))
    }

    // MARK: - Storage Quota Tests

    @Test("Storage quota persists across instances")
    func storageQuotaPersistence() {
        let defaults = makeTestDefaults()

        let settings1 = AttachmentSettings(defaults: defaults)
        settings1.storageQuota = .tenGB

        let settings2 = AttachmentSettings(defaults: defaults)
        #expect(settings2.storageQuota == .tenGB)
    }

    @Test("Unlimited quota persists across instances")
    func unlimitedQuotaPersistence() {
        let defaults = makeTestDefaults()

        let settings1 = AttachmentSettings(defaults: defaults)
        settings1.storageQuota = .unlimited

        let settings2 = AttachmentSettings(defaults: defaults)
        #expect(settings2.storageQuota == .unlimited)
    }

    @Test("Unlimited quota never exceeds")
    func unlimitedQuotaNeverExceeds() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.storageQuota = .unlimited

        #expect(!settings.wouldExceedQuota(
            currentSize: 1_000_000_000_000,
            addingSize: 1_000_000_000_000
        ))
    }

    @Test("Storage quota boundary - just under limit")
    func storageQuotaBoundaryUnder() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.storageQuota = .fiveGB  // 5_368_709_120 bytes

        #expect(!settings.wouldExceedQuota(
            currentSize: 5_000_000_000,
            addingSize: 368_709_119
        ))
    }

    @Test("Storage quota boundary - at limit")
    func storageQuotaBoundaryAt() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.storageQuota = .fiveGB  // 5_368_709_120 bytes

        #expect(!settings.wouldExceedQuota(
            currentSize: 5_000_000_000,
            addingSize: 368_709_120
        ))
    }

    @Test("Storage quota boundary - just over limit")
    func storageQuotaBoundaryOver() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.storageQuota = .fiveGB  // 5_368_709_120 bytes

        #expect(settings.wouldExceedQuota(
            currentSize: 5_000_000_000,
            addingSize: 368_709_121
        ))
    }

    @Test("Storage quota wouldExceed - 1GB limit")
    func storageQuotaOneGB() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.storageQuota = .oneGB

        #expect(!settings.wouldExceedQuota(currentSize: 0, addingSize: 1_073_741_824))
        #expect(settings.wouldExceedQuota(currentSize: 0, addingSize: 1_073_741_825))
    }

    @Test("Storage quota wouldExceed - 10GB limit")
    func storageQuotaTenGB() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.storageQuota = .tenGB

        #expect(!settings.wouldExceedQuota(currentSize: 0, addingSize: 10_737_418_240))
        #expect(settings.wouldExceedQuota(currentSize: 0, addingSize: 10_737_418_241))
    }

    // MARK: - Reset Tests

    @Test("Reset returns to defaults")
    func resetReturnsToDefaults() {
        let defaults = makeTestDefaults()

        let settings = AttachmentSettings(defaults: defaults)
        settings.downloadBehavior = .always
        settings.storageQuota = .unlimited

        settings.reset()

        #expect(settings.downloadBehavior == .onDemand)
        #expect(settings.storageQuota == .fiveGB)
    }

    @Test("Reset persists to UserDefaults")
    func resetPersistsToUserDefaults() {
        let defaults = makeTestDefaults()

        let settings1 = AttachmentSettings(defaults: defaults)
        settings1.downloadBehavior = .always
        settings1.storageQuota = .unlimited
        settings1.reset()

        let settings2 = AttachmentSettings(defaults: defaults)
        #expect(settings2.downloadBehavior == .onDemand)
        #expect(settings2.storageQuota == .fiveGB)
    }

    // MARK: - Enum Tests

    @Test("AttachmentDownloadBehavior display names")
    func downloadBehaviorDisplayNames() {
        #expect(AttachmentDownloadBehavior.onDemand.displayName == "On Demand")
        #expect(AttachmentDownloadBehavior.wifiOnly.displayName == "WiFi Only")
        #expect(AttachmentDownloadBehavior.always.displayName == "Always")
    }

    @Test("AttachmentDownloadBehavior descriptions are not empty")
    func downloadBehaviorDescriptions() {
        #expect(!AttachmentDownloadBehavior.onDemand.description.isEmpty)
        #expect(!AttachmentDownloadBehavior.wifiOnly.description.isEmpty)
        #expect(!AttachmentDownloadBehavior.always.description.isEmpty)
    }

    @Test("AttachmentStorageQuota display names")
    func storageQuotaDisplayNames() {
        #expect(AttachmentStorageQuota.oneGB.displayName == "1 GB")
        #expect(AttachmentStorageQuota.fiveGB.displayName == "5 GB")
        #expect(AttachmentStorageQuota.tenGB.displayName == "10 GB")
        #expect(AttachmentStorageQuota.unlimited.displayName == "Unlimited")
    }

    @Test("AttachmentStorageQuota bytes values")
    func storageQuotaBytesValues() {
        #expect(AttachmentStorageQuota.oneGB.bytes == 1_073_741_824)
        #expect(AttachmentStorageQuota.fiveGB.bytes == 5_368_709_120)
        #expect(AttachmentStorageQuota.tenGB.bytes == 10_737_418_240)
        #expect(AttachmentStorageQuota.unlimited.bytes == 0)
    }

    @Test("AttachmentStorageQuota rawValue matches bytes")
    func storageQuotaRawValue() {
        #expect(AttachmentStorageQuota.oneGB.rawValue == AttachmentStorageQuota.oneGB.bytes)
        #expect(AttachmentStorageQuota.fiveGB.rawValue == AttachmentStorageQuota.fiveGB.bytes)
        #expect(AttachmentStorageQuota.tenGB.rawValue == AttachmentStorageQuota.tenGB.bytes)
        #expect(AttachmentStorageQuota.unlimited.rawValue == 0)
    }

    // MARK: - Edge Case Tests

    @Test("Multiple settings instances share same UserDefaults")
    func multipleInstancesShareStorage() {
        let defaults = makeTestDefaults()

        let settings1 = AttachmentSettings(defaults: defaults)
        _ = AttachmentSettings(defaults: defaults)

        settings1.downloadBehavior = .always
        settings1.storageQuota = .unlimited

        // Create a new instance - should read from the same UserDefaults
        let settings3 = AttachmentSettings(defaults: defaults)
        #expect(settings3.downloadBehavior == .always)
        #expect(settings3.storageQuota == .unlimited)
    }

    @Test("Zero size never exceeds any quota")
    func zeroSizeNeverExceeds() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)

        settings.storageQuota = .oneGB
        #expect(!settings.wouldExceedQuota(currentSize: 0, addingSize: 0))

        settings.storageQuota = .unlimited
        #expect(!settings.wouldExceedQuota(currentSize: 0, addingSize: 0))
    }

    @Test("Large current size with small addition exceeds")
    func largeCurrentSizeExceeds() {
        let defaults = makeTestDefaults()
        let settings = AttachmentSettings(defaults: defaults)
        settings.storageQuota = .oneGB

        #expect(settings.wouldExceedQuota(
            currentSize: 1_073_741_823,
            addingSize: 2
        ))
    }
}
