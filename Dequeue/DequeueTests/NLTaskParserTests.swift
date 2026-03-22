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

    func testIn3Months() {
        // Reference: Feb 19, 2026 → May 19, 2026
        let result = parser.parse("Renew subscription in 3 months")
        XCTAssertEqual(result.title, "Renew subscription")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 19)
    }

    func testIn1Month() {
        // Reference: Feb 19, 2026 → March 19, 2026
        let result = parser.parse("Follow up in 1 month")
        XCTAssertEqual(result.title, "Follow up")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day], from: result.dueTime!)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 19)
    }

    func testIn1Year() {
        // Reference: Feb 19, 2026 → Feb 19, 2027
        let result = parser.parse("Review annual contract in 1 year")
        XCTAssertEqual(result.title, "Review annual contract")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 19)
    }

    // MARK: - Date: Indefinite Article "in a/an"

    func testInAnHour() {
        // Reference: Feb 19, 2026 at 10:00 AM → 11:00 AM same day
        let result = parser.parse("Quick call in an hour")
        XCTAssertEqual(result.title, "Quick call")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 11) // 10 AM + 1 hr
    }

    func testInADay() {
        // Reference: Feb 19, 2026 → Feb 20, 2026
        let result = parser.parse("Follow up in a day")
        XCTAssertEqual(result.title, "Follow up")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 20)
    }

    func testInAWeek() {
        // Reference: Feb 19, 2026 → Feb 26, 2026
        let result = parser.parse("Check status in a week")
        XCTAssertEqual(result.title, "Check status")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 26)
    }

    func testInAMonth() {
        // Reference: Feb 19, 2026 → March 19, 2026
        let result = parser.parse("Review proposal in a month")
        XCTAssertEqual(result.title, "Review proposal")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 19)
    }

    func testInAYear() {
        // Reference: Feb 19, 2026 → Feb 19, 2027
        let result = parser.parse("Renew license in a year")
        XCTAssertEqual(result.title, "Renew license")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 19)
    }

    func testInAMinute() {
        // Reference: Feb 19, 2026 at 10:00 → 10:01
        let result = parser.parse("Send the ping in a minute")
        XCTAssertEqual(result.title, "Send the ping")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 1)
    }

    func testNextMonth() {
        // Reference: Feb 19, 2026 → March 1, 2026 at defaultTime (9 AM)
        let result = parser.parse("Budget review next month")
        XCTAssertEqual(result.title, "Budget review")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 1)
        XCTAssertEqual(components.hour, 9) // defaultTime
    }

    func testEndOfMonth() {
        // Reference: Feb 19, 2026 → Feb 28, 2026 at 17:00
        let result = parser.parse("Submit invoices end of month")
        XCTAssertEqual(result.title, "Submit invoices")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28)
        XCTAssertEqual(components.hour, 17)
    }

    func testEOM() {
        // Reference: Feb 19, 2026 → Feb 28, 2026 at 17:00
        let result = parser.parse("Close out tickets eom")
        XCTAssertEqual(result.title, "Close out tickets")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28)
        XCTAssertEqual(components.hour, 17)
    }

    // MARK: - Date: Quarter/Year

    func testEndOfQuarter() {
        // Reference: Feb 19, 2026 → Q1 ends Mar 31, 2026 at 17:00
        let result = parser.parse("Finish Q1 goals end of quarter")
        XCTAssertEqual(result.title, "Finish Q1 goals")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 31)
        XCTAssertEqual(components.hour, 17)
    }

    func testEOQ() {
        // Reference: Feb 19, 2026 → Q1 ends Mar 31, 2026 at 17:00
        let result = parser.parse("Submit OKRs eoq")
        XCTAssertEqual(result.title, "Submit OKRs")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 31)
        XCTAssertEqual(components.hour, 17)
    }

    func testEndOfYear() {
        // Reference: Feb 19, 2026 → Dec 31, 2026 at 17:00
        let result = parser.parse("Annual review end of year")
        XCTAssertEqual(result.title, "Annual review")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 31)
        XCTAssertEqual(components.hour, 17)
    }

    func testEOY() {
        // Reference: Feb 19, 2026 → Dec 31, 2026 at 17:00
        let result = parser.parse("File taxes eoy")
        XCTAssertEqual(result.title, "File taxes")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.month, .day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 31)
        XCTAssertEqual(components.hour, 17)
    }

    func testNextYear() {
        // Reference: Feb 19, 2026 → Jan 1, 2027
        let result = parser.parse("Plan vacation next year")
        XCTAssertEqual(result.title, "Plan vacation")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }

    func testByNextYear() {
        // Reference: Feb 19, 2026 → Jan 1, 2027
        let result = parser.parse("Launch v2 by next year")
        XCTAssertEqual(result.title, "Launch v2")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
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

    // MARK: - Date: Named Month ("next/this October")

    func testNextMonthNameFuture() {
        // "next October" from Feb 19 2026 → Oct 1, 2026
        let result = parser.parse("Conference prep next October")
        XCTAssertEqual(result.title, "Conference prep")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 1)
    }

    func testNextMonthNamePast() {
        // "next January" from Feb 19 2026 → Jan 1, 2027 (Jan 2026 already passed)
        let result = parser.parse("New year plan next January")
        XCTAssertEqual(result.title, "New year plan")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }

    func testThisMonthNameFuture() {
        // "this March" from Feb 19 2026 → Mar 1, 2026
        let result = parser.parse("Spring cleanup this March")
        XCTAssertEqual(result.title, "Spring cleanup")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 1)
    }

    func testByNextMonthName() {
        // "by next July" from Feb 19 2026 → Jul 1, 2026
        let result = parser.parse("Finish thesis by next July")
        XCTAssertEqual(result.title, "Finish thesis")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 1)
    }

    func testNextMonthAbbreviated() {
        // "next Sep" from Feb 19 2026 → Sep 1, 2026
        let result = parser.parse("Budget review next Sep")
        XCTAssertEqual(result.title, "Budget review")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 1)
    }

    // MARK: - Date: Ordinal Day-of-Month ("the 5th", "by the 22nd")

    func testOrdinalDayFutureThisMonth() {
        // "the 25th" from Feb 19 2026 → Feb 25, 2026 (future in current month)
        let result = parser.parse("Pay rent the 25th")
        XCTAssertEqual(result.title, "Pay rent")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 25)
    }

    func testOrdinalDayPastRollsToNextMonth() {
        // "the 5th" from Feb 19 2026 → Mar 5, 2026 (Feb 5 is in the past)
        let result = parser.parse("Submit report the 5th")
        XCTAssertEqual(result.title, "Submit report")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 5)
    }

    func testByOrdinalDay() {
        // "by the 22nd" from Feb 19 2026 → Feb 22, 2026
        let result = parser.parse("Finish draft by the 22nd")
        XCTAssertEqual(result.title, "Finish draft")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 22)
    }

    func testOnOrdinalDay() {
        // "on the 1st" from Feb 19 2026 → Mar 1, 2026 (Feb 1 is in the past)
        let result = parser.parse("Team sync on the 1st")
        XCTAssertEqual(result.title, "Team sync")
        XCTAssertNotNil(result.dueTime)

        let components = calendar.dateComponents([.year, .month, .day], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
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

    // MARK: - Time-of-Day Compound Phrases

    func testThisMorning() {
        let result = parser.parse("Submit report this morning")
        XCTAssertEqual(result.title, "Submit report")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 19) // today
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    func testThisAfternoon() {
        let result = parser.parse("Call client this afternoon")
        XCTAssertEqual(result.title, "Call client")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 19) // today
        XCTAssertEqual(components.hour, 14) // 2 PM
    }

    func testThisEvening() {
        let result = parser.parse("Family dinner this evening")
        XCTAssertEqual(result.title, "Family dinner")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 19) // today
        XCTAssertEqual(components.hour, 18) // 6 PM
    }

    func testTomorrowMorning() {
        let result = parser.parse("Standup tomorrow morning")
        XCTAssertEqual(result.title, "Standup")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 20) // tomorrow
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    func testTomorrowAfternoon() {
        let result = parser.parse("Review PR tomorrow afternoon")
        XCTAssertEqual(result.title, "Review PR")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 20) // tomorrow
        XCTAssertEqual(components.hour, 14) // 2 PM
    }

    func testTomorrowEvening() {
        let result = parser.parse("Date night tomorrow evening")
        XCTAssertEqual(result.title, "Date night")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 20) // tomorrow
        XCTAssertEqual(components.hour, 18) // 6 PM
    }

    func testDayNameMorning() {
        // Reference is Wednesday Feb 19; next Friday = Feb 20
        let result = parser.parse("Team brunch Friday morning")
        XCTAssertEqual(result.title, "Team brunch")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 20) // next Friday
        XCTAssertEqual(components.hour, 9)
    }

    func testNextDayNameAfternoon() {
        // Reference is Wednesday Feb 19; next Monday = Feb 23
        let result = parser.parse("Planning session next Monday afternoon")
        XCTAssertEqual(result.title, "Planning session")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 23) // next Monday
        XCTAssertEqual(components.hour, 14) // 2 PM
    }

    func testCompoundPhraseExplicitTimeOverrides() {
        // "tomorrow morning at 10am" — explicit "at 10am" should override the morning default
        let result = parser.parse("Standup tomorrow morning at 10am")
        XCTAssertEqual(result.title, "Standup")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 20) // tomorrow
        XCTAssertEqual(components.hour, 10) // explicit at 10am wins
    }

    func testByTomorrowMorning() {
        let result = parser.parse("Submit invoice by tomorrow morning")
        XCTAssertEqual(result.title, "Submit invoice")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.hour, 9)
    }

    func testDayAfterTomorrowMorning() {
        // Reference: Feb 19 → day after tomorrow = Feb 21 at 9 AM
        let result = parser.parse("Team offsite day after tomorrow morning")
        XCTAssertEqual(result.title, "Team offsite")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 21)
        XCTAssertEqual(components.hour, 9)
    }

    func testDayAfterTomorrowAfternoon() {
        // Reference: Feb 19 → day after tomorrow = Feb 21 at 2 PM
        let result = parser.parse("Dentist day after tomorrow afternoon")
        XCTAssertEqual(result.title, "Dentist")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 21)
        XCTAssertEqual(components.hour, 14)
    }

    func testDayAfterTomorrowEvening() {
        // Reference: Feb 19 → day after tomorrow = Feb 21 at 6 PM
        let result = parser.parse("Dinner with parents day after tomorrow evening")
        XCTAssertEqual(result.title, "Dinner with parents")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 21)
        XCTAssertEqual(components.hour, 18)
    }

    // MARK: - Tonight (compound keyword — explicit "at X" overrides 9 PM default)

    func testTonightDefaultsToNinePM() {
        // Reference: Feb 19; tonight → today at 9 PM
        let result = parser.parse("Watch movie tonight")
        XCTAssertEqual(result.title, "Watch movie")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 19) // today
        XCTAssertEqual(components.hour, 21) // 9 PM
    }

    func testTonightWithExplicitTimeOverride() {
        // "tonight at 7pm" — explicit "at 7pm" should override the 9 PM default
        let result = parser.parse("Dinner reservation tonight at 7pm")
        XCTAssertEqual(result.title, "Dinner reservation")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 19) // today
        XCTAssertEqual(components.hour, 19) // 7 PM (explicit override)
    }

    func testByTonightDefaultsToNinePM() {
        let result = parser.parse("Submit report by tonight")
        XCTAssertEqual(result.title, "Submit report")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 21)
    }

    func testTonightAt1030PM() {
        // "tonight at 10:30pm" — explicit time with minutes
        let result = parser.parse("Late call tonight at 10:30pm")
        XCTAssertEqual(result.title, "Late call")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 30)
    }

    // MARK: - This Weekday ("this Friday", "this Monday", etc.)

    func testThisFriday() {
        // Reference: Wednesday Feb 19; "this Friday" → next Friday = Feb 20
        let result = parser.parse("Team lunch this Friday")
        XCTAssertEqual(result.title, "Team lunch")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 20) // Friday Feb 20
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.hour, 9) // default time
    }

    func testThisMonday() {
        // Reference: Wednesday Feb 19; "this Monday" → next Monday = Feb 23
        let result = parser.parse("Sprint planning this Monday")
        XCTAssertEqual(result.title, "Sprint planning")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month], from: result.dueTime!)
        XCTAssertEqual(components.day, 23) // Monday Feb 23
        XCTAssertEqual(components.month, 2)
    }

    func testThisSaturday() {
        // Reference: Wednesday Feb 19; "this Saturday" → Feb 21
        let result = parser.parse("Groceries this Saturday")
        XCTAssertEqual(result.title, "Groceries")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month], from: result.dueTime!)
        XCTAssertEqual(components.day, 21) // Saturday Feb 21
        XCTAssertEqual(components.month, 2)
    }

    func testThisWednesdayAtTime() {
        // Reference: Wednesday Feb 19; "this Wednesday at 2pm" → next Wednesday = Feb 25 at 2 PM
        let result = parser.parse("Review this Wednesday at 2pm")
        XCTAssertEqual(result.title, "Review")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 25) // next Wednesday Feb 25
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.hour, 14) // 2 PM
    }

    // MARK: - Spelled-Out Number Relative Dates

    func testInTwoWeeks() {
        // Reference: Wednesday Feb 19; "in two weeks" → March 5 (Feb 19 + 14 days)
        let result = parser.parse("Ship feature in two weeks")
        XCTAssertEqual(result.title, "Ship feature")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month], from: result.dueTime!)
        XCTAssertEqual(components.day, 5)
        XCTAssertEqual(components.month, 3)
    }

    func testInThreeDays() {
        // Reference: Wednesday Feb 19; "in three days" → Feb 22
        let result = parser.parse("Follow up in three days")
        XCTAssertEqual(result.title, "Follow up")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month], from: result.dueTime!)
        XCTAssertEqual(components.day, 22)
        XCTAssertEqual(components.month, 2)
    }

    func testInFiveHours() {
        // Reference: Feb 19 10:00 AM; "in five hours" → Feb 19 3:00 PM
        let result = parser.parse("Call back in five hours")
        XCTAssertEqual(result.title, "Call back")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 15) // 10 AM + 5 hours = 3 PM
    }

    func testInTwelveMonths() {
        // Reference: Feb 19, 2026; "in twelve months" → Feb 19, 2027
        let result = parser.parse("Annual review in twelve months")
        XCTAssertEqual(result.title, "Annual review")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.month, .year], from: result.dueTime!)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.year, 2027)
    }

    func testInTenMinutes() {
        // Reference: Feb 19 10:00 AM; "in ten minutes" → Feb 19 10:10 AM
        let result = parser.parse("Timer in ten minutes")
        XCTAssertEqual(result.title, "Timer")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 10)
    }

    func testACoupleOfDays() {
        // Reference: Feb 19; "a couple of days" → Feb 21
        let result = parser.parse("Follow up a couple of days")
        XCTAssertEqual(result.title, "Follow up")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month], from: result.dueTime!)
        XCTAssertEqual(components.day, 21)
        XCTAssertEqual(components.month, 2)
    }

    func testACoupleWeeks() {
        // Reference: Feb 19; "a couple weeks" → March 5 (Feb 19 + 14 days)
        let result = parser.parse("Revisit a couple weeks")
        XCTAssertEqual(result.title, "Revisit")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month], from: result.dueTime!)
        XCTAssertEqual(components.day, 5)
        XCTAssertEqual(components.month, 3)
    }

    func testAFewWeeks() {
        // Reference: Feb 19; "a few weeks" → March 12 (Feb 19 + 21 days)
        let result = parser.parse("Launch in a few weeks")
        XCTAssertEqual(result.title, "Launch")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month], from: result.dueTime!)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.month, 3)
    }

    func testAFewHours() {
        // Reference: Feb 19 10:00 AM; "a few hours" → Feb 19 1:00 PM (10 AM + 3 hours)
        let result = parser.parse("Ping team in a few hours")
        XCTAssertEqual(result.title, "Ping team")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .hour], from: result.dueTime!)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 13) // 10 AM + 3 hours = 1 PM
    }

    // MARK: - Bare AM/PM Time (no "at" prefix)

    func testBareTomorrowWithAMPMHour() {
        // "tomorrow 3pm" — bare AM/PM time without "at" prefix
        // Reference: Wed Feb 19 → tomorrow = Thu Feb 20 at 15:00
        let result = parser.parse("Call dentist tomorrow 3pm")
        XCTAssertEqual(result.title, "Call dentist")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
    }

    func testBareNextDayNameWithAMPMHour() {
        // "Friday 10am" — bare AM/PM time with day name
        // Reference: Thu Feb 19, 2026. nextWeekday(.friday): currentWeekday=5 (Thu),
        // targetWeekday=6 (Fri), daysToAdd=1 → Feb 20, 2026
        let result = parser.parse("Team standup Friday 10am")
        XCTAssertEqual(result.title, "Team standup")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 20) // Feb 20 (next Friday from Thursday Feb 19)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 0)
    }

    func testBareTimeWithMinutesAndAMPM() {
        // "9:30am Monday" — bare time with minutes, no "at" prefix
        // Reference: Wed Feb 19 → next Monday = Feb 23 (4 days)
        let result = parser.parse("Send invoice Monday 9:30am")
        XCTAssertEqual(result.title, "Send invoice")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 23) // Feb 23 (next Monday)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 30)
    }

    func testBareTimeWithTodayKeyword() {
        // "5pm today" — bare AM/PM time with today keyword
        // Reference: Feb 19 10:00 AM → today at 17:00
        let result = parser.parse("Submit report 5pm today")
        XCTAssertEqual(result.title, "Submit report")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.hour, 17)
        XCTAssertEqual(components.minute, 0)
    }

    func testBareTimeOverridesCompoundTonightTime() {
        // "tonight 11pm" — bare AM/PM should override compound 9 PM default
        // Reference: Feb 19 → today at 23:00
        let result = parser.parse("Lock up tonight 11pm")
        XCTAssertEqual(result.title, "Lock up")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 0)
    }

    func testBareTimeWithPM12Format() {
        // "12pm tomorrow" — noon
        let result = parser.parse("Lunch tomorrow 12pm")
        XCTAssertEqual(result.title, "Lunch")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.hour, 12) // noon
        XCTAssertEqual(components.minute, 0)
    }

    func testBareTimeWithMonthNameDate() {
        // "March 5th 2pm" — month name date + bare AM/PM
        // Mar 5 is in the future from Feb 19 → March 5 2026 at 14:00
        let result = parser.parse("Board meeting March 5th 2pm")
        XCTAssertEqual(result.title, "Board meeting")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 5)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 0)
    }

    func testAtPrefixStillTakesPriorityOverBareTime() {
        // "at 3pm" — explicit "at" prefix should still work as before
        // Reference: Feb 19 10:00 AM → today at 15:00
        let result = parser.parse("Call at 3pm")
        XCTAssertEqual(result.title, "Call")
        XCTAssertNotNil(result.dueTime)
        let components = calendar.dateComponents([.day, .month, .hour, .minute], from: result.dueTime!)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
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

    // MARK: - Recurrence Parsing

    func testEveryDay() {
        let result = parser.parse("Water plants every day")
        XCTAssertEqual(result.title, "Water plants")
        XCTAssertEqual(result.recurrenceRule?.frequency, .daily)
        XCTAssertEqual(result.recurrenceRule?.interval, 1)
        XCTAssertTrue(result.hasStructuredData)
    }

    func testDaily() {
        let result = parser.parse("Morning run daily")
        XCTAssertEqual(result.title, "Morning run")
        XCTAssertEqual(result.recurrenceRule?.frequency, .daily)
        XCTAssertEqual(result.recurrenceRule?.interval, 1)
    }

    func testEveryWeek() {
        let result = parser.parse("Team sync every week")
        XCTAssertEqual(result.title, "Team sync")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.interval, 1)
    }

    func testWeekly() {
        let result = parser.parse("Review backlog weekly")
        XCTAssertEqual(result.title, "Review backlog")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
    }

    func testEveryWeekday() {
        let result = parser.parse("Standup every weekday at 9am")
        XCTAssertEqual(result.title, "Standup")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, RecurrenceDay.weekdays)
    }

    func testEveryWeekdays() {
        // Plural form
        let result = parser.parse("Check email every weekdays")
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, RecurrenceDay.weekdays)
    }

    func testEveryWeekend() {
        let result = parser.parse("Hiking every weekend")
        XCTAssertEqual(result.title, "Hiking")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, RecurrenceDay.weekends)
    }

    func testEveryWeekends() {
        // Plural form
        let result = parser.parse("Meal prep every weekends")
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, RecurrenceDay.weekends)
    }

    func testEveryMonday() {
        let result = parser.parse("Team standup every Monday")
        XCTAssertEqual(result.title, "Team standup")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [RecurrenceDay.monday])
        XCTAssertNil(result.dueTime) // "Monday" should not produce a due date
    }

    func testEveryFriday() {
        let result = parser.parse("Gym every Friday 6am")
        XCTAssertEqual(result.title, "Gym")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [RecurrenceDay.friday])
    }

    func testEverySunday() {
        let result = parser.parse("Meal planning every Sunday")
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [RecurrenceDay.sunday])
    }

    func testEveryMonth() {
        let result = parser.parse("Pay rent every month")
        XCTAssertEqual(result.title, "Pay rent")
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(result.recurrenceRule?.interval, 1)
    }

    func testMonthly() {
        let result = parser.parse("Budget review monthly")
        XCTAssertEqual(result.title, "Budget review")
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
    }

    func testEveryYear() {
        let result = parser.parse("Renew passport every year")
        XCTAssertEqual(result.title, "Renew passport")
        XCTAssertEqual(result.recurrenceRule?.frequency, .yearly)
    }

    func testYearly() {
        let result = parser.parse("Tax filing yearly")
        XCTAssertEqual(result.recurrenceRule?.frequency, .yearly)
    }

    func testAnnually() {
        let result = parser.parse("Car service annually")
        XCTAssertEqual(result.recurrenceRule?.frequency, .yearly)
    }

    func testEvery2Days() {
        let result = parser.parse("Take medication every 2 days")
        XCTAssertEqual(result.title, "Take medication")
        XCTAssertEqual(result.recurrenceRule?.frequency, .daily)
        XCTAssertEqual(result.recurrenceRule?.interval, 2)
    }

    func testEvery3Weeks() {
        let result = parser.parse("Deep clean every 3 weeks")
        XCTAssertEqual(result.title, "Deep clean")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.interval, 3)
    }

    func testEvery6Months() {
        let result = parser.parse("Dentist every 6 months")
        XCTAssertEqual(result.title, "Dentist")
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(result.recurrenceRule?.interval, 6)
    }

    func testEveryOtherDay() {
        let result = parser.parse("Weights every other day")
        XCTAssertEqual(result.title, "Weights")
        XCTAssertEqual(result.recurrenceRule?.frequency, .daily)
        XCTAssertEqual(result.recurrenceRule?.interval, 2)
    }

    func testEveryOtherWeek() {
        let result = parser.parse("Sprint planning every other week")
        XCTAssertEqual(result.title, "Sprint planning")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.interval, 2)
    }

    func testBiweekly() {
        let result = parser.parse("1:1 with manager biweekly")
        XCTAssertEqual(result.title, "1:1 with manager")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.interval, 2)
    }

    func testFortnightly() {
        let result = parser.parse("Newsletter fortnightly")
        XCTAssertEqual(result.title, "Newsletter")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.interval, 2)
    }

    func testNoRecurrenceForPlainTask() {
        let result = parser.parse("Buy groceries tomorrow")
        XCTAssertNil(result.recurrenceRule)
    }

    func testHasStructuredDataWithRecurrence() {
        let result = parser.parse("Standup daily")
        XCTAssertTrue(result.hasStructuredData)
    }

    func testRecurrenceCombinedWithPriorityAndTag() {
        let result = parser.parse("Code review every Monday p:high #work")
        XCTAssertEqual(result.title, "Code review")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [RecurrenceDay.monday])
        XCTAssertEqual(result.priority, 2)
        XCTAssertEqual(result.tags, ["work"])
    }

    func testEveryMondayCaseInsensitive() {
        let result = parser.parse("Meeting EVERY MONDAY")
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [RecurrenceDay.monday])
    }

    // MARK: - Multi-day Weekly Recurrence

    func testEveryMondayAndWednesday() {
        let result = parser.parse("Gym every Monday and Wednesday")
        XCTAssertEqual(result.title, "Gym")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.interval, 1)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [.monday, .wednesday])
        XCTAssertNil(result.dueTime) // no due date from day names inside recurrence
    }

    func testEveryTuesdayAndThursday() {
        let result = parser.parse("Therapy every Tuesday and Thursday")
        XCTAssertEqual(result.title, "Therapy")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [.tuesday, .thursday])
    }

    func testEveryMonWedFriAbbreviatedCommaSeparated() {
        // Abbreviated day names with comma separator
        let result = parser.parse("Standup every Mon, Wed, Fri")
        XCTAssertEqual(result.title, "Standup")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [.monday, .wednesday, .friday])
    }

    func testEveryMondayWednesdayAndFridayOxfordComma() {
        // Three days with Oxford comma
        let result = parser.parse("Workout every Monday, Wednesday, and Friday")
        XCTAssertEqual(result.title, "Workout")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [.monday, .wednesday, .friday])
    }

    func testEveryTuesdayAndThursdayWithTime() {
        // Multi-day recurrence combined with a time expression
        let result = parser.parse("Team sync every Tuesday and Thursday at 10am")
        XCTAssertEqual(result.title, "Team sync")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [.tuesday, .thursday])
    }

    func testEveryMondayAndWednesdayCaseInsensitive() {
        let result = parser.parse("Yoga every MONDAY and WEDNESDAY")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [.monday, .wednesday])
    }

    func testEveryMondayAndWednesdayWithPriorityAndTag() {
        let result = parser.parse("1:1 every Monday and Friday p:high #work")
        XCTAssertEqual(result.title, "1:1")
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.daysOfWeek, [.monday, .friday])
        XCTAssertEqual(result.priority, 2)
        XCTAssertEqual(result.tags, ["work"])
    }

    // MARK: - Quarterly Recurrence

    func testQuarterly() {
        let result = parser.parse("Business review quarterly")
        XCTAssertEqual(result.title, "Business review")
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(result.recurrenceRule?.interval, 3)
    }

    func testEveryQuarter() {
        let result = parser.parse("Tax estimate every quarter")
        XCTAssertEqual(result.title, "Tax estimate")
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(result.recurrenceRule?.interval, 3)
    }

    func testQuarterlyWithPriority() {
        let result = parser.parse("Board update quarterly p:high")
        XCTAssertEqual(result.title, "Board update")
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(result.recurrenceRule?.interval, 3)
        XCTAssertEqual(result.priority, 2)
    }

    func testQuarterlyCaseInsensitive() {
        let result = parser.parse("Check-in QUARTERLY")
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(result.recurrenceRule?.interval, 3)
    }

    func testHasStructuredDataWithQuarterly() {
        let result = parser.parse("Review quarterly")
        XCTAssertTrue(result.hasStructuredData)
    }

    // MARK: - Bimonthly Recurrence

    func testBimonthly() {
        let result = parser.parse("Newsletter bimonthly")
        XCTAssertEqual(result.title, "Newsletter")
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(result.recurrenceRule?.interval, 2)
    }

    func testBimonthlyWithTag() {
        let result = parser.parse("Dentist bimonthly #health")
        XCTAssertEqual(result.title, "Dentist")
        XCTAssertEqual(result.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(result.recurrenceRule?.interval, 2)
        XCTAssertEqual(result.tags, ["health"])
    }

    func testBimonthlyDistinctFromBiweekly() {
        // Bimonthly → monthly interval 2; biweekly → weekly interval 2
        let bim = parser.parse("Task bimonthly")
        let biw = parser.parse("Task biweekly")
        XCTAssertEqual(bim.recurrenceRule?.frequency, .monthly)
        XCTAssertEqual(bim.recurrenceRule?.interval, 2)
        XCTAssertEqual(biw.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(biw.recurrenceRule?.interval, 2)
    }
}
