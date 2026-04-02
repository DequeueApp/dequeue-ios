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
        service.addFocusTime(1_500) // 25 minutes
        // Focus time is tracked but doesn't directly affect streak
        XCTAssertFalse(service.streakInfo.isTodayActive)
    }

    // MARK: - Persistence

    func testRecordsPersist() throws {
        service.recordTaskCompletion()
        service.recordTaskCompletion()

        // Verify persistence by reading UserDefaults directly instead of
        // creating a second service instance. Creating ephemeral service
        // instances triggers a Swift 6 runtime crash during deallocation
        // in swift_task_deinitOnExecutorImpl (rdar://FB15432891).
        // Note: isTodayActive is a computed property on the live service and
        // cannot be tested via raw UserDefaults. The serialization of the
        // underlying records is verified below.
        let data = try XCTUnwrap(
            userDefaults.data(forKey: "streakTrackerRecords"),
            "Expected streakTrackerRecords to be persisted in UserDefaults"
        )
        let records = try XCTUnwrap(
            try? JSONDecoder().decode(
                [String: DailyProductivityRecord].self, from: data
            ),
            "Expected streakTrackerRecords data to be decodable"
        )
        let today = Calendar.current.startOfDay(for: Date())
        let key = ISO8601DateFormatter().string(from: today).prefix(10)
        let todayRecord = try XCTUnwrap(
            records[String(key)],
            "Expected a record for today's date key"
        )
        XCTAssertEqual(todayRecord.tasksCompleted, 2)
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
            focusTimeSeconds: 3_600
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

    // MARK: - Multi-Day Streak Scenarios

    /// Seeds the shared `userDefaults` with active records for the given day offsets
    /// (negative = past, e.g. -1 = yesterday) and reloads the existing service instance.
    ///
    /// We reload rather than recreate because creating short-lived `@MainActor` service
    /// instances inside a test body triggers a Swift 6 deinit crash in
    /// `swift_task_deinitOnExecutorImpl` (rdar://FB15432891).  `reloadFromStorage()`
    /// re-reads the seeded `UserDefaults` and recalculates state on the existing object.
    private func seedDays(_ offsets: [Int], tasksCompleted: Int = 1) throws {
        var records: [String: DailyProductivityRecord] = [:]
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone

        for offset in offsets {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = formatter.string(from: date)
            records[key] = DailyProductivityRecord(
                dateString: key,
                tasksCompleted: tasksCompleted,
                tasksCreated: 0,
                stacksCompleted: 0,
                focusTimeSeconds: 0
            )
        }

        let data = try JSONEncoder().encode(records)
        userDefaults.set(data, forKey: "streakTrackerRecords")
        // Reload the existing service instance (avoids deinit crash on ephemeral instances).
        service.reloadFromStorage()
    }

    func testCurrentStreakIncludesPriorConsecutiveDays() throws {
        // Seed yesterday and day-before-yesterday as active
        try seedDays([-2, -1])
        service.recordTaskCompletion()   // today → streak of 3
        XCTAssertEqual(service.streakInfo.currentStreak, 3)
    }

    func testCurrentStreakBreaksAtGap() throws {
        // Day-before-yesterday active, yesterday skipped → gap breaks the chain
        try seedDays([-2])
        service.recordTaskCompletion()   // today → only today counts
        XCTAssertEqual(service.streakInfo.currentStreak, 1)
    }

    func testCurrentStreakZeroWhenOnlyYesterdayActiveAndNotToday() throws {
        // Yesterday was active but nothing done today → streak resets to 0
        try seedDays([-1])
        XCTAssertEqual(service.streakInfo.currentStreak, 0)
        XCTAssertFalse(service.streakInfo.isTodayActive)
    }

    func testLongestStreakBeatsByHistoricalRun() throws {
        // 4-day consecutive streak ending last week, then a gap, then active today
        try seedDays([-7, -6, -5, -4])
        service.recordTaskCompletion()   // today: currentStreak = 1
        XCTAssertEqual(service.streakInfo.longestStreak, 4)
        XCTAssertEqual(service.streakInfo.currentStreak, 1)
    }

    func testLongestStreakEqualsCurrentWhenContinuing() throws {
        // 3-day streak still running — longest should match current
        try seedDays([-2, -1])
        service.recordTaskCompletion()   // streak = 3 with no prior longer run
        XCTAssertEqual(service.streakInfo.currentStreak, 3)
        XCTAssertEqual(service.streakInfo.longestStreak, 3)
    }

    func testTotalActiveDaysCountsMultipleDays() throws {
        // Two prior active days plus today = 3 total active days
        try seedDays([-2, -1])
        service.recordTaskCompletion()
        XCTAssertEqual(service.streakInfo.totalActiveDays, 3)
        XCTAssertEqual(service.streakInfo.totalTasksCompleted, 3)
    }

    func testMilestoneThreeDetectedOnThirdConsecutiveDay() throws {
        // Reaching exactly a milestone value triggers recentMilestone
        try seedDays([-2, -1])
        service.recordTaskCompletion()   // streak hits 3 == StreakMilestone.three
        XCTAssertEqual(service.streakInfo.currentStreak, 3)
        XCTAssertEqual(service.recentMilestone, .three)
    }

    func testNoMilestoneWhenStreakIsNotAtMilestoneValue() throws {
        // Streak of 2 is not a milestone value
        try seedDays([-1])
        service.recordTaskCompletion()   // streak = 2
        XCTAssertEqual(service.streakInfo.currentStreak, 2)
        XCTAssertNil(service.recentMilestone)
    }

    func testWeekActivityIncludesSeededPastDays() throws {
        // Seed three consecutive past days — all should appear as active in weekActivity
        try seedDays([-1, -2, -3])
        let activeDays = service.streakInfo.weekActivity.filter(\.isActive)
        XCTAssertEqual(activeDays.count, 3)
    }

    func testWeekActivityTodayReflectsCompletions() {
        service.recordTaskCompletion()
        let today = service.streakInfo.weekActivity.last
        XCTAssertNotNil(today)
        XCTAssertEqual(today?.tasksCompleted, 1)
        XCTAssertTrue(today?.isActive ?? false)
    }

    func testMonthActivityTodayReflectsCompletions() {
        service.recordTaskCompletion()
        service.recordTaskCompletion()
        let today = service.streakInfo.monthActivity.last
        XCTAssertNotNil(today)
        XCTAssertEqual(today?.tasksCompleted, 2)
        XCTAssertTrue(today?.isActive ?? false)
    }
}
