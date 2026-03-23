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

    /// Extracted recurrence rule, if any "every …" / "daily" / "weekly" etc. pattern was found
    let recurrenceRule: RecurrenceRule?

    /// Whether any structured data was extracted (beyond just the title)
    var hasStructuredData: Bool {
        dueTime != nil || startTime != nil || priority != nil || !tags.isEmpty || recurrenceRule != nil
    }
}

// MARK: - Parser

/// Parses natural language task input into structured task data.
///
/// Supports:
/// - **Dates**: "today", "tonight", "tomorrow", "next Monday", "this Friday",
///   "in 2 hours", "in an hour", "in a day", "by Friday at 3pm", "Jan 15", "1/15", "next week"
/// - **Times**: "at 3pm", "at 15:00", "at 3:30pm", "at noon", "at midnight";
///   explicit "at X" always overrides a compound time-of-day (e.g., "tonight at 7pm" → 7 PM)
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
            return NLTaskParseResult(
                title: "", dueTime: nil, startTime: nil, priority: nil, tags: [], recurrenceRule: nil
            )
        }

        var working = trimmed
        var extractedPriority: Int?
        var extractedTags: [String] = []
        var extractedDueDate: Date?
        var extractedStartDate: Date?
        var extractedTime: (hour: Int, minute: Int)?
        var extractedRecurrenceRule: RecurrenceRule?

        // 0. Extract recurrence patterns first so "every Monday at 9am" doesn't lose "Monday".
        if let (remaining, rule) = extractRecurrenceRule(from: working) {
            (working, extractedRecurrenceRule) = (remaining, rule)
        }

        // 1. Extract compound date+time phrases first — these must run before the
        //    separate time and date extractors so "tomorrow morning" isn't split
        //    into bare "tomorrow" + orphaned "morning".
        //    e.g., "tomorrow morning", "this afternoon", "Friday evening"
        var compoundDueDate: Date?
        (working, compoundDueDate) = extractCompoundDateTimeKeywords(from: working)

        // 2. Extract priority markers (do first — they're unambiguous)
        (working, extractedPriority) = extractPriority(from: working)

        // 3. Extract tags (#word)
        (working, extractedTags) = extractTags(from: working)

        // 4. Extract explicit time expressions ("at 3pm", "at 15:00").
        //    Always run — an explicit "at X" overrides the time baked into a compound phrase.
        (working, extractedTime) = extractTime(from: working)

        // 5. Extract start date first — "from/starting <date>" is more specific
        //    than bare date keywords, so it must consume its tokens before due date extraction.
        (working, extractedStartDate) = extractStartDate(from: working, time: nil)

        // 6. Extract due date expressions ("tomorrow", "next Monday", "Jan 15", etc.).
        //    If a compound date was already found, use it (but let an explicit "at X" override
        //    the baked-in time so "tomorrow morning at 10am" respects the 10 AM).
        if let compound = compoundDueDate {
            if let time = extractedTime {
                // Explicit time overrides the time-of-day default
                var comps = calendar.dateComponents([.year, .month, .day], from: compound)
                comps.hour = time.hour
                comps.minute = time.minute
                comps.second = 0
                extractedDueDate = calendar.date(from: comps) ?? compound
            } else {
                extractedDueDate = compound
            }
        } else {
            (working, extractedDueDate) = extractDueDate(from: working, time: extractedTime)
        }

        // 7. If we got a time but no due date, assume today
        if let time = extractedTime, extractedDueDate == nil {
            var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            components.hour = time.hour
            components.minute = time.minute
            components.second = 0
            extractedDueDate = calendar.date(from: components)

            // If the time already passed today, bump to tomorrow
            if let due = extractedDueDate, due <= referenceDate {
                extractedDueDate = calendar.date(byAdding: .day, value: 1, to: due)
            }
        }

        // 8. Clean up title
        let title = cleanTitle(working)

        return NLTaskParseResult(
            title: title,
            dueTime: extractedDueDate,
            startTime: extractedStartDate,
            priority: extractedPriority,
            tags: extractedTags,
            recurrenceRule: extractedRecurrenceRule
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

        // Fall through to bare AM/PM patterns (no "at" prefix required)
        if let found = extractBareAMPMTime(from: result) {
            return found
        }

        return (result, nil)
    }

    // MARK: - Compound Date+Time Keywords

    /// Extracts compound date+time-of-day phrases that encode both a day AND a time.
    ///
    /// Supported patterns (with optional "by " prefix):
    /// - `tonight` → today 9 PM (explicit "at X" overrides the time)
    /// - `this morning` → today 9 AM
    /// - `this afternoon` → today 2 PM
    /// - `this evening` → today 6 PM
    /// - `tomorrow morning/afternoon/evening` → tomorrow at corresponding time
    /// - `<day> morning/afternoon/evening` (e.g., "Friday morning", "next Monday evening")
    ///
    /// These are extracted before the separate time/date extractors so tokens
    /// like "morning", "afternoon", and "tonight" aren't left as orphaned text,
    /// and so that explicit "at X" times override the baked-in time-of-day defaults.
    private func extractCompoundDateTimeKeywords(from text: String) -> (String, Date?) {
        var result = text

        let timeOfDay: [String: (Int, Int)] = [
            "morning": (9, 0),
            "afternoon": (14, 0),
            "evening": (18, 0)
        ]
        let todPattern = "morning|afternoon|evening"

        // "tonight" — today at 9 PM; explicit "at X" overrides the 9 PM default
        let tonightPattern = #"\b(?:by\s+)?tonight\b"#
        if let match = result.range(of: tonightPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, dateWithTime(referenceDate, hour: 21, minute: 0))
        }

        // "this morning/afternoon/evening"
        let thisTODPattern = #"\b(?:by\s+)?this\s+("# + todPattern + #")\b"#
        if let regex = try? NSRegularExpression(pattern: thisTODPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let todRange = Range(match.range(at: 1), in: result),
           let fullRange = Range(match.range, in: result),
           let time = timeOfDay[String(result[todRange]).lowercased()] {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, dateWithTime(referenceDate, hour: time.0, minute: time.1))
        }

        // "day after tomorrow morning/afternoon/evening" — must be before "tomorrow" to avoid partial match
        let datTODPattern = #"\b(?:by\s+)?day after tomorrow\s+("# + todPattern + #")\b"#
        if let regex = try? NSRegularExpression(pattern: datTODPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let todRange = Range(match.range(at: 1), in: result),
           let fullRange = Range(match.range, in: result),
           let time = timeOfDay[String(result[todRange]).lowercased()],
           let dat = calendar.date(byAdding: .day, value: 2, to: referenceDate) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, dateWithTime(dat, hour: time.0, minute: time.1))
        }

        // "tomorrow morning/afternoon/evening" — must be before bare "tomorrow"
        let tomorrowTODPattern = #"\b(?:by\s+)?tomorrow\s+("# + todPattern + #")\b"#
        if let regex = try? NSRegularExpression(pattern: tomorrowTODPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let todRange = Range(match.range(at: 1), in: result),
           let fullRange = Range(match.range, in: result),
           let time = timeOfDay[String(result[todRange]).lowercased()],
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, dateWithTime(tomorrow, hour: time.0, minute: time.1))
        }

        // "<day> morning/afternoon/evening" e.g. "Friday morning", "next Monday afternoon"
        let dayNamePattern = allDayNames.joined(separator: "|")
        let dayTODPattern = #"\b(?:(?:next|on|by)\s+)?("# + dayNamePattern + #")\s+("# + todPattern + #")\b"#
        if let regex = try? NSRegularExpression(pattern: dayTODPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let dayRange = Range(match.range(at: 1), in: result),
           let todRange = Range(match.range(at: 2), in: result),
           let fullRange = Range(match.range, in: result),
           let time = timeOfDay[String(result[todRange]).lowercased()],
           let weekday = weekdayFromName(String(result[dayRange]).lowercased()),
           let date = nextWeekday(weekday) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, dateWithTime(date, hour: time.0, minute: time.1))
        }

        return (result, nil)
    }

    // MARK: - Due Date Extraction

    /// Extracts date expressions and returns the remaining text + parsed date.
    /// Split into sub-methods to keep cyclomatic complexity manageable.
    private func extractDueDate(from text: String, time: (hour: Int, minute: Int)?) -> (String, Date?) {
        let resolvedTime = time ?? defaultTime

        // Try each date pattern in order of specificity
        let extractors: [(String, (hour: Int, minute: Int)) -> (String, Date?)?] = [
            extractKeywordDate,
            extractRelativeDate,
            extractNamedDayDate,
            extractCalendarDate
        ]

        for extractor in extractors {
            if let extracted = extractor(text, resolvedTime) {
                return extracted
            }
        }

        return (text, nil)
    }

    /// Extracts keyword dates: today, tonight, tomorrow, day after tomorrow,
    /// next month, next week, this weekend, eod, eow, eom
    private func extractKeywordDate(
        from text: String,
        time resolvedTime: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text

        // "today"
        if let match = result.range(of: #"\b(?:by\s+)?today\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, dateWithTime(referenceDate, hour: resolvedTime.hour, minute: resolvedTime.minute))
        }

        // "day after tomorrow" — must be checked before "tomorrow" to avoid partial match
        let dayAfterTomorrowPattern = #"\b(?:by\s+)?day after tomorrow\b"#
        if let match = result.range(of: dayAfterTomorrowPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = calendar.date(byAdding: .day, value: 2, to: referenceDate) {
                return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        // "tomorrow"
        if let match = result.range(of: #"\b(?:by\s+)?tomorrow\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) {
                return (result, dateWithTime(tomorrow, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        // "next month" (first day of next calendar month)
        if let match = result.range(of: #"\b(?:by\s+)?next month\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = nextFirstOfMonth() {
                return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        // "next year" (January 1 of next calendar year)
        if let match = result.range(of: #"\b(?:by\s+)?next year\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = firstDayOfNextYear() {
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
        let thisWeekendPattern = #"\b(?:by\s+)?this weekend\b"#
        if let match = result.range(of: thisWeekendPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = nextWeekday(.saturday) {
                return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        return extractEndOfKeywordDate(from: result, time: resolvedTime)
    }

    /// Extracts "end of X" shorthand keywords: eod, eow, eom and their long forms.
    /// Extracted into a sub-helper to keep `extractKeywordDate` within complexity limits.
    private func extractEndOfKeywordDate(
        from text: String,
        time resolvedTime: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text

        // "end of day" / "eod"
        let eodPattern = #"\b(?:by\s+)?(?:end of day|eod)\b"#
        if let match = result.range(of: eodPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, dateWithTime(referenceDate, hour: 17, minute: 0))
        }

        // "end of week" / "eow"
        let eowPattern = #"\b(?:by\s+)?(?:end of week|eow)\b"#
        if let match = result.range(of: eowPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = nextWeekday(.friday) {
                return (result, dateWithTime(date, hour: 17, minute: 0))
            }
        }

        // "end of month" / "eom"
        let eomPattern = #"\b(?:by\s+)?(?:end of month|eom)\b"#
        if let match = result.range(of: eomPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = lastDayOfMonth() {
                return (result, dateWithTime(date, hour: 17, minute: 0))
            }
        }

        // "end of quarter" / "eoq"
        let eoqPattern = #"\b(?:by\s+)?(?:end of quarter|eoq)\b"#
        if let match = result.range(of: eoqPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = lastDayOfQuarter() {
                return (result, dateWithTime(date, hour: 17, minute: 0))
            }
        }

        // "end of year" / "eoy"
        let eoyPattern = #"\b(?:by\s+)?(?:end of year|eoy)\b"#
        if let match = result.range(of: eoyPattern, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            if let date = lastDayOfYear() {
                return (result, dateWithTime(date, hour: 17, minute: 0))
            }
        }

        return nil
    }

    /// Extracts relative date expressions: "in X hours/minutes/days/weeks"
    /// Supports both numeric ("in 3 days") and indefinite article forms ("in a day", "in an hour").
    private func extractRelativeDate(
        from text: String,
        time: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text
        let units = #"minute|minutes|min|mins|hour|hours|hr|hrs|day|days|week|weeks|month|months|year|years"#

        // "in a/an <unit>" — treat as "in 1 <unit>" (e.g. "in an hour", "in a day", "in a week")
        let articlePattern = #"\bin\s+an?\s+("# + units + #")\b"#
        if let regex = try? NSRegularExpression(pattern: articlePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let unitRange = Range(match.range(at: 1), in: result),
           let fullRange = Range(match.range, in: result) {
            let unit = String(result[unitRange]).lowercased()
            let component = calendarComponentForUnit(unit)
            if let date = calendar.date(byAdding: component, value: 1, to: referenceDate) {
                result = result.replacingCharacters(in: fullRange, with: "")
                return (result, date)
            }
        }

        // Informal spoken-number patterns: "a couple (of) days", "a few weeks", "in two months"
        if let found = extractSpokenNumberDate(from: result, time: time) {
            return found
        }

        // "in <number> <unit>" — e.g. "in 3 days", "in 2 hours"
        let inPattern = #"\bin\s+(\d+)\s+("# + units + #")\b"#
        guard let regex = try? NSRegularExpression(pattern: inPattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let numRange = Range(match.range(at: 1), in: result),
              let unitRange = Range(match.range(at: 2), in: result) else {
            return nil
        }

        let num = Int(result[numRange]) ?? 0
        let unit = String(result[unitRange]).lowercased()
        let component = calendarComponentForUnit(unit)

        guard let date = calendar.date(byAdding: component, value: num, to: referenceDate),
              let fullRange = Range(match.range, in: result) else {
            return nil
        }

        result = result.replacingCharacters(in: fullRange, with: "")
        return (result, date)
    }

    /// Extracts named day expressions: "next Monday", "this Friday", "on Friday", bare "Saturday" at end
    private func extractNamedDayDate(
        from text: String,
        time resolvedTime: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text
        let dayNamePattern = allDayNames.joined(separator: "|")

        // "next Monday/Tuesday/..." or "on/by Monday/Tuesday/..."
        let nextDayPattern = #"\b(?:next|on|by)\s+("# + dayNamePattern + #")\b"#
        if let found = extractDayNameMatch(from: result, pattern: nextDayPattern, time: resolvedTime) {
            return found
        }

        // "this Monday/Tuesday/..." — next occurrence (same semantics as "on <day>")
        let thisDayPattern = #"\bthis\s+("# + dayNamePattern + #")\b"#
        if let found = extractDayNameMatch(from: result, pattern: thisDayPattern, time: resolvedTime) {
            return found
        }

        // Bare day name at end: "Buy milk Monday"
        let bareDayPattern = #"\b("# + dayNamePattern + #")\s*$"#
        if let regex = try? NSRegularExpression(pattern: bareDayPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let dayRange = Range(match.range(at: 1), in: result) {
            let dayName = String(result[dayRange]).lowercased()
            if let weekday = weekdayFromName(dayName),
               let date = nextWeekday(weekday),
               let fullRange = Range(match.range, in: result) {
                result = result.replacingCharacters(in: fullRange, with: "")
                return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
            }
        }

        return nil
    }

    private func extractDayNameMatch(
        from text: String,
        pattern: String,
        time resolvedTime: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let dayRange = Range(match.range(at: 1), in: result) else {
            return nil
        }

        let dayName = String(result[dayRange]).lowercased()
        guard let weekday = weekdayFromName(dayName),
              let date = nextWeekday(weekday),
              let fullRange = Range(match.range, in: result) else {
            return nil
        }

        result = result.replacingCharacters(in: fullRange, with: "")
        return (result, dateWithTime(date, hour: resolvedTime.hour, minute: resolvedTime.minute))
    }

    /// Extracts calendar dates: "Jan 15", "March 3rd", "3/15", "12-25"
    private func extractCalendarDate(
        from text: String,
        time resolvedTime: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        if let found = extractNextNamedMonthDate(from: text, time: resolvedTime) {
            return found
        }
        if let found = extractOrdinalDayDate(from: text, time: resolvedTime) {
            return found
        }
        if let found = extractMonthNameDate(from: text, time: resolvedTime) {
            return found
        }
        return extractSlashDate(from: text, time: resolvedTime)
    }

    private func extractMonthNameDate(
        from text: String,
        time resolvedTime: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text
        // swiftlint:disable:next line_length
        let monthNames = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
        let monthDayPattern = #"\b(?:by\s+|on\s+)?("# + monthNames + #")\s+(\d{1,2})(?:st|nd|rd|th)?\b"#
        guard let regex = try? NSRegularExpression(pattern: monthDayPattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let monthRange = Range(match.range(at: 1), in: result),
              let dayRange = Range(match.range(at: 2), in: result) else {
            return nil
        }

        let monthStr = String(result[monthRange]).lowercased()
        let day = Int(result[dayRange]) ?? 1
        guard let month = monthFromName(monthStr),
              let date = resolveMonthDay(month: month, day: day, time: resolvedTime),
              let fullRange = Range(match.range, in: result) else {
            return nil
        }

        result = result.replacingCharacters(in: fullRange, with: "")
        return (result, date)
    }

    private func extractSlashDate(
        from text: String,
        time resolvedTime: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text
        let slashDatePattern = #"\b(?:by\s+|on\s+)?(\d{1,2})[/-](\d{1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: slashDatePattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let monthRange = Range(match.range(at: 1), in: result),
              let dayRange = Range(match.range(at: 2), in: result) else {
            return nil
        }

        let month = Int(result[monthRange]) ?? 1
        let day = Int(result[dayRange]) ?? 1
        guard month >= 1, month <= 12, day >= 1, day <= 31,
              let date = resolveMonthDay(month: month, day: day, time: resolvedTime),
              let fullRange = Range(match.range, in: result) else {
            return nil
        }

        result = result.replacingCharacters(in: fullRange, with: "")
        return (result, date)
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
        let dayNames = [
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun"
        ]
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
}

// MARK: - NLTaskParser Date Helpers

private extension NLTaskParser {
    func dateWithTime(_ date: Date, hour: Int, minute: Int) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    /// Returns the first day of next calendar month
    func nextFirstOfMonth() -> Date? {
        let components = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let firstOfCurrentMonth = calendar.date(from: components),
              let firstOfNextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfCurrentMonth) else {
            return nil
        }
        return firstOfNextMonth
    }

    /// Returns the last day of the current calendar month
    func lastDayOfMonth() -> Date? {
        let components = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let firstOfCurrentMonth = calendar.date(from: components),
              let firstOfNextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfCurrentMonth),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: firstOfNextMonth) else {
            return nil
        }
        return lastDay
    }

    /// Returns the last day of the current calendar quarter (Q1=Mar 31, Q2=Jun 30, Q3=Sep 30, Q4=Dec 31)
    func lastDayOfQuarter() -> Date? {
        let month = calendar.component(.month, from: referenceDate)
        let year = calendar.component(.year, from: referenceDate)
        // Determine last month of the current quarter
        let lastQuarterMonth: Int
        switch month {
        case 1...3: lastQuarterMonth = 3
        case 4...6: lastQuarterMonth = 6
        case 7...9: lastQuarterMonth = 9
        default: lastQuarterMonth = 12
        }
        // Last day of lastQuarterMonth = first of (lastQuarterMonth + 1) minus 1 day
        var components = DateComponents()
        components.year = year
        components.month = lastQuarterMonth + 1 > 12 ? 1 : lastQuarterMonth + 1
        components.day = 1
        if lastQuarterMonth == 12 { components.year = year + 1 }
        guard let firstOfNextMonth = calendar.date(from: components) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: firstOfNextMonth)
    }

    /// Returns the last day of the current calendar year (December 31)
    func lastDayOfYear() -> Date? {
        let year = calendar.component(.year, from: referenceDate)
        var components = DateComponents()
        components.year = year
        components.month = 12
        components.day = 31
        return calendar.date(from: components)
    }

    /// Returns the first day of the next calendar year (January 1)
    func firstDayOfNextYear() -> Date? {
        let year = calendar.component(.year, from: referenceDate)
        var components = DateComponents()
        components.year = year + 1
        components.month = 1
        components.day = 1
        return calendar.date(from: components)
    }

    /// Returns the next occurrence of the given weekday (always in the future)
    func nextWeekday(_ target: Weekday) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: referenceDate)
        let targetWeekday = target.calendarValue

        var daysToAdd = targetWeekday - currentWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7
        }

        return calendar.date(byAdding: .day, value: daysToAdd, to: referenceDate)
    }

    /// Resolves a month/day pair to the next occurrence (future-biased)
    func resolveMonthDay(month: Int, day: Int, time: (hour: Int, minute: Int)) -> Date? {
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
}

// MARK: - NLTaskParser Title Cleanup

private extension NLTaskParser {
    func cleanTitle(_ text: String) -> String {
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

// MARK: - NLTaskParser Utility Helpers

private extension NLTaskParser {
    var allDayNames: [String] {
        [
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun"
        ]
    }

    func calendarComponentForUnit(_ unit: String) -> Calendar.Component {
        switch unit {
        case "minute", "minutes", "min", "mins": return .minute
        case "hour", "hours", "hr", "hrs": return .hour
        case "day", "days": return .day
        case "week", "weeks": return .weekOfYear
        case "month", "months": return .month
        case "year", "years": return .year
        default: return .hour
        }
    }

    func weekdayFromName(_ name: String) -> Weekday? {
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

    func monthFromName(_ name: String) -> Int? {
        let months: [String: Int] = [
            "jan": 1, "january": 1, "feb": 2, "february": 2,
            "mar": 3, "march": 3, "apr": 4, "april": 4,
            "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
            "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10, "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]
        return months[name.lowercased()]
    }

    /// Extracts informal spoken-number date expressions.
    /// Handles "a couple (of) <unit>" → 2, "a few <unit>" → 3, and
    /// "in <word> <unit>" → N (e.g. "in two weeks", "in three days").
    func extractSpokenNumberDate(
        from text: String,
        time: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text
        let units = #"minute|minutes|min|mins|hour|hours|hr|hrs|day|days|week|weeks|month|months|year|years"#

        // "a couple (of) <unit>" / "in a couple (of) <unit>" — 2 units
        let couplePattern = #"\b(?:in\s+)?a\s+couple(?:\s+of)?\s+("# + units + #")\b"#
        if let regex = try? NSRegularExpression(pattern: couplePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let unitRange = Range(match.range(at: 1), in: result),
           let fullRange = Range(match.range, in: result) {
            let component = calendarComponentForUnit(String(result[unitRange]).lowercased())
            if let date = calendar.date(byAdding: component, value: 2, to: referenceDate) {
                result = result.replacingCharacters(in: fullRange, with: "")
                return (result, date)
            }
        }

        // "a few <unit>" / "in a few <unit>" — 3 units
        let fewPattern = #"\b(?:in\s+)?a\s+few\s+("# + units + #")\b"#
        if let regex = try? NSRegularExpression(pattern: fewPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let unitRange = Range(match.range(at: 1), in: result),
           let fullRange = Range(match.range, in: result) {
            let component = calendarComponentForUnit(String(result[unitRange]).lowercased())
            if let date = calendar.date(byAdding: component, value: 3, to: referenceDate) {
                result = result.replacingCharacters(in: fullRange, with: "")
                return (result, date)
            }
        }

        // "in <spelled-out number> <unit>" — e.g. "in two weeks", "in three days"
        let wordNums = "one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty"
        let spelledPattern = #"\bin\s+("# + wordNums + #")\s+("# + units + #")\b"#
        if let regex = try? NSRegularExpression(pattern: spelledPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let wordRange = Range(match.range(at: 1), in: result),
           let unitRange = Range(match.range(at: 2), in: result),
           let fullRange = Range(match.range, in: result) {
            let component = calendarComponentForUnit(String(result[unitRange]).lowercased())
            if let value = wordToNumber(String(result[wordRange]).lowercased()),
               let date = calendar.date(byAdding: component, value: value, to: referenceDate) {
                result = result.replacingCharacters(in: fullRange, with: "")
                return (result, date)
            }
        }

        return nil
    }

    /// Adjusts a parsed hour value based on an optional AM/PM string.
    func adjustHourForAMPM(hour: Int, ampm: String?) -> Int {
        guard let ampm = ampm else {
            // No AM/PM — hours > 12 are 24h format; 1-12 are interpreted as-is
            return hour
        }
        if ampm == "pm" && hour < 12 {
            return hour + 12
        } else if ampm == "am" && hour == 12 {
            return 0
        }
        return hour
    }

    /// Extracts bare AM/PM time expressions that have no "at" prefix.
    ///
    /// Matches:
    /// - `3pm` / `10am` — hour + AM/PM suffix
    /// - `3:30pm` / `10:00am` — hour:minute + AM/PM suffix
    ///
    /// AM/PM is **required** to avoid false positives on bare numbers.
    func extractBareAMPMTime(from text: String) -> (String, (hour: Int, minute: Int)?)? {
        var result = text

        // "3:30pm" / "10:00am" — hour:minute + AM/PM
        let bareTimeWithMinPattern = #"\b(\d{1,2}):(\d{2})\s*([aApP][mM])\b"#
        if let regex = try? NSRegularExpression(pattern: bareTimeWithMinPattern),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let hourRange = Range(match.range(at: 1), in: result),
           let minRange = Range(match.range(at: 2), in: result),
           let ampmRange = Range(match.range(at: 3), in: result) {
            var hour = Int(result[hourRange]) ?? 0
            let minute = Int(result[minRange]) ?? 0
            let ampm = String(result[ampmRange]).lowercased()
            hour = adjustHourForAMPM(hour: hour, ampm: ampm)
            if let fullRange = Range(match.range, in: result) {
                result = result.replacingCharacters(in: fullRange, with: "")
            }
            return (result, (hour, minute))
        }

        // "3pm" / "10am" — bare hour + AM/PM, no minutes
        let bareTimePattern = #"\b(\d{1,2})\s*([aApP][mM])\b"#
        if let regex = try? NSRegularExpression(pattern: bareTimePattern),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let hourRange = Range(match.range(at: 1), in: result),
           let ampmRange = Range(match.range(at: 2), in: result) {
            var hour = Int(result[hourRange]) ?? 0
            let ampm = String(result[ampmRange]).lowercased()
            hour = adjustHourForAMPM(hour: hour, ampm: ampm)
            if let fullRange = Range(match.range, in: result) {
                result = result.replacingCharacters(in: fullRange, with: "")
            }
            return (result, (hour, 0))
        }

        return nil
    }

    /// Converts a spelled-out number word to its integer value.
    /// Supports one through twelve, plus fifteen, twenty, and thirty.
    func wordToNumber(_ word: String) -> Int? {
        let numberWords: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30
        ]
        return numberWords[word.lowercased()]
    }

    /// Extracts "next <month>" / "this <month>" expressions.
    /// Examples: "next October", "this July", "by next March"
    /// Resolves to the 1st of the named month, next occurrence in time.
    func extractNextNamedMonthDate(
        from text: String,
        time resolvedTime: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text
        // swiftlint:disable:next line_length
        let monthNames = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
        let pattern = #"\b(?:by\s+)?(?:next|this)\s+("# + monthNames + #")\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let monthRange = Range(match.range(at: 1), in: result),
              let fullRange = Range(match.range, in: result) else {
            return nil
        }

        let monthStr = String(result[monthRange]).lowercased()
        guard let month = monthFromName(monthStr),
              let date = resolveMonthDay(month: month, day: 1, time: resolvedTime) else {
            return nil
        }

        result = result.replacingCharacters(in: fullRange, with: "")
        return (result, date)
    }

    /// Extracts ordinal day-of-month expressions: "the 5th", "the 15th", "by the 22nd"
    /// Resolves to that day of the current month if in the future, otherwise next month.
    func extractOrdinalDayDate(
        from text: String,
        time resolvedTime: (hour: Int, minute: Int)
    ) -> (String, Date?)? {
        var result = text
        let pattern = #"\b(?:by\s+|on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let dayRange = Range(match.range(at: 1), in: result),
              let fullRange = Range(match.range, in: result) else {
            return nil
        }

        let day = Int(result[dayRange]) ?? 1
        guard day >= 1, day <= 31 else { return nil }

        let currentMonth = calendar.component(.month, from: referenceDate)
        let currentYear = calendar.component(.year, from: referenceDate)

        var comps = DateComponents()
        comps.day = day
        comps.hour = resolvedTime.hour
        comps.minute = resolvedTime.minute
        comps.second = 0

        // Try this month first
        comps.year = currentYear
        comps.month = currentMonth
        if let date = calendar.date(from: comps), date > referenceDate {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, date)
        }

        // Otherwise next month
        if let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: referenceDate) {
            comps.year = calendar.component(.year, from: nextMonthDate)
            comps.month = calendar.component(.month, from: nextMonthDate)
            if let date = calendar.date(from: comps) {
                result = result.replacingCharacters(in: fullRange, with: "")
                return (result, date)
            }
        }

        return nil
    }

    // MARK: - Recurrence Extraction

    // swiftlint:disable cyclomatic_complexity
    /// Extracts recurring task patterns from text, returning the cleaned string and rule.
    ///
    /// Supported patterns:
    /// - `every day` / `daily` → `.daily`
    /// - `every week` / `weekly` → `.weekly`
    /// - `every weekday` / `every weekdays` → `.weekdays`
    /// - `every weekend` / `every weekends` → weekly on Sat+Sun
    /// - `every Monday` (any named day) → weekly on that day
    /// - `every month` / `monthly` → `.monthly`
    /// - `every year` / `yearly` / `annually` → `.yearly`
    /// - `every 2 days` / `every 3 weeks` / `every 6 months` → interval-based rule
    /// - `every other day/week/month/year` → interval: 2
    /// - `biweekly` / `fortnightly` → every 2 weeks
    /// - `semiannually` / `semi-annually` → every 6 months
    /// - `biennial` / `biennially` → every 2 years
    func extractRecurrenceRule(from text: String) -> (String, RecurrenceRule?)? {
        var result = text
        let dayNames = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"

        // "every 2 days/weeks/months/years" — interval-based (must run before single-unit checks)
        let intervalPattern = #"\bevery\s+(\d+)\s+(day|days|week|weeks|month|months|year|years)\b"#
        if let regex = try? NSRegularExpression(pattern: intervalPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let numRange = Range(match.range(at: 1), in: result),
           let unitRange = Range(match.range(at: 2), in: result),
           let fullRange = Range(match.range, in: result) {
            let interval = Int(result[numRange]) ?? 1
            let unit = String(result[unitRange]).lowercased()
            let frequency: RecurrenceFrequency
            switch unit {
            case "week", "weeks": frequency = .weekly
            case "month", "months": frequency = .monthly
            case "year", "years": frequency = .yearly
            default: frequency = .daily
            }
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, RecurrenceRule(frequency: frequency, interval: interval))
        }

        // "every other day/week/month/year" → interval: 2
        let otherPattern = #"\bevery\s+other\s+(day|week|month|year)\b"#
        if let regex = try? NSRegularExpression(pattern: otherPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let unitRange = Range(match.range(at: 1), in: result),
           let fullRange = Range(match.range, in: result) {
            let unit = String(result[unitRange]).lowercased()
            let frequency: RecurrenceFrequency
            switch unit {
            case "week": frequency = .weekly
            case "month": frequency = .monthly
            case "year": frequency = .yearly
            default: frequency = .daily
            }
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, RecurrenceRule(frequency: frequency, interval: 2))
        }

        // "every weekday(s)" — Mon–Fri
        let weekdayPattern = #"\bevery\s+weekdays?\b"#
        if let regex = try? NSRegularExpression(pattern: weekdayPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .weekdays)
        }

        // "every weekend(s)" — Sat+Sun
        let weekendPattern = #"\bevery\s+weekends?\b"#
        if let regex = try? NSRegularExpression(pattern: weekendPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, RecurrenceRule(frequency: .weekly, daysOfWeek: RecurrenceDay.weekends))
        }

        // "every Monday and Wednesday" / "every Mon, Wed, Fri" — two or more named days.
        // Must run BEFORE single-named-day check so "every Monday and Wednesday" isn't
        // partially matched as "every Monday" (leaving " and Wednesday" as stray text).
        if let extracted = extractMultiDayWeeklyRule(from: result) {
            return extracted
        }

        // "every Monday" / "every Friday" / … → weekly on that day
        let namedDayPattern = #"\bevery\s+("# + dayNames + #")\b"#
        if let regex = try? NSRegularExpression(pattern: namedDayPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let dayRange = Range(match.range(at: 1), in: result),
           let fullRange = Range(match.range, in: result),
           let recDay = recurrenceDayFromName(String(result[dayRange])) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, RecurrenceRule(frequency: .weekly, daysOfWeek: [recDay]))
        }

        // "every day"
        let everyDayPattern = #"\bevery\s+day\b"#
        if let regex = try? NSRegularExpression(pattern: everyDayPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .daily)
        }

        // "every week"
        let everyWeekPattern = #"\bevery\s+week\b"#
        if let regex = try? NSRegularExpression(pattern: everyWeekPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .weekly)
        }

        // "every month"
        let everyMonthPattern = #"\bevery\s+month\b"#
        if let regex = try? NSRegularExpression(pattern: everyMonthPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .monthly)
        }

        // "every year"
        let everyYearPattern = #"\bevery\s+year\b"#
        if let regex = try? NSRegularExpression(pattern: everyYearPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .yearly)
        }

        // "daily"
        let dailyPattern = #"\bdaily\b"#
        if let regex = try? NSRegularExpression(pattern: dailyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .daily)
        }

        // "weekly"
        let weeklyPattern = #"\bweekly\b"#
        if let regex = try? NSRegularExpression(pattern: weeklyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .weekly)
        }

        // "monthly"
        let monthlyPattern = #"\bmonthly\b"#
        if let regex = try? NSRegularExpression(pattern: monthlyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .monthly)
        }

        // "semiannually" / "semi-annually" → every 6 months (twice a year)
        // Must be checked BEFORE the "annually" pattern below, because \bannually\b
        // would match the "annually" suffix of "semi-annually" and consume it first.
        if let match = result.range(of: #"\bsemi-?annually\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, RecurrenceRule(frequency: .monthly, interval: 6))
        }

        // "biennial" / "biennially" → every 2 years
        // Must be checked BEFORE the "yearly/annually" pattern to prevent the
        // "annually" suffix from being consumed independently.
        // Regex: biennial (8 chars, single-l) with optional "ly" suffix.
        if let match = result.range(of: #"\bbiennial(?:ly)?\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, RecurrenceRule(frequency: .yearly, interval: 2))
        }

        // "yearly" / "annually"
        let yearlyPattern = #"\b(?:yearly|annually)\b"#
        if let regex = try? NSRegularExpression(pattern: yearlyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .yearly)
        }

        // "biweekly" / "fortnightly"
        let biweeklyPattern = #"\b(?:biweekly|fortnightly)\b"#
        if let regex = try? NSRegularExpression(pattern: biweeklyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, .biweekly)
        }

        // "quarterly" / "every quarter" → monthly, interval 3
        let quarterlyPattern = #"\b(?:quarterly|every\s+quarter)\b"#
        if let regex = try? NSRegularExpression(pattern: quarterlyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let fullRange = Range(match.range, in: result) {
            result = result.replacingCharacters(in: fullRange, with: "")
            return (result, RecurrenceRule(frequency: .monthly, interval: 3))
        }

        // "bimonthly" → every 2 months
        // Note: in English "bimonthly" is ambiguous (twice-a-month vs every-two-months);
        // we follow the same convention as "biweekly" and treat it as "every two months".
        if let match = result.range(of: #"\bbimonthly\b"#, options: [.regularExpression, .caseInsensitive]) {
            result = result.replacingCharacters(in: match, with: "")
            return (result, RecurrenceRule(frequency: .monthly, interval: 2))
        }

        return nil
    }

    // swiftlint:enable cyclomatic_complexity

    /// Extracts multi-day weekly recurrence from phrases like "every Monday and Wednesday"
    /// or "every Mon, Wed, Fri". Returns the cleaned text and rule, or nil if no match.
    ///
    /// Supports:
    /// - Two days: `every Tuesday and Thursday`
    /// - Three or more: `every Mon, Wed, Fri`
    /// - Oxford comma: `every Monday, Wednesday, and Friday`
    /// - Abbreviations: `Mon`, `Tue`, `Wed`, `Thu`, `Fri`, `Sat`, `Sun` (and variants)
    func extractMultiDayWeeklyRule(from text: String) -> (String, RecurrenceRule?)? {
        let allDayPat = allDayNames.joined(separator: "|")
        // Separator: comma (with optional "and") OR bare "and" with surrounding spaces
        let sep = #"(?:\s*,\s*(?:and\s*)?|\s+and\s+)"#
        // Full phrase: "every <day> (<sep> <day>)+" — must have at least two days
        let pattern = #"\bevery\s+(?:"# + allDayPat + #")(?:"# + sep + #"(?:"# + allDayPat + #"))+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let fullRange = Range(match.range, in: text) else {
            return nil
        }
        let matchedText = String(text[fullRange])
        guard let dayRegex = try? NSRegularExpression(
            pattern: "\\b(" + allDayPat + ")\\b",
            options: .caseInsensitive
        ) else {
            return nil
        }
        let dayMatches = dayRegex.matches(
            in: matchedText,
            range: NSRange(matchedText.startIndex..., in: matchedText)
        )
        let extractedDays = dayMatches.compactMap { mch -> RecurrenceDay? in
            guard let rng = Range(mch.range(at: 1), in: matchedText) else { return nil }
            return recurrenceDayFromName(String(matchedText[rng]))
        }
        let daySet = Set(extractedDays)
        guard daySet.count >= 2 else { return nil }
        var result = text
        result = result.replacingCharacters(in: fullRange, with: "")
        return (result, RecurrenceRule(frequency: .weekly, daysOfWeek: daySet))
    }

    /// Maps a day name string (case-insensitive) to a `RecurrenceDay`.
    /// Supports both full names ("monday") and common abbreviations ("mon", "tue", etc.).
    func recurrenceDayFromName(_ name: String) -> RecurrenceDay? {
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
