//
//  DeepLinkManager.swift
//  Dequeue
//
//  Manages deep link navigation from notifications (DEQ-211)
//

import Foundation
import SwiftData

// MARK: - Deep Link Destination

/// Represents a destination for deep link navigation
struct DeepLinkDestination: Equatable {
    let parentId: String
    let parentType: ParentType

    /// Creates a destination from notification userInfo
    init?(userInfo: [AnyHashable: Any]) {
        guard let parentId = userInfo[NotificationConstants.UserInfoKey.parentId] as? String,
              let parentTypeRaw = userInfo[NotificationConstants.UserInfoKey.parentType] as? String,
              let parentType = ParentType(rawValue: parentTypeRaw) else {
            return nil
        }
        self.parentId = parentId
        self.parentType = parentType
    }

    init(parentId: String, parentType: ParentType) {
        self.parentId = parentId
        self.parentType = parentType
    }
}

// MARK: - Deep Link Manager

/// Observable manager for deep link navigation state
@MainActor
@Observable
final class DeepLinkManager {
    /// The pending navigation destination from a notification tap
    var pendingDestination: DeepLinkDestination?

    /// Clears the pending destination after navigation completes
    func clearDestination() {
        pendingDestination = nil
    }

    /// Sets a pending destination for navigation
    func navigate(to destination: DeepLinkDestination) {
        pendingDestination = destination
    }

    /// Sets a pending destination from parentId and parentType
    func navigate(to parentId: String, parentType: ParentType) {
        pendingDestination = DeepLinkDestination(parentId: parentId, parentType: parentType)
    }
}

// MARK: - Notification for Deep Links

extension Notification.Name {
    /// Posted when a reminder notification is tapped and should trigger navigation
    static let reminderNotificationTapped = Notification.Name("com.dequeue.reminderNotificationTapped")
}

// MARK: - Environment Key

private struct DeepLinkManagerKey: EnvironmentKey {
    static let defaultValue: DeepLinkManager? = nil
}

extension EnvironmentValues {
    var deepLinkManager: DeepLinkManager? {
        get { self[DeepLinkManagerKey.self] }
        set { self[DeepLinkManagerKey.self] = newValue }
    }
}
