//
//  RecurrenceRuleTests.swift
//  DequeueTests
//
//  Tests for RecurrenceRule model, date calculations, and RecurringTaskService
//

import XCTest
@testable import Dequeue

@MainActor
final class RecurrenceRuleTests: XCTestCase {

    // MARK: - RecurrenceRule Model Tests

    func testDailyPreset() {
        let rule = RecurrenceRule.daily
        XCTAssertEqual(rule.frequency, .daily)
        XCTAssertEqual(rule.interval, 1)
        XCTAssertTrue(rule.daysOfWeek.isEmpty)
        XCTAssertNil(rule.dayOfMonth)
        XCTAssertEqual(rule.end, .never)
    }

    func testWeeklyPreset() {
        let rule = RecurrenceRule.weekly
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 1)
        XCTAssertTrue(rule.daysOfWeek.isEmpty)
    }

    func testWeekdaysPreset() {
        let rule = RecurrenceRule.weekdays
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 1)
        XCTAssertEqual(rule.daysOfWeek, RecurrenceDay.weekdays)
        XCTAssertTrue(rule.daysOfWeek.contains(.monday))
        XCTAssertTrue(rule.daysOfWeek.contains(.friday))
        XCTAssertFalse(rule.daysOfWeek.contains(.saturday))
        XCTAssertFalse(rule.daysOfWeek.contains(.sunday))
    }

    func testBiweeklyPreset() {
        let rule = RecurrenceRule.biweekly
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 2)
    }

    func testMonthlyPreset() {
        let rule = RecurrenceRule.monthly
        XCTAssertEqual(rule.frequency, .monthly)
        XCTAssertEqual(rule.interval, 1)
    }

    func testYearlyPreset() {
        let rule = RecurrenceRule.yearly
        XCTAssertEqual(rule.frequency, .yearly)
        XCTAssertEqual(rule.interval, 1)
    }

    func testIntervalClampedToOne() {
        let rule = RecurrenceRule(frequency: .daily, interval: 0)
        XCTAssertEqual(rule.interval, 1)

        let ruleNegative = RecurrenceRule(frequency: .daily, interval: -5)
        XCTAssertEqual(ruleNegative.interval, 1)
    }

    // MARK: - Display Text Tests

    func testDailyDisplayText() {
        let rule = RecurrenceRule.daily
        XCTAssertEqual(rule.displayText, "Every daily")
        XCTAssertEqual(rule.shortText, "Daily")
    }

    func testWeeklyDisplayText() {
        let rule = RecurrenceRule.weekly
        XCTAssertEqual(rule.shortText, "Weekly")
    }

    func testWeekdaysDisplayText() {
        let rule = RecurrenceRule.weekdays
        XCTAssertEqual(rule.shortText, "Weekdays")
    }

    func testBiweeklyDisplayText() {
        let rule = RecurrenceRule.biweekly
        XCTAssertEqual(rule.shortText, "Every 2 weeks")
    }

    func testMonthlyDisplayText() {
        let rule = RecurrenceRule.monthly
        XCTAssertEqual(rule.shortText, "Monthly")
    }

    func testYearlyDisplayText() {
        let rule = RecurrenceRule.yearly
        XCTAssertEqual(rule.shortText, "Yearly")
    }

    func testCustomDaysDisplayText() {
        let rule = RecurrenceRule(
            frequency: .weekly,
            daysOfWeek: [.monday, .wednesday, .friday]
        )
        XCTAssertEqual(rule.shortText, "Mon, Wed, Fri")
    }

    func testEvery3DaysDisplayText() {
        let rule = RecurrenceRule(frequency: .daily, interval: 3)
        XCTAssertEqual(rule.shortText, "Every 3 days")
    }

    func testEvery2MonthsDisplayText() {
        let rule = RecurrenceRule(frequency: .monthly, interval: 2)
        XCTAssertEqual(rule.shortText, "Every 2 months")
    }

    // MARK: - End Condition Tests

    func testEndNever() {
        let rule = RecurrenceRule(frequency: .daily, end: .never)
        XCTAssertEqual(rule.end, .never)
        XCTAssertFalse(rule.displayText.contains("times"))
        XCTAssertFalse(rule.displayText.contains("until"))
    }

    func testEndAfterOccurrences() {
        let rule = RecurrenceRule(frequency: .daily, end: .afterOccurrences(5))
        XCTAssertEqual(rule.end, .afterOccurrences(5))
        XCTAssertTrue(rule.displayText.contains("5 times"))
    }

    func testEndOnDate() {
        let endDate = Date(timeIntervalSince1970: 1_800_000_000) // future date
        let rule = RecurrenceRule(frequency: .daily, end: .onDate(endDate))
        if case .onDate(let date) = rule.end {
            XCTAssertEqual(date, endDate)
        } else {
            XCTFail("Expected onDate end condition")
        }
        XCTAssertTrue(rule.displayText.contains("until"))
    }

    // MARK: - JSON Encoding/Decoding Tests

    func testEncodeDecode() {
        let original = RecurrenceRule(
            frequency: .weekly,
            interval: 2,
            daysOfWeek: [.monday, .wednesday, .friday],
            end: .afterOccurrences(10),
            occurrenceCount: 3
        )

        let data = original.toData()
        XCTAssertNotNil(data)

        let decoded = RecurrenceRule.fromData(data)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.frequency, .weekly)
        XCTAssertEqual(decoded?.interval, 2)
        XCTAssertEqual(decoded?.daysOfWeek, [.monday, .wednesday, .friday])
        XCTAssertEqual(decoded?.end, .afterOccurrences(10))
        XCTAssertEqual(decoded?.occurrenceCount, 3)
    }

    func testDecodeNilData() {
        let decoded = RecurrenceRule.fromData(nil)
        XCTAssertNil(decoded)
    }

    func testDecodeInvalidData() {
        let decoded = RecurrenceRule.fromData(Data("invalid".utf8))
        XCTAssertNil(decoded)
    }

    func testEncodeDecodeAllPresets() {
        for (name, preset) in RecurrenceRule.presets {
            let data = preset.toData()
            XCTAssertNotNil(data, "Failed to encode preset: \(name)")
            let decoded = RecurrenceRule.fromData(data)
            XCTAssertNotNil(decoded, "Failed to decode preset: \(name)")
            XCTAssertEqual(decoded?.frequency, preset.frequency, "Frequency mismatch for: \(name)")
            XCTAssertEqual(decoded?.interval, preset.interval, "Interval mismatch for: \(name)")
        }
    }

    func testEncodeDecodeEndDate() {
        let endDate = Date(timeIntervalSince1970: 1_800_000_000)
        let rule = RecurrenceRule(frequency: .monthly, end: .onDate(endDate))
        let data = rule.toData()
        let decoded = RecurrenceRule.fromData(data)
        XCTAssertNotNil(decoded)
        if case .onDate(let decodedDate) = decoded?.end {
            XCTAssertEqual(decodedDate.timeIntervalSince1970, endDate.timeIntervalSince1970, accuracy: 1)
        } else {
            XCTFail("Expected onDate end condition after decode")
        }
    }

    // MARK: - RecurrenceDay Tests

    func testRecurrenceDayWeekdays() {
        let weekdays = RecurrenceDay.weekdays
        XCTAssertEqual(weekdays.count, 5)
        XCTAssertFalse(weekdays.contains(.sunday))
        XCTAssertFalse(weekdays.contains(.saturday))
    }

    func testRecurrenceDayWeekends() {
        let weekends = RecurrenceDay.weekends
        XCTAssertEqual(weekends.count, 2)
        XCTAssertTrue(weekends.contains(.saturday))
        XCTAssertTrue(weekends.contains(.sunday))
    }

    func testRecurrenceDayShortNames() {
        XCTAssertEqual(RecurrenceDay.monday.shortName, "Mon")
        XCTAssertEqual(RecurrenceDay.tuesday.shortName, "Tue")
        XCTAssertEqual(RecurrenceDay.wednesday.shortName, "Wed")
        XCTAssertEqual(RecurrenceDay.thursday.shortName, "Thu")
        XCTAssertEqual(RecurrenceDay.friday.shortName, "Fri")
        XCTAssertEqual(RecurrenceDay.saturday.shortName, "Sat")
        XCTAssertEqual(RecurrenceDay.sunday.shortName, "Sun")
    }

    func testRecurrenceDaySingleLetters() {
        XCTAssertEqual(RecurrenceDay.monday.singleLetter, "M")
        XCTAssertEqual(RecurrenceDay.wednesday.singleLetter, "W")
        XCTAssertEqual(RecurrenceDay.friday.singleLetter, "F")
    }

    func testAllRecurrenceDaysCovered() {
        XCTAssertEqual(RecurrenceDay.allCases.count, 7)
    }

    // MARK: - Frequency Tests

    func testFrequencyDisplayNames() {
        XCTAssertEqual(RecurrenceFrequency.daily.displayName, "Daily")
        XCTAssertEqual(RecurrenceFrequency.weekly.displayName, "Weekly")
        XCTAssertEqual(RecurrenceFrequency.monthly.displayName, "Monthly")
        XCTAssertEqual(RecurrenceFrequency.yearly.displayName, "Yearly")
    }

    func testFrequencyCalendarComponents() {
        XCTAssertEqual(RecurrenceFrequency.daily.calendarComponent, .day)
        XCTAssertEqual(RecurrenceFrequency.weekly.calendarComponent, .weekOfYear)
        XCTAssertEqual(RecurrenceFrequency.monthly.calendarComponent, .month)
        XCTAssertEqual(RecurrenceFrequency.yearly.calendarComponent, .year)
    }

    // MARK: - Presets List Tests

    func testPresetsContainExpectedPresets() {
        let presets = RecurrenceRule.presets
        XCTAssertEqual(presets.count, 6)

        let names = presets.map { $0.name }
        XCTAssertTrue(names.contains("Daily"))
        XCTAssertTrue(names.contains("Weekdays"))
        XCTAssertTrue(names.contains("Weekly"))
        XCTAssertTrue(names.contains("Biweekly"))
        XCTAssertTrue(names.contains("Monthly"))
        XCTAssertTrue(names.contains("Yearly"))
    }

    // MARK: - Equatable Tests

    func testRulesAreEqual() {
        let rule1 = RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: [.monday])
        let rule2 = RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: [.monday])
        XCTAssertEqual(rule1, rule2)
    }

    func testRulesAreNotEqual() {
        let rule1 = RecurrenceRule(frequency: .weekly, interval: 1)
        let rule2 = RecurrenceRule(frequency: .weekly, interval: 2)
        XCTAssertNotEqual(rule1, rule2)
    }

    func testDifferentFrequenciesNotEqual() {
        let rule1 = RecurrenceRule(frequency: .daily)
        let rule2 = RecurrenceRule(frequency: .weekly)
        XCTAssertNotEqual(rule1, rule2)
    }

    // MARK: - Weekend Display Tests

    func testWeekendDaysDisplayText() {
        let rule = RecurrenceRule(frequency: .weekly, daysOfWeek: RecurrenceDay.weekends)
        XCTAssertEqual(rule.shortText, "Weekends")
    }

    // MARK: - Monthly Day Display

    func testMonthlyWithDayOfMonth() {
        let rule = RecurrenceRule(frequency: .monthly, dayOfMonth: 15)
        XCTAssertTrue(rule.displayText.contains("on day 15"))
    }
}
