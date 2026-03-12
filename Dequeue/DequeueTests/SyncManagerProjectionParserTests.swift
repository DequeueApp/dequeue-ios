//
//  SyncManagerProjectionParserTests.swift
//  DequeueTests
//
//  Tests for the static status-parsing helpers in SyncManager+ProjectionSync,
//  and the nonisolated date-parsing utilities parseISO8601(_:) and
//  dateFromUnixMs(_:) used throughout the projection sync pipeline.
//  These pure/nonisolated functions map raw API strings → typed Swift values
//  and handle legacy values ("draft", "in_progress") as well as unknown/garbage input.
//

import Testing
import Foundation
import SwiftData
@testable import Dequeue

@Suite("SyncManager Projection Parser Tests")
struct SyncManagerProjectionParserTests {

    // MARK: - parseArcStatus

    @Suite("parseArcStatus")
    struct ParseArcStatusTests {
        @Test("parses known arc statuses")
        func parsesKnownValues() {
            #expect(SyncManager.parseArcStatus("active") == .active)
            #expect(SyncManager.parseArcStatus("completed") == .completed)
            #expect(SyncManager.parseArcStatus("paused") == .paused)
            #expect(SyncManager.parseArcStatus("archived") == .archived)
        }

        @Test("is case-insensitive")
        func isCaseInsensitive() {
            #expect(SyncManager.parseArcStatus("ACTIVE") == .active)
            #expect(SyncManager.parseArcStatus("Completed") == .completed)
            #expect(SyncManager.parseArcStatus("PAUSED") == .paused)
            #expect(SyncManager.parseArcStatus("Archived") == .archived)
        }

        @Test("returns .active for unknown values")
        func returnsActiveForUnknown() {
            #expect(SyncManager.parseArcStatus("unknown") == .active)
            #expect(SyncManager.parseArcStatus("") == .active)
            #expect(SyncManager.parseArcStatus("deleted") == .active)
        }
    }

    // MARK: - parseStackStatus

    @Suite("parseStackStatus")
    struct ParseStackStatusTests {
        @Test("parses known stack statuses")
        func parsesKnownValues() {
            #expect(SyncManager.parseStackStatus("active") == .active)
            #expect(SyncManager.parseStackStatus("completed") == .completed)
            #expect(SyncManager.parseStackStatus("closed") == .closed)
            #expect(SyncManager.parseStackStatus("archived") == .archived)
        }

        @Test("maps legacy 'draft' to .active")
        func mapsDraftToActive() {
            #expect(SyncManager.parseStackStatus("draft") == .active)
        }

        @Test("maps legacy 'in_progress' to .active")
        func mapsInProgressToActive() {
            #expect(SyncManager.parseStackStatus("in_progress") == .active)
        }

        @Test("is case-insensitive")
        func isCaseInsensitive() {
            #expect(SyncManager.parseStackStatus("ACTIVE") == .active)
            #expect(SyncManager.parseStackStatus("Completed") == .completed)
            #expect(SyncManager.parseStackStatus("CLOSED") == .closed)
            #expect(SyncManager.parseStackStatus("Archived") == .archived)
            #expect(SyncManager.parseStackStatus("DRAFT") == .active)
            #expect(SyncManager.parseStackStatus("In_Progress") == .active)
        }

        @Test("returns .active for unknown values")
        func returnsActiveForUnknown() {
            #expect(SyncManager.parseStackStatus("unknown") == .active)
            #expect(SyncManager.parseStackStatus("") == .active)
            #expect(SyncManager.parseStackStatus("pending") == .active)
        }
    }

    // MARK: - parseTaskStatus

    @Suite("parseTaskStatus")
    struct ParseTaskStatusTests {
        @Test("parses known task statuses")
        func parsesKnownValues() {
            #expect(SyncManager.parseTaskStatus("pending") == .pending)
            #expect(SyncManager.parseTaskStatus("completed") == .completed)
            #expect(SyncManager.parseTaskStatus("blocked") == .blocked)
            #expect(SyncManager.parseTaskStatus("closed") == .closed)
        }

        @Test("maps legacy 'in_progress' to .pending")
        func mapsInProgressToPending() {
            #expect(SyncManager.parseTaskStatus("in_progress") == .pending)
        }

        @Test("is case-insensitive")
        func isCaseInsensitive() {
            #expect(SyncManager.parseTaskStatus("PENDING") == .pending)
            #expect(SyncManager.parseTaskStatus("Completed") == .completed)
            #expect(SyncManager.parseTaskStatus("BLOCKED") == .blocked)
            #expect(SyncManager.parseTaskStatus("Closed") == .closed)
            #expect(SyncManager.parseTaskStatus("IN_PROGRESS") == .pending)
        }

        @Test("returns .pending for unknown values")
        func returnsPendingForUnknown() {
            #expect(SyncManager.parseTaskStatus("unknown") == .pending)
            #expect(SyncManager.parseTaskStatus("") == .pending)
            #expect(SyncManager.parseTaskStatus("active") == .pending)
        }
    }

    // MARK: - parseReminderStatus

    @Suite("parseReminderStatus")
    struct ParseReminderStatusTests {
        @Test("parses known reminder statuses")
        func parsesKnownValues() {
            #expect(SyncManager.parseReminderStatus("active") == .active)
            #expect(SyncManager.parseReminderStatus("snoozed") == .snoozed)
            #expect(SyncManager.parseReminderStatus("fired") == .fired)
        }

