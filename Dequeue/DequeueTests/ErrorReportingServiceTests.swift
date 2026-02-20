//
//  ErrorReportingServiceTests.swift
//  DequeueTests
//
//  Tests for ErrorReportingService - error truncation, logging extensions,
//  and configuration behavior in test environments
//

import XCTest
@testable import Dequeue

@MainActor
final class ErrorReportingServiceTests: XCTestCase {

    // MARK: - truncateErrorMessage - Under Limit

    func testTruncateShortMessage() {
        let message = "Short error"
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertEqual(result, message, "Short messages should pass through unchanged")
    }

    func testTruncateEmptyMessage() {
        let result = ErrorReportingService.truncateErrorMessage("")
        XCTAssertEqual(result, "", "Empty string should pass through unchanged")
    }

    func testTruncateExactly500Characters() {
        let message = String(repeating: "a", count: 500)
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertEqual(result, message, "Exactly 500 character message should not be truncated")
        XCTAssertEqual(result.count, 500)
    }

    func testTruncateAt499Characters() {
        let message = String(repeating: "b", count: 499)
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertEqual(result, message, "499 character message should not be truncated")
    }

    // MARK: - truncateErrorMessage - Over Limit

    func testTruncateAt501Characters() {
        let message = String(repeating: "c", count: 501)
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertTrue(result.hasSuffix("...[truncated]"), "Truncated message should end with truncation indicator")
        XCTAssertEqual(result.count, 500, "Truncated message should be exactly 500 characters")
    }

    func testTruncateLongMessage() {
        let message = String(repeating: "x", count: 2000)
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertTrue(result.hasSuffix("...[truncated]"))
        XCTAssertEqual(result.count, 500)
    }

    func testTruncateVeryLongMessage() {
        let message = String(repeating: "z", count: 100_000)
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertTrue(result.hasSuffix("...[truncated]"))
        XCTAssertEqual(result.count, 500)
    }

    func testTruncatePreservesPrefix() {
        let prefix = "ERROR: Something went wrong in "
        let message = prefix + String(repeating: "d", count: 500)
        let result = ErrorReportingService.truncateErrorMessage(message)

        // The truncated message should start with the same prefix
        XCTAssertTrue(result.hasPrefix(prefix), "Truncation should preserve the beginning of the message")
        XCTAssertTrue(result.hasSuffix("...[truncated]"))
    }

    func testTruncateWithUnicodeCharacters() {
        // Unicode characters (emoji) that are single Character values in Swift
        let message = String(repeating: "🔥", count: 501)
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertTrue(result.hasSuffix("...[truncated]"))
        XCTAssertEqual(result.count, 500)
    }

    func testTruncateWithMultibyteCharacters() {
        // Mix of ASCII and multi-byte characters
        let message = "Error: " + String(repeating: "日本語", count: 200)
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertTrue(result.count <= 500)
        if message.count > 500 {
            XCTAssertTrue(result.hasSuffix("...[truncated]"))
        }
    }

    func testTruncationIndicatorContent() {
        // Verify the truncation indicator is what we expect
        let message = String(repeating: "a", count: 501)
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertTrue(result.hasSuffix("...[truncated]"))
        // The non-truncated portion should be 500 - "...[truncated]".count = 486 characters
        let indicatorLength = "...[truncated]".count  // 14
        let contentLength = 500 - indicatorLength  // 486
        let content = String(result.prefix(contentLength))
        XCTAssertEqual(content, String(repeating: "a", count: contentLength))
    }

    // MARK: - truncateErrorMessage - Boundary Values

    func testTruncateMessageOfLengthEqualToMaxMinusIndicator() {
        // 486 characters = 500 - "...[truncated]".count
        // This is under the limit, should not be truncated
        let indicatorLength = "...[truncated]".count
        let message = String(repeating: "e", count: 500 - indicatorLength)
        let result = ErrorReportingService.truncateErrorMessage(message)
        XCTAssertEqual(result, message, "Message shorter than max should not be truncated")
        XCTAssertFalse(result.contains("[truncated]"))
    }

    // MARK: - Logging Extension Methods (Smoke Tests)

    // These methods call through to the private `log()` which early-returns
    // when Sentry is not configured (test environment). We verify they don't crash.

    func testLogSyncStartDoesNotCrash() {
        // Should not crash even without Sentry configured
        ErrorReportingService.logSyncStart(syncId: "test-sync-1", trigger: "manual")
    }

    func testLogSyncCompleteDoesNotCrash() {
        ErrorReportingService.logSyncComplete(
            syncId: "test-sync-1",
            duration: 1.5,
            itemsUploaded: 10,
            itemsDownloaded: 5
        )
    }

    func testLogSyncFailureWithInternetReachable() {
        let error = NSError(domain: "test", code: 500, userInfo: [
            NSLocalizedDescriptionKey: "Internal Server Error"
        ])
        ErrorReportingService.logSyncFailure(
            syncId: "test-sync-2",
            duration: 0.5,
            error: error,
            failureReason: "Server returned 500",
            internetReachable: true
        )
    }

