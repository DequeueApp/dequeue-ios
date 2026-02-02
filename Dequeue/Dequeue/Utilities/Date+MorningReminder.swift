//
//  Date+MorningReminder.swift
//  Dequeue
//
//  Shared date utilities for creating reminder times
//

import Foundation

extension Date {
    /// Creates a reminder date at 8:00 AM on the same day as this date.
    ///
    /// Uses the current timezone to ensure consistent reminder scheduling
    /// regardless of the user's locale.
    ///
    /// - Returns: A Date set to 8:00 AM on this date, or nil if the calculation fails
    func morningReminderTime() -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        return calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: self
        )
    }
}