        @Test("is case-insensitive")
        func isCaseInsensitive() {
            #expect(SyncManager.parseReminderStatus("ACTIVE") == .active)
            #expect(SyncManager.parseReminderStatus("Snoozed") == .snoozed)
            #expect(SyncManager.parseReminderStatus("FIRED") == .fired)
        }

        @Test("returns .active for unknown values")
        func returnsActiveForUnknown() {
            #expect(SyncManager.parseReminderStatus("unknown") == .active)
            #expect(SyncManager.parseReminderStatus("") == .active)
            #expect(SyncManager.parseReminderStatus("pending") == .active)
        }
    }
}

// MARK: - Date Parsing Utilities

// These tests cover the nonisolated instance helpers parseISO8601(_:) and
// dateFromUnixMs(_:) defined in SyncManager+ProjectionSync.swift.  They are
// called on every sync pull to convert raw API date strings / Unix-ms timestamps
// into Swift Date values.  A SyncManager is constructed with an in-memory
// ModelContainer so the nonisolated methods can be called synchronously.

@Suite("SyncManager Date Parsers")
struct SyncManagerDateParsersTests {

    // MARK: - Helpers

    private static func makeSyncManager() throws -> SyncManager {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Event.self, configurations: config)
        return SyncManager(modelContainer: container)
    }

    // MARK: - parseISO8601

    @Suite("parseISO8601")
    struct ParseISO8601Tests {

        @Test("returns nil for nil input")
        func returnsNilForNilInput() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            #expect(sm.parseISO8601(nil) == nil)
        }

        @Test("returns nil for empty string")
        func returnsNilForEmptyString() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            #expect(sm.parseISO8601("") == nil)
        }

        @Test("returns nil for obviously invalid string")
        func returnsNilForGarbage() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            #expect(sm.parseISO8601("not-a-date") == nil)
        }

        @Test("parses a UTC ISO8601 date string correctly")
        func parsesUTCDateString() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            // Build the expected date from components to avoid hardcoding a timestamp.
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let comps = DateComponents(year: 2024, month: 1, day: 15, hour: 10, minute: 30, second: 45)
            let expected = try #require(cal.date(from: comps))
            let result = sm.parseISO8601("2024-01-15T10:30:45Z")
            #expect(result != nil)
            if let result = result {
                // Allow 1-second tolerance for any sub-second rounding
                #expect(abs(result.timeIntervalSince1970 - expected.timeIntervalSince1970) < 1)
            }
        }

        @Test("parses a date at Unix epoch correctly")
        func parsesUnixEpoch() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            let result = sm.parseISO8601("1970-01-01T00:00:00Z")
            #expect(result != nil)
            if let result = result {
                #expect(abs(result.timeIntervalSince1970) < 1)
            }
        }

        @Test("round-trips through SyncManager.iso8601Standard formatter")
        func roundTrip() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            let original = Date(timeIntervalSince1970: 1_700_000_000)
            let string = SyncManager.iso8601Standard.string(from: original)
            let parsed = sm.parseISO8601(string)
            #expect(parsed != nil)
            if let parsed = parsed {
                #expect(abs(parsed.timeIntervalSince1970 - original.timeIntervalSince1970) < 1)
            }
        }
    }

    // MARK: - dateFromUnixMs (non-optional)

    @Suite("dateFromUnixMs — non-optional")
    struct DateFromUnixMsTests {

        @Test("epoch ms 0 returns Unix epoch")
        func epochZeroIsUnixEpoch() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            let date = sm.dateFromUnixMs(Int64(0))
            #expect(date.timeIntervalSince1970 == 0)
        }

        @Test("positive ms converts correctly")
        func positiveMs() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            // Use a round known value: 1_000_000_000_000 ms == 1_000_000_000 s (2001-09-09T01:46:40Z)
            let ms = Int64(1_000_000_000_000)
            let date = sm.dateFromUnixMs(ms)
            let expected = Date(timeIntervalSince1970: 1_000_000_000)
            #expect(abs(date.timeIntervalSince1970 - expected.timeIntervalSince1970) < 0.001)
        }

        @Test("1000 ms equals exactly 1 second")
        func oneSecond() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            let date = sm.dateFromUnixMs(Int64(1_000))
            #expect(date.timeIntervalSince1970 == 1.0)
        }

        @Test("large timestamp stays within Double precision")
        func largeTimestamp() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            // Year ~2100: well within Double representable range
            let date = sm.dateFromUnixMs(Int64(4_102_444_800_000))
            #expect(date.timeIntervalSince1970 > 0)
        }
    }

    // MARK: - dateFromUnixMs (optional overload)

    @Suite("dateFromUnixMs — optional")
    struct DateFromUnixMsOptionalTests {

        @Test("nil input returns nil")
        func nilInputReturnsNil() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            let result: Date? = sm.dateFromUnixMs(nil as Int64?)
            #expect(result == nil)
        }

        @Test("non-nil input returns correct date")
        func nonNilInputConverts() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            let ms = Int64?(1_000_000_000_000)
            let result = sm.dateFromUnixMs(ms)
            let expected = Date(timeIntervalSince1970: 1_000_000_000)
            #expect(result != nil)
            if let result = result {
                #expect(abs(result.timeIntervalSince1970 - expected.timeIntervalSince1970) < 0.001)
            }
        }

        @Test("epoch ms 0 in optional overload returns epoch date")
        func epochZeroOptional() throws {
            let sm = try SyncManagerDateParsersTests.makeSyncManager()
            let result = sm.dateFromUnixMs(Int64?(0))
            #expect(result != nil)
            if let result = result {
                #expect(result.timeIntervalSince1970 == 0)
            }
        }
    }
}
