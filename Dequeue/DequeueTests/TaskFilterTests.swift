//
//  TaskFilterTests.swift
//  DequeueTests
//
//  Tests for TaskFilter model, TaskFilterService, and FilterPreset.
//

import Testing
import Foundation
import SwiftData

@testable import Dequeue

// MARK: - Test Helpers

@MainActor
private func makeFilterTestContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: QueueTask.self, Stack.self, Tag.self, Reminder.self, Arc.self,
        configurations: config
    )
    return container.mainContext
}

@MainActor
private func makeFilterTask(
    title: String,
    dueTime: Date? = nil,
    status: TaskStatus = .pending,
    priority: Int? = nil,
    tags: [String] = [],
    stack: Stack? = nil,
    isDeleted: Bool = false,
    in context: ModelContext
) throws -> QueueTask {
    let task = QueueTask(
        title: title,
        dueTime: dueTime,
        tags: tags,
        status: status,
        priority: priority,
        isDeleted: isDeleted,
        stack: stack
    )
    context.insert(task)
    try context.save()
    return task
}

// MARK: - TaskFilter Model Tests

@Suite("TaskFilter Model")
@MainActor
struct TaskFilterModelTests {
    @Test("Default filter has no active filters")
    func defaultFilter() {
        let filter = TaskFilter.default
        #expect(!filter.isActive)
        #expect(filter.activeFilterCount == 0)
    }

    @Test("Active filter count tracks each category")
    func activeFilterCount() {
        var filter = TaskFilter()
        #expect(filter.activeFilterCount == 0)

        filter.statusFilter = .pending
        #expect(filter.activeFilterCount == 1)

        filter.priorityFilter = .high
        #expect(filter.activeFilterCount == 2)

        filter.dateRangeFilter = .today
        #expect(filter.activeFilterCount == 3)

        filter.selectedTagIds = ["tag1"]
        #expect(filter.activeFilterCount == 4)

        filter.selectedStackIds = ["stack1"]
        #expect(filter.activeFilterCount == 5)

        filter.showOnlyWithDueDate = true
        #expect(filter.activeFilterCount == 6)

        filter.searchText = "test"
        #expect(filter.activeFilterCount == 7)
    }

    @Test("isActive returns true when any filter set")
    func isActiveDetection() {
        var filter = TaskFilter()
        #expect(!filter.isActive)

        filter.statusFilter = .completed
        #expect(filter.isActive)
    }

    @Test("Reset clears all filters")
    func reset() {
        var filter = TaskFilter()
        filter.statusFilter = .blocked
        filter.priorityFilter = .high
        filter.dateRangeFilter = .today
        filter.searchText = "hello"
        filter.selectedTagIds = ["a"]
        filter.selectedStackIds = ["b"]
        filter.showOnlyWithDueDate = true
        filter.sortBy = .priority
        filter.sortAscending = false

        filter.reset()

        #expect(!filter.isActive)
        #expect(filter.activeFilterCount == 0)
        #expect(filter.sortBy == .sortOrder)
        #expect(filter.sortAscending == true)
    }

    @Test("TaskFilter is Codable")
    func codable() throws {
        var filter = TaskFilter()
        filter.statusFilter = .blocked
        filter.priorityFilter = .high
        filter.searchText = "test"
        filter.sortBy = .dueDate

        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(TaskFilter.self, from: data)

        #expect(decoded.statusFilter == .blocked)
        #expect(decoded.priorityFilter == .high)
        #expect(decoded.searchText == "test")
        #expect(decoded.sortBy == .dueDate)
    }

    @Test("Equatable works correctly")
    func equatable() {
        let a = TaskFilter()
        var b = TaskFilter()
        #expect(a == b)

        b.statusFilter = .completed
        #expect(a != b)
    }
}

// MARK: - DateRangeFilter Tests

@Suite("DateRangeFilter")
@MainActor
struct DateRangeFilterTests {
    @Test("Any returns no bounds")
    func anyRange() {
        let range = DateRangeFilter.any.dateRange()
        #expect(range.start == nil)
        #expect(range.end == nil)
    }

    @Test("Overdue returns nil start and start-of-today end")
    func overdueRange() {
        let range = DateRangeFilter.overdue.dateRange()
        #expect(range.start == nil)
        #expect(range.end != nil)
    }

