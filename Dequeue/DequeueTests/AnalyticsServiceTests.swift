//
//  AnalyticsServiceTests.swift
//  DequeueTests
//
//  Tests for AnalyticsService — productivity metrics, daily completions,
//  tag/stack breakdowns, hourly productivity, streaks.
//

import Testing
import Foundation
import SwiftData

@testable import Dequeue

// MARK: - Test Helpers

@MainActor
private func makeAnalyticsContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: QueueTask.self, Stack.self, Tag.self, Reminder.self, Arc.self,
        configurations: config
    )
    return container.mainContext
}

@MainActor
private func makeAnalyticsTask(
    title: String,
    status: TaskStatus = .pending,
    priority: Int? = nil,
    dueTime: Date? = nil,
    tags: [String] = [],
    stack: Stack? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    in context: ModelContext
) -> QueueTask {
    let task = QueueTask(
        title: title,
        dueTime: dueTime,
        tags: tags,
        status: status,
        priority: priority,
        createdAt: createdAt,
        updatedAt: updatedAt,
        stack: stack
    )
    context.insert(task)
    try? context.save()
    return task
}

// MARK: - Summary Tests

@Suite("ProductivitySummary")
struct ProductivitySummaryTests {
    @Test("Completion rate calculation")
    func completionRate() {
        let summary = ProductivitySummary(
            totalTasks: 10,
            completedTasks: 7,
            pendingTasks: 2,
            overdueTasks: 1,
            blockedTasks: 0
        )
        #expect(summary.completionRate == 0.7)
        #expect(summary.completionPercentage == 70)
    }

    @Test("Zero tasks returns zero rate")
    func zeroTasks() {
        let summary = ProductivitySummary(
            totalTasks: 0,
            completedTasks: 0,
            pendingTasks: 0,
            overdueTasks: 0,
            blockedTasks: 0
        )
        #expect(summary.completionRate == 0)
        #expect(summary.completionPercentage == 0)
    }

    @Test("100% completion")
    func fullCompletion() {
        let summary = ProductivitySummary(
            totalTasks: 5,
            completedTasks: 5,
            pendingTasks: 0,
            overdueTasks: 0,
            blockedTasks: 0
        )
        #expect(summary.completionRate == 1.0)
        #expect(summary.completionPercentage == 100)
    }
}

// MARK: - Analytics Service Tests

@Suite("AnalyticsService")
struct AnalyticsServiceTests {
    @Test("Summary counts tasks correctly")
    @MainActor func summaryCountsCorrectly() throws {
        let context = try makeAnalyticsContext()
        _ = makeAnalyticsTask(title: "Active", status: .pending, in: context)
        _ = makeAnalyticsTask(title: "Done", status: .completed, in: context)
        _ = makeAnalyticsTask(title: "Blocked", status: .blocked, in: context)
        _ = makeAnalyticsTask(title: "Also Done", status: .completed, in: context)

        let service = AnalyticsService(modelContext: context)
        let summary = service.getProductivitySummary()

        #expect(summary.totalTasks == 4)
        #expect(summary.completedTasks == 2)
        #expect(summary.pendingTasks == 1)
        #expect(summary.blockedTasks == 1)
    }

    @Test("Overdue tasks detected correctly")
    @MainActor func overdueDetection() throws {
        let context = try makeAnalyticsContext()
        let pastDate = Date().addingTimeInterval(-86400) // Yesterday
        let futureDate = Date().addingTimeInterval(86400) // Tomorrow

        _ = makeAnalyticsTask(title: "Overdue", dueTime: pastDate, in: context)
        _ = makeAnalyticsTask(title: "Future", dueTime: futureDate, in: context)
        _ = makeAnalyticsTask(title: "Done Past", status: .completed, dueTime: pastDate, in: context)

        let service = AnalyticsService(modelContext: context)
        let summary = service.getProductivitySummary()

        #expect(summary.overdueTasks == 1) // Only pending past-due
    }

    @Test("Empty state returns zeros")
    @MainActor func emptyState() throws {
        let context = try makeAnalyticsContext()
        let service = AnalyticsService(modelContext: context)
        let summary = service.getProductivitySummary()

        #expect(summary.totalTasks == 0)
        #expect(summary.completionRate == 0)
    }

    @Test("Daily completions returns correct count")
    @MainActor func dailyCompletions() throws {
        let context = try makeAnalyticsContext()
        let now = Date()
        _ = makeAnalyticsTask(title: "Done Today", status: .completed, updatedAt: now, in: context)

        let service = AnalyticsService(modelContext: context)
        let data = service.getDailyCompletions(days: 7)

        #expect(data.count == 7)
        // Last entry (today) should have 1 completion
        #expect(data.last?.completed == 1)
    }

    @Test("Daily completions has day labels")
    @MainActor func dailyLabels() throws {
        let context = try makeAnalyticsContext()
        let service = AnalyticsService(modelContext: context)
        let data = service.getDailyCompletions(days: 3)

        #expect(data.count == 3)
        for day in data {
            #expect(!day.dayLabel.isEmpty)
        }
    }

