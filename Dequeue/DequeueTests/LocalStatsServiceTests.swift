//
//  LocalStatsServiceTests.swift
//  DequeueTests
//
//  Tests for LocalStatsService - computes stats from local SwiftData store
//

import Testing
import Foundation
import SwiftData
@testable import Dequeue

@Suite("LocalStatsService", .serialized)
@MainActor
struct LocalStatsServiceTests {

    // MARK: - Helpers

    private func makeTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Arc.self, Stack.self, QueueTask.self, Reminder.self,
            Event.self, Attachment.self, Device.self, Tag.self, SyncConflict.self,
            configurations: config
        )
    }

    private func makeService(container: ModelContainer) -> LocalStatsService {
        LocalStatsService(modelContext: container.mainContext)
    }

    // MARK: - Empty Store

    @Test("Empty store returns all zeros")
    func emptyStoreReturnsZeros() throws {
        let container = try makeTestContainer()
        let service = makeService(container: container)

        let stats = try service.getStats()

        #expect(stats.tasks.total == 0)
        #expect(stats.tasks.active == 0)
        #expect(stats.tasks.completed == 0)
        #expect(stats.tasks.overdue == 0)
        #expect(stats.tasks.completedToday == 0)
        #expect(stats.tasks.completedThisWeek == 0)
        #expect(stats.tasks.createdToday == 0)
        #expect(stats.tasks.createdThisWeek == 0)
        #expect(stats.tasks.completionRate == 0.0)

        #expect(stats.priority.none == 0)
        #expect(stats.priority.low == 0)
        #expect(stats.priority.medium == 0)
        #expect(stats.priority.high == 0)
        #expect(stats.priority.total == 0)

        #expect(stats.stacks.total == 0)
        #expect(stats.stacks.active == 0)
        #expect(stats.stacks.totalArcs == 0)

        #expect(stats.completionStreak == 0)
    }

    // MARK: - Task Stats

    @Test("Counts total non-deleted tasks")
    func countsTotalTasks() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        ctx.insert(QueueTask(title: "Task 1", status: .pending))
        ctx.insert(QueueTask(title: "Task 2", status: .completed))
        ctx.insert(QueueTask(title: "Task 3", status: .blocked))

        let deleted = QueueTask(title: "Deleted", status: .pending)
        deleted.isDeleted = true
        ctx.insert(deleted)

        try ctx.save()

        let service = makeService(container: container)
        let stats = try service.getStats()

        #expect(stats.tasks.total == 3)
    }

    @Test("Excludes recurrence templates from stats")
    func excludesRecurrenceTemplates() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        ctx.insert(QueueTask(title: "Real task", status: .pending))

        let template = QueueTask(title: "Template task", status: .pending)
        template.isRecurrenceTemplate = true
        ctx.insert(template)

        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.tasks.total == 1) // Only real task counted
    }

    @Test("Counts active tasks (pending + blocked)")
    func countsActiveTasks() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        ctx.insert(QueueTask(title: "Pending", status: .pending))
        ctx.insert(QueueTask(title: "Blocked", status: .blocked))
        ctx.insert(QueueTask(title: "Completed", status: .completed))
        ctx.insert(QueueTask(title: "Closed", status: .closed))
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.tasks.active == 2)
    }

    @Test("Counts completed tasks")
    func countsCompletedTasks() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        ctx.insert(QueueTask(title: "Done 1", status: .completed))
        ctx.insert(QueueTask(title: "Done 2", status: .completed))
        ctx.insert(QueueTask(title: "Not done", status: .pending))
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.tasks.completed == 2)
        #expect(stats.tasks.completionRate == 2.0 / 3.0)
    }

    @Test("Counts overdue tasks")
    func countsOverdueTasks() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let overdue = QueueTask(title: "Overdue", dueTime: Date().addingTimeInterval(-3600), status: .pending)
        ctx.insert(overdue)

        let notOverdue = QueueTask(title: "Future", dueTime: Date().addingTimeInterval(3600), status: .pending)
        ctx.insert(notOverdue)

        let completedOverdue = QueueTask(
            title: "Completed Overdue",
            dueTime: Date().addingTimeInterval(-3600),
            status: .completed
        )
        ctx.insert(completedOverdue)

        let noDueDate = QueueTask(title: "No Due", status: .pending)
        ctx.insert(noDueDate)
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.tasks.overdue == 1) // Only pending with past due date
    }

    @Test("Blocked tasks with past due date count as overdue")
    func blockedOverdueTasksCounted() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let blockedOverdue = QueueTask(
            title: "Blocked Overdue",
            dueTime: Date().addingTimeInterval(-3600),
            status: .blocked
        )
        ctx.insert(blockedOverdue)

        let pendingOverdue = QueueTask(
            title: "Pending Overdue",
            dueTime: Date().addingTimeInterval(-3600),
            status: .pending
        )
        ctx.insert(pendingOverdue)
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        // Both blocked and pending tasks with past due date count as overdue
        #expect(stats.tasks.overdue == 2)
    }

    @Test("Counts tasks created today")
    func countsCreatedToday() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let calendar = Calendar.current

        // Created now (today)
        ctx.insert(QueueTask(title: "Today", status: .pending))

        // Created yesterday — use calendar arithmetic to avoid midnight boundary issues
        let yesterday = QueueTask(title: "Yesterday", status: .pending)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))! // Safe: subtracting 1 day from valid date
        yesterday.createdAt = yesterdayDate
        ctx.insert(yesterday)
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.tasks.createdToday == 1)
    }

    @Test("Counts tasks completed today using explicit completedAt only")
    func countsCompletedToday() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        // Completed today with completedAt set
        let completedToday = QueueTask(title: "Done today", status: .completed)
        completedToday.completedAt = Date()
        ctx.insert(completedToday)

        // Completed yesterday — use calendar arithmetic to avoid midnight boundary issues
        let calendar = Calendar.current
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))! // Safe: subtracting 1 day from valid date
        let completedYesterday = QueueTask(title: "Done yesterday", status: .completed)
        completedYesterday.completedAt = yesterdayDate
        completedYesterday.updatedAt = yesterdayDate
        ctx.insert(completedYesterday)

        // Completed but no completedAt (legacy) — should NOT count in time-based stats
        let legacyCompleted = QueueTask(title: "Legacy completed", status: .completed)
        legacyCompleted.completedAt = nil
        ctx.insert(legacyCompleted)

        // Pending (not completed)
        ctx.insert(QueueTask(title: "Pending", status: .pending))
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.tasks.completedToday == 1)
        #expect(stats.tasks.completed == 3) // Total completed still counts all
    }

    // MARK: - Priority Breakdown

    @Test("Breaks down active tasks by priority")
    func priorityBreakdown() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        ctx.insert(QueueTask(title: "No priority", status: .pending, priority: nil))
        ctx.insert(QueueTask(title: "Low", status: .pending, priority: 1))
        ctx.insert(QueueTask(title: "Medium", status: .pending, priority: 2))
        ctx.insert(QueueTask(title: "High 1", status: .pending, priority: 3))
        ctx.insert(QueueTask(title: "High 2", status: .blocked, priority: 3))

        // Completed tasks should NOT be counted in priority breakdown
        ctx.insert(QueueTask(title: "Done High", status: .completed, priority: 3))
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.priority.none == 1)
        #expect(stats.priority.low == 1)
        #expect(stats.priority.medium == 1)
        #expect(stats.priority.high == 2)
        #expect(stats.priority.total == 5)
    }

    // MARK: - Stack Stats

    @Test("Counts stacks and arcs")
    func countsStacksAndArcs() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        let stack1 = Stack(title: "Active Stack")
        stack1.statusRawValue = StackStatus.active.rawValue
        ctx.insert(stack1)

        let stack2 = Stack(title: "Completed Stack")
        stack2.statusRawValue = StackStatus.completed.rawValue
        ctx.insert(stack2)

        let draft = Stack(title: "Draft Stack")
        draft.isDraft = true
        ctx.insert(draft)

        let deletedStack = Stack(title: "Deleted Stack")
        deletedStack.isDeleted = true
        ctx.insert(deletedStack)

        ctx.insert(Arc(title: "Arc 1"))
        ctx.insert(Arc(title: "Arc 2"))

        let deletedArc = Arc(title: "Deleted Arc")
        deletedArc.isDeleted = true
        ctx.insert(deletedArc)
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.stacks.total == 2) // excludes drafts and deleted
        #expect(stats.stacks.active == 1) // only active status
        #expect(stats.stacks.totalArcs == 2) // excludes deleted
    }

    // MARK: - Completion Streak

    @Test("Calculates streak from consecutive completed days")
    func calculatesStreak() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let calendar = Calendar.current

        // Complete a task today
        let today = QueueTask(title: "Today", status: .completed)
        today.completedAt = Date()
        ctx.insert(today)

        // Complete a task yesterday
        let yesterday = QueueTask(title: "Yesterday", status: .completed)
        yesterday.completedAt = calendar.date(byAdding: .day, value: -1, to: Date())! // Safe: adding days to a valid Date always succeeds
        yesterday.updatedAt = yesterday.completedAt! // Safe: set on preceding line
        ctx.insert(yesterday)

        // Complete a task 2 days ago
        let twoDaysAgo = QueueTask(title: "Two days ago", status: .completed)
        twoDaysAgo.completedAt = calendar.date(byAdding: .day, value: -2, to: Date())! // Safe: adding days to a valid Date always succeeds
        twoDaysAgo.updatedAt = twoDaysAgo.completedAt! // Safe: set on preceding line
        ctx.insert(twoDaysAgo)

        // Gap on day 3 (no completion)

        // Complete a task 4 days ago (shouldn't count due to gap)
        let fourDaysAgo = QueueTask(title: "Four days ago", status: .completed)
        fourDaysAgo.completedAt = calendar.date(byAdding: .day, value: -4, to: Date())! // Safe: adding days to a valid Date always succeeds
        fourDaysAgo.updatedAt = fourDaysAgo.completedAt! // Safe: set on preceding line
        ctx.insert(fourDaysAgo)
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.completionStreak == 3) // today + yesterday + 2 days ago
    }

    @Test("Streak starts from yesterday if no completions today")
    func streakStartsFromYesterday() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let calendar = Calendar.current

        // No completions today, but yesterday and day before
        let yesterday = QueueTask(title: "Yesterday", status: .completed)
        yesterday.completedAt = calendar.date(byAdding: .day, value: -1, to: Date())! // Safe: adding days to a valid Date always succeeds
        yesterday.updatedAt = yesterday.completedAt! // Safe: set on preceding line
        ctx.insert(yesterday)

        let twoDaysAgo = QueueTask(title: "Two days ago", status: .completed)
        twoDaysAgo.completedAt = calendar.date(byAdding: .day, value: -2, to: Date())! // Safe: adding days to a valid Date always succeeds
        twoDaysAgo.updatedAt = twoDaysAgo.completedAt! // Safe: set on preceding line
        ctx.insert(twoDaysAgo)
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.completionStreak == 2)
    }

    @Test("Zero streak when no recent completions")
    func zeroStreak() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let calendar = Calendar.current

        // Only completions from a week ago (with gap)
        let weekAgo = QueueTask(title: "Old", status: .completed)
        weekAgo.completedAt = calendar.date(byAdding: .day, value: -7, to: Date())! // Safe: adding days to a valid Date always succeeds
        weekAgo.updatedAt = weekAgo.completedAt! // Safe: set on preceding line
        ctx.insert(weekAgo)
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.completionStreak == 0)
    }

    // MARK: - Integration

    @Test("Complete stats response with mixed data")
    func completeStatsWithMixedData() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext

        // Create a stack with tasks
        let stack = Stack(title: "My Stack")
        stack.statusRawValue = StackStatus.active.rawValue
        ctx.insert(stack)

        let task1 = QueueTask(title: "Pending task", status: .pending, priority: 2)
        task1.stack = stack
        ctx.insert(task1)

        let task2 = QueueTask(title: "Completed task", status: .completed)
        task2.completedAt = Date()
        task2.stack = stack
        ctx.insert(task2)

        ctx.insert(Arc(title: "An Arc"))
        try ctx.save()

        let stats = try makeService(container: container).getStats()

        #expect(stats.tasks.total == 2)
        #expect(stats.tasks.active == 1)
        #expect(stats.tasks.completed == 1)
        #expect(stats.tasks.completionRate == 0.5)
        #expect(stats.stacks.total == 1)
        #expect(stats.stacks.active == 1)
        #expect(stats.stacks.totalArcs == 1)
        #expect(stats.priority.medium == 1)
    }
}
