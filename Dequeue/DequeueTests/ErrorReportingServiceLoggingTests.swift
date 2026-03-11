//
//  ErrorReportingServiceLoggingTests.swift
//  DequeueTests
//
//  Smoke tests for ErrorReportingService+Logging — sync-lifecycle, API-response,
//  and app-lifecycle logging helpers.
//
//  Because Sentry is not configured in the test environment, these tests verify
//  that none of the logging methods crash under representative inputs, including
//  every branch in the status-code and internetReachable conditional paths.
//

import Testing
import Foundation
@testable import Dequeue

@Suite("ErrorReportingService Logging Smoke Tests")
@MainActor
struct ErrorReportingServiceLoggingTests {

    // MARK: - logSyncStart

    @Test("logSyncStart does not crash")
    func testLogSyncStart() {
        ErrorReportingService.logSyncStart(syncId: "abc-123", trigger: "manual")
    }

    @Test("logSyncStart with empty strings does not crash")
    func testLogSyncStartEmptyStrings() {
        ErrorReportingService.logSyncStart(syncId: "", trigger: "")
    }

    // MARK: - logSyncComplete

    @Test("logSyncComplete with typical values does not crash")
    func testLogSyncCompleteTypical() {
        ErrorReportingService.logSyncComplete(
            syncId: "sync-001",
            duration: 1.25,
            itemsUploaded: 10,
            itemsDownloaded: 5
        )
    }

    @Test("logSyncComplete with zero items does not crash")
    func testLogSyncCompleteZeroItems() {
        ErrorReportingService.logSyncComplete(
            syncId: "sync-002",
            duration: 0.0,
            itemsUploaded: 0,
            itemsDownloaded: 0
        )
    }

    @Test("logSyncComplete with large counts does not crash")
    func testLogSyncCompleteLargeCounts() {
        ErrorReportingService.logSyncComplete(
            syncId: "sync-003",
            duration: 120.5,
            itemsUploaded: 10_000,
            itemsDownloaded: 50_000
        )
    }

    // MARK: - logSyncFailure (internetReachable = true → server issue branch)

    @Test("logSyncFailure with internet reachable takes server-issue branch without crashing")
    func testLogSyncFailureServerIssue() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [NSLocalizedDescriptionKey: "Cannot connect to host"]
        )
        ErrorReportingService.logSyncFailure(
            syncId: "fail-001",
            duration: 2.0,
            error: error,
            failureReason: "connection refused",
            internetReachable: true
        )
    }

    // MARK: - logSyncFailure (internetReachable = false → offline branch)

    @Test("logSyncFailure offline takes info branch without crashing")
    func testLogSyncFailureOffline() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )
        ErrorReportingService.logSyncFailure(
            syncId: "fail-002",
            duration: 0.1,
            error: error,
            failureReason: "no internet",
            internetReachable: false
        )
    }

    // MARK: - logAPIResponse — success branch (200…299)

    @Test("logAPIResponse 200 takes success branch without crashing")
    func testLogAPIResponse200() {
        ErrorReportingService.logAPIResponse(endpoint: "/api/events", statusCode: 200, responseSize: 512)
    }

    @Test("logAPIResponse 204 (no content) without responseSize does not crash")
    func testLogAPIResponse204NoSize() {
        ErrorReportingService.logAPIResponse(endpoint: "/api/stacks", statusCode: 204, responseSize: nil)
    }

    @Test("logAPIResponse 299 (upper success boundary) does not crash")
    func testLogAPIResponse299() {
        ErrorReportingService.logAPIResponse(endpoint: "/api/tasks", statusCode: 299, responseSize: 128)
    }

    // MARK: - logAPIResponse — client-error branch (400…499)

    @Test("logAPIResponse 400 takes warning branch without crashing")
    func testLogAPIResponse400() {
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/events",
            statusCode: 400,
            responseSize: 64,
            error: "bad request body"
        )
    }

    @Test("logAPIResponse 401 without error string does not crash")
    func testLogAPIResponse401NoError() {
        ErrorReportingService.logAPIResponse(endpoint: "/api/auth", statusCode: 401, responseSize: nil)
    }

    @Test("logAPIResponse 404 does not crash")
    func testLogAPIResponse404() {
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/tasks/missing-id",
            statusCode: 404,
            responseSize: 32,
            error: "not found"
        )
    }

    @Test("logAPIResponse 429 with long error string truncates and does not crash")
    func testLogAPIResponse429LongError() {
        let longError = String(repeating: "x", count: 1000)
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/rate-limited",
            statusCode: 429,
            responseSize: 0,
            error: longError
        )
    }

    @Test("logAPIResponse 499 (upper client-error boundary) does not crash")
    func testLogAPIResponse499() {
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/cancelled",
            statusCode: 499,
            responseSize: nil,
            error: "client closed request"
        )
    }

    // MARK: - logAPIResponse — server-error branch (500…599)

    @Test("logAPIResponse 500 takes error branch without crashing")
    func testLogAPIResponse500() {
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/events",
            statusCode: 500,
            responseSize: 256,
            error: "internal server error"
        )
    }

    @Test("logAPIResponse 502 without error string does not crash")
    func testLogAPIResponse502NoError() {
        ErrorReportingService.logAPIResponse(endpoint: "/api/sync", statusCode: 502, responseSize: nil)
    }

    @Test("logAPIResponse 503 does not crash")
    func testLogAPIResponse503() {
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/health",
            statusCode: 503,
            responseSize: 48,
            error: "service unavailable"
        )
    }

    @Test("logAPIResponse 599 (upper server-error boundary) does not crash")
    func testLogAPIResponse599() {
        ErrorReportingService.logAPIResponse(endpoint: "/api/gateway", statusCode: 599, responseSize: 0)
    }

    // MARK: - logAPIResponse — unrecognised status codes (no branch taken)

    @Test("logAPIResponse 300 (redirect, no branch) does not crash")
    func testLogAPIResponse300NoBranch() {
        ErrorReportingService.logAPIResponse(endpoint: "/api/redirect", statusCode: 300, responseSize: nil)
    }

    @Test("logAPIResponse 600 (above all ranges) does not crash")
    func testLogAPIResponse600NoBranch() {
        ErrorReportingService.logAPIResponse(endpoint: "/api/unknown", statusCode: 600, responseSize: nil)
    }

    // MARK: - logAppLaunch

    @Test("logAppLaunch cold launch takes Sentry capture branch without crashing")
    func testLogAppLaunchCold() {
        ErrorReportingService.logAppLaunch(isWarmLaunch: false)
    }

    @Test("logAppLaunch warm launch skips Sentry capture without crashing")
    func testLogAppLaunchWarm() {
        ErrorReportingService.logAppLaunch(isWarmLaunch: true)
    }

    // MARK: - logAppForeground

    @Test("logAppForeground does not crash")
    func testLogAppForeground() {
        ErrorReportingService.logAppForeground()
    }

    // MARK: - logAppBackground

    @Test("logAppBackground with zero pending items does not crash")
    func testLogAppBackgroundZero() {
        ErrorReportingService.logAppBackground(pendingSyncItems: 0)
    }

    @Test("logAppBackground with pending items does not crash")
    func testLogAppBackgroundWithItems() {
        ErrorReportingService.logAppBackground(pendingSyncItems: 42)
    }
}
