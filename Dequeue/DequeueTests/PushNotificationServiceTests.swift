//
//  PushNotificationServiceTests.swift
//  DequeueTests
//
//  Tests for the iOS-side push notification pipeline (DEQ-283):
//   • Device-token register / deregister, including 1-retry on transient 5xx.
//   • Local-vs-remote dedup bookkeeping (60s NSCache window).
//   • Silent-push handler success / failure / timeout paths.
//

import Testing
import Foundation
import os
@testable import Dequeue

// MARK: - Stub URLProtocol (no real network)

/// URLProtocol subclass that lets tests script HTTP responses in-process.
/// Avoids actual network I/O so the suite stays hermetic.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct StubResponse: Sendable {
        let statusCode: Int
        let body: Data
        let throwError: Error?
        init(statusCode: Int = 200, body: Data = Data(), throwError: Error? = nil) {
            self.statusCode = statusCode
            self.body = body
            self.throwError = throwError
        }
    }

    /// FIFO queue of canned responses keyed by HTTP method. Each request
    /// pops the head. If no canned response is available we return 200 OK.
    nonisolated(unsafe) static var responses: [String: [StubResponse]] = [:]
    /// Records every request the SUT issued (URL + method) so tests can assert on it.
    nonisolated(unsafe) static var requests: [(url: URL, method: String, body: Data?)] = []
    nonisolated(unsafe) static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responses = [:]
        requests = []
    }

    static func enqueue(method: String, response: StubResponse) {
        lock.lock(); defer { lock.unlock() }
        responses[method, default: []].append(response)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let url = request.url ?? URL(string: "about:blank")!
        Self.lock.lock()
        Self.requests.append((url, method, request.httpBody))
        var queue = Self.responses[method] ?? []
        let response = queue.isEmpty ? StubResponse(statusCode: 200) : queue.removeFirst()
        Self.responses[method] = queue
        Self.lock.unlock()

        if let error = response.throwError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Test helpers

/// Sendable, lock-backed mutable clock for tests. Use via the `now()` closure
/// passed into `PushNotificationService`. Uses `OSAllocatedUnfairLock` so the
/// closure can be called from both sync and async contexts under Swift 6.
final class FakeClock: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: Date.distantPast)

    init(start: Date) { storage.withLock { $0 = start } }

    func now() -> Date { storage.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        storage.withLock { $0.addTimeInterval(interval) }
    }
}

/// Test-only `SilentPushSyncing` implementation. Records call count and
/// dispatches the requested behaviour (success / throwing / hang-until-cancel).
final class FakeSyncer: SilentPushSyncing, @unchecked Sendable {
    enum Behavior: Sendable {
        case success
        case error
        case hang
    }

    private let behavior: Behavior
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    var callCount: Int { counter.withLock { $0 } }

    func runRESTProjectionSync() async throws {
        counter.withLock { $0 += 1 }
        switch behavior {
        case .success:
            return
        case .error:
            throw URLError(.timedOut)
        case .hang:
            // Sleep beyond any reasonable timeout. Cancellation propagates
            // from the parent task group so we surrender promptly when the
            // timeout sibling wins.
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
}

// MARK: - Tests

@Suite("PushNotificationService Tests", .serialized)
struct PushNotificationServiceTests {

    // MARK: Token registration

    @Test("Token persists locally and POSTs to the registration endpoint")
    @MainActor
    func tokenRegistrationPersistsAndPostsToAPI() async throws {
        let env = TestEnv()
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))

        let service = env.makeService(tokenProvider: { "bearer-token" }, deviceIdProvider: { "device-abc" })

        let tokenBytes = Data([0xab, 0xcd, 0xef, 0x01, 0x02, 0x03])
        await service.handleAPNsTokenRegistered(tokenBytes)

        #expect(service.cachedDeviceToken == "abcdef010203")
        // last_registered_at should be set after a successful POST.
        #expect(env.defaults.object(forKey: "dequeue.push.lastRegisteredAt") != nil)

        let requests = StubURLProtocol.requests.filter { $0.method == "POST" }
        #expect(requests.count == 1)
        #expect(requests.first?.url.absoluteString.contains("/devices/push-token") == true)
    }