    @Test("Today range covers 24 hours from start of day")
    func todayRange() {
        let now = Date()
        let range = DateRangeFilter.today.dateRange(from: now)
        let startOfToday = Calendar.current.startOfDay(for: now)
        #expect(range.start == startOfToday)
        #expect(range.end != nil)
        // Should be exactly 24 hours
        if let end = range.end {
            let diff = end.timeIntervalSince(startOfToday)
            #expect(abs(diff - 86400) < 1)
        }
    }

    @Test("This week covers 7 days")
    func thisWeekRange() {
        let now = Date()
        let range = DateRangeFilter.thisWeek.dateRange(from: now)
        if let start = range.start, let end = range.end {
            let diff = end.timeIntervalSince(start)
            #expect(abs(diff - 7 * 86400) < 1)
        }
    }

    @Test("NoDueDate returns nil bounds")
    func noDueDateRange() {
        let range = DateRangeFilter.noDueDate.dateRange()
        #expect(range.start == nil)
        #expect(range.end == nil)
    }

    @Test("Tomorrow range covers 24 hours starting from tomorrow")
    func tomorrowRange() {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let range = DateRangeFilter.tomorrow.dateRange(from: now)

        let expectedStart = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        let expectedEnd = calendar.date(byAdding: .day, value: 2, to: startOfToday)

        #expect(range.start == expectedStart)
        #expect(range.end == expectedEnd)

        // Exactly 24 hours
        if let start = range.start, let end = range.end {
            let diff = end.timeIntervalSince(start)
            #expect(abs(diff - 86400) < 1)
        }
    }

    @Test("Next week covers days 7-14 from today")
    func nextWeekRange() {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let range = DateRangeFilter.nextWeek.dateRange(from: now)

        let expectedStart = calendar.date(byAdding: .day, value: 7, to: startOfToday)
        let expectedEnd = calendar.date(byAdding: .day, value: 14, to: startOfToday)

        #expect(range.start == expectedStart)
        #expect(range.end == expectedEnd)

        // Exactly 7 days span
        if let start = range.start, let end = range.end {
            let diff = end.timeIntervalSince(start)
            #expect(abs(diff - 7 * 86400) < 1)
        }
    }

    @Test("This month covers start of today to 1 month out")
    func thisMonthRange() {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let range = DateRangeFilter.thisMonth.dateRange(from: now)

        let expectedEnd = calendar.date(byAdding: .month, value: 1, to: startOfToday)

        #expect(range.start == startOfToday)
        #expect(range.end == expectedEnd)
        #expect(range.end != nil)
    }

    @Test("Custom returns nil bounds (handled separately)")
    func customRange() {
        let range = DateRangeFilter.custom.dateRange()
        #expect(range.start == nil)
        #expect(range.end == nil)
    }

    @Test("Overdue end equals start of today")
    func overdueEndIsStartOfToday() {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let range = DateRangeFilter.overdue.dateRange(from: now)
        #expect(range.start == nil)
        #expect(range.end == startOfToday)
    }

    @Test("DateRangeFilter id equals rawValue")
    func idEqualsRawValue() {
        for filter in DateRangeFilter.allCases {
            #expect(filter.id == filter.rawValue)
        }
    }

    @Test("All cases have display names")
    func displayNames() {
        for range in DateRangeFilter.allCases {
            #expect(!range.displayName.isEmpty)
        }
    }

    @Test("All cases have icons")
    func icons() {
        for range in DateRangeFilter.allCases {
            #expect(!range.icon.isEmpty)
        }
    }
}

// MARK: - TaskSortOption Tests

@Suite("TaskSortOption")
@MainActor
struct TaskSortOptionTests {
    @Test("All options have display names")
    func displayNames() {
        for opt in TaskSortOption.allCases {
            #expect(!opt.displayName.isEmpty)
        }
    }

    @Test("All options have icons")
    func icons() {
        for opt in TaskSortOption.allCases {
            #expect(!opt.icon.isEmpty)
        }
    }
}

// MARK: - TaskFilterService Tests

@Suite("TaskFilterService")
@MainActor
struct TaskFilterServiceTests {
    @Test("Apply with default filter returns all non-deleted tasks")
    @MainActor func defaultFilterReturnsAll() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Task A", in: context)
        _ = try makeFilterTask(title: "Task B", in: context)
        _ = try makeFilterTask(title: "Deleted", isDeleted: true, in: context)

        let service = TaskFilterService(modelContext: context)
        let results = service.fetchFiltered(filter: .default)

