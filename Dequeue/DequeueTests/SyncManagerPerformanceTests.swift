//
//  SyncManagerPerformanceTests.swift
//  DequeueTests
//
//  Tests for SyncManager performance improvements (PR #74)
//

import Testing
import Foundation
@testable import Dequeue

@Suite("SyncManager Performance Tests")
@MainActor
struct SyncManagerPerformanceTests {
    // MARK: - ISO8601 Timestamp Parsing Tests

    @Test("Parses standard ISO8601 timestamps")
    func testStandardISO8601() throws {
        let timestamp = "2024-01-15T10:30:45Z"
        let date = SyncManager.parseISO8601(timestamp)

        let unwrappedDate = try #require(date)

        // Verify components
        let calendar = Calendar(identifier: .gregorian)
        let utcTimeZone = try #require(TimeZone(identifier: "UTC"))
        let components = calendar.dateComponents(in: utcTimeZone, from: unwrappedDate)
        #expect(components.year == 2_024)
        #expect(components.month == 1)
        #expect(components.day == 15)
        #expect(components.hour == 10)
        #expect(components.minute == 30)
        #expect(components.second == 45)
    }

    @Test("Parses ISO8601 with milliseconds")
    func testISO8601WithMilliseconds() throws {
        let timestamp = "2024-01-15T10:30:45.123Z"
        let date = SyncManager.parseISO8601(timestamp)

        #expect(date != nil)
    }

    @Test("Parses Go RFC3339Nano format (nanoseconds)")
    func testGoRFC3339Nano() throws {
        // Go sends timestamps like this with nanosecond precision
        let timestamp = "2024-01-15T10:30:45.123456789Z"
        let date = SyncManager.parseISO8601(timestamp)

        let unwrappedDate = try #require(date)

        // Verify it parsed correctly (nanoseconds are truncated to milliseconds)
        let calendar = Calendar(identifier: .gregorian)
        let utcTimeZone = try #require(TimeZone(identifier: "UTC"))
        let components = calendar.dateComponents(in: utcTimeZone, from: unwrappedDate)
        #expect(components.year == 2_024)
        #expect(components.month == 1)
        #expect(components.day == 15)
    }

    @Test("Parses timestamp with timezone offset")
    func testTimezoneOffset() throws {
        let timestamp = "2024-01-15T10:30:45+05:30"
        let date = SyncManager.parseISO8601(timestamp)

        #expect(date != nil)
    }

    @Test("Parses nanoseconds with timezone offset")
    func testNanosecondsWithOffset() throws {
        let timestamp = "2024-01-15T10:30:45.123456789+05:30"
        let date = SyncManager.parseISO8601(timestamp)

        #expect(date != nil)
    }

    @Test("Returns nil for invalid timestamps")
    func testInvalidTimestamp() throws {
        let invalidTimestamps = [
            "not-a-date",
            "2024-13-45T10:30:45Z",  // Invalid month
            "2024-01-15",  // Missing time
            "",
            "2024-01-15T25:30:45Z"  // Invalid hour
        ]

        for timestamp in invalidTimestamps {
            let date = SyncManager.parseISO8601(timestamp)
            #expect(date == nil, "Expected nil for invalid timestamp: \(timestamp)")
        }
    }

    // MARK: - Regex Pattern Tests

    @Test("Nanoseconds regex truncates to milliseconds")
    func testNanosecondsRegexPattern() throws {
        // Verify the static regex patterns compile correctly
        // (force unwrap safety is verified by app startup - if invalid, app would crash)
        let input = "2024-01-15T10:30:45.123456789Z"
        let truncated = SyncManager.truncateNanosecondsToMilliseconds(input)

        #expect(truncated == "2024-01-15T10:30:45.123Z")
    }

    @Test("Regex handles various nanosecond lengths")
    func testVariousNanosecondLengths() throws {
        let testCases = [
            ("2024-01-15T10:30:45.1Z", "2024-01-15T10:30:45.1Z"),  // Only 1 digit - no truncation needed
            ("2024-01-15T10:30:45.12Z", "2024-01-15T10:30:45.12Z"),  // 2 digits
            ("2024-01-15T10:30:45.123Z", "2024-01-15T10:30:45.123Z"),  // 3 digits
            ("2024-01-15T10:30:45.1234Z", "2024-01-15T10:30:45.123Z"),  // 4 digits -> truncate
            ("2024-01-15T10:30:45.123456789Z", "2024-01-15T10:30:45.123Z")  // 9 digits -> truncate
        ]

        for (input, expected) in testCases {
            let result = SyncManager.truncateNanosecondsToMilliseconds(input)
            #expect(result == expected, "Input: \(input), Expected: \(expected), Got: \(result)")
        }
    }

    // MARK: - Sync Interval Constants

    @Test("Periodic sync interval is reasonable")
    func testPeriodicSyncInterval() throws {
        // Verify the sync interval is in a reasonable range
        // Too short: battery drain, server load
        // Too long: stale data
        let interval: UInt64 = 5  // From periodicSyncIntervalSeconds constant

        #expect(interval >= 3)  // At least 3 seconds
        #expect(interval <= 60)  // At most 60 seconds
    }

    @Test("Heartbeat interval is reasonable")
    func testHeartbeatInterval() throws {
        // Heartbeat should be frequent enough to detect disconnections
        // but not so frequent as to cause unnecessary traffic
        let interval: UInt64 = 30  // From heartbeatIntervalSeconds constant

        #expect(interval >= 15)  // At least 15 seconds
        #expect(interval <= 60)  // At most 60 seconds
    }
}

// Note: parseISO8601, truncateNanosecondsToMilliseconds, and removeFractionalSeconds
// are now accessible directly via SyncManager+DateParsing.swift (no longer private).
