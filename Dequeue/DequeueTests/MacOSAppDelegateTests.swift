//
//  MacOSAppDelegateTests.swift
//  DequeueTests
//
//  Unit tests for the macOS NSApplicationDelegate shim (DEQ-285).
//  Tests are guarded by `#if os(macOS)` and only exercise the macOS-specific
//  delta from the shared PushNotificationService logic:
//
//   • Payload extraction from `[String: Any]` (macOS userInfo type).
//   • Forwarding to PushNotificationService without a fetchCompletionHandler.
//   • applicationDidFinishLaunching delegates to registerIfSignedIn.
//   • didRegisterForRemoteNotifications / didFail forwarding.
//
//  Shared sync logic (handleSilentPush paths, dedup, token register) is
//  already exercised on macOS by PushNotificationServiceTests which build
//  and run under the macOS destination.
//

#if os(macOS)
import AppKit
import Testing
import Foundation
@testable import Dequeue

// MARK: - Spy push-notification service

/// Records calls to `PushNotificationServiceProtocol` methods so the
/// AppDelegate tests can assert on forwarding behaviour without spinning up
/// the full push-notification stack.
@MainActor
final class SpyPushNotificationService: PushNotificationServiceProtocol, @unchecked Sendable {
    // MARK: Protocol surface
    private(set) var cachedDeviceToken: String?

    // MARK: Call recording
    private(set) var registerIfSignedInCallCount = 0
    private(set) var refreshTokenIfStaleCallCount = 0
    private(set) var deregisterOnSignOutCallCount = 0
    private(set) var handleAPNsTokenRegisteredCalls: [Data] = []
    private(set) var handleAPNsRegistrationFailedErrors: [Error] = []
    private(set) var handleSilentPushPayloads: [SilentPushPayload] = []

    /// Configurable result for `handleSilentPush`; defaults to `.newData`.
    var stubbedSilentPushResult: SilentPushResult = .newData

    // MARK: Thread-safe nonisolated bookkeeping
    nonisolated(unsafe) private var _markedRemoteIds: [String] = []
    nonisolated(unsafe) private var _isRecentlyDelivered = false
    private let lock = NSLock()

    // MARK: Protocol conformance

    func handleAPNsTokenRegistered(_ tokenData: Data) async {
        handleAPNsTokenRegisteredCalls.append(tokenData)
        cachedDeviceToken = tokenData.map { String(format: "%02x", $0) }.joined()
    }

    func handleAPNsRegistrationFailed(_ error: Error) {
        handleAPNsRegistrationFailedErrors.append(error)
    }

    func registerIfSignedIn() async {
        registerIfSignedInCallCount += 1
    }

    func refreshTokenIfStale() async {
        refreshTokenIfStaleCallCount += 1
    }

    func deregisterOnSignOut() async {
        deregisterOnSignOutCallCount += 1
    }

    nonisolated func markRemoteDelivered(reminderId: String) {
        lock.lock(); defer { lock.unlock() }
        _markedRemoteIds.append(reminderId)
    }

    nonisolated func isRemoteRecentlyDelivered(reminderId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRecentlyDelivered
    }

    func handleSilentPush(payload: SilentPushPayload) async -> SilentPushResult {
        handleSilentPushPayloads.append(payload)
        return stubbedSilentPushResult
    }
}

// MARK: - Tests

@Suite("macOS AppDelegate (DEQ-285)", .serialized)
@MainActor
struct MacOSAppDelegateTests {

    // MARK: - Test lifecycle helpers

    /// Wire AppContext with a fresh spy; return both the delegate and the spy.
    /// Callers are responsible for tearing down by calling `cleanup()`.
    func makeDelegate() -> (DequeueAppDelegate, SpyPushNotificationService) {
        AppContext.shared.resetForTesting()
        let spy = SpyPushNotificationService()
        AppContext.shared.setPushServiceForTesting(spy)
        return (DequeueAppDelegate(), spy)
    }

    func cleanup() {
        AppContext.shared.resetForTesting()
    }

    // MARK: - applicationDidFinishLaunching

    @Test("applicationDidFinishLaunching calls registerIfSignedIn")
    func applicationDidFinishLaunchingRegisters() async throws {
        let (delegate, spy) = makeDelegate()
        defer { cleanup() }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // Delegate spawns a Task; yield to let it land.
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms
        #expect(spy.registerIfSignedInCallCount == 1)
    }

    @Test("applicationDidFinishLaunching no-ops when pushService is nil")
    func applicationDidFinishLaunchingNoOpWhenNilService() async throws {
        AppContext.shared.resetForTesting() // no pushService wired
        defer { cleanup() }

        let delegate = DequeueAppDelegate()
        // Must not crash
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await Task.sleep(nanoseconds: 50_000_000)
        // No assertion needed beyond "does not crash"
    }

    // MARK: - didRegisterForRemoteNotificationsWithDeviceToken

