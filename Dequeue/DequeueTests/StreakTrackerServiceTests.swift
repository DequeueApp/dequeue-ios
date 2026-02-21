//
//  StreakTrackerServiceTests.swift
//  DequeueTests
//
//  Tests for the streak tracker service.
//

import XCTest
@testable import Dequeue

@MainActor
final class StreakTrackerServiceTests: XCTestCase {

    private var service: StreakTrackerService!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "StreakTrackerTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        service = StreakTrackerService(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        service = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStreakIsZero() {
        XCTAssertEqual(service.streakInfo.currentStreak, 0)
        XCTAssertEqual(service.streakInfo.longestStreak, 0)
    }

    func testInitialTodayIsInactive() {
        XCTAssertFalse(service.streakInfo.isTodayActive)
        XCTAssertEqual(service.streakInfo.todayTasksCompleted, 0)
    }

    func testInitialTotalsAreZero() {
        XCTAssertEqual(service.streakInfo.totalTasksCompleted, 0)
        XCTAssertEqual(service.streakInfo.totalActiveDays, 0)
    }

    func testInitialTasksRemainingForStreak() {
        XCTAssertEqual(
            service.streakInfo.tasksRemainingForStreak,
            StreakTrackerService.minimumTasksForStreak
        )
    }

    // MARK: - Task Completion

    func testRecordTaskCompletion() {
        service.recordTaskCompletion()

        XCTAssertEqual(service.streakInfo.todayTasksCompleted, 1)
        XCTAssertTrue(service.streakInfo.isTodayActive)
    }

    func testMultipleTaskCompletions() {
        service.recordTaskCompletion()
        service.recordTaskCompletion()
        service.recordTaskCompletion()

        XCTAssertEqual(service.streakInfo.todayTasksCompleted, 3)
    }

    func testTaskCompletionUpdatesTotal() {
        service.recordTaskCompletion()
        service.recordTaskCompletion()

        XCTAssertEqual(service.streakInfo.totalTasksCompleted, 2)
    }

    func testTaskCompletionActivatesStreak() {
        service.recordTaskCompletion()

        XCTAssertEqual(service.streakInfo.currentStreak, 1)
        XCTAssertEqual(service.streakInfo.tasksRemainingForStreak, 0)
    }

    // MARK: - Task Creation

    func testRecordTaskCreation() {
        service.recordTaskCreation()
        // Task creation doesn't affect streak
        XCTAssertFalse(service.streakInfo.isTodayActive)
    }

    // MARK: - Stack Completion

    func testRecordStackCompletion() {
        service.recordStackCompletion()
        // Stack completion doesn't directly count as task completion
        // but is tracked separately
        XCTAssertEqual(service.streakInfo.todayTasksCompleted, 0)
    }

    // MARK: - Focus Time

    func testAddFocusTime() {
        service.addFocusTime(1500) // 25 minutes
        // Focus time is tracked but doesn't directly affect streak
        XCTAssertFalse(service.streakInfo.isTodayActive)
    }

    // MARK: - Persistence

    func testRecordsPersist() {
        service.recordTaskCompletion()
        service.recordTaskCompletion()

        // Create new service with same UserDefaults
        let service2 = StreakTrackerService(userDefaults: userDefaults)
        XCTAssertEqual(service2.streakInfo.todayTasksCompleted, 2)
        XCTAssertTrue(service2.streakInfo.isTodayActive)
    }

    // MARK: - Week Activity

    func testWeekActivityHas7Days() {
        XCTAssertEqual(service.streakInfo.weekActivity.count, 7)
    }

    func testWeekActivityLastDayIsToday() {
        let lastDay = service.streakInfo.weekActivity.last
        XCTAssertNotNil(lastDay)

        let calendar = Calendar.current
        XCTAssertTrue(calendar.isDateInToday(lastDay!.date))
    }

    // MARK: - Month Activity

    func testMonthActivityHas30Days() {
        XCTAssertEqual(service.streakInfo.monthActivity.count, 30)
    }

    // MARK: - Milestones

    func testCheckMilestoneReturnsNilWhenNoStreak() {
        let milestone = service.checkMilestone()
        XCTAssertNil(milestone)
    }

    func testDismissMilestone() {
        service.dismissMilestone()
        XCTAssertNil(service.recentMilestone)
    }

    // MARK: - Day Activity Model

    func testDayActivityIntensityLevel() {
        let zero = DayActivity(dateString: "2026-01-01", date: Date(), tasksCompleted: 0, isActive: false)
        XCTAssertEqual(zero.intensityLevel, 0)

        let one = DayActivity(dateString: "2026-01-01", date: Date(), tasksCompleted: 1, isActive: true)
        XCTAssertEqual(one.intensityLevel, 1)

        let three = DayActivity(dateString: "2026-01-01", date: Date(), tasksCompleted: 3, isActive: true)
        XCTAssertEqual(three.intensityLevel, 2)

        let five = DayActivity(dateString: "2026-01-01", date: Date(), tasksCompleted: 5, isActive: true)
        XCTAssertEqual(five.intensityLevel, 3)

        let ten = DayActivity(dateString: "2026-01-01", date: Date(), tasksCompleted: 10, isActive: true)
        XCTAssertEqual(ten.intensityLevel, 4)
    }

    // MARK: - Daily Record

    func testDailyRecordIsActive() {
        let active = DailyProductivityRecord(
            dateString: "2026-01-01",
            tasksCompleted: 1,
            tasksCreated: 0,
            stacksCompleted: 0,
            focusTimeSeconds: 0
        )
        XCTAssertTrue(active.isActive)

        let inactive = DailyProductivityRecord(
            dateString: "2026-01-01",
            tasksCompleted: 0,
            tasksCreated: 5,
            stacksCompleted: 0,
            focusTimeSeconds: 3600
        )
        XCTAssertFalse(inactive.isActive)
    }

    func testDailyRecordIdentifiable() {
        let record = DailyProductivityRecord(
            dateString: "2026-02-19",
            tasksCompleted: 0,
            tasksCreated: 0,
            stacksCompleted: 0,
            focusTimeSeconds: 0
        )
        XCTAssertEqual(record.id, "2026-02-19")
    }

    // MARK: - Streak Milestone

    func testMilestoneEmojis() {
        XCTAssertEqual(StreakMilestone.three.emoji, "🔥")
        XCTAssertEqual(StreakMilestone.seven.emoji, "⭐")
        XCTAssertEqual(StreakMilestone.thirty.emoji, "🏆")
        XCTAssertEqual(StreakMilestone.oneHundred.emoji, "💯")
        XCTAssertEqual(StreakMilestone.threeHundredSixtyFive.emoji, "👑")
    }

    func testMilestoneTitles() {
        XCTAssertEqual(StreakMilestone.seven.title, "Week Warrior")
        XCTAssertEqual(StreakMilestone.thirty.title, "Month Master")
        XCTAssertEqual(StreakMilestone.threeHundredSixtyFive.title, "Year Champion")
    }

    // MARK: - Minimum Tasks Threshold

    func testMinimumTasksForStreak() {
        XCTAssertEqual(StreakTrackerService.minimumTasksForStreak, 1)
    }
}