        #expect(results.count == 2)
    }

    @Test("Status filter: pending only")
    @MainActor func statusFilterPending() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Active", status: .pending, in: context)
        _ = try makeFilterTask(title: "Done", status: .completed, in: context)
        _ = try makeFilterTask(title: "Blocked", status: .blocked, in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.statusFilter = .pending
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 1)
        #expect(results[0].title == "Active")
    }

    @Test("Status filter: completed only")
    @MainActor func statusFilterCompleted() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Active", status: .pending, in: context)
        _ = try makeFilterTask(title: "Done", status: .completed, in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.statusFilter = .completed
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 1)
        #expect(results[0].title == "Done")
    }

    @Test("Priority filter: high only")
    @MainActor func priorityFilterHigh() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "High", priority: 3, in: context)
        _ = try makeFilterTask(title: "Low", priority: 1, in: context)
        _ = try makeFilterTask(title: "None", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.priorityFilter = .high
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 1)
        #expect(results[0].title == "High")
    }

    @Test("Search text filters by title")
    @MainActor func searchByTitle() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Buy groceries", in: context)
        _ = try makeFilterTask(title: "Fix bug #123", in: context)
        _ = try makeFilterTask(title: "Review PR", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.searchText = "bug"
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 1)
        #expect(results[0].title == "Fix bug #123")
    }

    @Test("Search is case-insensitive")
    @MainActor func searchCaseInsensitive() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "IMPORTANT Task", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.searchText = "important"
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 1)
    }

    @Test("Tag filter works")
    @MainActor func tagFilter() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Work Task", tags: ["work"], in: context)
        _ = try makeFilterTask(title: "Personal", tags: ["personal"], in: context)
        _ = try makeFilterTask(title: "Both", tags: ["work", "personal"], in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.selectedTagIds = ["work"]
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 2) // "Work Task" and "Both"
    }

    @Test("Show only with due dates")
    @MainActor func onlyWithDueDates() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Has Due", dueTime: Date(), in: context)
        _ = try makeFilterTask(title: "No Due", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.showOnlyWithDueDate = true
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 1)
        #expect(results[0].title == "Has Due")
    }

    @Test("Sort by title ascending")
    @MainActor func sortByTitleAsc() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Charlie", in: context)
        _ = try makeFilterTask(title: "Alice", in: context)
        _ = try makeFilterTask(title: "Bob", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.sortBy = .title
        filter.sortAscending = true
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.map(\.title) == ["Alice", "Bob", "Charlie"])
    }

    @Test("Sort by title descending")
    @MainActor func sortByTitleDesc() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Charlie", in: context)
        _ = try makeFilterTask(title: "Alice", in: context)
        _ = try makeFilterTask(title: "Bob", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.sortBy = .title
        filter.sortAscending = false
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.map(\.title) == ["Charlie", "Bob", "Alice"])
    }

    @Test("Sort by priority")
    @MainActor func sortByPriority() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Low", priority: 1, in: context)
        _ = try makeFilterTask(title: "High", priority: 3, in: context)
        _ = try makeFilterTask(title: "Med", priority: 2, in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.sortBy = .priority
        filter.sortAscending = false
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results[0].title == "High")
        #expect(results[2].title == "Low")
    }

    @Test("Combined filters work together")
    @MainActor func combinedFilters() throws {
        let context = try makeFilterTestContext()
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))

        _ = try makeFilterTask(title: "High Priority Tomorrow", dueTime: tomorrow, priority: 3, in: context)
        _ = try makeFilterTask(title: "Low Priority Tomorrow", dueTime: tomorrow, priority: 1, in: context)
        _ = try makeFilterTask(title: "High Priority No Date", priority: 3, in: context)
        _ = try makeFilterTask(title: "Completed", status: .completed, priority: 3, in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.priorityFilter = .high
        filter.statusFilter = .pending
        filter.showOnlyWithDueDate = true
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 1)
        #expect(results[0].title == "High Priority Tomorrow")
    }

    @Test("NoDueDate filter returns tasks without due dates")
    @MainActor func noDueDateFilter() throws {
        let context = try makeFilterTestContext()
        _ = try makeFilterTask(title: "Has Due", dueTime: Date(), in: context)
        _ = try makeFilterTask(title: "No Due", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.dateRangeFilter = .noDueDate
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 1)
        #expect(results[0].title == "No Due")
    }
}

// MARK: - FilterPreset Tests

