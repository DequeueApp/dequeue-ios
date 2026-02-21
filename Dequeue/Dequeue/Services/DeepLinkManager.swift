//
//  DeepLinkManager.swift
//  Dequeue
//
//  Manages deep link navigation from notifications, widgets, and Spotlight (DEQ-211)
//

import Foundation
import CoreSpotlight

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

    /// Creates a destination from a dequeue:// URL
    /// Supports:
    ///   - dequeue://stack/{id}
    ///   - dequeue://task/{id}
    ///   - dequeue://arc/{id}
    ///   - dequeue://stats
    ///   - dequeue://home
    init?(url: URL) {
        guard url.scheme == "dequeue" else { return nil }
        let host = url.host() ?? url.host
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        // Handle dequeue://stack/{id}
        if host == "stack", let id = pathComponents.first {
            self.parentId = id
            self.parentType = .stack
        } else if host == "task", let id = pathComponents.first {
            self.parentId = id
            self.parentType = .task
        } else if host == "arc", let id = pathComponents.first {
            self.parentId = id
            self.parentType = .arc
        } else {
            // Unknown or generic routes (home, stats) — no specific destination
            return nil
        }
    }

    /// Creates a destination from a Spotlight user activity
    init?(userActivity: NSUserActivity) {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let url = URL(string: identifier) else {
            return nil
        }
        self.init(url: url)
    }
}

// MARK: - Notification for Deep Links

extension Notification.Name {
    /// Posted when a reminder notification is tapped and should trigger navigation
    static let reminderNotificationTapped = Notification.Name("com.dequeue.reminderNotificationTapped")

    /// Posted when a deep link URL is opened (widgets, Spotlight, Shortcuts)
    static let deepLinkOpened = Notification.Name("com.dequeue.deepLinkOpened")
}

// MARK: - Deep Link Manager

/// Centralized handler for processing deep link URLs from any source
enum DeepLinkManager {
    /// User info key for the DeepLinkDestination
    static let destinationKey = "destination"

    /// Process a dequeue:// URL and post a navigation notification if it resolves to a destination.
    /// Call from `.onOpenURL` in the root view.
    static func handleURL(_ url: URL) {
        guard let destination = DeepLinkDestination(url: url) else { return }
        NotificationCenter.default.post(
            name: .deepLinkOpened,
            object: nil,
            userInfo: [destinationKey: destination]
        )
    }

    /// Process a Spotlight continuation user activity.
    /// Call from `.onContinueUserActivity(CSSearchableItemActionType)` in the root view.
    static func handleSpotlight(_ userActivity: NSUserActivity) {
        guard let destination = DeepLinkDestination(userActivity: userActivity) else { return }
        NotificationCenter.default.post(
            name: .deepLinkOpened,
            object: nil,
            userInfo: [destinationKey: destination]
        )
    }
}
