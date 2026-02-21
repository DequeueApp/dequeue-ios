//
//  NLTaskParser.swift
//  Dequeue
//
//  Natural language task input parser.
//  Parses user text like "Buy groceries tomorrow at 5pm #errands p:high"
//  into structured task fields (title, due date, tags, priority).
//

import Foundation

// MARK: - Parsed Result

/// The result of parsing a natural language task input string.
///
/// Contains the extracted title (cleaned of inline markers), optional due date,
/// optional priority, and any extracted tags.
///
/// Example inputs and their parsed results:
/// ```
/// "Buy milk tomorrow at 3pm"
///   → title: "Buy milk", dueTime: <tomorrow 3:00 PM>
///
/// "Review PR #errands #work p:high"
///   → title: "Review PR", tags: ["errands", "work"], priority: 2
///
/// "Call dentist next Monday"
///   → title: "Call dentist", dueTime: <next Monday 9:00 AM>
/// ```
struct NLTaskParseResult: Equatable, Sendable {
    /// The cleaned task title with date/tag/priority markers removed
    let title: String

    /// Parsed due date, if any temporal expression was found
    let dueTime: Date?

    /// Parsed start date, if any "from"/"starting" expression was found
    let startTime: Date?

    /// Extracted priority (0=low, 1=medium, 2=high, 3=urgent), nil if not specified
    let priority: Int?

    /// Extracted tag names (without the # prefix)
    let tags: [String]

    /// Whether any structured data was extracted (beyond just the title)
    var hasStructuredData: Bool {
        dueTime != nil || startTime != nil || priority != nil || !tags.isEmpty
    }
}

// MARK: - Parser

/// Parses natural language task input into structured task data.
///
/// Supports:
/// - **Dates**: "today", "tomorrow", "next Monday", "in 2 hours", "by Friday at 3pm",
///   "Jan 15", "1/15", "next week"
/// - **Times**: "at 3pm", "at 15:00", "at 3:30pm", "at noon", "at midnight"
/// - **Priority**: "p:high", "p:urgent", "p:low", "p:med", "!!", "!!!", "p1"-"p4"
/// - **Tags**: "#work", "#errands", "#home"
///
/// The parser is intentionally stateless and uses the provided `referenceDate`
/// and `calendar` for all date calculations, making it fully testable.
struct NLTaskParser: Sendable {

    // MARK: - Configuration

    /// The calendar to use for date calculations
    let calendar: Calendar

    /// The reference date for relative date expressions ("today", "tomorrow", etc.)
    let referenceDate: Date

    /// Default time to use when a date is specified without a time (e.g., "tomorrow")
    let defaultTime: (hour: Int, minute: Int)

    init(
        calendar: Calendar = .current,
        referenceDate: Date = Date(),
        defaultTime: (hour: Int, minute: Int) = (9, 0)
    ) {
        self.calendar = calendar
        self.referenceDate = referenceDate
        self.defaultTime = defaultTime
    }

    // MARK: - Public API

