//
//  PushNotificationService.swift
//  Dequeue
//
//  APNs device-token registration + remote-push dedup bookkeeping for the
//  reminder delivery pipeline (DEQ-283, parent DEQ-276).
//
//  Responsibilities:
//   • POST /v1/devices/push-token on launch + auth state change + 7d stale.
//   • DELETE /v1/devices/push-token on sign-out (across all three teardown paths).
//   • Track recently-arrived remote reminderIds in a 60s NSCache so the
//     `UNUserNotificationCenterDelegate` can suppress redundant local fires.
//   • Emit structured Sentry breadcrumbs for every interesting transition.
//
//  All persistent state (cached token, last-registered timestamp) lives under
//  the `dequeue.push.*` UserDefaults namespace so it survives app relaunch
//  but is wiped on app uninstall along with everything else.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import os.log
import Sentry

// MARK: - PushNotificationServiceProtocol

/// Protocol surface used by AppDelegate, AuthService teardown, and tests.
@MainActor
protocol PushNotificationServiceProtocol: AnyObject, Sendable {
    /// Cached device token (hex string), if registered with APNs.
    var cachedDeviceToken: String? { get }

    /// Apple-callback entry: stash the raw token, then POST to the API.
    /// Idempotent — subsequent calls with the same token re-POST to refresh
    /// `last_seen_at` on the server.
    func handleAPNsTokenRegistered(_ tokenData: Data) async

    /// Apple-callback entry: failed registration. Telemetry only.
    func handleAPNsRegistrationFailed(_ error: Error)

    /// Called when the user has just signed in. Triggers
    /// `registerForRemoteNotifications` on the main thread and (once the token
    /// arrives) the upload to the API.
    func registerIfSignedIn() async

    /// Called on app foregrounding. Re-POSTs the cached token if `last_registered_at`
    /// is older than 7 days, otherwise no-op.
    func refreshTokenIfStale() async

    /// Called on every sign-out path. DELETEs the device-id from the API and
    /// clears local push state. Idempotent.
    func deregisterOnSignOut() async

    // MARK: Dedup bookkeeping

    /// Mark a remote-delivered reminderId as recently seen (in-memory, 60s TTL).
    /// `nonisolated` so the `UNUserNotificationCenter` delegate can call this
    /// from its `nonisolated async` callback without an actor hop.
    nonisolated func markRemoteDelivered(reminderId: String)

    /// Whether a remote push for this reminderId arrived within the last 60s.
    /// `nonisolated` so the `UNUserNotificationCenter` delegate can call this
    /// from its `nonisolated async` callback without an actor hop.
    nonisolated func isRemoteRecentlyDelivered(reminderId: String) -> Bool

    // MARK: Background sync entry

    /// Called by `application:didReceiveRemoteNotification:fetchCompletionHandler:`.
    /// Kicks off REST-only sync with a 20s hard deadline. Returns the appropriate
    /// `UIBackgroundFetchResult` for the silent-push completion handler.
    ///
    /// `SilentPushPayload` is Sendable; the AppDelegate extracts it from the
    /// non-Sendable `[AnyHashable: Any]` userInfo dictionary before crossing
    /// the actor boundary.
    func handleSilentPush(payload: SilentPushPayload) async -> SilentPushResult
}

/// Sendable extract of the fields we care about from an APNs userInfo
/// dictionary. AppDelegate extracts these before crossing the Task boundary
/// so we don't carry `Any` across actors (Swift 6 strict concurrency).
struct SilentPushPayload: Sendable, Equatable {
    let reminderId: String?
    /// Backend-provided dispatch timestamp in Unix **milliseconds**. Modelled
    /// as `Int64` to match the project-wide CLAUDE.md timestamp convention.
    /// Conversion to `Date` happens internally inside `handleSilentPush` by
    /// dividing by 1_000.0 to land on a Double for `TimeInterval`.
    let sentAtMs: Int64?
}