    @Test("Transient 5xx triggers exactly one retry, then succeeds")
    @MainActor
    func tokenRegistrationRetriesOnceOnTransient5xx() async throws {
        let env = TestEnv()
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 503))
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))

        let service = env.makeService(deviceIdProvider: { "device-xyz" })

        await service.handleAPNsTokenRegistered(Data([0x01, 0x02]))

        let postCount = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        #expect(postCount == 2)
        #expect(env.defaults.object(forKey: "dequeue.push.lastRegisteredAt") != nil)
    }

    @Test("Permanent 4xx does not retry and does not persist last_registered_at")
    @MainActor
    func tokenRegistrationDoesNotRetryOn400() async throws {
        let env = TestEnv()
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 400))

        let service = env.makeService(deviceIdProvider: { "device-xyz" })

        await service.handleAPNsTokenRegistered(Data([0x01]))

        let postCount = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        #expect(postCount == 1)
        #expect(env.defaults.object(forKey: "dequeue.push.lastRegisteredAt") == nil)
    }

    @Test("Repeated 5xx telemetry-only, retries once then surrenders")
    @MainActor
    func tokenRegistrationDoesNotBlockOnRepeatedFailure() async throws {
        let env = TestEnv()
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 503))
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 503))

        let service = env.makeService(deviceIdProvider: { "device-xyz" })

        await service.handleAPNsTokenRegistered(Data([0x01]))

        let postCount = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        #expect(postCount == 2)
        #expect(service.cachedDeviceToken == "01")
        #expect(env.defaults.object(forKey: "dequeue.push.lastRegisteredAt") == nil)
    }

    // MARK: Deregister

    @Test("Deregister issues DELETE and clears local state")
    @MainActor
    func deregisterIssuesDeleteAndClearsLocalState() async throws {
        let env = TestEnv()
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))
        StubURLProtocol.enqueue(method: "DELETE", response: .init(statusCode: 204))

        let service = env.makeService(deviceIdProvider: { "device-zzz" })

        await service.handleAPNsTokenRegistered(Data([0xfa]))
        #expect(service.cachedDeviceToken == "fa")

        await service.deregisterOnSignOut()

        #expect(service.cachedDeviceToken == nil)
        #expect(env.defaults.object(forKey: "dequeue.push.cachedToken") == nil)
        #expect(env.defaults.object(forKey: "dequeue.push.lastRegisteredAt") == nil)

        let deletes = StubURLProtocol.requests.filter { $0.method == "DELETE" }
        #expect(deletes.count == 1)
        #expect(deletes.first?.url.absoluteString.contains("deviceId=device-zzz") == true)
    }

    @Test("Deregister is a no-op when no token is cached")
    @MainActor
    func deregisterIsNoopWhenNoTokenCached() async throws {
        let env = TestEnv()
        let service = env.makeService()

        await service.deregisterOnSignOut()

        let deletes = StubURLProtocol.requests.filter { $0.method == "DELETE" }
        #expect(deletes.isEmpty)
    }

    @Test("Deregister still clears local state when auth-token fetch fails")
    @MainActor
    func deregisterClearsLocalStateEvenWhenTokenFetchFails() async throws {
        let env = TestEnv()
        // Register normally first so we have local state to clear.
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))
        let throwOnSignOut = ThrowingTokenProvider()
        let service = env.makeService(
            tokenProvider: { try await throwOnSignOut.getToken() },
            deviceIdProvider: { "device-zzz" }
        )
        await service.handleAPNsTokenRegistered(Data([0xfa]))
        #expect(service.cachedDeviceToken == "fa")

        // Now flip the token provider so the deregister token fetch throws.
        // This simulates Clerk session being torn down before the deregister
        // network call (a real race seen in production sign-out).
        throwOnSignOut.shouldThrow = true

        await service.deregisterOnSignOut()

        // Local state must be cleared regardless of the token-fetch failure —
        // server-side reconciler will reap the orphaned token via APNs 410s.
        #expect(service.cachedDeviceToken == nil)
        #expect(env.defaults.object(forKey: "dequeue.push.cachedToken") == nil)
        let deletes = StubURLProtocol.requests.filter { $0.method == "DELETE" }
        #expect(deletes.isEmpty, "DELETE skipped when token unavailable")
    }

    // MARK: Stale-token refresh

    @Test("Fresh last_registered_at skips re-POST")
    @MainActor
    func refreshTokenIfStaleSkipsWhenFresh() async throws {
        let env = TestEnv()
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))
        let service = env.makeService(deviceIdProvider: { "device-fresh" })

        await service.handleAPNsTokenRegistered(Data([0x12]))
        let baseline = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        #expect(baseline == 1)

        await service.refreshTokenIfStale()

        let afterRefresh = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        #expect(afterRefresh == baseline)
    }

    @Test("Stale last_registered_at triggers one re-POST")
    @MainActor
    func refreshTokenIfStaleRepostsWhenStale() async throws {
        let env = TestEnv()
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))
        let service = env.makeService(deviceIdProvider: { "device-stale" })

        await service.handleAPNsTokenRegistered(Data([0x99]))
        // Backdate last_registered_at to 10 days ago. Stored as Int64 ms
        // per CLAUDE.md / the production write path.
        let tenDaysAgoMs = Int64(Date().addingTimeInterval(-10 * 24 * 60 * 60).timeIntervalSince1970 * 1_000)
        env.defaults.set(tenDaysAgoMs, forKey: "dequeue.push.lastRegisteredAt")
        let baseline = StubURLProtocol.requests.filter { $0.method == "POST" }.count

        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))
        await service.refreshTokenIfStale()

        let afterRefresh = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        #expect(afterRefresh == baseline + 1)
    }

    // MARK: Dedup bookkeeping

    @Test("Remote delivery within window is recognised")
    @MainActor
    func remoteDeliveryWithinWindowIsRecognized() async throws {
        let env = TestEnv()
        let service = env.makeService()

        service.markRemoteDelivered(reminderId: "rem-1")
        #expect(service.isRemoteRecentlyDelivered(reminderId: "rem-1"))
        #expect(!service.isRemoteRecentlyDelivered(reminderId: "rem-2"))
    }

    @Test("Remote delivery cache entry expires after the 60s window")
    @MainActor
    func remoteDeliveryWindowExpires() async throws {
        let env = TestEnv()
        let clock = FakeClock(start: Date())
        let service = env.makeService(now: { clock.now() })

        service.markRemoteDelivered(reminderId: "rem-expire")
        #expect(service.isRemoteRecentlyDelivered(reminderId: "rem-expire"))

        // Inside the window.
        clock.advance(by: 45)
        #expect(service.isRemoteRecentlyDelivered(reminderId: "rem-expire"))

        // Past the window — expired entry should be evicted.
        clock.advance(by: 20) // total 65s
        #expect(!service.isRemoteRecentlyDelivered(reminderId: "rem-expire"))
    }

    // MARK: Silent push sync

    @Test("Silent-push sync success returns .newData")
    @MainActor
    func silentPushSyncSuccessReturnsNewData() async throws {
        let env = TestEnv()
        let syncer = FakeSyncer(behavior: .success)
        let service = env.makeService(silentPushSyncer: syncer)

        let result = await service.handleSilentPush(
            payload: SilentPushPayload(reminderId: "rem-1", sentAtMs: nil)
        )

        #expect(result == .newData)
        #expect(syncer.callCount == 1)
        // The dedup cache is intentionally NOT stamped on silent-push
        // receipt — only on alert-push *presentation* via
        // `NotificationService.willPresent` path 1. This avoids missing the
        // local fallback if APNs fails to deliver the alert push at remindAt.
        #expect(!service.isRemoteRecentlyDelivered(reminderId: "rem-1"))
    }

    @Test("Silent-push sync throwing returns .failed")
    @MainActor
    func silentPushSyncErrorReturnsFailed() async throws {
        let env = TestEnv()
        let syncer = FakeSyncer(behavior: .error)
        let service = env.makeService(silentPushSyncer: syncer)

        let result = await service.handleSilentPush(
            payload: SilentPushPayload(reminderId: "rem-1", sentAtMs: nil)
        )

        #expect(result == .failed)
    }

    @Test("Silent-push sync timeout surfaces .failed via tiny injected timeout")
    @MainActor
    func silentPushSyncTimesOut() async throws {
        let env = TestEnv()
        let syncer = FakeSyncer(behavior: .hang)
        // Inject a tiny timeout via init so we exercise the timeout path
        // through `handleSilentPush` rather than poking at internals.
        let service = env.makeService(silentPushSyncer: syncer, silentPushSyncTimeout: 0.2)

        let result = await service.handleSilentPush(
            payload: SilentPushPayload(reminderId: "rem-1", sentAtMs: nil)
        )

        #expect(result == .failed)
    }

    @Test("nil reminderId leaves no side-effects in the dedup cache")
    @MainActor
    func nilReminderIdNoDedupCacheSideEffects() async throws {
        let env = TestEnv()
        let syncer = FakeSyncer(behavior: .success)
        let service = env.makeService(silentPushSyncer: syncer)

        let result = await service.handleSilentPush(
            payload: SilentPushPayload(reminderId: nil, sentAtMs: nil)
        )

        // Sync still ran (the silent push wakes us regardless of payload).
        #expect(result == .newData)
        #expect(syncer.callCount == 1)
        // The dedup cache is intentionally NOT stamped on silent-push
        // receipt (see comment in handleSilentPush). Asserting the obvious
        // empty-string lookup here just confirms no accidental stamp.
        #expect(!service.isRemoteRecentlyDelivered(reminderId: ""))
    }

    @Test("Unavailable syncer surfaces .failed cleanly")
    @MainActor
    func unavailableSyncerReturnsFailed() async throws {
        let env = TestEnv()
        // No injected syncer + AppContext not wired in tests → service falls
        // through to .failure(kind: "unavailable") which maps to .failed.
        let service = env.makeService()
        let result = await service.handleSilentPush(
            payload: SilentPushPayload(reminderId: "rem-1", sentAtMs: nil)
        )
        #expect(result == .failed)
    }

    // MARK: Coverage gap fills

    @Test("handleAPNsRegistrationFailed emits telemetry without throwing")
    @MainActor
    func handleAPNsRegistrationFailedDoesNotThrow() async throws {
        let env = TestEnv()
        let service = env.makeService()
        // Should not crash, should not change cached state.
        service.handleAPNsRegistrationFailed(URLError(.notConnectedToInternet))
        #expect(service.cachedDeviceToken == nil)
    }

    @Test("refreshTokenIfStale is a no-op when not authenticated")
    @MainActor
    func refreshTokenIfStaleNoopWhenSignedOut() async throws {
        let env = TestEnv()
        // Pre-populate the suite so a service built later with
        // `isAuthenticatedProvider: { false }` reads the cached token but
        // still bails on the auth guard. This exercises the guard at the
        // top of `refreshTokenIfStale` even when local state otherwise
        // looks ready to refresh. Timestamp stored as Int64 ms.
        env.defaults.set("cached-old", forKey: "dequeue.push.cachedToken")
        env.defaults.set(Int64(Date.distantPast.timeIntervalSince1970 * 1_000), forKey: "dequeue.push.lastRegisteredAt")
        let service = env.makeService(isAuthenticatedProvider: { false })

        await service.refreshTokenIfStale()

        let posts = StubURLProtocol.requests.filter { $0.method == "POST" }
        #expect(posts.isEmpty)
    }

    @Test("refreshTokenIfStale falls through to registerIfSignedIn when no cached token")
    @MainActor
    func refreshTokenIfStaleFallsThroughToRegister() async throws {
        let env = TestEnv()
        // Authenticated but no token cached locally yet. Should hit the
        // `registerIfSignedIn` path (which on non-iOS test runners is a
        // breadcrumb-only no-op — the OS callback path isn't reachable from
        // unit tests). Critically: should not POST anything yet.
        let service = env.makeService()
        await service.refreshTokenIfStale()

        let posts = StubURLProtocol.requests.filter { $0.method == "POST" }
        #expect(posts.isEmpty)
        #expect(service.cachedDeviceToken == nil)
    }
}

