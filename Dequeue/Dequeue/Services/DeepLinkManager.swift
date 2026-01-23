//
//  DeepLinkManager.swift
//  Dequeue
//
//  Manages deep link navigation from notifications (DEQ-211)
//

import Foundation

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
}

// MARK: - Notification for Deep Links

extension Notification.Name {
    /// Posted when a reminder notification is tapped and should trigger navigation
    static let reminderNotificationTapped = Notification.Name("com.dequeue.reminderNotificationTapped")
}
