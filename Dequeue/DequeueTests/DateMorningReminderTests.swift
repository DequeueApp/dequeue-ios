//
//  DateMorningReminderTests.swift
//  DequeueTests
//
//  Tests for Date+MorningReminder extension
//

import Testing
import Foundation
@testable import Dequeue

@Suite("Date+MorningReminder Tests")
struct DateMorningReminderTests {
    // MARK: - Basic Functionality

    @Test("morningReminderTime returns 8:00 AM on the same day")
    func morningReminderTimeReturns8AM() {
        let calendar = Calendar.current
        // Create a date at 3:45 PM
        let components = DateComponents(year: 2026, month: 2, day: 20, hour: 15, minute: 45, second: 30)
        let date = calendar.date(from: components)!

        let reminderTime = date.morningReminderTime()

        #expect(reminderTime != nil)
        if let reminder = reminderTime {
            let reminderComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder)
            #expect(reminderComponents.year == 2026)
            #expect(reminderComponents.month == 2)
            #expect(reminderComponents.day == 20)
            #expect(reminderComponents.hour == 8)
            #expect(reminderComponents.minute == 0)
            #expect(reminderComponents.second == 0)
        }
    }

    @Test("morningReminderTime preserves the date when called on morning time")
    func morningReminderTimePreservesDateForMorning() {
        let calendar = Calendar.current
        // Create a date at 6:00 AM
        let components = DateComponents(year: 2026, month: 6, day: 15, hour: 6, minute: 0, second: 0)
        let date = calendar.date(from: components)!

        let reminderTime = date.morningReminderTime()

        #expect(reminderTime != nil)
        if let reminder = reminderTime {
            let reminderComponents = calendar.dateComponents([.hour, .minute, .day], from: reminder)
            #expect(reminderComponents.hour == 8)
            #expect(reminderComponents.minute == 0)
            #expect(reminderComponents.day == 15)
        }
    }

    @Test("morningReminderTime works for midnight")
    func morningReminderTimeWorksForMidnight() {
        let calendar = Calendar.current
        let components = DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        let date = calendar.date(from: components)!

        let reminderTime = date.morningReminderTime()

        #expect(reminderTime != nil)
        if let reminder = reminderTime {
            let reminderComponents = calendar.dateComponents([.hour, .minute, .day], from: reminder)
            #expect(reminderComponents.hour == 8)
            #expect(reminderComponents.minute == 0)
            #expect(reminderComponents.day == 1)
        }
    }

    @Test("morningReminderTime works for 11:59 PM")
    func morningReminderTimeWorksForEndOfDay() {
        let calendar = Calendar.current
        let components = DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 59)
        let date = calendar.date(from: components)!

        let reminderTime = date.morningReminderTime()

        #expect(reminderTime != nil)
        if let reminder = reminderTime {
            let reminderComponents = calendar.dateComponents([.hour, .minute, .day, .month], from: reminder)
            #expect(reminderComponents.hour == 8)
            #expect(reminderComponents.minute == 0)
            #expect(reminderComponents.day == 31)
            #expect(reminderComponents.month == 12)
        }
    }

    @Test("morningReminderTime called on exactly 8:00 AM returns the same time")
    func morningReminderTimeAtExact8AM() {
        let calendar = Calendar.current
        let components = DateComponents(year: 2026, month: 3, day: 10, hour: 8, minute: 0, second: 0)
        let date = calendar.date(from: components)!

        let reminderTime = date.morningReminderTime()

        #expect(reminderTime != nil)
        if let reminder = reminderTime {
            let reminderComponents = calendar.dateComponents([.hour, .minute, .second], from: reminder)
            #expect(reminderComponents.hour == 8)
            #expect(reminderComponents.minute == 0)
            #expect(reminderComponents.second == 0)
        }
    }

    @Test("morningReminderTime works for leap day")
    func morningReminderTimeWorksForLeapDay() {
        let calendar = Calendar.current
        // Feb 29, 2028 is a leap year
        let components = DateComponents(year: 2028, month: 2, day: 29, hour: 14, minute: 30)
        let date = calendar.date(from: components)!

        let reminderTime = date.morningReminderTime()

        #expect(reminderTime != nil)
        if let reminder = reminderTime {
            let reminderComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder)
            #expect(reminderComponents.year == 2028)
            #expect(reminderComponents.month == 2)
            #expect(reminderComponents.day == 29)
            #expect(reminderComponents.hour == 8)
            #expect(reminderComponents.minute == 0)
        }
    }

    @Test("morningReminderTime returns non-nil for current date")
    func morningReminderTimeReturnsNonNilForNow() {
        let result = Date().morningReminderTime()
        #expect(result != nil)
    }
}
