//
//  AttachmentSettings.swift
//  Dequeue
//
//  User preferences for attachment download and storage behavior
//

import Foundation
import SwiftUI

// MARK: - Download Behavior

/// Controls when attachments are automatically downloaded
enum AttachmentDownloadBehavior: String, CaseIterable, Codable {
    case onDemand = "on_demand"
    case wifiOnly = "wifi_only"
    case always = "always"

    var displayName: String {
        switch self {
        case .onDemand:
            return "On-demand only"
        case .wifiOnly:
            return "Auto-download on WiFi"
        case .always:
            return "Always auto-download"
        }
    }

    var description: String {
        switch self {
        case .onDemand:
            return "Files are only downloaded when you tap to view them"
        case .wifiOnly:
            return "Files are downloaded automatically when connected to WiFi"
        case .always:
            return "Files are downloaded automatically on any network"
        }
    }
}

// MARK: - Storage Quota

/// Maximum local storage for attachments
enum AttachmentStorageQuota: Int64, CaseIterable, Codable {
    case oneGB = 1_073_741_824       // 1 GB
    case fiveGB = 5_368_709_120      // 5 GB
    case tenGB = 10_737_418_240      // 10 GB
    case unlimited = 0               // 0 means unlimited

    var displayName: String {
        switch self {
        case .oneGB:
            return "1 GB"
        case .fiveGB:
            return "5 GB"
        case .tenGB:
            return "10 GB"
        case .unlimited:
            return "Unlimited"
        }
    }

    var bytes: Int64 {
        rawValue
    }

    /// Check if a given size would exceed this quota
    func wouldExceed(currentSize: Int64, addingSize: Int64) -> Bool {
        guard self != .unlimited else { return false }
        return (currentSize + addingSize) > rawValue
    }
}

// MARK: - Attachment Settings

/// User preferences for attachment handling
@Observable
final class AttachmentSettings {
    // MARK: - Keys

    private enum Keys {
        static let downloadBehavior = "attachmentDownloadBehavior"
        static let storageQuota = "attachmentStorageQuota"
        static let storageQuotaSet = "attachmentStorageQuotaSet"
    }

    // MARK: - Properties

    /// When to automatically download attachments
    var downloadBehavior: AttachmentDownloadBehavior {
        didSet {
            UserDefaults.standard.set(downloadBehavior.rawValue, forKey: Keys.downloadBehavior)
        }
    }

    /// Maximum local storage for attachments
    var storageQuota: AttachmentStorageQuota {
        didSet {
            UserDefaults.standard.set(storageQuota.rawValue, forKey: Keys.storageQuota)
            UserDefaults.standard.set(true, forKey: Keys.storageQuotaSet)
        }
    }

    // MARK: - Initialization

    init() {
        // Load download behavior
        if let savedBehavior = UserDefaults.standard.string(forKey: Keys.downloadBehavior),
           let behavior = AttachmentDownloadBehavior(rawValue: savedBehavior) {
            self.downloadBehavior = behavior
        } else {
            self.downloadBehavior = .onDemand
        }

        // Load storage quota
        if !UserDefaults.standard.bool(forKey: Keys.storageQuotaSet) {
            // Not set yet, use default
            self.storageQuota = .fiveGB
        } else {
            let savedQuota = UserDefaults.standard.integer(forKey: Keys.storageQuota)
            if let quota = AttachmentStorageQuota(rawValue: Int64(savedQuota)) {
                self.storageQuota = quota
            } else {
                self.storageQuota = .fiveGB
            }
        }
    }

    // MARK: - Methods

    /// Check if we should auto-download based on current network status
    func shouldAutoDownload(isOnWiFi: Bool) -> Bool {
        switch downloadBehavior {
        case .onDemand:
            return false
        case .wifiOnly:
            return isOnWiFi
        case .always:
            return true
        }
    }

    /// Check if adding a file would exceed quota
    func wouldExceedQuota(currentSize: Int64, addingSize: Int64) -> Bool {
        storageQuota.wouldExceed(currentSize: currentSize, addingSize: addingSize)
    }

    /// Reset to defaults
    func reset() {
        downloadBehavior = .onDemand
        storageQuota = .fiveGB
    }
}

// MARK: - Environment Key

private struct AttachmentSettingsKey: EnvironmentKey {
    static let defaultValue = AttachmentSettings()
}

extension EnvironmentValues {
    var attachmentSettings: AttachmentSettings {
        get { self[AttachmentSettingsKey.self] }
        set { self[AttachmentSettingsKey.self] = newValue }
    }
}
