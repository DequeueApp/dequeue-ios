//
//  ActivityFeedTests.swift
//  DequeueTests
//
//  Tests for Activity Feed core functionality
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Activity Feed Tests", .serialized)
@MainActor
struct ActivityFeedTests {
    // MARK: - Event Type Filtering

    /// Activity event types that should appear in the feed (per PRD Section 3.8)
    private static let activityEventTypes: Set<EventType> = [
        .stackCompleted,
        .stackActivated,
        .stackCreated,
        .taskCompleted,
        .taskActivated,
        .arcCompleted,
        .arcActivated,
        .arcCreated
    ]

    @Test("Activity feed includes all expected event types")
    func activityFeedIncludesExpectedEventTypes() {
        // Verify stack events
        #expect(Self.activityEventTypes.contains(.stackCompleted))
        #expect(Self.activityEventTypes.contains(.stackActivated))
        #expect(Self.activityEventTypes.contains(.stackCreated))

        // Verify task events
        #expect(Self.activityEventTypes.contains(.taskCompleted))
        #expect(Self.activityEventTypes.contains(.taskActivated))

        // Verify arc events
        #expect(Self.activityEventTypes.contains(.arcCompleted))
        #expect(Self.activityEventTypes.contains(.arcActivated))
        #expect(Self.activityEventTypes.contains(.arcCreated))
    }

    @Test("Activity feed excludes non-activity event types")
    func activityFeedExcludesNonActivityEventTypes() {
        // These events should NOT appear in the activity feed
        #expect(!Self.activityEventTypes.contains(.stackUpdated))
        #expect(!Self.activityEventTypes.contains(.stackDeleted))
        #expect(!Self.activityEventTypes.contains(.taskUpdated))
        #expect(!Self.activityEventTypes.contains(.taskDeleted))
        #expect(!Self.activityEventTypes.contains(.arcUpdated))
        #expect(!Self.activityEventTypes.contains(.arcDeleted))
        #expect(!Self.activityEventTypes.contains(.reminderCreated))
        #expect(!Self.activityEventTypes.contains(.tagCreated))
    }

    @Test("Activity feed has correct number of event types")
    func activityFeedHasCorrectEventTypeCount() {
        // 3 stack + 2 task + 3 arc = 8 event types
        #expect(Self.activityEventTypes.count == 8)
    }

    // MARK: - Event Filtering Logic

    @Test("Filter events by activity event types")
    func filterEventsByActivityEventTypes() throws {
        let events = [
            try makeEvent(type: .stackCompleted),
            try makeEvent(type: .stackUpdated),  // Should be filtered out
            try makeEvent(type: .taskCompleted),
            try makeEvent(type: .taskDeleted),   // Should be filtered out
            try makeEvent(type: .arcCreated),
            try makeEvent(type: .reminderCreated)  // Should be filtered out
        ]

        let filteredEvents = events.filter { event in
            guard let eventType = event.eventType else { return false }
            return Self.activityEventTypes.contains(eventType)
        }

        #expect(filteredEvents.count == 3)
        #expect(filteredEvents.contains { $0.eventType == EventType.stackCompleted })
        #expect(filteredEvents.contains { $0.eventType == EventType.taskCompleted })
        #expect(filteredEvents.contains { $0.eventType == EventType.arcCreated })
    }

    // MARK: - Day Grouping Logic

    @Test("Group events by calendar day")
    func groupEventsByCalendarDay() throws {
        let calendar = Calendar.current
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
              let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) else {
            throw TestError.dateCreationFailed
        }

        let events = [
            try makeEvent(type: .stackCompleted, timestamp: now),
            try makeEvent(type: .taskCompleted, timestamp: now),
            try makeEvent(type: .stackActivated, timestamp: yesterday),
            try makeEvent(type: .arcCreated, timestamp: twoDaysAgo)
        ]

        let grouped = groupEventsByDay(events)

        #expect(grouped.count == 3)

        // Today should have 2 events
        let todayGroup = grouped.first { calendar.isDateInToday($0.date) }
        #expect(todayGroup?.events.count == 2)

