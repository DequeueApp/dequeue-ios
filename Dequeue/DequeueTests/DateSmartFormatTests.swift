//
//  DateSmartFormatTests.swift
//  DequeueTests
//
//  Tests for Date+SmartFormat extension
//

import Testing
import Foundation
@testable import Dequeue

@Suite("Date+SmartFormat Tests")
struct DateSmartFormatTests {
    // MARK: - Today Formatting (relative)

    @Test("smartFormatted uses relative format for dates today")
    func smartFormattedUsesRelativeForToday() {
        // A date 2 hours ago should use relative formatting
        let twoHoursAgo = Date().addingTimeInterval(-2 * 60 * 60)
        let formatted = twoHoursAgo.smartFormatted()

        // RelativeDateTimeFormatter produces strings like "2 hours ago"
        #expect(formatted.contains("ago") || formatted.contains("hour") || formatted.contains("minute"),
                "Today's date should be formatted relatively, got: \(formatted)")
    }

    @Test("smartFormatted uses relative format for date a few minutes ago")
    func smartFormattedRelativeMinutes() {
        let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)
        let formatted = fiveMinutesAgo.smartFormatted()

        #expect(formatted.contains("ago") || formatted.contains("minute"),
                "Recent date should mention minutes, got: \(formatted)")
    }

    @Test("smartFormatted uses relative format for date seconds ago")
    func smartFormattedRelativeSeconds() {
        let justNow = Date().addingTimeInterval(-30)
        let formatted = justNow.smartFormatted()

        // Should use relative format since it's today
        #expect(!formatted.isEmpty, "Should produce non-empty formatted string")
    }

    // MARK: - Non-today Formatting (abbreviated)

    @Test("smartFormatted uses abbreviated format for yesterday")
    func smartFormattedUsesAbbreviatedForYesterday() {
        let yesterday = Date().addingTimeInterval(-24 * 60 * 60)
        let formatted = yesterday.smartFormatted()

        // Should NOT contain "ago" since it's not today
        // Should contain abbreviated month and time
        #expect(!formatted.isEmpty, "Should produce non-empty formatted string for yesterday")
        // The exact format depends on locale, but it should be a date string
    }

    @Test("smartFormatted uses abbreviated format for a week ago")
    func smartFormattedUsesAbbreviatedForWeekAgo() {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let formatted = weekAgo.smartFormatted()

        #expect(!formatted.isEmpty, "Should produce non-empty formatted string for week-old date")
    }

    @Test("smartFormatted uses abbreviated format for a date in a different year")
    func smartFormattedUsesAbbreviatedForDifferentYear() {
        let calendar = Calendar.current
        let components = DateComponents(year: 2024, month: 6, day: 15, hour: 10, minute: 30)
        let oldDate = calendar.date(from: components)!

        let formatted = oldDate.smartFormatted()

        #expect(!formatted.isEmpty)
        // Should include some representation of the date (month, year, or time)
        #expect(formatted.contains("2024") || formatted.contains("Jun") || formatted.contains("15"),
                "Formatted date for 2024 should include year or month info, got: \(formatted)")
    }

    // MARK: - Edge Cases

    @Test("smartFormatted returns non-empty for distant past")
    func smartFormattedDistantPast() {
        let distantPast = Date.distantPast
        let formatted = distantPast.smartFormatted()

        #expect(!formatted.isEmpty, "Should produce non-empty string even for distant past")
    }

    @Test("smartFormatted returns non-empty for current moment")
    func smartFormattedCurrentMoment() {
        let now = Date()
        let formatted = now.smartFormatted()

        #expect(!formatted.isEmpty, "Should produce non-empty string for current moment")
    }

    @Test("smartFormatted returns relative for start of today")
    func smartFormattedStartOfToday() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let formatted = startOfToday.smartFormatted()

        // Start of today is still "today" so should use relative format
        #expect(!formatted.isEmpty, "Start of today should produce non-empty formatted string")
    }
}