/// Mirror of `UIBackgroundFetchResult` so cross-platform code can model the
/// outcome without importing UIKit (tests run on macOS too).
enum SilentPushResult: Sendable, Equatable {
    case newData
    case noData
    case failed
}

// MARK: - Constants

private enum PushDefaults {
    nonisolated static let cachedToken = "dequeue.push.cachedToken"
    nonisolated static let lastRegisteredAt = "dequeue.push.lastRegisteredAt"
    /// Stale window after which we re-POST the cached token on foregrounding.
    nonisolated static let staleInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    /// In-memory dedup window for remote-delivered reminderIds.
    nonisolated static let dedupWindow: TimeInterval = 60
    /// Hard cap on the silent-push REST sync. Apple gives BG fetch ~30s; we
    /// leave ourselves 10s of head room so we always call the completion
    /// handler before the system kills us.
    nonisolated static let silentPushSyncTimeout: TimeInterval = 20
    nonisolated static let registerEndpointPath = "/devices/push-token"
}

// MARK: - Wire bodies

/// Wire shape for `POST /v1/devices/push-token`. Mirrors the request struct
/// shipped in dequeue-api#200 (`DeviceTokenRequest`). Encodable so the body
/// stays type-safe end-to-end — per CLAUDE.md no `[String: Any]` in service
/// code.
private struct DeviceTokenRegistrationBody: Encodable, Sendable {
    let deviceId: String
    let token: String
    let platform: String
    let environment: String
    let bundleId: String
    let appVersion: String
}

// MARK: - PushNotificationService

@MainActor
final class PushNotificationService: PushNotificationServiceProtocol {
    static let shared = PushNotificationService()

    // Dependencies — overridable for tests via the designated init.
    private let urlSession: URLSession
    private let userDefaults: UserDefaults
    private let baseURLProvider: @MainActor () -> URL
    private let tokenProvider: @MainActor () async throws -> String
    private let deviceIdProvider: @Sendable () async -> String
    private let isAuthenticatedProvider: @MainActor () -> Bool
    private let now: @Sendable () -> Date

    /// In-memory cache of `reminderId -> Date` for remote pushes that landed
    /// within the dedup window. NSCache is intentionally `nonisolated(unsafe)`
    /// because UNUserNotificationCenter delegate callbacks are
    /// `nonisolated async` and need a way to read this state without an
    /// actor hop (NSCache is documented thread-safe).
    nonisolated(unsafe) private let recentRemotes = NSCache<NSString, NSDate>()

    /// Optional override for the live SyncManager. When nil we resolve via
    /// `AppContext.shared.syncManager` at call time. The protocol-level type
    /// erasure is intentional — tests inject a stub conforming to
    /// `SilentPushSyncing` without dragging in the full SyncManager surface.
    private let silentPushSyncer: SilentPushSyncing?

    /// Silent-push REST sync timeout. Production uses `PushDefaults.silentPushSyncTimeout`
    /// (20s); tests inject a much smaller value to keep the timeout path fast.
    private let silentPushSyncTimeout: TimeInterval

    private(set) var cachedDeviceToken: String?