@Suite("FilterPreset")
@MainActor
struct FilterPresetTests {
    @Test("Built-in presets have names and icons")
    func builtInsValid() {
        for preset in FilterPreset.builtInPresets {
            #expect(!preset.name.isEmpty)
            #expect(!preset.icon.isEmpty)
            #expect(!preset.id.isEmpty)
        }
    }

    @Test("Overdue preset has correct filter")
    func overduePreset() {
        let preset = FilterPreset.builtInPresets.first { $0.name == "Overdue" }
        #expect(preset != nil)
        #expect(preset?.filter.dateRangeFilter == .overdue)
        #expect(preset?.filter.statusFilter == .pending)
    }

    @Test("High Priority preset has correct filter")
    func highPriorityPreset() {
        let preset = FilterPreset.builtInPresets.first { $0.name == "High Priority" }
        #expect(preset != nil)
        #expect(preset?.filter.priorityFilter == .high)
    }

    @Test("Preset round-trips through JSON")
    func presetCodable() throws {
        var filter = TaskFilter()
        filter.statusFilter = .blocked
        let preset = FilterPreset(name: "Test", icon: "star.fill", filter: filter)

        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(FilterPreset.self, from: data)

        #expect(decoded.name == "Test")
        #expect(decoded.icon == "star.fill")
        #expect(decoded.filter.statusFilter == .blocked)
    }

    @Test("Save and load presets from UserDefaults")
    @MainActor func saveLoadPresets() throws {
        let context = try makeFilterTestContext()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = TaskFilterService(modelContext: context)

        // Initially empty
        let initial = service.loadPresets(from: defaults)
        #expect(initial.isEmpty)

        // Save
        var filter = TaskFilter()
        filter.statusFilter = .completed
        let preset = service.addPreset(name: "Completed", filter: filter, userDefaults: defaults)

        // Load
        let loaded = service.loadPresets(from: defaults)
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Completed")

        // Remove
        service.removePreset(id: preset.id, userDefaults: defaults)
        let afterRemove = service.loadPresets(from: defaults)
        #expect(afterRemove.isEmpty)
    }
}

// MARK: - Extended TaskFilterService Tests

@Suite("TaskFilterService — Extended Coverage", .serialized)
@MainActor
struct TaskFilterServiceExtendedTests {

    // MARK: - Search by description and tags

