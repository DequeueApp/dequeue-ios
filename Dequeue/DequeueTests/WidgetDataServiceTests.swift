//
//  WidgetDataServiceTests.swift
//  DequeueTests
//
//  Tests for WidgetDataService — verifies widget data is correctly
//  written to UserDefaults from SwiftData models.
//  Uses per-test unique UserDefaults to guarantee test isolation.
//  DEQ-120, DEQ-121
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container with all required models
@MainActor
private func makeTestContainer() throws -> ModelContainer {
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

/// Creates a unique UserDefaults instance for test isolation
@MainActor
private func makeIsolatedDefaults() -> UserDefaults {
    let suite = "com.dequeue.tests.widgets.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

/// Reads decoded widget data from UserDefaults
@MainActor
private func readDefaults<T: Decodable>(_ defaults: UserDefaults, key: String, as type: T.Type) -> T? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder.widgetDecoder.decode(type, from: data)
}

// MARK: - Active Stack Widget Tests

@Suite("WidgetDataService Active Stack Tests")
@MainActor
struct WidgetDataServiceActiveStackTests {
    @Test("writes active stack data when active stack exists")
    func writesActiveStackData() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(
            id: "stack-active-1", title: "My Active Stack",
            status: .active, priority: 2, isActive: true
        )
        context.insert(stack)

        let task1 = QueueTask(
            id: "task-1", title: "First Task",
            status: .pending, sortOrder: 0, stack: stack
        )
        context.insert(task1)

        let task2 = QueueTask(
            id: "task-2", title: "Second Task",
            status: .pending, sortOrder: 1, stack: stack
        )
        context.insert(task2)

        let completedTask = QueueTask(
            id: "task-3", title: "Done Task",
            status: .completed, sortOrder: 2, stack: stack
        )
        context.insert(completedTask)

        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.activeStackKey, as: WidgetActiveStackData.self)

        #expect(data != nil)
        #expect(data?.stackTitle == "My Active Stack")
        #expect(data?.stackId == "stack-active-1")
        #expect(data?.activeTaskTitle == "First Task")
        #expect(data?.activeTaskId == "task-1")
        #expect(data?.pendingTaskCount == 2)
        #expect(data?.totalTaskCount == 3)
        #expect(data?.priority == 2)
    }

    @Test("clears active stack data when no active stack exists")
    func clearsActiveStackDataWhenNone() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        // Pre-populate with data that should be cleared
        let dummy = WidgetActiveStackData(
            stackTitle: "Old", stackId: "old",
            activeTaskTitle: nil, activeTaskId: nil,
            pendingTaskCount: 0, totalTaskCount: 0,
            dueDate: nil, priority: nil, tags: []
        )
        if let encoded = try? JSONEncoder.widgetEncoder.encode(dummy) {
            defaults.set(encoded, forKey: AppGroupConfig.activeStackKey)
        }

        // Create an inactive stack only
        let stack = Stack(id: "stack-inactive", title: "Inactive", status: .active, isActive: false)
        context.insert(stack)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.activeStackKey, as: WidgetActiveStackData.self)
        #expect(data == nil)
    }

    @Test("includes stack due date")
    func includesStackDueDate() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let dueDate = Date(timeIntervalSince1970: 1_900_000_000)
        let stack = Stack(
            id: "stack-due", title: "Due Stack",
            dueTime: dueDate, status: .active, isActive: true
        )
        context.insert(stack)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.activeStackKey, as: WidgetActiveStackData.self)
        #expect(data != nil)
        #expect(data?.dueDate != nil)
        if let decoded = data?.dueDate {
            #expect(abs(decoded.timeIntervalSince(dueDate)) < 1.0)
        }
    }

    @Test("excludes deleted active stacks")
    func excludesDeletedStacks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let deletedStack = Stack(
            id: "stack-deleted", title: "Deleted",
            status: .active, isDeleted: true, isActive: true
        )
        context.insert(deletedStack)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.activeStackKey, as: WidgetActiveStackData.self)
        #expect(data == nil)
    }
}

// MARK: - Up Next Widget Tests

@Suite("WidgetDataService Up Next Tests")
@MainActor
struct WidgetDataServiceUpNextTests {
    @Test("writes up next with tasks that have due dates")
    func writesUpNextWithDueDates() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-upnext", title: "Up Next Stack")
        context.insert(stack)

