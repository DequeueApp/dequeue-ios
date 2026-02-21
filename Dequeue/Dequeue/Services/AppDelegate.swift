//
//  AppDelegate.swift
//  Dequeue
//
//  UIKit App Delegate for handling system callbacks that require UIApplicationDelegate,
//  such as home screen Quick Actions (3D Touch / Haptic Touch shortcuts).
//

#if os(iOS)
import UIKit
import os.log

final class DequeueAppDelegate: NSObject, UIApplicationDelegate {
    /// Called when the app is launched via a quick action (cold launch).
    /// For warm launches, `windowScene(_:performActionFor:)` is called instead.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Check if launched from a quick action
        if let shortcutItem = options.shortcutItem {
            QuickActionService.shared.handleShortcutItem(shortcutItem)
        }

        let config = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = DequeueSceneDelegate.self
        return config
    }
}

/// Scene delegate for handling quick actions on warm launch
final class DequeueSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Called when a quick action is triggered while the app is running (warm launch).
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = QuickActionService.shared.handleShortcutItem(shortcutItem)
        completionHandler(handled)
    }
}
#endif
