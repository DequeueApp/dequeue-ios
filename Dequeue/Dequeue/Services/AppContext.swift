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

/// Minimal global registry so background callbacks (AppDelegate, push
/// handlers, UNUserNotification delegate) can reach the live `SyncManager`,
/// `AuthService`, and `PushNotificationService` without threading them through
/// every UIKit shim.
///
/// Set during `DequeueApp.init()` after services are constructed.
@MainActor
final class AppContext {
    static let shared = AppContext()

    private(set) var syncManager: SyncManager?
    private(set) var authService: (any AuthServiceProtocol)?
    private(set) var pushService: (any PushNotificationServiceProtocol)?

    private init() {}

    func configure(
        syncManager: SyncManager,
        authService: any AuthServiceProtocol,
        pushService: any PushNotificationServiceProtocol
    ) {
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
