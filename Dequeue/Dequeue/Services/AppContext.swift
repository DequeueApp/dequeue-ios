//
//  AppContext.swift
//  Dequeue
//
//  Minimal global registry that bridges UIKit / AppDelegate / UNUserNotification
//  delegate callbacks to the live SwiftUI-owned services. Set during
//  `DequeueApp.init()` after services are constructed.
//
//  Kept deliberately small: no business logic, no observable state, no
//  initialisation order surprises. Callers always treat the properties as
//  optional and bail safely when they're nil (e.g. very early launch race or
//  test environment that hasn't wired AppContext).
//

import Foundation
import os.log

/// Minimal global registry so background callbacks (AppDelegate, push
/// handlers, UNUserNotification delegate) can reach the live `SyncManager`,
/// `AuthService`, and `PushNotificationService` without threading them through
/// every UIKit shim.
///
/// Set during `DequeueApp.init()` after services are constructed.
@MainActor
final class AppContext {
    static let shared = AppContext()

    private static let logger = Logger(subsystem: "com.dequeue", category: "AppContext")

    private(set) var syncManager: SyncManager?
    private(set) var authService: (any AuthServiceProtocol)?
    private(set) var pushService: (any PushNotificationServiceProtocol)?

    private init() {}

    /// Configure the registry exactly once during `DequeueApp.init()`. A
    /// second call (e.g. a misconfigured test path that re-instantiates the
    /// app without calling `resetForTesting()` first) logs a warning so the
    /// silent-overwrite bug class is visible in os.log instead of producing
    /// confusing service-locator stale-reference symptoms downstream.
    func configure(
        syncManager: SyncManager,
        authService: any AuthServiceProtocol,
        pushService: any PushNotificationServiceProtocol
    ) {
        if self.syncManager != nil {
            Self.logger.warning("""
                AppContext.configure called twice; overwriting prior services. \
                This is usually a test-environment misconfiguration.
                """)
        }
        self.syncManager = syncManager
        self.authService = authService
        self.pushService = pushService
    }

    /// Test-only reset hook.
    #if DEBUG
    func resetForTesting() {
        syncManager = nil
        authService = nil
        pushService = nil
    }
    #endif
}