    func testLogSyncFailureWithoutInternet() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [
            NSLocalizedDescriptionKey: "The Internet connection appears to be offline."
        ])
        ErrorReportingService.logSyncFailure(
            syncId: "test-sync-3",
            duration: 0.1,
            error: error,
            failureReason: "No internet connection",
            internetReachable: false
        )
    }

    func testLogAPIResponseSuccess() {
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/v1/stacks",
            statusCode: 200,
            responseSize: 1024
        )
    }

    func testLogAPIResponseClientError() {
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/v1/stacks",
            statusCode: 404,
            responseSize: 128,
            error: "Not Found"
        )
    }

    func testLogAPIResponseServerError() {
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/v1/sync",
            statusCode: 500,
            responseSize: nil,
            error: "Internal Server Error"
        )
    }

    func testLogAPIResponseWithNilResponseSize() {
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/v1/tasks",
            statusCode: 204,
            responseSize: nil
        )
    }

    func testLogAPIResponseWithLongErrorMessage() {
        let longError = String(repeating: "Error detail. ", count: 100)
        ErrorReportingService.logAPIResponse(
            endpoint: "/api/v1/sync",
            statusCode: 500,
            responseSize: 0,
            error: longError
        )
    }

    func testLogAppLaunchCold() {
        ErrorReportingService.logAppLaunch(isWarmLaunch: false)
    }

    func testLogAppLaunchWarm() {
        ErrorReportingService.logAppLaunch(isWarmLaunch: true)
    }

    func testLogAppForeground() {
        ErrorReportingService.logAppForeground()
    }

    func testLogAppBackground() {
        ErrorReportingService.logAppBackground(pendingSyncItems: 5)
    }

    func testLogAppBackgroundWithZeroPendingItems() {
        ErrorReportingService.logAppBackground(pendingSyncItems: 0)
    }

    // MARK: - Core Logging Methods (Smoke Tests)

    func testLogDebugDoesNotCrash() {
        ErrorReportingService.logDebug("Test debug message")
    }

    func testLogInfoDoesNotCrash() {
        ErrorReportingService.logInfo("Test info message")
    }

    func testLogWarningDoesNotCrash() {
        ErrorReportingService.logWarning("Test warning message")
    }

    func testLogErrorDoesNotCrash() {
        ErrorReportingService.logError("Test error message")
    }

    func testLogWithAttributesDoesNotCrash() {
        ErrorReportingService.logDebug("Test with attributes", attributes: [
            "key1": "value1",
            "key2": 42,
            "key3": true
        ])
    }

    func testLogWithEmptyAttributesDoesNotCrash() {
        ErrorReportingService.logInfo("Test with empty attributes", attributes: [:])
    }

    // MARK: - Error Capture (Smoke Tests)

    func testCaptureErrorDoesNotCrash() {
        let error = NSError(domain: "test", code: 42, userInfo: nil)
        ErrorReportingService.capture(error: error)
    }

    func testCaptureErrorWithContextDoesNotCrash() {
        let error = NSError(domain: "test", code: 42, userInfo: nil)
        ErrorReportingService.capture(error: error, context: [
            "operation": "sync",
            "retryCount": 3
        ])
    }

    func testCaptureMessageDoesNotCrash() {
        ErrorReportingService.capture(message: "Test message")
    }

    // MARK: - User Context (Smoke Tests)

    func testSetUserDoesNotCrash() {
        ErrorReportingService.setUser(id: "user-123", email: "test@example.com")
    }

    func testSetUserWithoutEmailDoesNotCrash() {
        ErrorReportingService.setUser(id: "user-123")
    }

    func testClearUserDoesNotCrash() {
        ErrorReportingService.clearUser()
    }

    // MARK: - Breadcrumbs (Smoke Tests)

    func testAddBreadcrumbDoesNotCrash() {
        ErrorReportingService.addBreadcrumb(
            category: "test",
            message: "Test breadcrumb"
        )
    }

    func testAddBreadcrumbWithDataDoesNotCrash() {
        ErrorReportingService.addBreadcrumb(
            category: "navigation",
            message: "Navigated to stack detail",
            data: ["stackId": "stack-123"]
        )
    }

    // MARK: - API Response Status Code Ranges

    func testLogAPIResponseBoundaryStatusCodes() {
        // Test boundary values for status code ranges
        // 200 range boundary
        ErrorReportingService.logAPIResponse(endpoint: "/test", statusCode: 200, responseSize: 0)
        ErrorReportingService.logAPIResponse(endpoint: "/test", statusCode: 299, responseSize: 0)

        // 400 range boundary
        ErrorReportingService.logAPIResponse(endpoint: "/test", statusCode: 400, responseSize: 0)
        ErrorReportingService.logAPIResponse(endpoint: "/test", statusCode: 499, responseSize: 0)

        // 500 range boundary
        ErrorReportingService.logAPIResponse(endpoint: "/test", statusCode: 500, responseSize: 0)
        ErrorReportingService.logAPIResponse(endpoint: "/test", statusCode: 599, responseSize: 0)

        // Outside defined ranges (e.g., 300, 600) - should not log (no crash)
        ErrorReportingService.logAPIResponse(endpoint: "/test", statusCode: 301, responseSize: 0)
        ErrorReportingService.logAPIResponse(endpoint: "/test", statusCode: 600, responseSize: 0)
        ErrorReportingService.logAPIResponse(endpoint: "/test", statusCode: 100, responseSize: 0)
    }

    // MARK: - Configuration Constants

    func testTracePropagationTargetsIncludesExpectedHosts() {
        let targets = Configuration.tracePropagationTargets
        XCTAssertTrue(targets.contains("api.dequeue.app"))
        XCTAssertTrue(targets.contains("sync.ardonos.com"))
        XCTAssertTrue(targets.contains("localhost"))
        XCTAssertTrue(targets.contains("127.0.0.1"))
    }
}
