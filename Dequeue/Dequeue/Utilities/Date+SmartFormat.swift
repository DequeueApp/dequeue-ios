//
//  Date+SmartFormat.swift
//  Dequeue
//
//  Smart date formatting utilities
//

import Foundation

extension Date {
    /// Formats the date as "X hours ago" if it was today, otherwise shows the day and time.
    ///
    /// Examples:
    /// - "2 hours ago" (if created today)
    /// - "Jan 10, 10:30 AM" (if created on a different day)
    func smartFormatted() -> String {
        if Calendar.current.isDateInToday(self) {
            // Use relative formatting for today
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: self, relativeTo: Date())
        } else {
            // Use abbreviated date and time for other days
            return self.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
