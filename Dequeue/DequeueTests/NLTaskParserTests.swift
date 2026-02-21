//
//  NLTaskParserTests.swift
//  DequeueTests
//
//  Comprehensive tests for the natural language task input parser.
//

import XCTest
@testable import Dequeue

@MainActor
final class NLTaskParserTests: XCTestCase {

    // Fixed reference date: Wednesday, Feb 19, 2026 at 10:00 AM EST
    private var referenceDate: Date!
    private var calendar: Calendar!
    private var parser: NLTaskParser!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 19
        components.hour = 10
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/New_York")
        referenceDate = calendar.date(from: components)!

        parser = NLTaskParser(
            calendar: calendar,
            referenceDate: referenceDate,
            defaultTime: (9, 0)
        )
    }

    // MARK: - Basic Title Parsing

    func testPlainTextReturnsTitle() {
        let result = parser.parse("Buy groceries")
        XCTAssertEqual(result.title, "Buy groceries")
        XCTAssertNil(result.dueTime)
        XCTAssertNil(result.startTime)
        XCTAssertNil(result.priority)
        XCTAssertTrue(result.tags.isEmpty)
        XCTAssertFalse(result.hasStructuredData)
    }

    func testEmptyInputReturnsEmpty() {
        let result = parser.parse("")
        XCTAssertEqual(result.title, "")
        XCTAssertFalse(result.hasStructuredData)
    }

    func testWhitespaceOnlyReturnsEmpty() {
        let result = parser.parse("   ")
        XCTAssertEqual(result.title, "")
    }

    // MARK: - Priority Parsing

    func testPriorityColonHigh() {
        let result = parser.parse("Review PR p:high")
        XCTAssertEqual(result.title, "Review PR")
        XCTAssertEqual(result.priority, 2)
    }

    func testPriorityColonUrgent() {
        let result = parser.parse("Fix crash p:urgent")
        XCTAssertEqual(result.title, "Fix crash")
        XCTAssertEqual(result.priority, 3)
    }

    func testPriorityColonLow() {
        let result = parser.parse("Clean desk p:low")
        XCTAssertEqual(result.title, "Clean desk")
        XCTAssertEqual(result.priority, 0)
    }

    func testPriorityColonMedium() {
        let result = parser.parse("Reply to email p:med")
        XCTAssertEqual(result.title, "Reply to email")
        XCTAssertEqual(result.priority, 1)
    }

    func testPriorityColonMediumFull() {
        let result = parser.parse("Reply to email p:medium")
        XCTAssertEqual(result.title, "Reply to email")
        XCTAssertEqual(result.priority, 1)
    }

    func testPriorityP1() {
        let result = parser.parse("Deploy hotfix p1")
        XCTAssertEqual(result.title, "Deploy hotfix")
        XCTAssertEqual(result.priority, 3) // p1 = urgent
    }

    func testPriorityP2() {
        let result = parser.parse("Code review p2")
        XCTAssertEqual(result.title, "Code review")
        XCTAssertEqual(result.priority, 2) // p2 = high
    }

    func testPriorityP3() {
        let result = parser.parse("Update docs p3")
        XCTAssertEqual(result.title, "Update docs")
        XCTAssertEqual(result.priority, 1) // p3 = medium
    }

    func testPriorityP4() {
        let result = parser.parse("Archive old files p4")
        XCTAssertEqual(result.title, "Archive old files")
        XCTAssertEqual(result.priority, 0) // p4 = low
    }

    func testPriorityTripleExclamation() {
        let result = parser.parse("Server down !!!")
        XCTAssertEqual(result.title, "Server down")
        XCTAssertEqual(result.priority, 3)
    }

    func testPriorityDoubleExclamation() {
        let result = parser.parse("Customer complaint !!")
        XCTAssertEqual(result.title, "Customer complaint")
        XCTAssertEqual(result.priority, 2)
    }

    // MARK: - Tag Parsing

    func testSingleTag() {
        let result = parser.parse("Buy milk #errands")
        XCTAssertEqual(result.title, "Buy milk")
        XCTAssertEqual(result.tags, ["errands"])
    }

    func testMultipleTags() {
        let result = parser.parse("Team meeting #work #meetings #q1")
        XCTAssertEqual(result.title, "Team meeting")
        XCTAssertEqual(result.tags, ["work", "meetings", "q1"])
    }

    func testTagsWithHyphens() {
        let result = parser.parse("Fix bug #bug-fix #high-priority")
        XCTAssertEqual(result.title, "Fix bug")
        XCTAssertEqual(result.tags, ["bug-fix", "high-priority"])
    }

    func testTagsWithUnderscores() {
        let result = parser.parse("Write tests #unit_tests")
        XCTAssertEqual(result.title, "Write tests")
        XCTAssertEqual(result.tags, ["unit_tests"])
    }

    func testPureNumberHashNotTag() {
        // #123 should NOT be treated as a tag (it could be an issue number)
        let result = parser.parse("Fix issue #123")
        XCTAssertEqual(result.title, "Fix issue #123")
        XCTAssertTrue(result.tags.isEmpty)
    }

    // MARK: - Date: Today/Tomorrow

    func testTodayParsing() {
        let result = parser.parse("Finish report today")
        XCTAssertEqual(result.title, "Finish report")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 9) // default time
        XCTAssertEqual(components.minute, 0)
    }

    func testTomorrowParsing() {
        let result = parser.parse("Call dentist tomorrow")
        XCTAssertEqual(result.title, "Call dentist")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.hour, 9)
    }

    func testTonightParsing() {
        let result = parser.parse("Watch movie tonight")
        XCTAssertEqual(result.title, "Watch movie")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour], from: result.dueTime!)
        XCTAssertEqual(components.hour, 21) // 9 PM
    }

    func testByTomorrowParsing() {
        let result = parser.parse("Submit report by tomorrow")
        XCTAssertEqual(result.title, "Submit report")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day], from: result.dueTime!)
        XCTAssertEqual(components.day, 20)
    }

    func testDayAfterTomorrowParsing() {
        let result = parser.parse("Prepare slides day after tomorrow")
        XCTAssertEqual(result.title, "Prepare slides")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day], from: result.dueTime!)
        XCTAssertEqual(components.day, 21)
    }

    // MARK: - Date: Relative Time

    func testInTwoHours() {
        let result = parser.parse("Check on deployment in 2 hours")
        XCTAssertEqual(result.title, "Check on deployment")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour], from: result.dueTime!)
        XCTAssertEqual(components.hour, 12) // 10 AM + 2 hours
    }

    func testIn30Minutes() {
        let result = parser.parse("Stand-up meeting in 30 minutes")
        XCTAssertEqual(result.title, "Stand-up meeting")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 30)
    }

    func testIn3Days() {
        let result = parser.parse("Follow up in 3 days")
        XCTAssertEqual(result.title, "Follow up")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day], from: result.dueTime!)
        XCTAssertEqual(components.day, 22)
    }

    func testIn2Weeks() {
        let result = parser.parse("Review performance in 2 weeks")
        XCTAssertEqual(result.title, "Review performance")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day], from: result.dueTime!)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 5)
    }

    // MARK: - Date: Day Names

    func testNextMonday() {
        // Reference is Wednesday Feb 19, so next Monday = Feb 23
        let result = parser.parse("Team sync next Monday")
        XCTAssertEqual(result.title, "Team sync")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day], from: result.dueTime!)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 23)
    }

    func testOnFriday() {
        // Reference is Wednesday Feb 19, so Friday = Feb 20
        let result = parser.parse("Retrospective on Friday")
        XCTAssertEqual(result.title, "Retrospective")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day], from: result.dueTime!)
        XCTAssertEqual(components.day, 20)
    }

    func testBareDayName() {
        let result = parser.parse("Grocery shopping Saturday")
        XCTAssertEqual(result.title, "Grocery shopping")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day], from: result.dueTime!)
        XCTAssertEqual(components.day, 21) // next Saturday
    }

    func testNextWeek() {
        let result = parser.parse("Dentist appointment next week")
        XCTAssertEqual(result.title, "Dentist appointment")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day], from: result.dueTime!)
        XCTAssertEqual(components.day, 23) // next Monday
    }

    func testThisWeekend() {
        let result = parser.parse("Clean garage this weekend")
        XCTAssertEqual(result.title, "Clean garage")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day], from: result.dueTime!)
        XCTAssertEqual(components.day, 21) // next Saturday
    }

    func testEndOfDay() {
        let result = parser.parse("Submit timesheet end of day")
        XCTAssertEqual(result.title, "Submit timesheet")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 17) // 5 PM
    }

    func testEOD() {
        let result = parser.parse("Respond to client eod")
        XCTAssertEqual(result.title, "Respond to client")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour], from: result.dueTime!)
        XCTAssertEqual(components.hour, 17)
    }

    func testEndOfWeek() {
        let result = parser.parse("Deploy to staging end of week")
        XCTAssertEqual(result.title, "Deploy to staging")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 20) // Friday
        XCTAssertEqual(components.hour, 17)
    }

    // MARK: - Date: Month/Day

    func testMonthDayFullName() {
        let result = parser.parse("Tax return by March 15")
        XCTAssertEqual(result.title, "Tax return")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day], from: result.dueTime!)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 15)
    }

    func testMonthDayAbbreviated() {
        let result = parser.parse("Conference registration Jan 10")
        XCTAssertEqual(result.title, "Conference registration")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        // Jan 10 is in the past (ref is Feb 19), so should be next year
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 10)
    }

    func testSlashDateFormat() {
        let result = parser.parse("Deadline 3/15")
        XCTAssertEqual(result.title, "Deadline")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day], from: result.dueTime!)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 15)
    }

    func testDashDateFormat() {
        let result = parser.parse("Launch 4-1")
        XCTAssertEqual(result.title, "Launch")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day], from: result.dueTime!)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 1)
    }

    // MARK: - Time Parsing

    func testAtTimePM() {
        let result = parser.parse("Meeting tomorrow at 3pm")
        XCTAssertEqual(result.title, "Meeting")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
    }

    func testAtTimeAM() {
        let result = parser.parse("Standup tomorrow at 9am")
        XCTAssertEqual(result.title, "Standup")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour], from: result.dueTime!)
        XCTAssertEqual(components.hour, 9)
    }

    func testAtTimeWithMinutes() {
        let result = parser.parse("Call tomorrow at 2:30pm")
        XCTAssertEqual(result.title, "Call")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 30)
    }

    func testAt24HourTime() {
        let result = parser.parse("Deploy tomorrow at 15:00")
        XCTAssertEqual(result.title, "Deploy")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
    }

    func testAtNoon() {
        let result = parser.parse("Lunch meeting at noon")
        XCTAssertEqual(result.title, "Lunch meeting")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour], from: result.dueTime!)
        XCTAssertEqual(components.hour, 12)
    }

    func testAtMidnight() {
        let result = parser.parse("Server maintenance at midnight")
        XCTAssertEqual(result.title, "Server maintenance")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour], from: result.dueTime!)
        XCTAssertEqual(components.hour, 0)
    }

    func testTimeAloneAssumesTodayOrTomorrow() {
        // At 10 AM ref time, "at 3pm" should be today at 3pm
        let result = parser.parse("Quick sync at 3pm")
        XCTAssertEqual(result.title, "Quick sync")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 19) // today
        XCTAssertEqual(components.hour, 15)
    }

    func testPastTimeGoesTomorrow() {
        // At 10 AM ref time, "at 8am" is already past — should be tomorrow
        let result = parser.parse("Morning run at 8am")
        XCTAssertEqual(result.title, "Morning run")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 20) // tomorrow
        XCTAssertEqual(components.hour, 8)
    }

    // MARK: - Start Date Parsing

    func testStartingTomorrow() {
        let result = parser.parse("Sprint planning starting tomorrow")
        XCTAssertEqual(result.title, "Sprint planning")
        XCTAssertNotNil(result.startTime)

        let components = calendar.dateComponents([.day], from: result.startTime!)
        XCTAssertEqual(components.day, 20)
    }

    func testFromMonday() {
        let result = parser.parse("New project from Monday")
        XCTAssertEqual(result.title, "New project")
        XCTAssertNotNil(result.startTime)

        let components = calendar.dateComponents([.day], from: result.startTime!)
        XCTAssertEqual(components.day, 23) // next Monday
    }

    // MARK: - Combined Parsing

    func testFullCombinedInput() {
        let result = parser.parse("Review PR tomorrow at 3pm #work #code-review p:high")
        XCTAssertEqual(result.title, "Review PR")
        XCTAssertNotNil(result.dueTime)
        XCTAssertEqual(result.priority, 2) // high
        XCTAssertEqual(result.tags, ["work", "code-review"])
        XCTAssertTrue(result.hasStructuredData)

        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.hour, 15)
    }

    func testDateAndTags() {
        let result = parser.parse("Buy birthday gift next Friday #personal #shopping")
        XCTAssertEqual(result.title, "Buy birthday gift")
        XCTAssertEqual(result.tags, ["personal", "shopping"])
        XCTAssertNotNil(result.dueTime)
    }

    func testPriorityAndDate() {
        let result = parser.parse("Server migration p:urgent by March 1")
        XCTAssertEqual(result.title, "Server migration")
        XCTAssertEqual(result.priority, 3)
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day], from: result.dueTime!)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 1)
    }

    func testAllFieldsCombined() {
        let result = parser.parse("Deploy v2.0 next Monday at 2pm #deploy #release p1")
        XCTAssertEqual(result.title, "Deploy v2.0")
        XCTAssertEqual(result.priority, 3) // p1 = urgent
        XCTAssertEqual(result.tags, ["deploy", "release"])
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 23) // next Monday
        XCTAssertEqual(components.hour, 14)
    }

    // MARK: - Edge Cases

    func testNumberInTitle() {
        let result = parser.parse("Buy 5 apples")
        XCTAssertEqual(result.title, "Buy 5 apples")
        XCTAssertNil(result.dueTime)
    }

    func testHashNumberPreserved() {
        // "#123" alone should not be treated as tag
        let result = parser.parse("Fix issue #123 tomorrow")
        XCTAssertTrue(result.title.contains("#123"))
        XCTAssertNotNil(result.dueTime)
    }

    func testMultipleSpacesCollapsed() {
        let result = parser.parse("Clean   up   code  tomorrow")
        XCTAssertEqual(result.title, "Clean up code")
        XCTAssertNotNil(result.dueTime)
    }

    func testAbbreviatedDayNames() {
        let result = parser.parse("Meeting next Wed")
        XCTAssertEqual(result.title, "Meeting")
        XCTAssertNotNil(result.dueTime)

        let weekday = calendar.component(.weekday, from: result.dueTime!)
        XCTAssertEqual(weekday, 4) // Wednesday
    }

    func testMinutesAbbreviated() {
        let result = parser.parse("Break in 15 min")
        XCTAssertEqual(result.title, "Break")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 15)
    }

    func testHoursAbbreviated() {
        let result = parser.parse("Check in 1 hr")
        XCTAssertEqual(result.title, "Check")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour], from: result.dueTime!)
        XCTAssertEqual(components.hour, 11)
    }

    // MARK: - NLTaskParseResult

    func testHasStructuredDataWithDate() {
        let result = parser.parse("Task tomorrow")
        XCTAssertTrue(result.hasStructuredData)
    }

    func testHasStructuredDataWithPriority() {
        let result = parser.parse("Task p:high")
        XCTAssertTrue(result.hasStructuredData)
    }

    func testHasStructuredDataWithTag() {
        let result = parser.parse("Task #work")
        XCTAssertTrue(result.hasStructuredData)
    }

    func testNoStructuredDataPlainText() {
        let result = parser.parse("Just a plain task")
        XCTAssertFalse(result.hasStructuredData)
    }
}