    /// Designated init. Defaults wire production paths; tests use this same
    /// init with their own URLSession / providers.
    init(
        urlSession: URLSession = .shared,
        userDefaults: UserDefaults = .standard,
        baseURLProvider: (@MainActor () -> URL)? = nil,
        tokenProvider: (@MainActor () async throws -> String)? = nil,
        deviceIdProvider: (@Sendable () async -> String)? = nil,
        isAuthenticatedProvider: (@MainActor () -> Bool)? = nil,
        silentPushSyncer: SilentPushSyncing? = nil,
        silentPushSyncTimeout: TimeInterval = PushDefaults.silentPushSyncTimeout,
        now: (@Sendable () -> Date)? = nil
    ) {
        // Resolve defaults inside the init so the closure literals don't need
        // to capture @MainActor state at the parameter-default position
        // (Swift 6 doesn't allow actor-isolated default values for non-isolated
        // parameters and is unhappy with mixed isolation defaults).
        let resolvedBaseURL: @MainActor () -> URL = baseURLProvider ?? { Configuration.dequeueAPIBaseURL }
        let resolvedTokenProvider: @MainActor () async throws -> String = tokenProvider ?? {
            guard let authService = AppContext.shared.authService else {
                throw AuthError.notAuthenticated
            }
            return try await authService.getAuthToken()
        }
        let resolvedDeviceIdProvider: @Sendable () async -> String =
            deviceIdProvider ?? { await DeviceService.shared.getDeviceId() }
        let resolvedIsAuthenticated: @MainActor () -> Bool =
            isAuthenticatedProvider ?? { AppContext.shared.authService?.isAuthenticated ?? false }
        let resolvedNow: @Sendable () -> Date = now ?? { Date() }
        self.urlSession = urlSession
        self.userDefaults = userDefaults
        self.baseURLProvider = resolvedBaseURL
        self.tokenProvider = resolvedTokenProvider
        self.deviceIdProvider = resolvedDeviceIdProvider
        self.isAuthenticatedProvider = resolvedIsAuthenticated
        self.silentPushSyncer = silentPushSyncer
        self.silentPushSyncTimeout = silentPushSyncTimeout
        self.now = resolvedNow
        self.cachedDeviceToken = userDefaults.string(forKey: PushDefaults.cachedToken)
        // Keep the dedup cache modest — we only need the last few seconds of
        // pushes. 256 entries is well past any plausible burst.
        recentRemotes.countLimit = 256
    }

    // MARK: - Public API

    func handleAPNsTokenRegistered(_ tokenData: Data) async {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        cachedDeviceToken = hex
        userDefaults.set(hex, forKey: PushDefaults.cachedToken)

        ErrorReportingService.addBreadcrumb(
            category: "push",
            message: "APNs token received",
            data: ["token_prefix": String(hex.prefix(8))]
        )

        // POST to API — fire-and-forget retry loop. We don't block the main
        // thread on the callback; the OS only cares that we received the
        // token, not that the server has acknowledged it.
        await postDeviceToken(hex)
    }

    func handleAPNsRegistrationFailed(_ error: Error) {
        ErrorReportingService.addBreadcrumb(
            category: "push",
            message: "APNs registration failed",
            level: .warning,
            data: ["error": error.localizedDescription]
        )
        ErrorReportingService.capture(
            error: error,
            context: ["source": "apns_registration"]
        )
    }