    @Test("didRegisterForRemoteNotificationsWithDeviceToken forwards token data")
    func didRegisterForwardsToken() async throws {
        let (delegate, spy) = makeDelegate()
        defer { cleanup() }

        let tokenBytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        let tokenData = Data(tokenBytes)
        delegate.application(NSApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: tokenData)

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(spy.handleAPNsTokenRegisteredCalls.count == 1)
        #expect(spy.handleAPNsTokenRegisteredCalls.first == tokenData)
    }

    @Test("didRegisterForRemoteNotificationsWithDeviceToken no-ops when service is nil")
    func didRegisterNoOpWhenNilService() async throws {
        AppContext.shared.resetForTesting()
        defer { cleanup() }

        let delegate = DequeueAppDelegate()
        let tokenData = Data([0x01, 0x02])
        // Must not crash
        delegate.application(NSApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: tokenData)
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    // MARK: - didFailToRegisterForRemoteNotificationsWithError

    @Test("didFailToRegisterForRemoteNotificationsWithError forwards error")
    func didFailForwardsError() async throws {
        let (delegate, spy) = makeDelegate()
        defer { cleanup() }

        struct FakeAPNsError: Error {}
        let error = FakeAPNsError()
        delegate.application(NSApplication.shared, didFailToRegisterForRemoteNotificationsWithError: error)

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(spy.handleAPNsRegistrationFailedErrors.count == 1)
    }

    // MARK: - didReceiveRemoteNotification (macOS silent push)

    @Test("didReceiveRemoteNotification extracts reminder_id and sent_at correctly")
    func didReceiveRemoteNotificationExtracts() async throws {
        let (delegate, spy) = makeDelegate()
        defer { cleanup() }

        let userInfo: [String: Any] = [
            "reminder_id": "rem-abc123",
            "sent_at": NSNumber(value: Int64(1_700_000_000_000))
        ]
        delegate.application(NSApplication.shared, didReceiveRemoteNotification: userInfo)

        try await Task.sleep(nanoseconds: 100_000_000) // 100 ms for Task + sync
        #expect(spy.handleSilentPushPayloads.count == 1)
        let payload = try #require(spy.handleSilentPushPayloads.first)
        #expect(payload.reminderId == "rem-abc123")
        #expect(payload.sentAtMs == 1_700_000_000_000)
    }

    @Test("didReceiveRemoteNotification falls back to camelCase reminderId key")
    func didReceiveRemoteNotificationFallsBackToLocalKey() async throws {
        let (delegate, spy) = makeDelegate()
        defer { cleanup() }

        // Only the camelCase key is present (local notification shape).
        let userInfo: [String: Any] = ["reminderId": "rem-camel"]
        delegate.application(NSApplication.shared, didReceiveRemoteNotification: userInfo)

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(spy.handleSilentPushPayloads.count == 1)
        let payload = try #require(spy.handleSilentPushPayloads.first)
        #expect(payload.reminderId == "rem-camel")
        #expect(payload.sentAtMs == nil)
    }

    @Test("didReceiveRemoteNotification handles missing reminderId gracefully")
    func didReceiveRemoteNotificationMissingReminderId() async throws {
        let (delegate, spy) = makeDelegate()
        defer { cleanup() }

        // No identifier at all — sync should still run (mirrors iOS behaviour).
        let userInfo: [String: Any] = ["content-available": NSNumber(value: 1)]
        delegate.application(NSApplication.shared, didReceiveRemoteNotification: userInfo)

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(spy.handleSilentPushPayloads.count == 1)
        let payload = try #require(spy.handleSilentPushPayloads.first)
        #expect(payload.reminderId == nil)
        #expect(payload.sentAtMs == nil)
    }

    @Test("didReceiveRemoteNotification no-ops when pushService is nil")
    func didReceiveRemoteNotificationNoOpWhenNilService() async throws {
        AppContext.shared.resetForTesting()
        defer { cleanup() }

        let delegate = DequeueAppDelegate()
        // Must not crash regardless of the result value.
        delegate.application(
            NSApplication.shared,
            didReceiveRemoteNotification: ["reminder_id": "rem-noop"]
        )
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    @Test("didReceiveRemoteNotification discards SilentPushResult (no completion handler)")
    func didReceiveRemoteNotificationDiscardsResult() async throws {
        let (delegate, spy) = makeDelegate()
        defer { cleanup() }

        // Even when handleSilentPush returns .failed, the macOS path must not
        // crash — there is no UIBackgroundFetchResult completion handler to
        // call. If this test compiles and runs without error, the contract is
        // satisfied.
        spy.stubbedSilentPushResult = .failed

        let userInfo: [String: Any] = ["reminder_id": "rem-fail"]
        delegate.application(NSApplication.shared, didReceiveRemoteNotification: userInfo)

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(spy.handleSilentPushPayloads.count == 1)
        // No crash = success
    }
}
#endif // os(macOS)
