//
//  RecurringTaskServiceTests.swift
//  DequeueTests
//
//  Tests for RecurringTaskService date calculation and task creation
//

import XCTest
import SwiftData
@testable import Dequeue

@MainActor
final class RecurringTaskServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var service: RecurringTaskService!
    var stack: Stack!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self, Tag.self, Arc.self, Device.self,
            configurations: config
        )
        context = container.mainContext
        service = RecurringTaskService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        service = nil
        stack = nil
    }

    // MARK: - Date Calculation Tests

    func testDailyNextDate() {
        let rule = RecurrenceRule.daily
        let startDate = makeDate(2026, 2, 21, 9, 0)
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate, makeDate(2026, 2, 22, 9, 0))
    }

    func testDailyEvery3Days() {
        let rule = RecurrenceRule(frequency: .daily, interval: 3)
        let startDate = makeDate(2026, 2, 21, 9, 0)
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate, makeDate(2026, 2, 24, 9, 0))
    }

    func testWeeklyNextDate() {
        let rule = RecurrenceRule.weekly
        let startDate = makeDate(2026, 2, 21, 9, 0) // Saturday
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate, makeDate(2026, 2, 28, 9, 0))
    }

    func testBiweeklyNextDate() {
        let rule = RecurrenceRule.biweekly
        let startDate = makeDate(2026, 2, 21, 9, 0) // Saturday
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate, makeDate(2026, 3, 7, 9, 0))
    }

    func testWeeklyWithSpecificDays() {
        // Monday and Friday, starting on Monday Feb 23
        let rule = RecurrenceRule(
            frequency: .weekly,
            daysOfWeek: [.monday, .friday]
        )
        let monday = makeDate(2026, 2, 23, 9, 0) // Monday
        let nextDate = service.calculateNextDate(from: monday, rule: rule)

        XCTAssertNotNil(nextDate)
        // Next day in the set after Monday should be Friday
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: nextDate!)
        XCTAssertEqual(weekday, 6) // Friday = 6
    }

    func testWeeklyWithSpecificDaysWrapsToNextWeek() {
        // Only Monday, starting on Friday Feb 27
        let rule = RecurrenceRule(
            frequency: .weekly,
            daysOfWeek: [.monday]
        )
        let friday = makeDate(2026, 2, 27, 9, 0) // Friday
        let nextDate = service.calculateNextDate(from: friday, rule: rule)

        XCTAssertNotNil(nextDate)
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: nextDate!)
        XCTAssertEqual(weekday, 2) // Monday = 2
    }

    func testMonthlyNextDate() {
        let rule = RecurrenceRule.monthly
        let startDate = makeDate(2026, 2, 21, 9, 0)
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate, makeDate(2026, 3, 21, 9, 0))
    }

    func testMonthlyWithDayOfMonth() {
        let rule = RecurrenceRule(frequency: .monthly, dayOfMonth: 15)
        let startDate = makeDate(2026, 2, 21, 9, 0)
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        let calendar = Calendar.current
        let day = calendar.component(.day, from: nextDate!)
        XCTAssertEqual(day, 15)
    }

    func testMonthlyDay31ClampsToFeb() {
        // Day 31 in February should clamp to Feb 28
        let rule = RecurrenceRule(frequency: .monthly, dayOfMonth: 31)
        let startDate = makeDate(2026, 1, 31, 9, 0) // Jan 31
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: nextDate!)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28) // 2026 is not a leap year
    }

    func testYearlyNextDate() {
        let rule = RecurrenceRule.yearly
        let startDate = makeDate(2026, 2, 21, 9, 0)
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate, makeDate(2027, 2, 21, 9, 0))
    }

    func testMonthlyEvery2Months() {
        let rule = RecurrenceRule(frequency: .monthly, interval: 2)
        let startDate = makeDate(2026, 1, 15, 9, 0)
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate, makeDate(2026, 3, 15, 9, 0))
    }

    func testDailyCrossesMonthBoundary() {
        let rule = RecurrenceRule.daily
        let startDate = makeDate(2026, 2, 28, 9, 0)
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate, makeDate(2026, 3, 1, 9, 0))
    }

    func testDailyCrossesYearBoundary() {
        let rule = RecurrenceRule.daily
        let startDate = makeDate(2026, 12, 31, 9, 0)
        let nextDate = service.calculateNextDate(from: startDate, rule: rule)

        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate, makeDate(2027, 1, 1, 9, 0))
    }

    // MARK: - Next Occurrence Creation Tests

    func testCreateNextOccurrenceForDailyTask() async throws {
        let task = createRecurringTask(rule: .daily, dueTime: makeDate(2026, 2, 21, 9, 0))

        let nextTask = try await service.createNextOccurrence(for: task)

        XCTAssertNotNil(nextTask)
        XCTAssertEqual(nextTask?.title, "Test Recurring Task")
        XCTAssertEqual(nextTask?.dueTime, makeDate(2026, 2, 22, 9, 0))
        XCTAssertEqual(nextTask?.status, .pending)
        XCTAssertNotNil(nextTask?.recurrenceRuleData)
        XCTAssertEqual(nextTask?.recurrenceParentId, task.id)
        XCTAssertEqual(nextTask?.completedOccurrences, 1)
    }

    func testCreateNextOccurrencePreservesProperties() async throws {
        let task = createRecurringTask(rule: .weekly, dueTime: makeDate(2026, 2, 21, 9, 0))
        task.taskDescription = "Weekly review"
        task.tags = ["work", "review"]
        task.priority = 2
        try context.save()

        let nextTask = try await service.createNextOccurrence(for: task)

        XCTAssertNotNil(nextTask)
        XCTAssertEqual(nextTask?.taskDescription, "Weekly review")
        XCTAssertEqual(nextTask?.tags, ["work", "review"])
        XCTAssertEqual(nextTask?.priority, 2)
    }

    func testCreateNextOccurrencePreservesStartTimeLead() async throws {
        // Task starts 1 hour before due
        let task = createRecurringTask(rule: .daily, dueTime: makeDate(2026, 2, 21, 10, 0))
        task.startTime = makeDate(2026, 2, 21, 9, 0) // 1 hour before due
        try context.save()

        let nextTask = try await service.createNextOccurrence(for: task)

        XCTAssertNotNil(nextTask)
        XCTAssertEqual(nextTask?.dueTime, makeDate(2026, 2, 22, 10, 0))
        XCTAssertEqual(nextTask?.startTime, makeDate(2026, 2, 22, 9, 0)) // Still 1 hour before
    }

    func testNoOccurrenceForNonRecurring() async throws {
        let task = QueueTask(title: "One-time Task", status: .completed, sortOrder: 0, stack: stack)
        context.insert(task)
        try context.save()

        let nextTask = try await service.createNextOccurrence(for: task)
        XCTAssertNil(nextTask)
    }

    func testStopsAfterMaxOccurrences() async throws {
        let rule = RecurrenceRule(frequency: .daily, end: .afterOccurrences(3))
        let task = createRecurringTask(rule: rule, dueTime: makeDate(2026, 2, 21, 9, 0))
        task.completedOccurrences = 3 // Already at max
        try context.save()

        let nextTask = try await service.createNextOccurrence(for: task)
        XCTAssertNil(nextTask)
    }

    func testContinuesBeforeMaxOccurrences() async throws {
        let rule = RecurrenceRule(frequency: .daily, end: .afterOccurrences(5))
        let task = createRecurringTask(rule: rule, dueTime: makeDate(2026, 2, 21, 9, 0))
        task.completedOccurrences = 2 // Below max
        try context.save()

        let nextTask = try await service.createNextOccurrence(for: task)
        XCTAssertNotNil(nextTask)
        XCTAssertEqual(nextTask?.completedOccurrences, 3)
    }

    func testStopsAfterEndDate() async throws {
        let endDate = makeDate(2026, 2, 20, 0, 0) // Yesterday
        let rule = RecurrenceRule(frequency: .daily, end: .onDate(endDate))
        let task = createRecurringTask(rule: rule, dueTime: makeDate(2026, 2, 21, 9, 0))

        let nextTask = try await service.createNextOccurrence(for: task)
        XCTAssertNil(nextTask)
    }

    func testStopsWhenNextDateExceedsEndDate() async throws {
        // End date is tomorrow, but next occurrence would be day after
        let endDate = makeDate(2026, 2, 22, 0, 0)
        let rule = RecurrenceRule(frequency: .weekly, end: .onDate(endDate))
        let task = createRecurringTask(rule: rule, dueTime: makeDate(2026, 2, 21, 9, 0))

        let nextTask = try await service.createNextOccurrence(for: task)
        XCTAssertNil(nextTask) // Feb 28 > Feb 22
    }

    func testOccurrenceCountIncrementsOnCompletedTask() async throws {
        let task = createRecurringTask(rule: .daily, dueTime: makeDate(2026, 2, 21, 9, 0))
        XCTAssertEqual(task.completedOccurrences, 0)

        _ = try await service.createNextOccurrence(for: task)
        XCTAssertEqual(task.completedOccurrences, 1)

        // The new task should carry the incremented count
        let tasks = try context.fetch(FetchDescriptor<QueueTask>())
        let pendingTasks = tasks.filter { $0.status == .pending && $0.recurrenceRuleData != nil }
        XCTAssertEqual(pendingTasks.count, 1)
        XCTAssertEqual(pendingTasks.first?.completedOccurrences, 1)
    }

    func testRecurrenceParentIdChains() async throws {
        let task = createRecurringTask(rule: .daily, dueTime: makeDate(2026, 2, 21, 9, 0))
        let originalId = task.id

        let second = try await service.createNextOccurrence(for: task)
        XCTAssertEqual(second?.recurrenceParentId, originalId)

        // Complete second and create third — should still point to original
        if let second {
            let third = try await service.createNextOccurrence(for: second)
            XCTAssertEqual(third?.recurrenceParentId, originalId)
        }
    }

    func testCreateNextOccurrenceAddsToStack() async throws {
        let initialCount = stack.tasks.count
        let task = createRecurringTask(rule: .daily, dueTime: makeDate(2026, 2, 21, 9, 0))

        _ = try await service.createNextOccurrence(for: task)

        // Stack should have both the original and the new occurrence
        XCTAssertEqual(stack.tasks.count, initialCount + 2) // original + new
    }

    func testUsesCreatedAtWhenNoDueDate() async throws {
        let rule = RecurrenceRule.daily
        let task = QueueTask(
            title: "No Due Date Recurring",
            status: .completed,
            sortOrder: 0,
            createdAt: makeDate(2026, 2, 21, 9, 0),
            stack: stack,
            recurrenceRuleData: rule.toData()
        )
        context.insert(task)
        try context.save()

        let nextTask = try await service.createNextOccurrence(for: task)
        XCTAssertNotNil(nextTask)
        XCTAssertNotNil(nextTask?.dueTime) // Should get a due time based on createdAt + 1 day
    }

    // MARK: - Query Helper Tests

    func testRecurringTasksInStack() {
        _ = createRecurringTask(rule: .daily, dueTime: makeDate(2026, 2, 21, 9, 0))
        let nonRecurring = QueueTask(title: "Non-recurring", status: .pending, sortOrder: 1, stack: stack)
        context.insert(nonRecurring)
        try? context.save()

        let recurring = service.recurringTasks(in: stack)
        XCTAssertEqual(recurring.count, 1)
    }

    // MARK: - Helpers

    private func createRecurringTask(
        rule: RecurrenceRule,
        dueTime: Date?,
        status: TaskStatus = .completed
    ) -> QueueTask {
        let task = QueueTask(
            title: "Test Recurring Task",
            dueTime: dueTime,
            status: status,
            sortOrder: 0,
            stack: stack,
            recurrenceRuleData: rule.toData()
        )
        context.insert(task)
        try? context.save()
        return task
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = TimeZone.current
        return Calendar.current.date(from: components)!
    }
}

