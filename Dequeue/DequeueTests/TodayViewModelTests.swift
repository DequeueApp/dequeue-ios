//
//  TodayViewModelTests.swift
//  DequeueTests
//
//  Tests for TodayViewModel — task grouping by overdue/today/tomorrow/week.
//

import Testing
import Foundation
import SwiftData

@testable import Dequeue

// MARK: - Test Helpers

@MainActor
private func makeTodayTestContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: QueueTask.self, Stack.self, Reminder.self, Arc.self,
        configurations: config
    )
    return container.mainContext
}

@MainActor
private func insertTask(
    title: String,
    dueTime: Date? = nil,
    status: TaskStatus = .pending,
    priority: Int? = nil,
    isDeleted: Bool = false,
    in context: ModelContext
) -> QueueTask {
    let task = QueueTask(
        title: title,
        dueTime: dueTime,
        status: status,
        priority: priority,
        isDeleted: isDeleted
    )
    context.insert(task)
    try? context.save()
    return task
}

// MARK: - Today Section Tests

@Suite("TodaySection")
@MainActor
struct TodaySectionTests {
    @Test("All sections have unique ids")
    func uniqueIds() {
        let ids = TodaySection.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("All sections have titles")
    func hasTitles() {
        for section in TodaySection.allCases {
            #expect(!section.title.isEmpty)
        }
    }

    @Test("All sections have icons")
    func hasIcons() {
        for section in TodaySection.allCases {
            #expect(!section.icon.isEmpty)
        }
    }

    @Test("Section order is overdue, today, tomorrow, thisWeek")
    func sectionOrder() {
        let allCases = TodaySection.allCases
        #expect(allCases[0] == .overdue)
        #expect(allCases[1] == .today)
        #expect(allCases[2] == .tomorrow)
        #expect(allCases[3] == .thisWeek)
    }
}

// MARK: - ViewModel Grouping Tests

@Suite("TodayViewModel Task Grouping")
@MainActor
struct ViewModelGroupingTests {
    @Test("Empty state shows no tasks")
    @MainActor func emptyState() throws {
        let context = try makeTodayTestContext()
        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.overdueTasks.isEmpty)
        #expect(vm.todayTasks.isEmpty)
        #expect(vm.tomorrowTasks.isEmpty)
        #expect(vm.thisWeekTasks.isEmpty)
        #expect(vm.totalTaskCount == 0)
    }

    @Test("Groups overdue tasks correctly")
    @MainActor func overdueGrouping() throws {
        let context = try makeTodayTestContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        _ = insertTask(title: "Overdue", dueTime: yesterday, in: context)

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.overdueTasks.count == 1)
        #expect(vm.overdueTasks[0].title == "Overdue")
    }

    @Test("Groups today's tasks correctly")
    @MainActor func todayGrouping() throws {
        let context = try makeTodayTestContext()
        let todayLater = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        // Only add if it's still in the future
        if todayLater > Date() {
            _ = insertTask(title: "Today Task", dueTime: todayLater, in: context)
        }

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        if todayLater > Date() {
            #expect(vm.todayTasks.count == 1)
        }
    }

    @Test("Groups tomorrow's tasks correctly")
    @MainActor func tomorrowGrouping() throws {
        let context = try makeTodayTestContext()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let tomorrowNoon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow)!
        _ = insertTask(title: "Tomorrow Task", dueTime: tomorrowNoon, in: context)

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.tomorrowTasks.count == 1)
        #expect(vm.tomorrowTasks[0].title == "Tomorrow Task")
    }

    @Test("Groups this week's tasks correctly")
    @MainActor func thisWeekGrouping() throws {
        let context = try makeTodayTestContext()
        let inFiveDays = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        _ = insertTask(title: "This Week Task", dueTime: inFiveDays, in: context)

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.thisWeekTasks.count == 1)
        #expect(vm.thisWeekTasks[0].title == "This Week Task")
    }

    @Test("Excludes completed tasks from all sections")
    @MainActor func excludesCompleted() throws {
        let context = try makeTodayTestContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        _ = insertTask(title: "Done Overdue", dueTime: yesterday, status: .completed, in: context)
        _ = insertTask(title: "Done Tomorrow", dueTime: tomorrow, status: .completed, in: context)

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.totalTaskCount == 0)
    }

    @Test("Excludes deleted tasks from all sections")
    @MainActor func excludesDeleted() throws {
        let context = try makeTodayTestContext()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        _ = insertTask(title: "Deleted", dueTime: tomorrow, isDeleted: true, in: context)

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.totalTaskCount == 0)
    }

    @Test("Excludes tasks without due dates")
    @MainActor func excludesNoDueDate() throws {
        let context = try makeTodayTestContext()
        _ = insertTask(title: "No Due Date", in: context)

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.totalTaskCount == 0)
    }

    @Test("Tasks beyond 7 days are not included")
    @MainActor func excludesFarFuture() throws {
        let context = try makeTodayTestContext()
        let twoWeeks = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
        _ = insertTask(title: "Far Future", dueTime: twoWeeks, in: context)

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.totalTaskCount == 0)
    }

    @Test("Total count aggregates all sections")
    @MainActor func totalCount() throws {
        let context = try makeTodayTestContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let inFiveDays = Calendar.current.date(byAdding: .day, value: 5, to: Date())!

        _ = insertTask(title: "Overdue", dueTime: yesterday, in: context)
        _ = insertTask(title: "Tomorrow 1", dueTime: tomorrow, in: context)
        _ = insertTask(title: "Tomorrow 2", dueTime: tomorrow, in: context)
        _ = insertTask(title: "Week", dueTime: inFiveDays, in: context)

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.totalTaskCount == 4)
    }

    @Test("Completed today count works")
    @MainActor func completedTodayCount() throws {
        let context = try makeTodayTestContext()
        // Insert a completed task with recent updatedAt
        let task = insertTask(title: "Just Done", status: .completed, in: context)
        task.updatedAt = Date()
        try context.save()

        let vm = TodayViewModel(modelContext: context)
        vm.refresh()

        #expect(vm.completedTodayCount >= 1)
    }

    @Test("Refresh updates data")
    @MainActor func refreshUpdates() throws {
        let context = try makeTodayTestContext()
        let vm = TodayViewModel(modelContext: context)
        vm.refresh()
        #expect(vm.totalTaskCount == 0)

        // Add a task
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        _ = insertTask(title: "New Task", dueTime: tomorrow, in: context)

        vm.refresh()
        #expect(vm.totalTaskCount == 1)
    }
}
