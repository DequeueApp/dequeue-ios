//
//  WidgetDataServiceTests.swift
//  DequeueTests
//
//  Tests for WidgetDataService — verifies widget data is correctly
//  written to App Group UserDefaults from SwiftData models.
//  DEQ-120, DEQ-121
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container with all required models for widget data service tests
private func makeWidgetTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Device.self,
        SyncConflict.self,
        Attachment.self,
        Tag.self,
        Arc.self,
        configurations: config
    )
}

/// Reads widget data directly from App Group UserDefaults for test verification
@MainActor
private func readWidgetDefaults<T: Decodable>(key: String, as type: T.Type) -> T? {
    guard let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName),
          let data = defaults.data(forKey: key) else {
        return nil
    }
    return try? JSONDecoder.widgetDecoder.decode(type, from: data)
}

/// Cleans up all widget keys from UserDefaults
@MainActor
private func cleanupWidgetDefaults() {
    guard let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName) else { return }
    defaults.removeObject(forKey: AppGroupConfig.activeStackKey)
    defaults.removeObject(forKey: AppGroupConfig.upNextKey)
    defaults.removeObject(forKey: AppGroupConfig.statsKey)
    defaults.removeObject(forKey: AppGroupConfig.lastUpdateKey)
}

// MARK: - Active Stack Widget Tests

@Suite("WidgetDataService Active Stack Tests", .serialized)
@MainActor
struct WidgetDataServiceActiveStackTests {
    @Test("updateAllWidgets writes active stack data when active stack exists")
    func writesActiveStackData() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        // Create an active stack with tasks
        let stack = Stack(
            id: "stack-active-1",
            title: "My Active Stack",
            status: .active,
            priority: 2,
            isActive: true
        )
        context.insert(stack)

        let task1 = QueueTask(
            id: "task-1",
            title: "First Task",
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(task1)

        let task2 = QueueTask(
            id: "task-2",
            title: "Second Task",
            status: .pending,
            sortOrder: 1,
            stack: stack
        )
        context.insert(task2)

        let completedTask = QueueTask(
            id: "task-3",
            title: "Done Task",
            status: .completed,
            sortOrder: 2,
            stack: stack
        )
        context.insert(completedTask)

        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let activeData = readWidgetDefaults(
            key: AppGroupConfig.activeStackKey,
            as: WidgetActiveStackData.self
        )

        #expect(activeData != nil)
        #expect(activeData?.stackTitle == "My Active Stack")
        #expect(activeData?.stackId == "stack-active-1")
        #expect(activeData?.activeTaskTitle == "First Task")
        #expect(activeData?.activeTaskId == "task-1")
        #expect(activeData?.pendingTaskCount == 2)
        #expect(activeData?.totalTaskCount == 3)
        #expect(activeData?.priority == 2)
    }

    @Test("updateAllWidgets clears active stack data when no active stack")
    func clearsActiveStackDataWhenNone() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        // Pre-populate with some data to ensure it gets cleared
        if let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName) {
            let dummy = WidgetActiveStackData(
                stackTitle: "Old",
                stackId: "old",
                activeTaskTitle: nil,
                activeTaskId: nil,
                pendingTaskCount: 0,
                totalTaskCount: 0,
                dueDate: nil,
                priority: nil,
                tags: []
            )
            if let encoded = try? JSONEncoder.widgetEncoder.encode(dummy) {
                defaults.set(encoded, forKey: AppGroupConfig.activeStackKey)
            }
        }

        // Create a stack that is NOT active
        let stack = Stack(
            id: "stack-inactive",
            title: "Inactive Stack",
            status: .active,
            isActive: false
        )
        context.insert(stack)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let activeData = readWidgetDefaults(
            key: AppGroupConfig.activeStackKey,
            as: WidgetActiveStackData.self
        )
        #expect(activeData == nil)
    }

    @Test("updateAllWidgets includes stack due date")
    func includesStackDueDate() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let dueDate = Date(timeIntervalSince1970: 1_900_000_000)
        let stack = Stack(
            id: "stack-due",
            title: "Due Stack",
            dueTime: dueDate,
            status: .active,
            isActive: true
        )
        context.insert(stack)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let activeData = readWidgetDefaults(
            key: AppGroupConfig.activeStackKey,
            as: WidgetActiveStackData.self
        )

        #expect(activeData != nil)
        #expect(activeData?.dueDate != nil)
        if let decoded = activeData?.dueDate {
            #expect(abs(decoded.timeIntervalSince(dueDate)) < 1.0)
        }
    }
}