    @Test("Search matches task description")
    func searchByDescription() throws {
        let context = try makeFilterTestContext()
        let task = try makeFilterTask(title: "Task A", in: context)
        task.taskDescription = "This needs backend work"
        try context.save()
        let taskB = try makeFilterTask(title: "Task B", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.searchText = "backend"
        let results = service.apply(filter: filter, to: [task, taskB])

        #expect(results.count == 1)
        #expect(results[0].title == "Task A")
    }

    @Test("Search matches tag content")
    func searchByTagContent() throws {
        let context = try makeFilterTestContext()
        let task = try makeFilterTask(title: "Task A", tags: ["frontend"], in: context)
        let taskB = try makeFilterTask(title: "Task B", tags: ["backend"], in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.searchText = "front"
        let results = service.apply(filter: filter, to: [task, taskB])

        #expect(results.count == 1)
        #expect(results[0].title == "Task A")
    }

    @Test("Search with no matches returns empty")
    func searchNoMatches() throws {
        let context = try makeFilterTestContext()
        let task = try makeFilterTask(title: "Hello World", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.searchText = "zzzznotfound"
        let results = service.apply(filter: filter, to: [task])

        #expect(results.isEmpty)
    }

    // MARK: - Stack filter

    @Test("Stack filter matches tasks in selected stacks")
    func stackFilter() throws {
        let context = try makeFilterTestContext()
        let stack1 = Stack(title: "Work")
        let stack2 = Stack(title: "Personal")
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        let t1 = try makeFilterTask(title: "Work Task", stack: stack1, in: context)
        let t2 = try makeFilterTask(title: "Personal Task", stack: stack2, in: context)
        let t3 = try makeFilterTask(title: "No Stack", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.selectedStackIds = [stack1.id]
        let results = service.apply(filter: filter, to: [t1, t2, t3])

        #expect(results.count == 1)
        #expect(results[0].title == "Work Task")
    }

    @Test("Stack filter with multiple stacks uses OR logic")
    func multipleStackFilter() throws {
        let context = try makeFilterTestContext()
        let stack1 = Stack(title: "A")
        let stack2 = Stack(title: "B")
        context.insert(stack1)
        context.insert(stack2)
        try context.save()

        let t1 = try makeFilterTask(title: "In A", stack: stack1, in: context)
        let t2 = try makeFilterTask(title: "In B", stack: stack2, in: context)
        let t3 = try makeFilterTask(title: "Orphan", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.selectedStackIds = [stack1.id, stack2.id]
        let results = service.apply(filter: filter, to: [t1, t2, t3])

        #expect(results.count == 2)
    }

    // MARK: - Sort by sortOrder and dueDate nil handling

    @Test("Sort by sortOrder ascending")
    func sortBySortOrderAsc() throws {
        let context = try makeFilterTestContext()
        let t1 = try makeFilterTask(title: "Third", in: context)
        t1.sortOrder = 3
        let t2 = try makeFilterTask(title: "First", in: context)
        t2.sortOrder = 1
        let t3 = try makeFilterTask(title: "Second", in: context)
        t3.sortOrder = 2

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.sortBy = .sortOrder
        filter.sortAscending = true
        let results = service.apply(filter: filter, to: [t1, t2, t3])

        #expect(results[0].title == "First")
        #expect(results[1].title == "Second")
        #expect(results[2].title == "Third")
    }

    @Test("Sort by due date places nil last (ascending)")
    func sortByDueDateNilLast() throws {
        let context = try makeFilterTestContext()
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        let t1 = try makeFilterTask(title: "Tomorrow", dueTime: tomorrow, in: context)
        let t2 = try makeFilterTask(title: "Today", dueTime: Date(), in: context)
        let t3 = try makeFilterTask(title: "No Due", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.sortBy = .dueDate
        filter.sortAscending = true
        let results = service.apply(filter: filter, to: [t1, t2, t3])

        #expect(results[0].title == "Today")
        #expect(results[1].title == "Tomorrow")
        #expect(results[2].title == "No Due") // distantFuture sorts last
    }

    // MARK: - Date range filters

    @Test("Overdue filter returns tasks before start of today")
    func overdueFilter() throws {
        let context = try makeFilterTestContext()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))

        let t1 = try makeFilterTask(title: "Overdue", dueTime: yesterday, in: context)
        let t2 = try makeFilterTask(title: "Future", dueTime: tomorrow, in: context)
        let t3 = try makeFilterTask(title: "No Due", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.dateRangeFilter = .overdue
        let results = service.apply(filter: filter, to: [t1, t2, t3])

        #expect(results.count == 1)
        #expect(results[0].title == "Overdue")
    }

    @Test("Custom date range with start and end")
    func customDateRange() throws {
        let context = try makeFilterTestContext()
        let cal = Calendar.current
        let now = Date()
        let twoDaysAgo = try #require(cal.date(byAdding: .day, value: -2, to: now))
        let twoDaysFromNow = try #require(cal.date(byAdding: .day, value: 2, to: now))
        let fiveDaysFromNow = try #require(cal.date(byAdding: .day, value: 5, to: now))

        let t1 = try makeFilterTask(title: "In Range", dueTime: now, in: context)
        let t2 = try makeFilterTask(title: "Before Range", dueTime: twoDaysAgo, in: context)
        let t3 = try makeFilterTask(title: "After Range", dueTime: fiveDaysFromNow, in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.dateRangeFilter = .custom
        filter.customStartDate = try #require(cal.date(byAdding: .day, value: -1, to: now))
        filter.customEndDate = twoDaysFromNow
        let results = service.apply(filter: filter, to: [t1, t2, t3])

        #expect(results.count == 1)
        #expect(results[0].title == "In Range")
    }

    @Test("Custom date range with only start date")
    func customStartOnly() throws {
        let context = try makeFilterTestContext()
        let cal = Calendar.current
        let now = Date()
        let yesterday = try #require(cal.date(byAdding: .day, value: -1, to: now))
        let twoDaysAgo = try #require(cal.date(byAdding: .day, value: -2, to: now))

        let t1 = try makeFilterTask(title: "Recent", dueTime: now, in: context)
        let t2 = try makeFilterTask(title: "Old", dueTime: twoDaysAgo, in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.dateRangeFilter = .custom
        filter.customStartDate = yesterday
        filter.customEndDate = nil
        let results = service.apply(filter: filter, to: [t1, t2])

        #expect(results.count == 1)
        #expect(results[0].title == "Recent")
    }

    // MARK: - Combined multi-filter tests

    @Test("Status + tags + search combined")
    func statusTagsSearchCombined() throws {
        let context = try makeFilterTestContext()
        let t1 = try makeFilterTask(title: "Fix login bug", tags: ["bug"], in: context)
        let t2 = try makeFilterTask(title: "Add login feature", tags: ["feature"], in: context)
        let t3 = try makeFilterTask(
            title: "Fix signup bug",
            status: .completed,
            tags: ["bug"],
            in: context
        )

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.statusFilter = .pending
        filter.selectedTagIds = ["bug"]
        filter.searchText = "login"
        let results = service.apply(filter: filter, to: [t1, t2, t3])

        #expect(results.count == 1)
        #expect(results[0].title == "Fix login bug")
    }

    @Test("Empty input array returns empty results")
    func emptyInput() throws {
        let context = try makeFilterTestContext()
        let service = TaskFilterService(modelContext: context)

        var filter = TaskFilter()
        filter.statusFilter = .pending
        let results = service.apply(filter: filter, to: [])

        #expect(results.isEmpty)
    }

    @Test("Blocked status filter")
    func blockedFilter() throws {
        let context = try makeFilterTestContext()
        let t1 = try makeFilterTask(title: "Blocked", status: .blocked, in: context)
        let t2 = try makeFilterTask(title: "Pending", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.statusFilter = .blocked
        let results = service.apply(filter: filter, to: [t1, t2])

        #expect(results.count == 1)
        #expect(results[0].title == "Blocked")
    }
}

// MARK: - DateRangeFilter Extended Tests

@Suite("DateRangeFilter — Extended")
@MainActor
struct DateRangeFilterExtendedTests {
    @Test("Tomorrow returns correct bounds")
    func tomorrowRange() {
        let now = Date()
        let range = DateRangeFilter.tomorrow.dateRange(from: now)
        let startOfToday = Calendar.current.startOfDay(for: now)
        let expectedStart = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)
        let expectedEnd = Calendar.current.date(byAdding: .day, value: 2, to: startOfToday)
        #expect(range.start == expectedStart)
        #expect(range.end == expectedEnd)
    }

    @Test("Next week spans days 7 through 14")
    func nextWeekRange() {
        let now = Date()
        let range = DateRangeFilter.nextWeek.dateRange(from: now)
        let startOfToday = Calendar.current.startOfDay(for: now)
        let expectedStart = Calendar.current.date(byAdding: .day, value: 7, to: startOfToday)
        let expectedEnd = Calendar.current.date(byAdding: .day, value: 14, to: startOfToday)
        #expect(range.start == expectedStart)
        #expect(range.end == expectedEnd)
    }

    @Test("This month spans 1 month from today")
    func thisMonthRange() {
        let now = Date()
        let range = DateRangeFilter.thisMonth.dateRange(from: now)
        let startOfToday = Calendar.current.startOfDay(for: now)
        let expectedEnd = Calendar.current.date(byAdding: .month, value: 1, to: startOfToday)
        #expect(range.start == startOfToday)
        #expect(range.end == expectedEnd)
    }

    @Test("Custom returns nil bounds")
    func customRange() {
        let range = DateRangeFilter.custom.dateRange()
        #expect(range.start == nil)
        #expect(range.end == nil)
    }

    @Test("dateRange(from:) uses reference date correctly")
    func referenceDate() throws {
        let refDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let range = DateRangeFilter.today.dateRange(from: refDate)
        let startOfRef = Calendar.current.startOfDay(for: refDate)
        let expectedEnd = Calendar.current.date(byAdding: .day, value: 1, to: startOfRef)
        #expect(range.start == startOfRef)
        #expect(range.end == expectedEnd)
    }
}

// MARK: - PriorityFilter & StatusFilter Tests

@Suite("PriorityFilter Properties")
@MainActor
struct PriorityFilterPropertyTests {
    @Test("All priority filters have display names and colors")
    func properties() {
        for pf in PriorityFilter.allCases {
            #expect(!pf.displayName.isEmpty)
            #expect(!pf.color.isEmpty)
            #expect(pf.id == pf.rawValue)
        }
    }
}

@Suite("StatusFilter Properties")
@MainActor
struct StatusFilterPropertyTests {
    @Test("All status filters have display names")
    func properties() {
        for sf in StatusFilter.allCases {
            #expect(!sf.displayName.isEmpty)
            #expect(sf.id == sf.rawValue)
        }
    }
}