    @Test("Tag analytics breaks down by tag")
    @MainActor func tagBreakdown() throws {
        let context = try makeAnalyticsContext()
        _ = makeAnalyticsTask(title: "Work1", tags: ["work"], in: context)
        _ = makeAnalyticsTask(title: "Work2", status: .completed, tags: ["work"], in: context)
        _ = makeAnalyticsTask(title: "Personal", tags: ["personal"], in: context)

        let service = AnalyticsService(modelContext: context)
        let tags = service.getTagAnalytics()

        #expect(tags.count == 2)
        let workTag = tags.first { $0.tag == "work" }
        #expect(workTag?.totalTasks == 2)
        #expect(workTag?.completedTasks == 1)
    }

    @Test("Stack analytics breaks down by stack")
    @MainActor func stackBreakdown() throws {
        let context = try makeAnalyticsContext()
        let stack1 = Stack(title: "Inbox")
        let stack2 = Stack(title: "Projects")
        context.insert(stack1)
        context.insert(stack2)

        _ = makeAnalyticsTask(title: "T1", status: .completed, stack: stack1, in: context)
        _ = makeAnalyticsTask(title: "T2", stack: stack1, in: context)
        _ = makeAnalyticsTask(title: "T3", status: .completed, stack: stack2, in: context)

        let service = AnalyticsService(modelContext: context)
        let stacks = service.getStackAnalytics()

        #expect(stacks.count == 2)
        let inbox = stacks.first { $0.stackTitle == "Inbox" }
        #expect(inbox?.totalTasks == 2)
        #expect(inbox?.completedTasks == 1)
    }

    @Test("Hourly productivity returns 24 hours")
    @MainActor func hourlyProductivity() throws {
        let context = try makeAnalyticsContext()
        _ = makeAnalyticsTask(title: "Done", status: .completed, in: context)

        let service = AnalyticsService(modelContext: context)
        let hourly = service.getHourlyProductivity()

        #expect(hourly.count == 24)
        // At least one hour should have completions
        let totalCompletions = hourly.reduce(0) { $0 + $1.completions }
        #expect(totalCompletions >= 1)
    }

    @Test("Hourly has labels")
    @MainActor func hourlyLabels() throws {
        let context = try makeAnalyticsContext()
        let service = AnalyticsService(modelContext: context)
        let hourly = service.getHourlyProductivity()

        for hour in hourly {
            #expect(!hour.label.isEmpty)
        }
    }

    @Test("Average time to complete works")
    @MainActor func avgTimeToComplete() throws {
        let context = try makeAnalyticsContext()
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86400)
        _ = makeAnalyticsTask(
            title: "Done",
            status: .completed,
            createdAt: twoDaysAgo,
            updatedAt: Date(),
            in: context
        )

        let service = AnalyticsService(modelContext: context)
        let avg = service.averageTimeToComplete()

        #expect(avg != nil)
        #expect(avg! >= 1.5) // ~2 days
    }

    @Test("Average time to complete nil when no completed tasks")
    @MainActor func avgTimeNilWhenNoCompleted() throws {
        let context = try makeAnalyticsContext()
        _ = makeAnalyticsTask(title: "Pending", in: context)

        let service = AnalyticsService(modelContext: context)
        let avg = service.averageTimeToComplete()

        #expect(avg == nil)
    }

    @Test("Streak counts consecutive days")
    @MainActor func currentStreak() throws {
        let context = try makeAnalyticsContext()
        let today = Date()

        _ = makeAnalyticsTask(
            title: "Done Today",
            status: .completed,
            updatedAt: today,
            in: context
        )

        let service = AnalyticsService(modelContext: context)
        let streak = service.getCurrentStreak()

        #expect(streak >= 1)
    }

    @Test("Streak is 0 with no completed tasks")
    @MainActor func emptyStreak() throws {
        let context = try makeAnalyticsContext()
        let service = AnalyticsService(modelContext: context)
        let streak = service.getCurrentStreak()

        #expect(streak == 0)
    }

    @Test("Excludes deleted tasks from analytics")
    @MainActor func excludesDeleted() throws {
        let context = try makeAnalyticsContext()
        let task = makeAnalyticsTask(title: "Deleted", status: .completed, in: context)
        task.isDeleted = true
        try context.save()

        let service = AnalyticsService(modelContext: context)
        let summary = service.getProductivitySummary()

        #expect(summary.totalTasks == 0)
    }
}

// MARK: - Model Tests

@Suite("Analytics Models")
struct AnalyticsModelTests {
    @Test("DailyCompletionData has correct dayLabel")
    func dailyDataLabel() {
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 16))!
        let data = DailyCompletionData(date: monday, completed: 5, created: 3)
        #expect(!data.dayLabel.isEmpty)
    }

    @Test("TagAnalytics completion rate")
    func tagCompletionRate() {
        let tag = TagAnalytics(tag: "work", totalTasks: 10, completedTasks: 7)
        #expect(tag.completionRate == 0.7)
    }

    @Test("StackAnalytics completion rate")
    func stackCompletionRate() {
        let stack = StackAnalytics(
            stackId: "s1",
            stackTitle: "Inbox",
            totalTasks: 5,
            completedTasks: 3,
            avgCompletionDays: 2.5
        )
        #expect(stack.completionRate == 0.6)
    }

    @Test("HourlyProductivity labels")
    func hourlyLabels() {
        #expect(HourlyProductivity(hour: 0, completions: 0).label == "12AM")
        #expect(HourlyProductivity(hour: 9, completions: 0).label == "9AM")
        #expect(HourlyProductivity(hour: 12, completions: 0).label == "12PM")
        #expect(HourlyProductivity(hour: 17, completions: 0).label == "5PM")
    }
}