    /// Parse a natural language task input string into structured data.
    ///
    /// - Parameter input: The raw user input string
    /// - Returns: A `NLTaskParseResult` with extracted fields
    func parse(_ input: String) -> NLTaskParseResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NLTaskParseResult(title: "", dueTime: nil, startTime: nil, priority: nil, tags: [])
        }

        var working = trimmed
        var extractedPriority: Int?
        var extractedTags: [String] = []
        var extractedDueDate: Date?
        var extractedStartDate: Date?
        var extractedTime: (hour: Int, minute: Int)?

        // 1. Extract priority markers (do first — they're unambiguous)
        (working, extractedPriority) = extractPriority(from: working)

        // 2. Extract tags (#word)
        (working, extractedTags) = extractTags(from: working)

        // 3. Extract time expressions ("at 3pm", "at 15:00")
        (working, extractedTime) = extractTime(from: working)

        // 4. Extract date expressions ("tomorrow", "next Monday", "Jan 15", etc.)
        (working, extractedDueDate) = extractDueDate(from: working, time: extractedTime)

        // 5. Extract start date ("from Monday", "starting tomorrow")
        (working, extractedStartDate) = extractStartDate(from: working, time: nil)

        // 6. If we got a time but no date, assume today
        if extractedTime != nil && extractedDueDate == nil {
            var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            components.hour = extractedTime!.hour
            components.minute = extractedTime!.minute
            components.second = 0
            extractedDueDate = calendar.date(from: components)

            // If the time already passed today, bump to tomorrow
            if let due = extractedDueDate, due <= referenceDate {
                extractedDueDate = calendar.date(byAdding: .day, value: 1, to: due)
            }
        }

        // 7. Clean up title
        let title = cleanTitle(working)

        return NLTaskParseResult(
            title: title,
            dueTime: extractedDueDate,
            startTime: extractedStartDate,
            priority: extractedPriority,
            tags: extractedTags
        )
    }

    // MARK: - Priority Extraction

    /// Priority patterns:
    /// - `p:high`, `p:urgent`, `p:low`, `p:med`, `p:medium`
    /// - `p1` (urgent), `p2` (high), `p3` (medium), `p4` (low)
    /// - `!!!` (urgent), `!!` (high), `!` at end of word (medium)
    private func extractPriority(from text: String) -> (String, Int?) {
        var result = text
        var priority: Int?

        // p:label pattern
        let pLabelPattern = #"\bp:(urgent|high|med(?:ium)?|low|none)\b"#
        if let match = result.range(of: pLabelPattern, options: .regularExpression) {
            let label = String(result[match]).replacingOccurrences(of: "p:", with: "").lowercased()
            priority = priorityFromLabel(label)
            result = result.replacingCharacters(in: match, with: "")
        }

        // p1-p4 pattern
        if priority == nil {
            let pNumPattern = #"\bp([1-4])\b"#
            if let match = result.range(of: pNumPattern, options: .regularExpression) {
                let numStr = String(result[match]).replacingOccurrences(of: "p", with: "")
                if let num = Int(numStr) {
                    // p1 = urgent(3), p2 = high(2), p3 = medium(1), p4 = low(0)
                    priority = 4 - num
                }
                result = result.replacingCharacters(in: match, with: "")
            }
        }

        // Exclamation pattern (must be standalone or at end)
        if priority == nil {
            if let match = result.range(of: #"\s!!!(?:\s|$)"#, options: .regularExpression) {
                priority = 3 // urgent
                result = result.replacingCharacters(in: match, with: " ")
            } else if let match = result.range(of: #"\s!!(?:\s|$)"#, options: .regularExpression) {
                priority = 2 // high
                result = result.replacingCharacters(in: match, with: " ")
            }
        }

        return (result, priority)
    }

    private func priorityFromLabel(_ label: String) -> Int {
        switch label {
        case "urgent": return 3
        case "high": return 2
        case "med", "medium": return 1
        case "low": return 0
        case "none": return 0
        default: return 1
        }
    }

    // MARK: - Tag Extraction

    /// Extracts #tag patterns from the input
    private func extractTags(from text: String) -> (String, [String]) {
        var result = text
        var tags: [String] = []

        // Match #word (letters, numbers, hyphens, underscores) but not #123 (pure numbers)
        let tagPattern = #"#([a-zA-Z][a-zA-Z0-9_-]*)"#
        let regex = try? NSRegularExpression(pattern: tagPattern)
        let nsRange = NSRange(result.startIndex..., in: result)

        if let regex = regex {
            let matches = regex.matches(in: result, range: nsRange)
            // Collect tags in reverse to preserve indices
            for match in matches.reversed() {
                if let tagRange = Range(match.range(at: 1), in: result) {
                    tags.insert(String(result[tagRange]), at: 0)
                }
                if let fullRange = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: fullRange, with: "")
                }
            }
        }

        return (result, tags)
    }

    // MARK: - Time Extraction

    /// Extracts time expressions: "at 3pm", "at 15:00", "at 3:30pm", "at noon", "at midnight"
    private func extractTime(from text: String) -> (String, (hour: Int, minute: Int)?) {
        var result = text

        // "at noon" / "at midnight"
        let specialTimePattern = #"\bat\s+(noon|midnight)\b"#
        if let match = result.range(of: specialTimePattern, options: [.regularExpression, .caseInsensitive]) {
            let matched = String(result[match]).lowercased()
            let time: (Int, Int) = matched.contains("noon") ? (12, 0) : (0, 0)
            result = result.replacingCharacters(in: match, with: "")
            return (result, time)
        }

        // "at 3:30pm" / "at 3:30 pm" / "at 15:30"
        let timeWithMinPattern = #"\bat\s+(\d{1,2}):(\d{2})\s*([aApP][mM])?\b"#
        if let regex = try? NSRegularExpression(pattern: timeWithMinPattern),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            if let hourRange = Range(match.range(at: 1), in: result),
               let minRange = Range(match.range(at: 2), in: result) {
                var hour = Int(result[hourRange]) ?? 0
                let minute = Int(result[minRange]) ?? 0
                let ampm: String? = match.range(at: 3).location != NSNotFound
                    ? Range(match.range(at: 3), in: result).map { String(result[$0]).lowercased() }
                    : nil

                hour = adjustHourForAMPM(hour: hour, ampm: ampm)

                if let fullRange = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: fullRange, with: "")
                }
                return (result, (hour, minute))
            }
        }

        // "at 3pm" / "at 3 pm" / "at 15"
        let timePattern = #"\bat\s+(\d{1,2})\s*([aApP][mM])?\b"#
        if let regex = try? NSRegularExpression(pattern: timePattern),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            if let hourRange = Range(match.range(at: 1), in: result) {
                var hour = Int(result[hourRange]) ?? 0
                let ampm: String? = match.range(at: 2).location != NSNotFound
                    ? Range(match.range(at: 2), in: result).map { String(result[$0]).lowercased() }
                    : nil

                hour = adjustHourForAMPM(hour: hour, ampm: ampm)

                if let fullRange = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: fullRange, with: "")
                }
                return (result, (hour, minute: 0))
            }
        }

        return (result, nil)
    }

    private func adjustHourForAMPM(hour: Int, ampm: String?) -> Int {
        guard let ampm = ampm else {
            // No AM/PM — if hour <= 12 and looks like 12h format, be smart
            // Hours > 12 are 24h format
            return hour
        }
        if ampm == "pm" && hour < 12 {
            return hour + 12
        } else if ampm == "am" && hour == 12 {
            return 0
        }
        return hour
    }

    // MARK: - Due Date Extraction

    /// Extracts date expressions and returns the remaining text + parsed date
    private func extractDueDate(from text: String, time: (hour: Int, minute: Int)?) -> (String, Date?) {
        var result = text
        let resolvedTime = time ?? defaultTime

        // "today"
        if let match = result.range(of: #"\b(?:by\s+)?today\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, dateWithTime(referenceDate, hour: resolvedTime.hour, minute: resolvedTime.minute))
        }

        // "tonight"
        if let match = result.range(of: #"\b(?:by\s+)?tonight\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, dateWithTime(referenceDate, hour: 21, minute: 0))
        }

        // "tomorrow"
        if let match = result.range(of: #"\b(?:by\s+)?tomorrow\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) {
                return (result, dateWithTime(tomorrow, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        // "day after tomorrow"
        if let match = result.range(of: #"\b(?:by\s+)?day after tomorrow\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = calendar.date(byAdding: .day, value: 2, to: referenceDate) {
                return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        // "next week" (next Monday)
        if let match = result.range(of: #"\b(?:by\s+)?next week\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = nextWeekday(.monday) {
                return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        // "this weekend" (Saturday)
        if let match = result.range(of: #"\b(?:by\s+)?this weekend\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = nextWeekday(.saturday) {
                return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        // "end of day" / "eod"
        if let match = result.range(of: #"\b(?:by\s+)?(?:end of day|eod)\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, dateWithTime(referenceDate, hour: 17, minute: 0))
        }

        // "end of week" / "eow"
        if let match = result.range(of: #"\b(?:by\s+)?(?:end of week|eow)\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = nextWeekday(.friday) {
                return (result, dateWithTime(date, hour: 17, minute: 0))
            }
        }

        // "in X hours/minutes/days/weeks"
        let inPattern = #"\bin\s+(\d+)\s+(minute|minutes|min|mins|hour|hours|hr|hrs|day|days|week|weeks)\b"#
        if let regex = try? NSRegularExpression(pattern: inPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            if let numRange = Range(match.range(at: 1), in: result),
               let unitRange = Range(match.range(at: 2), in: result) {
                let num = Int(result[numRange]) ?? 0
                let unit = String(result[unitRange]).lowercased()
                let component: Calendar.Component
                switch unit {
                case "minute", "minutes", "min", "mins": component = .minute
                case "hour", "hours", "hr", "hrs": component = .hour
                case "day", "days": component = .day
                case "week", "weeks": component = .weekOfYear
                default: component = .hour
                }
                if let date = calendar.date(byAdding: component, value: num, to: referenceDate),
                   let fullRange = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: fullRange, with: "")
                    return (result, date)
                }
            }
        }

        // "next Monday/Tuesday/..." or "on Monday/Tuesday/..."
        let dayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun"]
        let dayNamePattern = dayNames.joined(separator: "|")
        let nextDayPattern = #"\b(?:next|on|by)\s+("# + dayNamePattern + #")\b"#
        if let regex = try? NSRegularExpression(pattern: nextDayPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            if let dayRange = Range(match.range(at: 1), in: result) {
                let dayName = String(result[dayRange]).lowercased()
                if let weekday = weekdayFromName(dayName),
                   let date = nextWeekday(weekday),
                   let fullRange = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: fullRange, with: "")
                    return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
                }
            }
        }

        // Bare day name at end: "Buy milk Monday"
        let bareDayPattern = #"\b("# + dayNamePattern + #")\s*$"#
        if let regex = try? NSRegularExpression(pattern: bareDayPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            if let dayRange = Range(match.range(at: 1), in: result) {
                let dayName = String(result[dayRange]).lowercased()
                if let weekday = weekdayFromName(dayName),
                   let date = nextWeekday(weekday),
                   let fullRange = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: fullRange, with: "")
                    return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
                }
            }
        }

        // "Jan 15" / "January 15" / "Feb 3" etc.
        let monthNames = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
        let monthDayPattern = #"\b(?:by\s+|on\s+)?("# + monthNames + #")\s+(\d{1,2})(?:st|nd|rd|th)?\b"#
        if let regex = try? NSRegularExpression(pattern: monthDayPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            if let monthRange = Range(match.range(at: 1), in: result),
               let dayRange = Range(match.range(at: 2), in: result) {
                let monthStr = String(result[monthRange]).lowercased()
                let day = Int(result[dayRange]) ?? 1
                if let month = monthFromName(monthStr),
                   let date = resolveMonthDay(month: month, day: day, time: resolvedTime),
                   let fullRange = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: fullRange, with: "")
                    return (result, date)
                }
            }
        }

        // "M/D" or "M-D" format (e.g., "1/15", "12-25")
        let slashDatePattern = #"\b(?:by\s+|on\s+)?(\d{1,2})[/-](\d{1,2})\b"#
        if let regex = try? NSRegularExpression(pattern: slashDatePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            if let monthRange = Range(match.range(at: 1), in: result),
               let dayRange = Range(match.range(at: 2), in: result) {
                let month = Int(result[monthRange]) ?? 1
                let day = Int(result[dayRange]) ?? 1
                if month >= 1 && month <= 12 && day >= 1 && day <= 31,
                   let date = resolveMonthDay(month: month, day: day, time: resolvedTime),
                   let fullRange = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: fullRange, with: "")
                    return (result, date)
                }
            }
        }

        return (result, nil)
    }

    // MARK: - Start Date Extraction

    /// Extracts start date: "from Monday", "starting tomorrow", "start: Jan 15"
    private func extractStartDate(from text: String, time: (hour: Int, minute: Int)?) -> (String, Date?) {
        var result = text
        let resolvedTime = time ?? defaultTime

        // "from tomorrow" / "starting tomorrow" / "start: tomorrow"
        let startTomorrowPattern = #"\b(?:from|starting|start:?)\s+tomorrow\b"#
        if let match = result.range(of: startTomorrowPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = calendar.date(byAdding: .day, value: 1, to: referenceDate) {
                return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        // "from today" / "starting today"
        let startTodayPattern = #"\b(?:from|starting|start:?)\s+today\b"#
        if let match = result.range(of: startTodayPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, dateWithTime(referenceDate, hour: resolvedTime.hour, minute: resolvedTime.minute))
        }

        // "from Monday" / "starting next Wednesday"
        let dayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun"]
        let dayNamePattern = dayNames.joined(separator: "|")
        let startDayPattern = #"\b(?:from|starting|start:?)\s+(?:next\s+)?("# + dayNamePattern + #")\b"#
        if let regex = try? NSRegularExpression(pattern: startDayPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            if let dayRange = Range(match.range(at: 1), in: result) {
                let dayName = String(result[dayRange]).lowercased()
                if let weekday = weekdayFromName(dayName),
                   let date = nextWeekday(weekday),
                   let fullRange = Range(match.range, in: result) {
                    result = result.replacingCharacters(in: fullRange, with: "")
                    return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
                }
            }
        }

        return (result, nil)
    }

    // MARK: - Date Helpers

    private func dateWithTime(_ date: Date, hour: Int, minute: Int) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    /// Returns the next occurrence of the given weekday (always in the future)
    private func nextWeekday(_ target: Weekday) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: referenceDate)
        let targetWeekday = target.calendarValue

        var daysToAdd = targetWeekday - currentWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7
        }

        return calendar.date(byAdding: .day, value: daysToAdd, to: referenceDate)
    }

    private func weekdayFromName(_ name: String) -> Weekday? {
        switch name.lowercased() {
        case "monday", "mon": return .monday
        case "tuesday", "tue", "tues": return .tuesday
        case "wednesday", "wed": return .wednesday
        case "thursday", "thu", "thur", "thurs": return .thursday
        case "friday", "fri": return .friday
        case "saturday", "sat": return .saturday
        case "sunday", "sun": return .sunday
        default: return nil
        }
    }

    private func monthFromName(_ name: String) -> Int? {
        let lowered = name.lowercased()
        let months = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]
        return months[lowered]
    }

    /// Resolves a month/day pair to the next occurrence (future-biased)
    private func resolveMonthDay(month: Int, day: Int, time: (hour: Int, minute: Int)) -> Date? {
        let currentYear = calendar.component(.year, from: referenceDate)

        var components = DateComponents()
        components.month = month
        components.day = day
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0

        // Try this year first
        components.year = currentYear
        if let date = calendar.date(from: components), date > referenceDate {
            return date
        }

        // If in the past, try next year
        components.year = currentYear + 1
        return calendar.date(from: components)
    }

    // MARK: - Title Cleanup

    private func cleanTitle(_ text: String) -> String {
        var result = text

        // Remove leading "by" if it's left over
        result = result.replacingOccurrences(of: #"^\s*by\s+"#, with: "", options: .regularExpression)

        // Collapse multiple spaces
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        // Trim
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }
}

// MARK: - Weekday Helper

private enum Weekday {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// Calendar weekday value (1 = Sunday, 7 = Saturday) per Foundation convention
    var calendarValue: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }
}
