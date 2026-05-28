//
//  PushNotificationServiceTests.swift
//  DequeueTests
//
//  Tests for the iOS-side push notification pipeline (DEQ-283):
//   • Device-token register / deregister, including 1-retry on transient 5xx.
//   • Local-vs-remote dedup bookkeeping (60s NSCache window).
//   • Silent-push handler timeout behaviour.
//

import XCTest
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

// MARK: - Tests

@MainActor
final class PushNotificationServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        // Use a clean, ephemeral UserDefaults suite so tests don't leak state.
        defaultsSuiteName = "PushNotificationServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        StubURLProtocol.reset()
    }

    override func tearDown() async throws {
        // Tear down the ephemeral defaults suite by its suite NAME (not by
        // some key inside it) so subsequent tests can't see stale values.
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        StubURLProtocol.reset()
        try await super.tearDown()
    }

    // MARK: Token registration

    func testTokenRegistrationPersistsAndPostsToAPI() async throws {
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))

        let service = makeService(
            tokenProvider: { "bearer-token" },
            deviceIdProvider: { "device-abc" }
        )

        let tokenBytes = Data([0xab, 0xcd, 0xef, 0x01, 0x02, 0x03])
        await service.handleAPNsTokenRegistered(tokenBytes)

        XCTAssertEqual(service.cachedDeviceToken, "abcdef010203")
        // last_registered_at should be set after a successful POST.
        XCTAssertNotNil(defaults.object(forKey: "dequeue.push.lastRegisteredAt"))

        let requests = StubURLProtocol.requests.filter { $0.method == "POST" }
        XCTAssertEqual(requests.count, 1, "Should POST once on first register")
        XCTAssertTrue(requests[0].url.absoluteString.contains("/devices/push-token"))
    }

    func testTokenRegistrationRetriesOnceOnTransient5xx() async throws {
        // First attempt 503, second attempt 200.
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 503))
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))

        let service = makeService(
            tokenProvider: { "bearer-token" },
            deviceIdProvider: { "device-xyz" }
        )

        await service.handleAPNsTokenRegistered(Data([0x01, 0x02]))

        let postCount = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        XCTAssertEqual(postCount, 2, "Should retry once then succeed")
        XCTAssertNotNil(defaults.object(forKey: "dequeue.push.lastRegisteredAt"))
    }

    func testTokenRegistrationDoesNotRetryOn400() async throws {
        // 400 is permanent — no retry, no last_registered_at write.
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 400))

        let service = makeService(
            tokenProvider: { "bearer-token" },
            deviceIdProvider: { "device-xyz" }
        )

        await service.handleAPNsTokenRegistered(Data([0x01]))

        let postCount = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        XCTAssertEqual(postCount, 1, "Permanent failure should not retry")
        XCTAssertNil(defaults.object(forKey: "dequeue.push.lastRegisteredAt"))
    }

    func testTokenRegistrationDoesNotBlockOnRepeatedFailure() async throws {
        // Both attempts fail with 503 — service must telemetry-only and return.
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 503))
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 503))

        let service = makeService(
            tokenProvider: { "bearer-token" },
            deviceIdProvider: { "device-xyz" }
        )

        await service.handleAPNsTokenRegistered(Data([0x01]))

        let postCount = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        XCTAssertEqual(postCount, 2, "Should attempt original + 1 retry")
        // Token still cached locally even though server didn't ack — next launch
        // will re-attempt.
        XCTAssertEqual(service.cachedDeviceToken, "01")
        XCTAssertNil(defaults.object(forKey: "dequeue.push.lastRegisteredAt"))
    }

    // MARK: Deregister

    func testDeregisterIssuesDeleteAndClearsLocalState() async throws {
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))
        StubURLProtocol.enqueue(method: "DELETE", response: .init(statusCode: 204))

        let service = makeService(
            tokenProvider: { "bearer-token" },
            deviceIdProvider: { "device-zzz" }
        )

        await service.handleAPNsTokenRegistered(Data([0xfa]))
        XCTAssertEqual(service.cachedDeviceToken, "fa")

        await service.deregisterOnSignOut()

        XCTAssertNil(service.cachedDeviceToken)
        XCTAssertNil(defaults.object(forKey: "dequeue.push.cachedToken"))
        XCTAssertNil(defaults.object(forKey: "dequeue.push.lastRegisteredAt"))

        let deletes = StubURLProtocol.requests.filter { $0.method == "DELETE" }
        XCTAssertEqual(deletes.count, 1)
        XCTAssertTrue(deletes[0].url.absoluteString.contains("deviceId=device-zzz"))
    }

    func testDeregisterIsNoopWhenNoTokenCached() async throws {
        let service = makeService(
            tokenProvider: { "bearer-token" },
            deviceIdProvider: { "device-zzz" }
        )

        await service.deregisterOnSignOut()

        let deletes = StubURLProtocol.requests.filter { $0.method == "DELETE" }
        XCTAssertEqual(deletes.count, 0, "Should not issue DELETE if no token cached")
    }

    // MARK: Stale-token refresh

    func testRefreshTokenIfStaleSkipsWhenFresh() async throws {
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))
        let service = makeService(
            tokenProvider: { "bearer-token" },
            deviceIdProvider: { "device-fresh" }
        )

        await service.handleAPNsTokenRegistered(Data([0x12]))
        // Drain the post count.
        let baseline = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        XCTAssertEqual(baseline, 1)

        // No additional canned response: if it tried to POST, it'd get default 200,
        // which would also increment requests.
        await service.refreshTokenIfStale()

        let afterRefresh = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        XCTAssertEqual(afterRefresh, baseline, "Fresh token should not re-POST")
    }

    func testRefreshTokenIfStaleRepostsWhenStale() async throws {
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))

        let service = makeService(
            tokenProvider: { "bearer-token" },
            deviceIdProvider: { "device-stale" }
        )

        await service.handleAPNsTokenRegistered(Data([0x99]))
        // Backdate last_registered_at to 10 days ago.
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        defaults.set(tenDaysAgo, forKey: "dequeue.push.lastRegisteredAt")
        let baseline = StubURLProtocol.requests.filter { $0.method == "POST" }.count

        // Queue another 200 response for the refresh POST.
        StubURLProtocol.enqueue(method: "POST", response: .init(statusCode: 200))
        await service.refreshTokenIfStale()

        let afterRefresh = StubURLProtocol.requests.filter { $0.method == "POST" }.count
        XCTAssertEqual(afterRefresh, baseline + 1, "Stale token should trigger one re-POST")
    }

    // MARK: Dedup bookkeeping

    func testRemoteDeliveryWithinWindowIsRecognized() async throws {
        let service = makeService()

        service.markRemoteDelivered(reminderId: "rem-1")
        XCTAssertTrue(service.isRemoteRecentlyDelivered(reminderId: "rem-1"))
        XCTAssertFalse(service.isRemoteRecentlyDelivered(reminderId: "rem-2"))
    }

    func testRemoteDeliveryWindowExpires() async throws {
        // Use the injected clock to fast-forward past the 60s dedup window.
        // After expiry the entry should be cleaned out of the NSCache and
        // subsequent lookups must return false. `FakeClock` is a Sendable
        // box around an OSAllocatedUnfairLock so the closure captured by
        // PushNotificationService stays Sendable under Swift 6.
        let clock = FakeClock(start: Date())
        let service = makeService(now: { clock.now() })

        service.markRemoteDelivered(reminderId: "rem-expire")
        XCTAssertTrue(service.isRemoteRecentlyDelivered(reminderId: "rem-expire"))

        // Inside the window.
        clock.advance(by: 45)
        XCTAssertTrue(service.isRemoteRecentlyDelivered(reminderId: "rem-expire"))

        // Past the window — expired entry should be evicted.
        clock.advance(by: 20) // total 65s
        XCTAssertFalse(service.isRemoteRecentlyDelivered(reminderId: "rem-expire"))
    }

    // MARK: Silent push sync

    func testSilentPushSyncSuccessReturnsNewData() async throws {
        let syncer = FakeSyncer(behavior: .success)
        let service = makeService(silentPushSyncer: syncer)

        let result = await service.handleSilentPush(
            userInfo: [NotificationConstants.UserInfoKey.remoteReminderId: "rem-1"]
        )

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(syncer.callCount, 1)
        XCTAssertTrue(service.isRemoteRecentlyDelivered(reminderId: "rem-1"))
    }

    func testSilentPushSyncErrorReturnsFailed() async throws {
        let syncer = FakeSyncer(behavior: .error)
        let service = makeService(silentPushSyncer: syncer)

        let result = await service.handleSilentPush(
            userInfo: [NotificationConstants.UserInfoKey.remoteReminderId: "rem-1"]
        )

        XCTAssertEqual(result, .failed)
    }

    func testSilentPushSyncTimesOut() async throws {
        let syncer = FakeSyncer(behavior: .hang)
        let service = makeService(silentPushSyncer: syncer)

        // Use a tiny custom timeout via the underlying runSilentPushSync to
        // keep the test fast; handleSilentPush always uses the production
        // 20s value so we exercise runSilentPushSync directly.
        let outcome = await service.runSilentPushSync(timeout: 0.2)

        XCTAssertEqual(outcome, .failure(kind: "timeout"))
    }

    func testMissingReminderIdInUserInfoIsHandledGracefully() async throws {
        // No reminder_id: handleSilentPush should still complete with .failed
        // (no sync manager wired) rather than crash on optional unwrap.
        let service = makeService()
        let result = await service.handleSilentPush(userInfo: ["other": "junk"])
        // AppContext is not configured in test → silent sync returns .failed.
        XCTAssertEqual(result, .failed)
    }

    // MARK: Helpers

    private func makeService(
        tokenProvider: @MainActor @escaping () async throws -> String = { "test-token" },
        deviceIdProvider: @Sendable @escaping () async -> String = { "test-device" },
        silentPushSyncer: SilentPushSyncing? = nil,
        now: @Sendable @escaping () -> Date = { Date() }
    ) -> PushNotificationService {
        PushNotificationService(
            urlSession: session,
            userDefaults: defaults,
            baseURLProvider: { URL(string: "https://api.test.dequeue.app/v1")! },
            tokenProvider: tokenProvider,
            deviceIdProvider: deviceIdProvider,
            isAuthenticatedProvider: { true },
            silentPushSyncer: silentPushSyncer,
            now: now
        )
    }
}

// MARK: - FakeClock

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

// MARK: - FakeSyncer

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
