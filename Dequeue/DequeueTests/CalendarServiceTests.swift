//
//  CalendarServiceTests.swift
//  DequeueTests
//
//  Tests for CalendarService and CalendarEvent model
//

import XCTest
@testable import Dequeue

final class CalendarServiceTests: XCTestCase {

    // MARK: - CalendarEvent Model Tests

    func testCalendarEventInitialization() {
        let start = Date()
        let end = start.addingTimeInterval(3600) // 1 hour later

        let event = CalendarEvent(
            title: "Team Meeting",
            startDate: start,
            endDate: end,
            location: "Conference Room A",
            calendarName: "Work"
        )

        XCTAssertEqual(event.title, "Team Meeting")
        XCTAssertEqual(event.startDate, start)
        XCTAssertEqual(event.endDate, end)
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(event.location, "Conference Room A")
        XCTAssertEqual(event.calendarName, "Work")
    }

    func testCalendarEventAllDay() {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

        let event = CalendarEvent(
            title: "Holiday",
            startDate: start,
            endDate: end,
            isAllDay: true,
            calendarName: "Personal"
        )

        XCTAssertTrue(event.isAllDay)
    }

    func testCalendarEventEquality() {
        let id = "test-event-123"
        let start = Date()
        let end = start.addingTimeInterval(3600)

        let event1 = CalendarEvent(id: id, title: "Event", startDate: start, endDate: end)
        let event2 = CalendarEvent(id: id, title: "Event", startDate: start, endDate: end)
        let event3 = CalendarEvent(id: "different", title: "Event", startDate: start, endDate: end)

        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }

    func testCalendarEventWithNotes() {
        let event = CalendarEvent(
            title: "Lunch",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            notes: "Bring documents"
        )

        XCTAssertEqual(event.notes, "Bring documents")
    }

    func testCalendarEventWithColor() {
        let event = CalendarEvent(
            title: "Sprint Review",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarColor: "#FF5733"
        )

        XCTAssertEqual(event.calendarColor, "#FF5733")
    }

    func testCalendarEventWithoutOptionals() {
        let event = CalendarEvent(
            title: "Quick Event",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800)
        )

        XCTAssertNil(event.location)
        XCTAssertNil(event.notes)
    }

    // MARK: - CalendarInfo Tests

    // Note: CalendarInfo requires EKCalendar which needs EventKit entitlement
    // Testing model-level behavior only

    // MARK: - CalendarError Tests

    func testCalendarErrorNotAuthorized() {
        let error = CalendarError.notAuthorized
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not authorized"))
    }

    func testCalendarErrorEventNotFound() {
        let error = CalendarError.eventNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not found"))
    }

    func testCalendarErrorSaveFailed() {
        let underlyingError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "disk full"])
        let error = CalendarError.saveFailed(underlyingError)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("disk full"))
    }

    // MARK: - Task Data from Event Tests

    func testTaskDataFromEventBasic() {
        let event = CalendarEvent(
            title: "Sprint Planning",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )

        let data = CalendarService.shared.taskDataFromEvent(event)
        XCTAssertEqual(data.title, "Sprint Planning")
        XCTAssertEqual(data.startTime, event.startDate)
        XCTAssertEqual(data.dueTime, event.endDate)
    }

    func testTaskDataFromEventWithLocation() {
        let event = CalendarEvent(
            title: "Client Meeting",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            location: "123 Main St"
        )

        let data = CalendarService.shared.taskDataFromEvent(event)
        XCTAssertNotNil(data.description)
        XCTAssertTrue(data.description!.contains("123 Main St"))
    }

    func testTaskDataFromEventWithNotes() {
        let event = CalendarEvent(
            title: "Code Review",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            notes: "Review PR #321"
        )

        let data = CalendarService.shared.taskDataFromEvent(event)
        XCTAssertNotNil(data.description)
        XCTAssertTrue(data.description!.contains("Review PR #321"))
    }

    func testTaskDataFromEventWithLocationAndNotes() {
        let event = CalendarEvent(
            title: "Workshop",
            startDate: Date(),
            endDate: Date().addingTimeInterval(7200),
            location: "Room 5B",
            notes: "Bring laptop"
        )

        let data = CalendarService.shared.taskDataFromEvent(event)
        XCTAssertNotNil(data.description)
        XCTAssertTrue(data.description!.contains("Room 5B"))
        XCTAssertTrue(data.description!.contains("Bring laptop"))
    }

    func testTaskDataFromEventNoOptionals() {
        let event = CalendarEvent(
            title: "Quick Sync",
            startDate: Date(),
            endDate: Date().addingTimeInterval(900)
        )

        let data = CalendarService.shared.taskDataFromEvent(event)
        XCTAssertNil(data.description)
    }

    // MARK: - Authorization Status Tests

    func testInitialAuthorizationStatus() {
        // CalendarService checks EKEventStore status on init
        let service = CalendarService.shared
        // Status should be one of the valid values
        let validStatuses: [Int] = [0, 1, 2, 3, 4] // EKAuthorizationStatus raw values
        XCTAssertTrue(validStatuses.contains(service.authorizationStatus.rawValue))
    }

    // MARK: - Events List Tests

    func testInitialEventsAreEmpty() {
        let service = CalendarService.shared
        // Without authorization, events should be empty
        if !service.isAuthorized {
            XCTAssertTrue(service.todayEvents.isEmpty)
            XCTAssertTrue(service.upcomingEvents.isEmpty)
        }
    }
}