// MARK: - Up Next Widget Tests

@Suite("WidgetDataService Up Next Tests", .serialized)
@MainActor
struct WidgetDataServiceUpNextTests {
    @Test("updateAllWidgets writes up next with tasks that have due dates")
    func writesUpNextWithDueDates() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-upnext", title: "Up Next Stack")
        context.insert(stack)

        let futureDue = Date(timeIntervalSinceNow: 3600) // 1 hour from now
        let task = QueueTask(
            id: "task-due-1",
            title: "Due Soon",
            dueTime: futureDue,
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(task)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let upNextData = readWidgetDefaults(
            key: AppGroupConfig.upNextKey,
            as: WidgetUpNextData.self
        )

        #expect(upNextData != nil)
        #expect(upNextData?.upcomingTasks.count == 1)
        #expect(upNextData?.upcomingTasks.first?.title == "Due Soon")
        #expect(upNextData?.upcomingTasks.first?.isOverdue == false)
        #expect(upNextData?.overdueCount == 0)
    }

    @Test("updateAllWidgets marks overdue tasks correctly")
    func marksOverdueTasksCorrectly() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-overdue", title: "Overdue Stack")
        context.insert(stack)

        let pastDue = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let overdueTask = QueueTask(
            id: "task-overdue-1",
            title: "Overdue Task",
            dueTime: pastDue,
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(overdueTask)

        let futureDue = Date(timeIntervalSinceNow: 7200) // 2 hours from now
        let futureTask = QueueTask(
            id: "task-future-1",
            title: "Future Task",
            dueTime: futureDue,
            status: .pending,
            sortOrder: 1,
            stack: stack
        )
        context.insert(futureTask)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let upNextData = readWidgetDefaults(
            key: AppGroupConfig.upNextKey,
            as: WidgetUpNextData.self
        )

        #expect(upNextData != nil)
        #expect(upNextData?.upcomingTasks.count == 2)
        #expect(upNextData?.overdueCount == 1)

        // Find the overdue task
        let overdue = upNextData?.upcomingTasks.first { $0.id == "task-overdue-1" }
        #expect(overdue?.isOverdue == true)

        // Find the future task
        let future = upNextData?.upcomingTasks.first { $0.id == "task-future-1" }
        #expect(future?.isOverdue == false)
    }

    @Test("updateAllWidgets limits up next to 10 tasks")
    func limitsUpNextTo10Tasks() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-many", title: "Many Tasks Stack")
        context.insert(stack)

        // Create 15 tasks with due dates
        for i in 0..<15 {
            let dueDate = Date(timeIntervalSinceNow: Double(i + 1) * 3600)
            let task = QueueTask(
                id: "task-limit-\(i)",
                title: "Task \(i)",
                dueTime: dueDate,
                status: .pending,
                sortOrder: i,
                stack: stack
            )
            context.insert(task)
        }
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let upNextData = readWidgetDefaults(
            key: AppGroupConfig.upNextKey,
            as: WidgetUpNextData.self
        )