        let futureDue = Date(timeIntervalSinceNow: 3600)
        let task = QueueTask(
            id: "task-due-1", title: "Due Soon",
            dueTime: futureDue, status: .pending, sortOrder: 0, stack: stack
        )
        context.insert(task)
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.upNextKey, as: WidgetUpNextData.self)
        #expect(data != nil)
        #expect(data?.upcomingTasks.count == 1)
        #expect(data?.upcomingTasks.first?.title == "Due Soon")
        #expect(data?.upcomingTasks.first?.isOverdue == false)
        #expect(data?.overdueCount == 0)
    }

    @Test("marks overdue tasks correctly")
    func marksOverdueTasksCorrectly() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-overdue", title: "Overdue Stack")
        context.insert(stack)

        context.insert(QueueTask(
            id: "task-overdue-1", title: "Overdue Task",
            dueTime: Date(timeIntervalSinceNow: -3600),
            status: .pending, sortOrder: 0, stack: stack
        ))
        context.insert(QueueTask(
            id: "task-future-1", title: "Future Task",
            dueTime: Date(timeIntervalSinceNow: 7200),
            status: .pending, sortOrder: 1, stack: stack
        ))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.upNextKey, as: WidgetUpNextData.self)
        #expect(data != nil)
        #expect(data?.upcomingTasks.count == 2)
        #expect(data?.overdueCount == 1)

        let overdue = data?.upcomingTasks.first { $0.id == "task-overdue-1" }
        #expect(overdue?.isOverdue == true)
    }

    @Test("limits up next to 10 tasks")
    func limitsUpNextTo10Tasks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-many", title: "Many Tasks")
        context.insert(stack)

        for i in 0..<15 {
            context.insert(QueueTask(
                id: "task-limit-\(i)", title: "Task \(i)",
                dueTime: Date(timeIntervalSinceNow: Double(i + 1) * 3600),
                status: .pending, sortOrder: i, stack: stack
            ))
        }
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.upNextKey, as: WidgetUpNextData.self)
        #expect(data != nil)
        #expect(data!.upcomingTasks.count <= 10)
    }

    @Test("excludes tasks without due dates")
    func excludesTasksWithoutDueDates() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-nodue", title: "No Due Stack")
        context.insert(stack)

        context.insert(QueueTask(
            id: "task-nodue", title: "No Due Date",
            status: .pending, sortOrder: 0, stack: stack
        ))
        context.insert(QueueTask(
            id: "task-withdue", title: "Has Due Date",
            dueTime: Date(timeIntervalSinceNow: 3600),
            status: .pending, sortOrder: 1, stack: stack
        ))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.upNextKey, as: WidgetUpNextData.self)
        #expect(data?.upcomingTasks.count == 1)
        #expect(data?.upcomingTasks.first?.title == "Has Due Date")
    }

    @Test("excludes completed tasks")
    func excludesCompletedTasks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-completed", title: "Done Stack")
        context.insert(stack)
        context.insert(QueueTask(
            id: "task-completed", title: "Already Done",
            dueTime: Date(timeIntervalSinceNow: 3600),
            status: .completed, sortOrder: 0, stack: stack
        ))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.upNextKey, as: WidgetUpNextData.self)
        #expect(data?.upcomingTasks.isEmpty == true)
    }

    @Test("includes stack info in task items")
    func includesStackInfoInTaskItems() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-info", title: "Info Stack")
        context.insert(stack)
        context.insert(QueueTask(
            id: "task-info", title: "Task With Stack Info",
            dueTime: Date(timeIntervalSinceNow: 3600),
            status: .pending, priority: 3, sortOrder: 0, stack: stack
        ))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.upNextKey, as: WidgetUpNextData.self)
        #expect(data?.upcomingTasks.first?.stackTitle == "Info Stack")
        #expect(data?.upcomingTasks.first?.stackId == "stack-info")
        #expect(data?.upcomingTasks.first?.priority == 3)
    }
}

// MARK: - Stats Widget Tests

@Suite("WidgetDataService Stats Tests")
@MainActor
struct WidgetDataServiceStatsTests {
    @Test("counts completed today correctly")
    func countsCompletedToday() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-stats", title: "Stats Stack")
        context.insert(stack)

