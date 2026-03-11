//
//  ErrorReportingServiceSyncObservabilityTests.swift
//  DequeueTests
//
//  Smoke tests for ErrorReportingService+SyncObservability — all the structured
//  breadcrumb/Sentry helpers for sync, WebSocket, auth, cert-pinning, and
//  Sentry performance transactions.
//
//  Because Sentry is not configured in the test environment, these tests verify
//  that none of the observability methods crash under representative inputs.
//  They do NOT assert on Sentry side-effects (those require a Sentry test spy
//  which is outside scope for smoke coverage).
//

import Testing
import Foundation
@testable import Dequeue

@Suite("ErrorReportingService SyncObservability Smoke Tests")
@MainActor
struct ErrorReportingServiceSyncObservabilityTests {

    // MARK: - logSyncStateTransition

    @Test("logSyncStateTransition without trigger does not crash")
    func testLogSyncStateTransitionNoTrigger() {
        ErrorReportingService.logSyncStateTransition(from: "disconnected", to: "connecting")
    }

    @Test("logSyncStateTransition with trigger does not crash")
    func testLogSyncStateTransitionWithTrigger() {
        ErrorReportingService.logSyncStateTransition(
            from: "connecting",
            to: "connected",
            trigger: "network-reachability"
        )
    }

    // MARK: - logWebSocketConnecting

    @Test("logWebSocketConnecting with plain URL does not crash")
    func testLogWebSocketConnectingPlainURL() {
        ErrorReportingService.logWebSocketConnecting(url: "wss://sync.ardonos.com/ws")
    }

    @Test("logWebSocketConnecting redacts token query param")
    func testLogWebSocketConnectingTokenURL() {
        // URL contains a token — redactToken() should sanitise it before logging.
        // We verify the call doesn't crash; redaction is an internal detail.
        ErrorReportingService.logWebSocketConnecting(
            url: "wss://sync.ardonos.com/ws?token=super-secret-jwt&version=2"
        )
    }

    @Test("logWebSocketConnecting with token-only URL does not crash")
    func testLogWebSocketConnectingTokenOnlyURL() {
        ErrorReportingService.logWebSocketConnecting(url: "wss://sync.ardonos.com/ws?token=abc123")
    }

    // MARK: - logWebSocketConnected

    @Test("logWebSocketConnected does not crash")
    func testLogWebSocketConnected() {
        ErrorReportingService.logWebSocketConnected()
    }

    // MARK: - logWebSocketDisconnected

    @Test("logWebSocketDisconnected without close code does not crash")
    func testLogWebSocketDisconnectedNoCode() {
        ErrorReportingService.logWebSocketDisconnected(reason: "server closed connection")
    }

    @Test("logWebSocketDisconnected with close code 1000 (normal) does not crash")
    func testLogWebSocketDisconnectedNormalClose() {
        ErrorReportingService.logWebSocketDisconnected(reason: "normal closure", code: 1000)
    }

    @Test("logWebSocketDisconnected with close code 1006 (abnormal) does not crash")
    func testLogWebSocketDisconnectedAbnormalClose() {
        ErrorReportingService.logWebSocketDisconnected(reason: "abnormal closure", code: 1006)
    }

    // MARK: - logWebSocketError