        #expect(upNextData != nil)
        #expect(upNextData!.upcomingTasks.count <= 10)
    }

    @Test("updateAllWidgets excludes tasks without due dates from up next")
    func excludesTasksWithoutDueDates() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-nodue", title: "No Due Stack")
        context.insert(stack)

        // Task without due date
        let noDueTask = QueueTask(
            id: "task-nodue",
            title: "No Due Date",
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(noDueTask)

        // Task with due date
        let dueDateTask = QueueTask(
            id: "task-withdue",
            title: "Has Due Date",
            dueTime: Date(timeIntervalSinceNow: 3600),
            status: .pending,
            sortOrder: 1,
            stack: stack
        )
        context.insert(dueDateTask)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let upNextData = readWidgetDefaults(
            key: AppGroupConfig.upNextKey,
            as: WidgetUpNextData.self
        )

        #expect(upNextData != nil)
        #expect(upNextData?.upcomingTasks.count == 1)
        #expect(upNextData?.upcomingTasks.first?.title == "Has Due Date")
    }

    @Test("updateAllWidgets excludes completed tasks from up next")
    func excludesCompletedTasks() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-completed", title: "Completed Stack")
        context.insert(stack)

        let completedTask = QueueTask(
            id: "task-completed",
            title: "Already Done",
            dueTime: Date(timeIntervalSinceNow: 3600),
            status: .completed,
            sortOrder: 0,
            stack: stack
        )
        context.insert(completedTask)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let upNextData = readWidgetDefaults(
            key: AppGroupConfig.upNextKey,
            as: WidgetUpNextData.self
        )

        #expect(upNextData != nil)
        #expect(upNextData?.upcomingTasks.isEmpty == true)
    }

    @Test("updateAllWidgets includes correct stack info in task items")
    func includesStackInfoInTaskItems() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-info", title: "Info Stack")
        context.insert(stack)

        let task = QueueTask(
            id: "task-info",
            title: "Task With Stack Info",
            dueTime: Date(timeIntervalSinceNow: 3600),
            status: .pending,
            priority: 3,
            sortOrder: 0,
            stack: stack
        )
        context.insert(task)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let upNextData = readWidgetDefaults(
            key: AppGroupConfig.upNextKey,
            as: WidgetUpNextData.self
        )

        #expect(upNextData?.upcomingTasks.first?.stackTitle == "Info Stack")
        #expect(upNextData?.upcomingTasks.first?.stackId == "stack-info")
        #expect(upNextData?.upcomingTasks.first?.priority == 3)
    }
}

// MARK: - Stats Widget Tests

@Suite("WidgetDataService Stats Tests", .serialized)
@MainActor
struct WidgetDataServiceStatsTests {
    @Test("updateAllWidgets counts completed today correctly")
    func countsCompletedToday() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-stats", title: "Stats Stack")
        context.insert(stack)

        // Task completed today (updatedAt is today)
        let todayTask1 = QueueTask(
            id: "task-today-1",
            title: "Done Today 1",
            status: .completed,
            sortOrder: 0,
            updatedAt: Date(), // now = today
            stack: stack
        )
        context.insert(todayTask1)

        let todayTask2 = QueueTask(
            id: "task-today-2",
            title: "Done Today 2",
            status: .completed,
            sortOrder: 1,
            updatedAt: Date(),
            stack: stack
        )
        context.insert(todayTask2)

        // Task completed yesterday (should not count)
        let yesterdayTask = QueueTask(
            id: "task-yesterday",
            title: "Done Yesterday",
            status: .completed,
            sortOrder: 2,
            updatedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            stack: stack
        )
        context.insert(yesterdayTask)

        // Pending task (should not count as completed)
        let pendingTask = QueueTask(
            id: "task-pending-stats",
            title: "Still Pending",
            status: .pending,
            sortOrder: 3,
            stack: stack
        )
        context.insert(pendingTask)

        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let statsData = readWidgetDefaults(
            key: AppGroupConfig.statsKey,
            as: WidgetStatsData.self
        )

