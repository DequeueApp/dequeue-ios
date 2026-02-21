//
//  CalendarService.swift
//  Dequeue
//
//  EventKit integration: sync tasks with system calendar, show upcoming events
//

import EventKit
import Foundation
import os

private let logger = Logger(subsystem: "com.dequeue", category: "CalendarService")

/// Manages EventKit integration for reading calendar events and optionally
/// syncing Dequeue tasks to a dedicated calendar.
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let eventStore = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var upcomingEvents: [CalendarEvent] = []
    @Published var todayEvents: [CalendarEvent] = []

    /// Name of the Dequeue-managed calendar for task sync
    private let dequeueCalendarTitle = "Dequeue Tasks"

    private init() {
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            updateAuthorizationStatus()
            if granted {
                logger.info("Calendar access granted")
                await refreshEvents()
            } else {
                logger.info("Calendar access denied")
            }
            return granted
        } catch {
            logger.error("Calendar access request failed: \(error)")
            updateAuthorizationStatus()
            return false
        }
    }

    private func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    // MARK: - Fetch Events

    /// Refreshes today's and upcoming events from the user's calendars
    func refreshEvents() async {
        guard isAuthorized else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        // Today's events
        todayEvents = fetchEvents(from: startOfToday, to: endOfToday)

        // Upcoming 7 days
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? now
        upcomingEvents = fetchEvents(from: now, to: weekEnd)

        logger.info("Refreshed: \(self.todayEvents.count) today, \(self.upcomingEvents.count) upcoming")
    }

    private func fetchEvents(from startDate: Date, to endDate: Date) -> [CalendarEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil // All calendars
        )
        let ekEvents = eventStore.events(matching: predicate)
        return ekEvents.map { CalendarEvent(from: $0) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Fetch events for a specific date range (used by calendar views)
    func events(for date: Date) -> [CalendarEvent] {
        guard isAuthorized else { return [] }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        return fetchEvents(from: start, to: end)
    }

    /// Fetch events for a date range
    func events(from startDate: Date, to endDate: Date) -> [CalendarEvent] {
        guard isAuthorized else { return [] }
        return fetchEvents(from: startDate, to: endDate)
    }

    // MARK: - Create Task from Event

    /// Creates task data from a calendar event (for import into Dequeue)
    func taskDataFromEvent(_ event: CalendarEvent) -> (title: String, description: String?, startTime: Date?, dueTime: Date?) {
        let description = [event.location, event.notes]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return (
            title: event.title,
            description: description.isEmpty ? nil : description,
            startTime: event.startDate,
            dueTime: event.endDate
        )
    }

    // MARK: - Export Task to Calendar

    /// Creates a calendar event from a Dequeue task
    func exportTaskToCalendar(
        title: String,
        startDate: Date?,
        endDate: Date?,
        notes: String? = nil
    ) throws -> String {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.notes = notes

        if let start = startDate {
            event.startDate = start
            event.endDate = endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: start)
        } else if let end = endDate {
            event.startDate = Calendar.current.date(byAdding: .hour, value: -1, to: end)
            event.endDate = end
        } else {
            // All-day event for today
            event.startDate = Calendar.current.startOfDay(for: Date())
            event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: event.startDate)
            event.isAllDay = true
        }

        // Use dedicated Dequeue calendar, or fall back to default
        event.calendar = getOrCreateDequeueCalendar() ?? eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent)
        logger.info("Exported task to calendar: \(title)")

        return event.eventIdentifier
    }

    /// Removes a previously exported calendar event
    func removeExportedEvent(identifier: String) throws {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }

        guard let event = eventStore.event(withIdentifier: identifier) else {
            logger.warning("Event not found for removal: \(identifier)")
            return
        }

        try eventStore.remove(event, span: .thisEvent)
        logger.info("Removed exported event: \(identifier)")
    }

    // MARK: - Dequeue Calendar Management

    private func getOrCreateDequeueCalendar() -> EKCalendar? {
        // Look for existing Dequeue calendar
        if let existing = eventStore.calendars(for: .event)
            .first(where: { $0.title == dequeueCalendarTitle }) {
            return existing
        }

        // Create new Dequeue calendar
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = dequeueCalendarTitle

        // Use iCloud source if available, otherwise local
        if let iCloudSource = eventStore.sources.first(where: { $0.sourceType == .calDAV }) {
            calendar.source = iCloudSource
        } else if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else {
            calendar.source = eventStore.defaultCalendarForNewEvents?.source
        }

        do {
            try eventStore.saveCalendar(calendar, commit: true)
            logger.info("Created Dequeue Tasks calendar")
            return calendar
        } catch {
            logger.error("Failed to create Dequeue calendar: \(error)")
            return nil
        }
    }

    // MARK: - Available Calendars

    func availableCalendars() -> [CalendarInfo] {
        guard isAuthorized else { return [] }
        return eventStore.calendars(for: .event).map { CalendarInfo(from: $0) }
    }
}

// MARK: - Models

/// Lightweight representation of a calendar event
struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarName: String
    let calendarColor: String? // Hex color

    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier ?? UUID().uuidString
        self.title = ekEvent.title ?? "Untitled Event"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay
        self.location = ekEvent.location
        self.notes = ekEvent.notes
        self.calendarName = ekEvent.calendar?.title ?? "Unknown"
        self.calendarColor = ekEvent.calendar?.cgColor.flatMap { color in
            let components = color.components ?? []
            guard components.count >= 3 else { return nil }
            let red = Int(components[0] * 255)
            let green = Int(components[1] * 255)
            let blue = Int(components[2] * 255)
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
    }

    // For testing/previews
    init(
        id: String = UUID().uuidString,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        calendarName: String = "Calendar",
        calendarColor: String? = "#007AFF"
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarName = calendarName
        self.calendarColor = calendarColor
    }

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}

/// Info about an available calendar
struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let colorHex: String?
    let isSubscribed: Bool

    init(from calendar: EKCalendar) {
        self.id = calendar.calendarIdentifier
        self.title = calendar.title
        self.colorHex = calendar.cgColor.flatMap { color in
            let components = color.components ?? []
            guard components.count >= 3 else { return nil }
            let red = Int(components[0] * 255)
            let green = Int(components[1] * 255)
            let blue = Int(components[2] * 255)
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
        self.isSubscribed = calendar.type == .subscription
    }
}

// MARK: - Errors

enum CalendarError: LocalizedError {
    case notAuthorized
    case eventNotFound
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access not authorized. Please enable in Settings."
        case .eventNotFound:
            return "Calendar event not found."
        case .saveFailed(let error):
            return "Failed to save calendar event: \(error.localizedDescription)"
        }
    }
}