// MARK: - TestEnv

/// Holds the per-test ephemeral UserDefaults suite + URLSession plumbing so
/// the @Suite struct stays free of mutable state (Swift Testing prefers per-
/// test isolation over XCTestCase-style setUp/tearDown).
@MainActor
private final class TestEnv {
    let defaults: UserDefaults
    let suiteName: String
    let session: URLSession

    init() {
        self.suiteName = "PushNotificationServiceTests-\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suiteName)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        self.session = URLSession(configuration: config)
        StubURLProtocol.reset()
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        StubURLProtocol.reset()
    }

    func makeService(
        tokenProvider: @MainActor @escaping () async throws -> String = { "test-token" },
        deviceIdProvider: @Sendable @escaping () async -> String = { "test-device" },
        isAuthenticatedProvider: @MainActor @escaping () -> Bool = { true },
        silentPushSyncer: SilentPushSyncing? = nil,
        silentPushSyncTimeout: TimeInterval = 1.0,
        now: @Sendable @escaping () -> Date = { Date() }
    ) -> PushNotificationService {
        PushNotificationService(
            urlSession: session,
            userDefaults: defaults,
            baseURLProvider: { URL(string: "https://api.test.dequeue.app/v1")! },
            tokenProvider: tokenProvider,
            deviceIdProvider: deviceIdProvider,
            isAuthenticatedProvider: isAuthenticatedProvider,
            silentPushSyncer: silentPushSyncer,
            silentPushSyncTimeout: silentPushSyncTimeout,
            // Skip the 500ms retry backoff in tests so the retry-on-5xx
            // test doesn't sleep for half a second.
            tokenRegisterRetryDelay: 0,
            now: now
        )
    }
}

// MARK: - ThrowingTokenProvider

/// Toggleable token provider used by `deregisterClearsLocalStateEvenWhenTokenFetchFails`.
/// The first call (POST-time, during register) returns a real token; once
/// `shouldThrow` flips true, subsequent calls (DELETE-time, during sign-out)
/// throw — simulating the Clerk session being torn down between register
/// and deregister.
final class ThrowingTokenProvider: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: false)
    var shouldThrow: Bool {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    func getToken() async throws -> String {
        if shouldThrow {
            throw URLError(.userAuthenticationRequired)
        }
        return "bearer-token"
    }
}
