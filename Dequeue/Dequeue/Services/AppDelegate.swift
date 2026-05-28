//
//  AppDelegate.swift
//  Dequeue
//
//  UIKit App Delegate for handling system callbacks that require UIApplicationDelegate:
//   • Home screen quick actions (3D Touch / Haptic Touch shortcuts).
//   • APNs remote-notification registration and silent push delivery (DEQ-283).
//

#if os(iOS)
import UIKit
import os.log

final class DequeueAppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "com.dequeue", category: "AppDelegate")

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

    /// App-level cold-launch hook. We register for remote notifications only
    /// when the user is already signed in — registering at launch when not
    /// signed in is a UX antipattern (prompts the user for push perms before
    /// they've even seen the app) and the device token would be useless to the
    /// backend without a Clerk user to attach it to. The sign-in completion
    /// path handles first-time registration via `PushNotificationService`.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            // AppContext is wired during DequeueApp.init() which runs before
            // this delegate method. The guard is defensive: if a future change
            // moves wiring later, we'd rather skip than crash.
            guard let push = AppContext.shared.pushService else { return }
            await push.registerIfSignedIn()
        }
        return true
    }

    // MARK: - APNs registration callbacks

    /// Apple-callback: device token successfully provisioned by the OS.
    /// We hand the raw bytes to `PushNotificationService` which hex-encodes,
    /// caches, and uploads to the API.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            guard let push = AppContext.shared.pushService else { return }
            await push.handleAPNsTokenRegistered(deviceToken)
        }
    }

    /// Apple-callback: OS failed to provision a token (e.g. user denied perms,
    /// network unavailable). Telemetry only — Apple will call us again the
    /// next time we ask.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            guard let push = AppContext.shared.pushService else { return }
            push.handleAPNsRegistrationFailed(error)
        }
    }

    /// Apple-callback: silent / background push arrived.
    ///
    /// Per the reminder-delivery design, this is the pre-wake path: at
    /// `remindAt - 30s` the backend sends a `content-available: 1` push
    /// carrying the reminderId; we run a REST-only projection sync (no
    /// WebSocket — too slow to establish in BG) and call the completion
    /// handler with `.newData` / `.noData` / `.failed`. The 20s hard timeout
    /// lives in `PushNotificationService.handleSilentPush`.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            guard let push = AppContext.shared.pushService else {
                completionHandler(.noData)
                return
            }
            let result = await push.handleSilentPush(userInfo: userInfo)
            switch result {
            case .newData: completionHandler(.newData)
            case .noData: completionHandler(.noData)
            case .failed: completionHandler(.failed)
            }
        }
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
