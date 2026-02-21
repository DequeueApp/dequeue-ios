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
) -> QueueTask {
    let task = QueueTask(
        title: title,
        dueTime: dueTime,
        status: status,
        priority: priority,
        tags: tags,
        isDeleted: isDeleted,
        stack: stack
    )
    context.insert(task)
    try? context.save()
    return task
}

// MARK: - TaskFilter Model Tests

@Suite("TaskFilter Model")
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
struct TaskFilterServiceTests {
    @Test("Apply with default filter returns all non-deleted tasks")
    @MainActor func defaultFilterReturnsAll() throws {
        let context = try makeFilterTestContext()
        _ = makeFilterTask(title: "Task A", in: context)
        _ = makeFilterTask(title: "Task B", in: context)
        _ = makeFilterTask(title: "Deleted", isDeleted: true, in: context)

        let service = TaskFilterService(modelContext: context)
        let results = service.fetchFiltered(filter: .default)

        #expect(results.count == 2)
    }

    @Test("Status filter: pending only")
    @MainActor func statusFilterPending() throws {
        let context = try makeFilterTestContext()
        _ = makeFilterTask(title: "Active", status: .pending, in: context)
        _ = makeFilterTask(title: "Done", status: .completed, in: context)
        _ = makeFilterTask(title: "Blocked", status: .blocked, in: context)

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
        _ = makeFilterTask(title: "Active", status: .pending, in: context)
        _ = makeFilterTask(title: "Done", status: .completed, in: context)

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
        _ = makeFilterTask(title: "High", priority: 3, in: context)
        _ = makeFilterTask(title: "Low", priority: 1, in: context)
        _ = makeFilterTask(title: "None", in: context)

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
        _ = makeFilterTask(title: "Buy groceries", in: context)
        _ = makeFilterTask(title: "Fix bug #123", in: context)
        _ = makeFilterTask(title: "Review PR", in: context)

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
        _ = makeFilterTask(title: "IMPORTANT Task", in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.searchText = "important"
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 1)
    }

    @Test("Tag filter works")
    @MainActor func tagFilter() throws {
        let context = try makeFilterTestContext()
        _ = makeFilterTask(title: "Work Task", tags: ["work"], in: context)
        _ = makeFilterTask(title: "Personal", tags: ["personal"], in: context)
        _ = makeFilterTask(title: "Both", tags: ["work", "personal"], in: context)

        let service = TaskFilterService(modelContext: context)
        var filter = TaskFilter()
        filter.selectedTagIds = ["work"]
        let results = service.apply(filter: filter, to: try context.fetch(FetchDescriptor<QueueTask>()))

        #expect(results.count == 2) // "Work Task" and "Both"
    }

    @Test("Show only with due dates")
    @MainActor func onlyWithDueDates() throws {
        let context = try makeFilterTestContext()
        _ = makeFilterTask(title: "Has Due", dueTime: Date(), in: context)
        _ = makeFilterTask(title: "No Due", in: context)

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
        _ = makeFilterTask(title: "Charlie", in: context)
        _ = makeFilterTask(title: "Alice", in: context)
        _ = makeFilterTask(title: "Bob", in: context)

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
        _ = makeFilterTask(title: "Charlie", in: context)
        _ = makeFilterTask(title: "Alice", in: context)
        _ = makeFilterTask(title: "Bob", in: context)

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
        _ = makeFilterTask(title: "Low", priority: 1, in: context)
        _ = makeFilterTask(title: "High", priority: 3, in: context)
        _ = makeFilterTask(title: "Med", priority: 2, in: context)

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
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        _ = makeFilterTask(title: "High Priority Tomorrow", dueTime: tomorrow, priority: 3, in: context)
        _ = makeFilterTask(title: "Low Priority Tomorrow", dueTime: tomorrow, priority: 1, in: context)
        _ = makeFilterTask(title: "High Priority No Date", priority: 3, in: context)
        _ = makeFilterTask(title: "Completed", status: .completed, priority: 3, in: context)

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
        _ = makeFilterTask(title: "Has Due", dueTime: Date(), in: context)
        _ = makeFilterTask(title: "No Due", in: context)

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