        #expect(statsData != nil)
        #expect(statsData?.completedToday == 2)
    }

    @Test("updateAllWidgets calculates completion rate")
    func calculatesCompletionRate() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-rate", title: "Rate Stack")
        context.insert(stack)

        // 3 completed out of 4 total = 0.75
        for i in 0..<3 {
            let task = QueueTask(
                id: "task-rate-c-\(i)",
                title: "Completed \(i)",
                status: .completed,
                sortOrder: i,
                stack: stack
            )
            context.insert(task)
        }

        let pendingTask = QueueTask(
            id: "task-rate-p",
            title: "Pending",
            status: .pending,
            sortOrder: 3,
            stack: stack
        )
        context.insert(pendingTask)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let statsData = readWidgetDefaults(
            key: AppGroupConfig.statsKey,
            as: WidgetStatsData.self
        )

        #expect(statsData != nil)
        if let rate = statsData?.completionRate {
            #expect(abs(rate - 0.75) < 0.01)
        }
    }

    @Test("updateAllWidgets calculates zero completion rate with no tasks")
    func zeroCompletionRateWithNoTasks() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        // No tasks at all
        WidgetDataService.updateAllWidgets(context: context)

        let statsData = readWidgetDefaults(
            key: AppGroupConfig.statsKey,
            as: WidgetStatsData.self
        )

        #expect(statsData != nil)
        #expect(statsData?.completionRate == 0.0)
        #expect(statsData?.completedToday == 0)
        #expect(statsData?.pendingTotal == 0)
    }

    @Test("updateAllWidgets counts overdue tasks")
    func countsOverdueTasks() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-overdue-stats", title: "Overdue Stats")
        context.insert(stack)

        // 2 overdue tasks
        let overdue1 = QueueTask(
            id: "task-od-1",
            title: "Overdue 1",
            dueTime: Date(timeIntervalSinceNow: -7200),
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(overdue1)

        let overdue2 = QueueTask(
            id: "task-od-2",
            title: "Overdue 2",
            dueTime: Date(timeIntervalSinceNow: -3600),
            status: .pending,
            sortOrder: 1,
            stack: stack
        )
        context.insert(overdue2)

        // 1 future task (not overdue)
        let future = QueueTask(
            id: "task-future-stats",
            title: "Future",
            dueTime: Date(timeIntervalSinceNow: 86400),
            status: .pending,
            sortOrder: 2,
            stack: stack
        )
        context.insert(future)

        // 1 pending task without due date (not overdue)
        let noDue = QueueTask(
            id: "task-nodue-stats",
            title: "No Due",
            status: .pending,
            sortOrder: 3,
            stack: stack
        )
        context.insert(noDue)

        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let statsData = readWidgetDefaults(
            key: AppGroupConfig.statsKey,
            as: WidgetStatsData.self
        )

        #expect(statsData != nil)
        #expect(statsData?.overdueCount == 2)
        #expect(statsData?.pendingTotal == 4)
    }

    @Test("updateAllWidgets counts active stacks")
    func countsActiveStacks() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        // 2 active stacks
        let active1 = Stack(id: "stack-a1", title: "Active 1", status: .active)
        context.insert(active1)

        let active2 = Stack(id: "stack-a2", title: "Active 2", status: .active)
        context.insert(active2)

        // 1 completed stack (should not count)
        let completed = Stack(id: "stack-c1", title: "Completed", status: .completed)
        context.insert(completed)

        // 1 archived stack (should not count)
        let archived = Stack(id: "stack-ar1", title: "Archived", status: .archived)
        context.insert(archived)

        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let statsData = readWidgetDefaults(
            key: AppGroupConfig.statsKey,
            as: WidgetStatsData.self
        )

        #expect(statsData != nil)
        #expect(statsData?.activeStackCount == 2)
    }

    @Test("updateAllWidgets excludes deleted tasks from stats")
    func excludesDeletedTasksFromStats() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let stack = Stack(id: "stack-del-stats", title: "Deleted Stats")
        context.insert(stack)

        // Non-deleted pending task
        let pendingTask = QueueTask(
            id: "task-alive",
            title: "Alive",
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(pendingTask)

        // Deleted pending task (should not count)
        let deletedTask = QueueTask(
            id: "task-dead",
            title: "Deleted",
            status: .pending,
            sortOrder: 1,
            isDeleted: true,
            stack: stack
        )
        context.insert(deletedTask)

        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let statsData = readWidgetDefaults(
            key: AppGroupConfig.statsKey,
            as: WidgetStatsData.self
        )

        #expect(statsData != nil)
        #expect(statsData?.pendingTotal == 1)
    }
}

// MARK: - Last Update Timestamp Tests