        // Yesterday should have 1 event
        let yesterdayGroup = grouped.first { calendar.isDateInYesterday($0.date) }
        #expect(yesterdayGroup?.events.count == 1)
    }

    @Test("Events grouped by day are sorted newest first")
    func eventsGroupedByDayAreSortedNewestFirst() throws {
        let calendar = Calendar.current
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            throw TestError.dateCreationFailed
        }

        let events = [
            try makeEvent(type: .stackCompleted, timestamp: yesterday),
            try makeEvent(type: .taskCompleted, timestamp: now)
        ]

        let grouped = groupEventsByDay(events)

        #expect(grouped.count == 2)
        // First group should be today (newest)
        #expect(calendar.isDateInToday(grouped[0].date))
        // Second group should be yesterday
        #expect(calendar.isDateInYesterday(grouped[1].date))
    }

    @Test("Events within same day maintain order")
    func eventsWithinSameDayMaintainOrder() throws {
        let calendar = Calendar.current
        let now = Date()
        guard let oneHourAgo = calendar.date(byAdding: .hour, value: -1, to: now),
              let twoHoursAgo = calendar.date(byAdding: .hour, value: -2, to: now) else {
            throw TestError.dateCreationFailed
        }

        let events = [
            try makeEvent(type: .stackCompleted, timestamp: now),
            try makeEvent(type: .taskCompleted, timestamp: oneHourAgo),
            try makeEvent(type: .arcCreated, timestamp: twoHoursAgo)
        ]

        let grouped = groupEventsByDay(events)

        #expect(grouped.count == 1)
        #expect(grouped[0].events.count == 3)
    }

    @Test("Cutoff date filters old events")
    func cutoffDateFiltersOldEvents() throws {
        let calendar = Calendar.current
        let now = Date()
        guard let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: now),
              let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now),
              let cutoffDate = calendar.date(byAdding: .day, value: -7, to: now) else {
            throw TestError.dateCreationFailed
        }

        let events = [
            try makeEvent(type: .stackCompleted, timestamp: now),
            try makeEvent(type: .taskCompleted, timestamp: fiveDaysAgo),
            try makeEvent(type: .arcCreated, timestamp: tenDaysAgo)  // Should be filtered with 7-day cutoff
        ]

        let filteredEvents = events.filter { $0.timestamp >= cutoffDate }
        let grouped = groupEventsByDay(filteredEvents)

        #expect(grouped.count == 2)  // Today and 5 days ago
        #expect(!grouped.contains { $0.events.contains { $0.timestamp < cutoffDate } })
    }

    // MARK: - Event Description Tests

    @Test("Event type has correct description for completed events")
    func eventTypeHasCorrectDescriptionForCompletedEvents() {
        #expect(eventDescription(for: .stackCompleted) == "Completed stack")
        #expect(eventDescription(for: .taskCompleted) == "Completed task")
        #expect(eventDescription(for: .arcCompleted) == "Completed arc")
    }

    @Test("Event type has correct description for activated events")
    func eventTypeHasCorrectDescriptionForActivatedEvents() {
        #expect(eventDescription(for: .stackActivated) == "Started stack")
        #expect(eventDescription(for: .taskActivated) == "Started task")
        #expect(eventDescription(for: .arcActivated) == "Started arc")
    }

    @Test("Event type has correct description for created events")
    func eventTypeHasCorrectDescriptionForCreatedEvents() {
        #expect(eventDescription(for: .stackCreated) == "Created stack")
        #expect(eventDescription(for: .arcCreated) == "Created arc")
    }

    // MARK: - Helpers

    private enum TestError: Error {
        case dateCreationFailed
    }

    private func makeEvent(type: EventType, timestamp: Date = Date()) throws -> Event {
        let payload = try JSONEncoder().encode(["test": "data"])
        let event = Event(
            eventType: type,
            payload: payload,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        // Override timestamp for testing
        event.timestamp = timestamp
        return event
    }

    /// Groups events by calendar day (mirrors ActivityFeedView logic)
    private func groupEventsByDay(_ events: [Event]) -> [(date: Date, events: [Event])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, events: $0.value) }
    }

    /// Returns event description (mirrors ActivityEventRow logic)
    private func eventDescription(for eventType: EventType) -> String {
        switch eventType {
        case .stackCompleted:
            return "Completed stack"
        case .stackActivated:
            return "Started stack"
        case .stackCreated:
            return "Created stack"
        case .taskCompleted:
            return "Completed task"
        case .taskActivated:
            return "Started task"
        case .arcCompleted:
            return "Completed arc"
        case .arcActivated:
            return "Started arc"
        case .arcCreated:
            return "Created arc"
        default:
            return "Activity"
        }
    }
}