        // 2 completed today
        context.insert(QueueTask(
            id: "task-today-1", title: "Done Today 1",
            status: .completed, sortOrder: 0, updatedAt: Date(), stack: stack
        ))
        context.insert(QueueTask(
            id: "task-today-2", title: "Done Today 2",
            status: .completed, sortOrder: 1, updatedAt: Date(), stack: stack
        ))
        // Completed yesterday
        context.insert(QueueTask(
            id: "task-yesterday", title: "Done Yesterday",
            status: .completed, sortOrder: 2,
            updatedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            stack: stack
        ))
        // Pending
        context.insert(QueueTask(
            id: "task-pending", title: "Still Pending",
            status: .pending, sortOrder: 3, stack: stack
        ))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.statsKey, as: WidgetStatsData.self)
        #expect(data != nil)
        #expect(data?.completedToday == 2)
    }

    @Test("calculates completion rate")
    func calculatesCompletionRate() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-rate", title: "Rate Stack")
        context.insert(stack)

        // 3 completed, 1 pending = 75%
        for i in 0..<3 {
            context.insert(QueueTask(
                id: "task-c-\(i)", title: "Completed \(i)",
                status: .completed, sortOrder: i, stack: stack
            ))
        }
        context.insert(QueueTask(
            id: "task-p", title: "Pending",
            status: .pending, sortOrder: 3, stack: stack
        ))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.statsKey, as: WidgetStatsData.self)
        #expect(data != nil)
        if let rate = data?.completionRate {
            #expect(abs(rate - 0.75) < 0.01)
        }
    }

    @Test("zero completion rate with no tasks")
    func zeroCompletionRateWithNoTasks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.statsKey, as: WidgetStatsData.self)
        #expect(data != nil)
        #expect(data?.completionRate == 0.0)
        #expect(data?.completedToday == 0)
        #expect(data?.pendingTotal == 0)
    }

    @Test("counts overdue tasks")
    func countsOverdueTasks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-od", title: "Overdue Stats")
        context.insert(stack)

        // 2 overdue
        context.insert(QueueTask(
            id: "task-od-1", title: "Overdue 1",
            dueTime: Date(timeIntervalSinceNow: -7200),
            status: .pending, sortOrder: 0, stack: stack
        ))
        context.insert(QueueTask(
            id: "task-od-2", title: "Overdue 2",
            dueTime: Date(timeIntervalSinceNow: -3600),
            status: .pending, sortOrder: 1, stack: stack
        ))
        // 1 future
        context.insert(QueueTask(
            id: "task-future", title: "Future",
            dueTime: Date(timeIntervalSinceNow: 86400),
            status: .pending, sortOrder: 2, stack: stack
        ))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.statsKey, as: WidgetStatsData.self)
        #expect(data?.overdueCount == 2)
        #expect(data?.pendingTotal == 3)
    }

    @Test("counts active stacks")
    func countsActiveStacks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        context.insert(Stack(id: "s-a1", title: "Active 1", status: .active))
        context.insert(Stack(id: "s-a2", title: "Active 2", status: .active))
        context.insert(Stack(id: "s-c1", title: "Completed", status: .completed))
        context.insert(Stack(id: "s-ar1", title: "Archived", status: .archived))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.statsKey, as: WidgetStatsData.self)
        #expect(data?.activeStackCount == 2)
    }

    @Test("excludes deleted tasks from stats")
    func excludesDeletedTasksFromStats() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(id: "stack-del", title: "Del Stats")
        context.insert(stack)
        context.insert(QueueTask(
            id: "task-alive", title: "Alive",
            status: .pending, sortOrder: 0, stack: stack
        ))
        context.insert(QueueTask(
            id: "task-dead", title: "Deleted",
            status: .pending, sortOrder: 1, isDeleted: true, stack: stack
        ))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        let data = readDefaults(defaults, key: AppGroupConfig.statsKey, as: WidgetStatsData.self)
        #expect(data?.pendingTotal == 1)
    }
}

// MARK: - Timestamp Tests

@Suite("WidgetDataService Timestamp Tests")
@MainActor
struct WidgetDataServiceTimestampTests {
    @Test("sets lastUpdate timestamp")
    func setsLastUpdateTimestamp() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let beforeUpdate = Date()
        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)
        let afterUpdate = Date()

        let lastUpdate = defaults.object(forKey: AppGroupConfig.lastUpdateKey) as? Date
        #expect(lastUpdate != nil)
        if let ts = lastUpdate {
            #expect(ts >= beforeUpdate)
            #expect(ts <= afterUpdate)
        }
    }
}

// MARK: - Integration Tests

@Suite("WidgetDataService Integration Tests")
@MainActor
struct WidgetDataServiceIntegrationTests {
    @Test("populates all three widget data stores")
    func populatesAllWidgetData() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let defaults = makeIsolatedDefaults()

        let stack = Stack(
            id: "stack-int", title: "Integration Stack",
            status: .active, priority: 2, isActive: true
        )
        context.insert(stack)
        context.insert(QueueTask(
            id: "task-int-1", title: "First Task",
            dueTime: Date(timeIntervalSinceNow: 3600),
            status: .pending, priority: 3, sortOrder: 0, stack: stack
        ))
        context.insert(QueueTask(
            id: "task-int-2", title: "Second Task",
            status: .completed, sortOrder: 1, updatedAt: Date(), stack: stack
        ))
        try context.save()

        WidgetDataService.updateAllWidgets(context: context, defaults: defaults, reloadTimelines: false)

        // Active stack
        let activeData = readDefaults(defaults, key: AppGroupConfig.activeStackKey, as: WidgetActiveStackData.self)
        #expect(activeData?.stackTitle == "Integration Stack")

        // Up next
        let upNextData = readDefaults(defaults, key: AppGroupConfig.upNextKey, as: WidgetUpNextData.self)
        #expect(upNextData?.upcomingTasks.count == 1)

        // Stats
        let statsData = readDefaults(defaults, key: AppGroupConfig.statsKey, as: WidgetStatsData.self)
        #expect(statsData?.completedToday == 1)
        #expect(statsData?.pendingTotal == 1)
        #expect(statsData?.activeStackCount == 1)

        // Timestamp
        let lastUpdate = defaults.object(forKey: AppGroupConfig.lastUpdateKey) as? Date
        #expect(lastUpdate != nil)
    }
}