    @Test("logWebSocketError with reconnectAttempt < 3 does not crash")
    func testLogWebSocketErrorEarlyAttempt() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: [NSLocalizedDescriptionKey: "The network connection was lost."]
        )
        ErrorReportingService.logWebSocketError(error, reconnectAttempt: 1)
    }

    @Test("logWebSocketError with reconnectAttempt == 2 (just below threshold) does not crash")
    func testLogWebSocketErrorAttemptTwo() {
        let error = NSError(domain: "TestError", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Connection failed"
        ])
        ErrorReportingService.logWebSocketError(error, reconnectAttempt: 2)
    }

    @Test("logWebSocketError with reconnectAttempt == 3 fires Sentry event and does not crash")
    func testLogWebSocketErrorAttemptThreshold() {
        // At attempt >= 3, the method captures a Sentry error event.
        // In test environment Sentry is not configured so it's a no-op.
        let error = NSError(domain: "TestError", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "WebSocket connection failing"
        ])
        ErrorReportingService.logWebSocketError(error, reconnectAttempt: 3)
    }

    @Test("logWebSocketError with high reconnectAttempt does not crash")
    func testLogWebSocketErrorHighAttempt() {
        let error = NSError(domain: "TestError", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Persistent failure"
        ])
        ErrorReportingService.logWebSocketError(error, reconnectAttempt: 20)
    }

    // MARK: - logSyncNetworkRequest

    @Test("logSyncNetworkRequest with 200 success does not crash")
    func testLogSyncNetworkRequest200() {
        ErrorReportingService.logSyncNetworkRequest(
            method: "POST",
            url: "https://sync.ardonos.com/v1/events",
            statusCode: 200,
            responseSize: 1024,
            duration: 0.35
        )
    }

    @Test("logSyncNetworkRequest with 401 does not fire Sentry error and does not crash")
    func testLogSyncNetworkRequest401Excluded() {
        // 401 is explicitly excluded from fireSyncNetworkError (DEQUEUE-APP-1 fix).
        ErrorReportingService.logSyncNetworkRequest(
            method: "GET",
            url: "https://sync.ardonos.com/v1/events",
            statusCode: 401,
            responseSize: nil,
            duration: 0.1,
            error: "Unauthorized"
        )
    }

    @Test("logSyncNetworkRequest with 403 fires Sentry error and does not crash")
    func testLogSyncNetworkRequest403() {
        ErrorReportingService.logSyncNetworkRequest(
            method: "GET",
            url: "https://sync.ardonos.com/v1/events",
            statusCode: 403,
            responseSize: nil,
            duration: 0.1,
            error: "Forbidden"
        )
    }

    @Test("logSyncNetworkRequest with 500 fires Sentry error and does not crash")
    func testLogSyncNetworkRequest500() {
        ErrorReportingService.logSyncNetworkRequest(
            method: "POST",
            url: "https://sync.ardonos.com/v1/events",
            statusCode: 500,
            responseSize: nil,
            duration: 2.1,
            error: "Internal Server Error"
        )
    }

    @Test("logSyncNetworkRequest with URL containing token does not crash")
    func testLogSyncNetworkRequestRedactsToken() {
        ErrorReportingService.logSyncNetworkRequest(
            method: "GET",
            url: "https://sync.ardonos.com/v1/stream?token=secret-token&format=json",
            statusCode: 200,
            responseSize: 256,
            duration: 0.5
        )
    }

    @Test("logSyncNetworkRequest with nil optional params does not crash")
    func testLogSyncNetworkRequestNilOptionals() {
        ErrorReportingService.logSyncNetworkRequest(
            method: "DELETE",
            url: "https://sync.ardonos.com/v1/events/123",
            statusCode: 204,
            responseSize: nil,
            duration: 0.05
        )
    }

    // MARK: - logSyncPull

    @Test("logSyncPull with checkpoint does not crash")
    func testLogSyncPullWithCheckpoint() {
        ErrorReportingService.logSyncPull(
            eventCount: 42,
            duration: 1.2,
            checkpoint: "checkpoint-abc-123"
        )
    }

    @Test("logSyncPull without checkpoint does not crash")
    func testLogSyncPullNoCheckpoint() {
        ErrorReportingService.logSyncPull(eventCount: 0, duration: 0.05, checkpoint: nil)
    }

    // MARK: - logSyncPush

    @Test("logSyncPush success does not crash")
    func testLogSyncPushSuccess() {
        ErrorReportingService.logSyncPush(eventCount: 7, duration: 0.4, success: true)
    }

    @Test("logSyncPush failure does not crash")
    func testLogSyncPushFailure() {
        ErrorReportingService.logSyncPush(eventCount: 3, duration: 0.9, success: false)
    }

    @Test("logSyncPush with zero events does not crash")
    func testLogSyncPushZeroEvents() {
        ErrorReportingService.logSyncPush(eventCount: 0, duration: 0.01, success: true)
    }

    // MARK: - logProjectionSyncStart

    @Test("logProjectionSyncStart does not crash")
    func testLogProjectionSyncStart() {
        ErrorReportingService.logProjectionSyncStart()
    }

    // MARK: - logProjectionSyncComplete

    @Test("logProjectionSyncComplete with entities does not crash")
    func testLogProjectionSyncComplete() {
        ErrorReportingService.logProjectionSyncComplete(
            stacks: 5,
            tasks: 30,
            arcs: 2,
            tags: 8,
            reminders: 3,
            duration: 1.7
        )
    }

    @Test("logProjectionSyncComplete with all-zero counts does not crash")
    func testLogProjectionSyncCompleteZero() {
        ErrorReportingService.logProjectionSyncComplete(
            stacks: 0, tasks: 0, arcs: 0, tags: 0, reminders: 0, duration: 0.1
        )
    }

    // MARK: - logProjectionSyncFailed

    @Test("logProjectionSyncFailed fires Sentry event and does not crash")
    func testLogProjectionSyncFailedServerError() {
        let error = NSError(domain: "SyncError", code: 500, userInfo: [
            NSLocalizedDescriptionKey: "Projection sync failed: server returned 500"
        ])
        ErrorReportingService.logProjectionSyncFailed(error: error, duration: 2.5)
    }

    @Test("logProjectionSyncFailed with URL error does not crash")
    func testLogProjectionSyncFailedURLError() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: [NSLocalizedDescriptionKey: "The network connection was lost."]
        )
        ErrorReportingService.logProjectionSyncFailed(error: error, duration: 0.3)
    }

    @Test("logProjectionSyncFailed with long error message does not crash")
    func testLogProjectionSyncFailedLongMessage() {
        let longMessage = String(repeating: "error detail. ", count: 200)
        let error = NSError(domain: "SyncError", code: 503, userInfo: [
            NSLocalizedDescriptionKey: longMessage
        ])
        ErrorReportingService.logProjectionSyncFailed(error: error, duration: 5.0)
    }

    // MARK: - logAuthTokenRefresh

    @Test("logAuthTokenRefresh success does not crash")
    func testLogAuthTokenRefreshSuccess() {
        ErrorReportingService.logAuthTokenRefresh(success: true)
    }

    @Test("logAuthTokenRefresh failure unsuppressed fires Sentry event and does not crash")
    func testLogAuthTokenRefreshFailureUnsuppressed() {
        ErrorReportingService.logAuthTokenRefresh(
            success: false,
            error: "Token expired",
            isSuppressed: false
        )
    }

    @Test("logAuthTokenRefresh failure suppressed skips Sentry event and does not crash")
    func testLogAuthTokenRefreshFailureSuppressed() {
        // DEQUEUE-APP-1: backgrounded-during-refresh race — should not flood Sentry.
        ErrorReportingService.logAuthTokenRefresh(
            success: false,
            error: "internal_clerk_error: token refresh interrupted",
            isSuppressed: true
        )
    }

    @Test("logAuthTokenRefresh failure without error string does not crash")
    func testLogAuthTokenRefreshFailureNoErrorString() {
        ErrorReportingService.logAuthTokenRefresh(success: false)
    }

    // MARK: - logCertPinningResult

    @Test("logCertPinningResult matched does not crash")
    func testLogCertPinningResultMatched() async throws {
        // nonisolated — dispatches to MainActor internally via Task.
        // We give it a small pause so the internal Task can complete.
        ErrorReportingService.logCertPinningResult(
            domain: "sync.ardonos.com",
            matched: true,
            hashes: ["sha256/abc123==", "sha256/def456=="]
        )
        // Yield to let the internal MainActor Task execute
        try await Task.sleep(for: .milliseconds(10))
    }

    @Test("logCertPinningResult mismatch fires Sentry event and does not crash")
    func testLogCertPinningResultMismatch() async throws {
        ErrorReportingService.logCertPinningResult(
            domain: "sync.ardonos.com",
            matched: false,
            hashes: ["sha256/unexpected=="]
        )
        try await Task.sleep(for: .milliseconds(10))
    }

    @Test("logCertPinningResult with empty hashes does not crash")
    func testLogCertPinningResultEmptyHashes() async throws {
        ErrorReportingService.logCertPinningResult(
            domain: "api.dequeue.app",
            matched: false,
            hashes: []
        )
        try await Task.sleep(for: .milliseconds(10))
    }

    // MARK: - recordProjectionSyncTransaction

    @Test("recordProjectionSyncTransaction success does not crash")
    func testRecordProjectionSyncTransactionSuccess() {
        let metrics = ErrorReportingService.ProjectionSyncMetrics(
            syncId: "sync-test-001",
            syncStart: Date().addingTimeInterval(-1.5),
            fetchDurationMs: 800,
            populateDurationMs: 700,
            stacks: 3,
            tasks: 20,
            arcs: 1,
            tags: 5,
            reminders: 2,
            success: true
        )
        ErrorReportingService.recordProjectionSyncTransaction(metrics)
    }

    @Test("recordProjectionSyncTransaction failure does not crash")
    func testRecordProjectionSyncTransactionFailure() {
        let metrics = ErrorReportingService.ProjectionSyncMetrics(
            syncId: "sync-test-002",
            syncStart: Date().addingTimeInterval(-0.3),
            fetchDurationMs: 300,
            populateDurationMs: 0,
            stacks: 0,
            tasks: 0,
            arcs: 0,
            tags: 0,
            reminders: 0,
            success: false
        )
        ErrorReportingService.recordProjectionSyncTransaction(metrics)
    }

    @Test("recordProjectionSyncTransaction with all-zero durations does not crash")
    func testRecordProjectionSyncTransactionZeroDurations() {
        let metrics = ErrorReportingService.ProjectionSyncMetrics(
            syncId: "sync-test-003",
            syncStart: Date(),
            fetchDurationMs: 0,
            populateDurationMs: 0,
            stacks: 0,
            tasks: 0,
            arcs: 0,
            tags: 0,
            reminders: 0,
            success: true
        )
        ErrorReportingService.recordProjectionSyncTransaction(metrics)
    }

    // MARK: - recordEventPushTransaction

    @Test("recordEventPushTransaction success does not crash")
    func testRecordEventPushTransactionSuccess() {
        let metrics = ErrorReportingService.EventPushMetrics(
            syncId: "push-test-001",
            pushStart: Date().addingTimeInterval(-0.5),
            httpDurationMs: 450,
            eventCount: 5,
            httpStatusCode: 200,
            success: true
        )
        ErrorReportingService.recordEventPushTransaction(metrics)
    }

    @Test("recordEventPushTransaction failure does not crash")
    func testRecordEventPushTransactionFailure() {
        let metrics = ErrorReportingService.EventPushMetrics(
            syncId: "push-test-002",
            pushStart: Date().addingTimeInterval(-1.0),
            httpDurationMs: 1000,
            eventCount: 3,
            httpStatusCode: 503,
            success: false
        )
        ErrorReportingService.recordEventPushTransaction(metrics)
    }

    @Test("recordEventPushTransaction with zero events does not crash")
    func testRecordEventPushTransactionZeroEvents() {
        let metrics = ErrorReportingService.EventPushMetrics(
            syncId: "push-test-003",
            pushStart: Date(),
            httpDurationMs: 50,
            eventCount: 0,
            httpStatusCode: 204,
            success: true
        )
        ErrorReportingService.recordEventPushTransaction(metrics)
    }
}
