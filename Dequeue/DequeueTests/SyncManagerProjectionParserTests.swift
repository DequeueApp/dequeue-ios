//
//  SyncManagerProjectionParserTests.swift
//  DequeueTests
//
//  Tests for the static status-parsing helpers in SyncManager+ProjectionSync.
//  These pure functions map raw API strings → typed Swift enums and handle legacy
//  values ("draft", "in_progress") as well as unknown/garbage input.
//

import Testing
import Foundation
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