@Suite("WidgetDataService Timestamp Tests", .serialized)
@MainActor
struct WidgetDataServiceTimestampTests {
    @Test("updateAllWidgets sets lastUpdate timestamp")
    func setsLastUpdateTimestamp() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        let beforeUpdate = Date()

        WidgetDataService.updateAllWidgets(context: context)

        let afterUpdate = Date()

        guard let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName) else {
            // App Group not available in test environment
            return
        }

        let lastUpdate = defaults.object(forKey: AppGroupConfig.lastUpdateKey) as? Date
        #expect(lastUpdate != nil)
        if let ts = lastUpdate {
            #expect(ts >= beforeUpdate)
            #expect(ts <= afterUpdate)
        }
    }

    @Test("updateAllWidgets updates timestamp on each call")
    func updatesTimestampOnEachCall() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        WidgetDataService.updateAllWidgets(context: context)

        guard let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName) else {
            return
        }

        let firstUpdate = defaults.object(forKey: AppGroupConfig.lastUpdateKey) as? Date
        #expect(firstUpdate != nil)

        // Small delay to ensure different timestamp
        Thread.sleep(forTimeInterval: 0.01)

        WidgetDataService.updateAllWidgets(context: context)

        let secondUpdate = defaults.object(forKey: AppGroupConfig.lastUpdateKey) as? Date
        #expect(secondUpdate != nil)

        if let first = firstUpdate, let second = secondUpdate {
            #expect(second >= first)
        }
    }
}

// MARK: - Integration Tests

@Suite("WidgetDataService Integration Tests", .serialized)
@MainActor
struct WidgetDataServiceIntegrationTests {
    @Test("updateAllWidgets populates all three widget data stores")
    func populatesAllWidgetData() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        // Create a realistic scenario
        let stack = Stack(
            id: "stack-integration",
            title: "Integration Stack",
            status: .active,
            priority: 2,
            isActive: true
        )
        context.insert(stack)

        let task1 = QueueTask(
            id: "task-int-1",
            title: "First Task",
            dueTime: Date(timeIntervalSinceNow: 3600),
            status: .pending,
            priority: 3,
            sortOrder: 0,
            stack: stack
        )
        context.insert(task1)

        let task2 = QueueTask(
            id: "task-int-2",
            title: "Second Task",
            status: .completed,
            sortOrder: 1,
            updatedAt: Date(),
            stack: stack
        )
        context.insert(task2)

        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        // Verify active stack
        let activeData = readWidgetDefaults(
            key: AppGroupConfig.activeStackKey,
            as: WidgetActiveStackData.self
        )
        #expect(activeData != nil)
        #expect(activeData?.stackTitle == "Integration Stack")

        // Verify up next
        let upNextData = readWidgetDefaults(
            key: AppGroupConfig.upNextKey,
            as: WidgetUpNextData.self
        )
        #expect(upNextData != nil)
        #expect(upNextData?.upcomingTasks.count == 1)

        // Verify stats
        let statsData = readWidgetDefaults(
            key: AppGroupConfig.statsKey,
            as: WidgetStatsData.self
        )
        #expect(statsData != nil)
        #expect(statsData?.completedToday == 1)
        #expect(statsData?.pendingTotal == 1)
        #expect(statsData?.activeStackCount == 1)

        // Verify timestamp
        guard let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName) else { return }
        let lastUpdate = defaults.object(forKey: AppGroupConfig.lastUpdateKey) as? Date
        #expect(lastUpdate != nil)
    }

    @Test("updateAllWidgets excludes deleted stacks from active stack")
    func excludesDeletedStacksFromActive() throws {
        let container = try makeWidgetTestContainer()
        let context = container.mainContext
        defer { cleanupWidgetDefaults() }

        // Create an active but deleted stack
        let deletedStack = Stack(
            id: "stack-deleted",
            title: "Deleted Stack",
            status: .active,
            isDeleted: true,
            isActive: true
        )
        context.insert(deletedStack)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context)

        let activeData = readWidgetDefaults(
            key: AppGroupConfig.activeStackKey,
            as: WidgetActiveStackData.self
        )
        #expect(activeData == nil)
    }
}