    func registerIfSignedIn() async {
        guard isAuthenticatedProvider() else {
            ErrorReportingService.addBreadcrumb(
                category: "push",
                message: "Skip APNs registration: not authenticated"
            )
            return
        }

        // Apple's `registerForRemoteNotifications` is itself idempotent and
        // it's intended to be called freely on launch / re-auth / etc., so we
        // don't need a local re-entrancy guard here. The OS will only emit
        // one `didRegisterForRemoteNotifications...` callback per provisioning
        // attempt.
        #if canImport(UIKit) && os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        ErrorReportingService.addBreadcrumb(
            category: "push",
            message: "Requested registerForRemoteNotifications"
        )
        #else
        ErrorReportingService.addBreadcrumb(
            category: "push",
            message: "registerForRemoteNotifications skipped (non-iOS platform)"
        )
        #endif
    }

    func refreshTokenIfStale() async {
        guard isAuthenticatedProvider() else { return }
        guard let token = cachedDeviceToken else {
            // No cached token yet; force a fresh register pass.
            await registerIfSignedIn()
            return
        }
        let lastRegistered = userDefaults.object(forKey: PushDefaults.lastRegisteredAt) as? Date
        let isStale: Bool = {
            guard let lastRegistered else { return true }
            return now().timeIntervalSince(lastRegistered) > PushDefaults.staleInterval
        }()
        guard isStale else { return }

        ErrorReportingService.addBreadcrumb(
            category: "push",
            message: "Device token stale, re-registering",
            data: [
                "age_days": Int((now().timeIntervalSince(lastRegistered ?? .distantPast)) / 86_400)
            ]
        )
        await postDeviceToken(token)
    }

    func deregisterOnSignOut() async {
        // Clear local state up front so a concurrent re-register can't see
        // stale-token bookkeeping.
        let token = cachedDeviceToken
        cachedDeviceToken = nil
        userDefaults.removeObject(forKey: PushDefaults.cachedToken)
        userDefaults.removeObject(forKey: PushDefaults.lastRegisteredAt)
        recentRemotes.removeAllObjects()

        guard token != nil else {
            // Nothing to deregister server-side.
            ErrorReportingService.addBreadcrumb(
                category: "push",
                message: "Sign-out: no cached token to deregister"
            )
            return
        }

        let deviceId = await deviceIdProvider()
        let baseURL = baseURLProvider()
        let url = baseURL.appendingPathComponent(PushDefaults.registerEndpointPath)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }
        components.queryItems = [URLQueryItem(name: "deviceId", value: deviceId)]
        guard let deleteURL = components.url else { return }

        var request = URLRequest(url: deleteURL)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10
        // Best-effort token fetch — if it fails we still emit telemetry and
        // bail. The next launch will not be able to re-target this device
        // record from the API side, but the server-side reconciler will reap
        // stale tokens via APNs 410s.
        let authToken: String
        do {
            authToken = try await tokenProvider()
        } catch {
            ErrorReportingService.addBreadcrumb(
                category: "push",
                message: "device_token_deregister: token fetch failed",
                level: .warning,
                data: ["error": error.localizedDescription]
            )
            return
        }
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            ErrorReportingService.addBreadcrumb(
                category: "push",
                message: "device_token_deregistered",
                data: ["status": status]
            )
        } catch {
            ErrorReportingService.addBreadcrumb(
                category: "push",
                message: "device_token_deregister network failure",
                level: .warning,
                data: ["error": error.localizedDescription]
            )
        }
    }

    // MARK: - Dedup bookkeeping

    nonisolated func markRemoteDelivered(reminderId: String) {
        let key = reminderId as NSString
        recentRemotes.setObject(now() as NSDate, forKey: key)
    }

    nonisolated func isRemoteRecentlyDelivered(reminderId: String) -> Bool {
        let key = reminderId as NSString
        guard let date = recentRemotes.object(forKey: key) as Date? else { return false }
        let elapsed = now().timeIntervalSince(date)
        if elapsed > PushDefaults.dedupWindow {
            recentRemotes.removeObject(forKey: key)
            return false
        }
        return true
    }

    // MARK: - Silent push handler

    func handleSilentPush(payload: SilentPushPayload) async -> SilentPushResult {
        let reminderId = payload.reminderId
        // `sentAtMs` carries Unix **milliseconds** per the project-wide
        // CLAUDE.md convention (matches the dequeue-api wire format). Convert
        // to a Date by dividing into seconds-since-epoch; parsing it as
        // seconds directly would yield a Date ~50,000 years in the future
        // and a wildly negative ageMs.
        let sentAt = payload.sentAtMs.map { Date(timeIntervalSince1970: Double($0) / 1_000.0) }
        let ageMs: Int? = sentAt.map { Int(now().timeIntervalSince($0) * 1_000) }

        // Mark this reminder as remote-delivered so the foreground willPresent
        // delegate can suppress the local twin if it lands within 60s.
        if let reminderId {
            markRemoteDelivered(reminderId: reminderId)
        }

        ErrorReportingService.addBreadcrumb(
            category: "push",
            message: "reminder_push_received",
            data: [
                "reminderId": reminderId ?? "<missing>",
                "ageMs": ageMs ?? -1
            ]
        )

        let syncStart = now()
        let result = await runSilentPushSync(timeout: silentPushSyncTimeout)
        let durationMs = Int(now().timeIntervalSince(syncStart) * 1_000)

        switch result {
        case .success(let fetchedCount):
            ErrorReportingService.addBreadcrumb(
                category: "push",
                message: "reminder_push_sync_completed",
                data: ["durationMs": durationMs, "fetchedCount": fetchedCount]
            )
            return fetchedCount > 0 ? .newData : .noData
        case .failure(let kind):
            ErrorReportingService.addBreadcrumb(
                category: "push",
                message: "reminder_push_sync_failed",
                level: .warning,
                data: ["durationMs": durationMs, "errorKind": kind]
            )
            return .failed
        }
    }

    // MARK: - Internal: POST device token

    /// Posts the cached token to the device-registration endpoint. Retries
    /// once on transient 5xx; permanent failures become telemetry breadcrumbs
    /// (we never block the OS callback on this).
    private func postDeviceToken(_ token: String) async {
        let deviceId = await deviceIdProvider()
        let baseURL = baseURLProvider()
        let url = baseURL.appendingPathComponent(PushDefaults.registerEndpointPath)

        let environment: String = {
            #if DEBUG
            return "development"
            #else
            return "production"
            #endif
        }()

        let platform: String = {
            #if os(macOS)
            return "macos"
            #else
            return "ios"
            #endif
        }()

        let body = DeviceTokenRegistrationBody(
            deviceId: deviceId,
            token: token,
            platform: platform,
            environment: environment,
            bundleId: Configuration.bundleIdentifier,
            appVersion: Configuration.appVersion
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // JSONEncoder can only throw `EncodingError`, which is unreachable for
        // an all-`String` Encodable. We still surface a defensive telemetry
        // breadcrumb if Swift surprises us.
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            ErrorReportingService.addBreadcrumb(
                category: "push",
                message: "device_token_register_failed",
                level: .warning,
                data: ["errorKind": "serialization"]
            )
            return
        }

        let authToken: String
        do {
            authToken = try await tokenProvider()
        } catch {
            ErrorReportingService.addBreadcrumb(
                category: "push",
                message: "device_token_register_failed",
                level: .warning,
                data: ["errorKind": "token_unavailable", "error": error.localizedDescription]
            )
            return
        }
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        // One retry on transient 5xx.
        for attempt in 1...2 {
            let outcome = await attemptPost(request: request)
            switch outcome {
            case .success(let status):
                userDefaults.set(now(), forKey: PushDefaults.lastRegisteredAt)
                ErrorReportingService.addBreadcrumb(
                    category: "push",
                    message: "device_token_registered",
                    data: ["status": status, "attempt": attempt]
                )
                return
            case let .retryable(status, error):
                if attempt < 2 {
                    ErrorReportingService.addBreadcrumb(
                        category: "push",
                        message: "device_token_register transient failure, retrying",
                        level: .warning,
                        data: [
                            "status": status,
                            "error": error?.localizedDescription ?? "",
                            "attempt": attempt
                        ]
                    )
                    // Don't swallow cancellation — if the enclosing task got
                    // cancelled (e.g. sign-out racing a pending retry), break
                    // out of the loop cleanly instead of issuing a doomed
                    // second POST against torn-down credentials.
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000)
                    } catch {
                        return
                    }
                    if Task.isCancelled { return }
                    continue
                }
                ErrorReportingService.addBreadcrumb(
                    category: "push",
                    message: "device_token_register_failed",
                    level: .warning,
                    data: [
                        "errorKind": "transient_5xx",
                        "status": status,
                        "error": error?.localizedDescription ?? "",
                        "attempt": attempt
                    ]
                )
            case let .permanent(status, error):
                ErrorReportingService.addBreadcrumb(
                    category: "push",
                    message: "device_token_register_failed",
                    level: .warning,
                    data: [
                        "errorKind": "permanent",
                        "status": status,
                        "error": error?.localizedDescription ?? ""
                    ]
                )
                return
            }
        }
    }

    private enum PostOutcome {
        case success(status: Int)
        case retryable(status: Int, error: Error?)
        case permanent(status: Int, error: Error?)
    }

    private func attemptPost(request: URLRequest) async -> PostOutcome {
        do {
            let (_, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            switch status {
            case 200...299:
                return .success(status: status)
            case 500...599:
                return .retryable(status: status, error: nil)
            default:
                return .permanent(status: status, error: nil)
            }
        } catch {
            // URLSession transport error — treat as retryable on first attempt.
            return .retryable(status: -1, error: error)
        }
    }

    // MARK: - Internal: silent-push REST sync

    /// Internal outcome enum for the silent-push REST sync. Callers go
    /// through `handleSilentPush` (which maps to `SilentPushResult`); tests
    /// assert on `SilentPushResult` only.
    private enum SilentSyncOutcome: Sendable, Equatable {
        case success(fetchedCount: Int)
        case failure(kind: String)
    }

    /// Kicks off a single REST-only projection sync via the injected
    /// `silentPushSyncer` (or the live `SyncManager` resolved through the app
    /// environment when no override is provided). We intentionally do NOT
    /// establish a WebSocket — TCP handshake + WebSocket upgrade is slower
    /// than the 20s silent-push budget, and Apple kills the process if we
    /// miss it.
    ///
    /// Returns `.failure(kind: "timeout")` if the sync exceeds the supplied
    /// deadline; `.failure(kind: "unavailable")` if the app context hasn't
    /// been wired yet (e.g. very early launch race).
    ///
    /// Private — callers should go through `handleSilentPush` which uses the
    /// `silentPushSyncTimeout` injected at init. Tests inject a tiny timeout
    /// via that init parameter rather than reaching in here directly.
    private func runSilentPushSync(timeout: TimeInterval) async -> SilentSyncOutcome {
        let syncer: SilentPushSyncing? = silentPushSyncer
            ?? AppContext.shared.syncManager.map(SyncManagerSilentPushAdapter.init)
        guard let syncer else {
            return .failure(kind: "unavailable")
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        let result: SilentSyncOutcome
        do {
            result = try await withThrowingTaskGroup(of: SilentSyncOutcome.self) { group in
                group.addTask {
                    do {
                        try await syncer.runRESTProjectionSync()
                        // We surface `fetchedCount: 1` so `handleSilentPush`
                        // maps to `UIBackgroundFetchResult.newData`. Returning
                        // `.noData` here would over time deprioritise the
                        // app's silent-push wake budget, and the projection
                        // sync API does not yet return a per-call fetched
                        // count. Refining this to a true fetched-count
                        // (and emitting `.noData` when zero events were
                        // applied) is the follow-up tracked in DEQ-284
                        // (delivery-reconciliation telemetry).
                        return .success(fetchedCount: 1)
                    } catch {
                        return .failure(kind: "sync_error")
                    }
                }
                group.addTask {
                    try? await Task.sleep(until: deadline, clock: ContinuousClock())
                    return .failure(kind: "timeout")
                }
                guard let first = try await group.next() else {
                    return .failure(kind: "empty")
                }
                group.cancelAll()
                return first
            }
        } catch {
            return .failure(kind: "task_group_error")
        }
        return result
    }
}

// MARK: - Silent-push sync abstraction

/// Minimal protocol the silent-push handler relies on. Decouples
/// `PushNotificationService` from the full `SyncManager` surface so tests
/// can supply a fake without staging the entire sync stack.
protocol SilentPushSyncing: Sendable {
    func runRESTProjectionSync() async throws
}

/// Production adapter that bridges `SyncManager.syncViaProjections()` to the
/// silent-push protocol. Sendable because `SyncManager` is itself an actor.
struct SyncManagerSilentPushAdapter: SilentPushSyncing {
    let syncManager: SyncManager
    func runRESTProjectionSync() async throws {
        try await syncManager.syncViaProjections()
    }
}
