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

    /// App-level cold-launch hook. Best-effort attempt to register for
    /// remote notifications when the user is already signed in.
    ///
    /// `@UIApplicationDelegateAdaptor` does NOT guarantee that the SwiftUI
    /// `App.init()` (which wires `AppContext`) completes before this delegate
    /// callback fires. In practice the guard often hits a nil `pushService`
    /// and silently no-ops on cold launch. That's intentional and harmless:
    /// both the sign-in completion path (`handleAuthStateChange`) and the
    /// foreground-active path (`refreshTokenIfStale`) call
    /// `registerIfSignedIn` again, covering the registration regardless of
    /// init ordering. We keep the call here as belt-and-suspenders for warm
    /// launches where `AppContext` is already wired.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
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
        // `userInfo` is `[AnyHashable: Any]` which is not Sendable. Extract
        // the Sendable values we need (reminder_id, sent_at) before the
        // `Task { @MainActor }` boundary so we satisfy Swift 6 strict
        // concurrency cleanly without leaking Any across actors.
        let reminderId = (userInfo[NotificationConstants.UserInfoKey.remoteReminderId] as? String)
            ?? (userInfo[NotificationConstants.UserInfoKey.reminderId] as? String)
        // APNs serialises JSON numbers as `NSNumber`. Per CLAUDE.md the wire
        // value is Unix milliseconds; coerce via `NSNumber.int64Value` so we
        // never lose precision regardless of whether iOS hands us an Int,
        // Double, or NSNumber under the hood.
        let sentAtMs: Int64? = (userInfo[NotificationConstants.UserInfoKey.remoteSentAtMs] as? NSNumber)?.int64Value
        let payload = SilentPushPayload(reminderId: reminderId, sentAtMs: sentAtMs)

        // Apple terminates the app if the completion handler is never called.
        // Wrap delivery in a one-shot guard so any path — success, early-
        // return, or task cancellation — still fires the callback exactly
        // once. The guard is captured by reference via a class wrapper so the
        // defer in the Task can see mutations.
        let completion = OneShotCompletion(handler: completionHandler)
        Task { @MainActor in
            defer { completion.callIfNeeded(.noData) }
            guard let push = AppContext.shared.pushService else {
                completion.callIfNeeded(.noData)
                return
            }
            let result = await push.handleSilentPush(payload: payload)
            switch result {
            case .newData: completion.callIfNeeded(.newData)
            case .noData: completion.callIfNeeded(.noData)
            case .failed: completion.callIfNeeded(.failed)
            }
        }
    }
}

/// Tiny class wrapper that ensures a `UIBackgroundFetchResult` completion
/// handler is invoked exactly once, even if the surrounding Task is cancelled
/// or returns via multiple paths. Apple terminates the app if the handler
/// never fires, so this is belt-and-suspenders for the silent-push wake.
private final class OneShotCompletion: @unchecked Sendable {
    private let handler: (UIBackgroundFetchResult) -> Void
    private var fired = false
    private let lock = NSLock()

    init(handler: @escaping (UIBackgroundFetchResult) -> Void) {
        self.handler = handler
    }

    func callIfNeeded(_ result: UIBackgroundFetchResult) {
        lock.lock()
        if fired {
            lock.unlock()
            return
        }
        fired = true
        lock.unlock()
        handler(result)
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
