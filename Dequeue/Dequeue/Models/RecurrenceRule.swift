//
//  RecurrenceRule.swift
//  Dequeue
//
//  Defines recurrence patterns for repeating tasks
//

import Foundation

/// Frequency of task recurrence
enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }
}

/// Days of the week for weekly recurrence
enum RecurrenceDay: Int, Codable, CaseIterable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var singleLetter: String {
        switch self {
        case .sunday: return "S"
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        }
    }

    /// Weekday set (Mon-Fri)
    static var weekdays: Set<RecurrenceDay> {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }

    /// Weekend set (Sat-Sun)
    static var weekends: Set<RecurrenceDay> {
        [.saturday, .sunday]
    }
}

/// End condition for recurrence
enum RecurrenceEnd: Codable, Sendable, Equatable {
    /// Recurrence never ends
    case never
    /// Recurrence ends after N occurrences
    case afterOccurrences(Int)
    /// Recurrence ends on a specific date
    case onDate(Date)
}

/// Defines when and how a task repeats
struct RecurrenceRule: Codable, Sendable, Equatable {
    /// How often the task repeats (daily, weekly, monthly, yearly)
    let frequency: RecurrenceFrequency

    /// Interval between occurrences (e.g., every 2 weeks = frequency: .weekly, interval: 2)
    let interval: Int

    /// For weekly frequency: which days of the week (empty = same day as original)
    let daysOfWeek: Set<RecurrenceDay>

    /// For monthly frequency: which day of the month (nil = same as original due date)
    let dayOfMonth: Int?

    /// When recurrence ends
    let end: RecurrenceEnd

    /// How many occurrences have been created so far
    var occurrenceCount: Int

    init(
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        daysOfWeek: Set<RecurrenceDay> = [],
        dayOfMonth: Int? = nil,
        end: RecurrenceEnd = .never,
        occurrenceCount: Int = 0
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.daysOfWeek = daysOfWeek
        self.dayOfMonth = dayOfMonth
        self.end = end
        self.occurrenceCount = occurrenceCount
    }

    // MARK: - Presets

    /// Every day
    static var daily: RecurrenceRule {
        RecurrenceRule(frequency: .daily)
    }

    /// Every week on the same day
    static var weekly: RecurrenceRule {
        RecurrenceRule(frequency: .weekly)
    }

    /// Every weekday (Mon-Fri)
    static var weekdays: RecurrenceRule {
        RecurrenceRule(frequency: .weekly, daysOfWeek: RecurrenceDay.weekdays)
    }

    /// Every month on the same day
    static var monthly: RecurrenceRule {
        RecurrenceRule(frequency: .monthly)
    }

    /// Every year on the same date
    static var yearly: RecurrenceRule {
        RecurrenceRule(frequency: .yearly)
    }

    /// Every 2 weeks on the same day
    static var biweekly: RecurrenceRule {
        RecurrenceRule(frequency: .weekly, interval: 2)
    }

    // MARK: - Display

    /// Human-readable description of the recurrence pattern
    var displayText: String {
        var parts: [String] = []

        if interval == 1 {
            parts.append("Every \(frequency.displayName.lowercased())")
        } else {
            let unit: String
            switch frequency {
            case .daily: unit = "days"
            case .weekly: unit = "weeks"
            case .monthly: unit = "months"
            case .yearly: unit = "years"
            }
            parts.append("Every \(interval) \(unit)")
        }

        if frequency == .weekly && !daysOfWeek.isEmpty {
            let sortedDays = daysOfWeek.sorted { $0.rawValue < $1.rawValue }
            if daysOfWeek == RecurrenceDay.weekdays {
                parts.append("on weekdays")
            } else if daysOfWeek == RecurrenceDay.weekends {
                parts.append("on weekends")
            } else {
                let dayNames = sortedDays.map { $0.shortName }
                parts.append("on \(dayNames.joined(separator: ", "))")
            }
        }

        if frequency == .monthly, let day = dayOfMonth {
            parts.append("on day \(day)")
        }

        switch end {
        case .never:
            break
        case .afterOccurrences(let count):
            parts.append("(\(count) times)")
        case .onDate(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append("until \(formatter.string(from: date))")
        }

        return parts.joined(separator: " ")
    }

    /// Short description for compact display
    var shortText: String {
        if interval == 1 {
            switch frequency {
            case .daily: return "Daily"
            case .weekly:
                if daysOfWeek == RecurrenceDay.weekdays { return "Weekdays" }
                if daysOfWeek == RecurrenceDay.weekends { return "Weekends" }
                if daysOfWeek.isEmpty { return "Weekly" }
                let sortedDays = daysOfWeek.sorted { $0.rawValue < $1.rawValue }
                return sortedDays.map { $0.shortName }.joined(separator: ", ")
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            }
        }
        switch frequency {
        case .daily: return "Every \(interval) days"
        case .weekly: return "Every \(interval) weeks"
        case .monthly: return "Every \(interval) months"
        case .yearly: return "Every \(interval) years"
        }
    }

    // MARK: - Presets List

    /// Common presets for quick selection
    static var presets: [(name: String, rule: RecurrenceRule)] {
        [
            ("Daily", .daily),
            ("Weekdays", .weekdays),
            ("Weekly", .weekly),
            ("Biweekly", .biweekly),
            ("Monthly", .monthly),
            ("Yearly", .yearly)
        ]
    }
}

// MARK: - JSON Encoding Helpers

extension RecurrenceRule {
    /// Encode to JSON Data for storage in SwiftData
    func toData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Decode from JSON Data
    static func fromData(_ data: Data?) -> RecurrenceRule? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(RecurrenceRule.self, from: data)
    }
}
