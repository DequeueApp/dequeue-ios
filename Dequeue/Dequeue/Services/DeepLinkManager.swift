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
    ///   - dequeue://action/{action-name} (Quick Actions)
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
            // Unknown or generic routes (home, stats, actions) — no specific destination
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

// MARK: - Quick Action Deep Link

/// Represents an action-based deep link (no specific item navigation)
enum DeepLinkAction: String {
    case addTask = "add-task"
    case activeStack = "active-stack"
    case search = "search"
    case newStack = "new-stack"
}

extension Notification.Name {
    /// Posted when an action deep link is triggered (Quick Actions, etc.)
    static let deepLinkActionTriggered = Notification.Name("com.dequeue.deepLinkActionTriggered")
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
    /// Also handles action-based URLs (dequeue://action/{action}).
    /// Call from `.onOpenURL` in the root view.
    static func handleURL(_ url: URL) {
        // Check for action-based deep links first (dequeue://action/{action})
        let host = url.host() ?? url.host
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if host == "action", let actionName = pathComponents.first,
           let action = DeepLinkAction(rawValue: actionName) {
            NotificationCenter.default.post(
                name: .deepLinkActionTriggered,
                object: nil,
                userInfo: ["action": action]
            )
            return
        }

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
