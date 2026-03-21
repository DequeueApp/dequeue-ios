//
//  TaskFilterServiceTests.swift
//  DequeueTests
//
//  Additional coverage for TaskFilterService — priority variants, sort directions,
//  and nil-dueDate descending ordering not yet covered in TaskFilterTests.swift.
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Shared Container (file-scoped)
//
// TaskFilterService.apply(filter:to:) never touches modelContext — it operates
// purely on the [QueueTask] array passed in. We still need a ModelContext for
// TaskFilterService.init, so we create ONE shared container for the entire file
// and reuse its mainContext across all tests.
//
// Why not a per-test container? Swift 6 has a @MainActor deinit bug
// (swift_task_deinitOnExecutorImpl double-free, rdar://FB15432891): when a
// ModelContainer is released while its mainContext is still alive, the teardown
// crashes and xcodebuild enters a crash-restart loop. Using a single long-lived
// container avoids all per-test teardown entirely.
//
// nonisolated(unsafe) is required for a mutable global in Swift 6 strict concurrency.
nonisolated(unsafe) private var _sharedFilterServiceContainer: ModelContainer?

@MainActor
private func sharedFilterServiceContext() throws -> ModelContext {
    if let existing = _sharedFilterServiceContainer {
        return existing.mainContext
    }
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: QueueTask.self, Stack.self, Tag.self, Reminder.self, Arc.self,
        configurations: config
    )
    _sharedFilterServiceContainer = container
    return container.mainContext
}

@MainActor
private func makeFilterService() throws -> TaskFilterService {
    let context = try sharedFilterServiceContext()
    return TaskFilterService(modelContext: context)
}

// MARK: - Task Factory
//
// Tasks are created as plain instances — NOT inserted into any context.
// apply(filter:to:) only reads task properties; no persistence needed.

@discardableResult
@MainActor
private func makeServiceTask(
    title: String,
    status: TaskStatus = .pending,
    priority: Int? = nil,
    dueTime: Date? = nil,
    tags: [String] = [],
    stack: Stack? = nil,
    sortOrder: Int = 0,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
) -> QueueTask {
    QueueTask(
        title: title,
        dueTime: dueTime,
        tags: tags,
        status: status,
        priority: priority,
        sortOrder: sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt,
        stack: stack
    )
}

// MARK: - Priority Filter — All Variants

@Suite("TaskFilterService — Priority Variants", .serialized)
@MainActor
struct TaskFilterServicePriorityTests {

    @Test("Priority filter .low returns only low-priority tasks")
    func priorityLow() throws {
        let service = try makeFilterService()

        let low = makeServiceTask(title: "Low", priority: 1)
        let med = makeServiceTask(title: "Medium", priority: 2)
        let high = makeServiceTask(title: "High", priority: 3)

        var filter = TaskFilter()
        filter.priorityFilter = .low
        let result = service.apply(filter: filter, to: [low, med, high])

        #expect(result.count == 1)
        #expect(result[0].title == "Low")
    }

    @Test("Priority filter .medium returns only medium-priority tasks")
    func priorityMedium() throws {
        let service = try makeFilterService()

        let low = makeServiceTask(title: "Low", priority: 1)
        let med = makeServiceTask(title: "Medium", priority: 2)
        let high = makeServiceTask(title: "High", priority: 3)

        var filter = TaskFilter()
        filter.priorityFilter = .medium
        let result = service.apply(filter: filter, to: [low, med, high])

        #expect(result.count == 1)
        #expect(result[0].title == "Medium")
    }

    @Test("Priority filter .none returns tasks with priority = 0 or nil (both map to 0)")
    func priorityNoneIsZero() throws {
        let service = try makeFilterService()

        let zeroPriority = makeServiceTask(title: "Zero", priority: 0)
        let nilPriority = makeServiceTask(title: "Nil", priority: nil)
        let lowPriority = makeServiceTask(title: "Low", priority: 1)

        var filter = TaskFilter()
        filter.priorityFilter = .none
        let result = service.apply(filter: filter, to: [zeroPriority, nilPriority, lowPriority])

        // PriorityFilter.none.rawValue == 0
        // applyPriorityFilter uses: ($0.priority ?? 0) == priority.rawValue
        // Both zeroPriority (priority=0) and nilPriority (priority=nil → 0) match
        #expect(result.count == 2)
        let titles = result.map(\.title)
        #expect(titles.contains("Zero"))
        #expect(titles.contains("Nil"))
    }

    @Test("Priority filter .any returns all tasks regardless of priority")
    func priorityAny() throws {
        let service = try makeFilterService()

        let low = makeServiceTask(title: "Low", priority: 1)
        let med = makeServiceTask(title: "Medium", priority: 2)
        let noPriority = makeServiceTask(title: "None", priority: nil)

        var filter = TaskFilter()
        filter.priorityFilter = .any
        let result = service.apply(filter: filter, to: [low, med, noPriority])

        #expect(result.count == 3)
    }
}

// MARK: - Sort Direction — All Options

@Suite("TaskFilterService — Sort Coverage", .serialized)
@MainActor
struct TaskFilterServiceSortTests {

    @Test("Sort by sortOrder descending")
    func sortBySortOrderDesc() throws {
        let service = try makeFilterService()

        let first = makeServiceTask(title: "First", sortOrder: 0)
        let second = makeServiceTask(title: "Second", sortOrder: 1)
        let third = makeServiceTask(title: "Third", sortOrder: 2)

        var filter = TaskFilter()
        filter.sortBy = .sortOrder
        filter.sortAscending = false
        let result = service.apply(filter: filter, to: [first, second, third])

        #expect(result.map(\.title) == ["Third", "Second", "First"])
    }

    @Test("Sort by createdAt ascending puts oldest first")
    func sortByCreatedAtAsc() throws {
        let service = try makeFilterService()

        let cal = Calendar.current
        let now = Date()
        let oldest = makeServiceTask(
            title: "Oldest",
            createdAt: cal.date(byAdding: .day, value: -2, to: now)!
        )
        let middle = makeServiceTask(
            title: "Middle",
            createdAt: cal.date(byAdding: .day, value: -1, to: now)!
        )
        let newest = makeServiceTask(title: "Newest", createdAt: now)

        var filter = TaskFilter()
        filter.sortBy = .createdAt
        filter.sortAscending = true
        let result = service.apply(filter: filter, to: [newest, oldest, middle])

        #expect(result.map(\.title) == ["Oldest", "Middle", "Newest"])
    }

    @Test("Sort by createdAt descending puts newest first")
    func sortByCreatedAtDesc() throws {
        let service = try makeFilterService()

        let cal = Calendar.current
        let now = Date()
        let oldest = makeServiceTask(
            title: "Oldest",
            createdAt: cal.date(byAdding: .day, value: -2, to: now)!
        )
        let middle = makeServiceTask(
            title: "Middle",
            createdAt: cal.date(byAdding: .day, value: -1, to: now)!
        )
        let newest = makeServiceTask(title: "Newest", createdAt: now)

        var filter = TaskFilter()
        filter.sortBy = .createdAt
        filter.sortAscending = false
        let result = service.apply(filter: filter, to: [oldest, middle, newest])

        #expect(result.map(\.title) == ["Newest", "Middle", "Oldest"])
    }

    @Test("Sort by updatedAt ascending puts least-recently-updated first")
    func sortByUpdatedAtAsc() throws {
        let service = try makeFilterService()

        let cal = Calendar.current
        let now = Date()
        let stale = makeServiceTask(
            title: "Stale",
            updatedAt: cal.date(byAdding: .day, value: -3, to: now)!
        )
        let recent = makeServiceTask(
            title: "Recent",
            updatedAt: cal.date(byAdding: .hour, value: -1, to: now)!
        )
        let fresh = makeServiceTask(title: "Fresh", updatedAt: now)

        var filter = TaskFilter()
        filter.sortBy = .updatedAt
        filter.sortAscending = true
        let result = service.apply(filter: filter, to: [fresh, stale, recent])

        #expect(result.map(\.title) == ["Stale", "Recent", "Fresh"])
    }

    @Test("Sort by updatedAt descending puts most-recently-updated first")
    func sortByUpdatedAtDesc() throws {
        let service = try makeFilterService()

        let cal = Calendar.current
        let now = Date()
        let stale = makeServiceTask(
            title: "Stale",
            updatedAt: cal.date(byAdding: .day, value: -3, to: now)!
        )
        let recent = makeServiceTask(
            title: "Recent",
            updatedAt: cal.date(byAdding: .hour, value: -1, to: now)!
        )
        let fresh = makeServiceTask(title: "Fresh", updatedAt: now)

        var filter = TaskFilter()
        filter.sortBy = .updatedAt
        filter.sortAscending = false
        let result = service.apply(filter: filter, to: [stale, recent, fresh])

        #expect(result.map(\.title) == ["Fresh", "Recent", "Stale"])
    }

    @Test("Sort by dueDate descending puts latest date first, nil last")
    func sortByDueDateDescNilLast() throws {
        let service = try makeFilterService()

        let cal = Calendar.current
        let now = Date()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!

        let noDue = makeServiceTask(title: "No Due", dueTime: nil)
        let dueNow = makeServiceTask(title: "Due Now", dueTime: now)
        let dueTomorrow = makeServiceTask(title: "Due Tomorrow", dueTime: tomorrow)

        var filter = TaskFilter()
        filter.sortBy = .dueDate
        filter.sortAscending = false
        let result = service.apply(filter: filter, to: [noDue, dueNow, dueTomorrow])

        // Descending: nil uses distantPast (smallest), so nil sorts LAST
        // Latest date (tomorrow) → now → nil (distantPast)
        #expect(result[0].title == "Due Tomorrow")
        #expect(result[1].title == "Due Now")
        #expect(result[2].title == "No Due")
    }

    @Test("Sort by priority ascending puts lowest numeric value first")
    func sortByPriorityAsc() throws {
        let service = try makeFilterService()

        let high = makeServiceTask(title: "High", priority: 3)
        let med = makeServiceTask(title: "Med", priority: 2)
        let low = makeServiceTask(title: "Low", priority: 1)

        var filter = TaskFilter()
        filter.sortBy = .priority
        filter.sortAscending = true
        let result = service.apply(filter: filter, to: [high, med, low])

        #expect(result.map(\.title) == ["Low", "Med", "High"])
    }
}

// MARK: - Tag Filter Edge Cases

@Suite("TaskFilterService — Tag Filter Edge Cases", .serialized)
@MainActor
struct TaskFilterServiceTagEdgeCaseTests {

    @Test("Tag filter with no tasks having the selected tag returns empty")
    func tagFilterNoMatchReturnsEmpty() throws {
        let service = try makeFilterService()

        let t1 = makeServiceTask(title: "Work", tags: ["work"])
        let t2 = makeServiceTask(title: "Other", tags: ["other"])

        var filter = TaskFilter()
        filter.selectedTagIds = ["personal"]
        let result = service.apply(filter: filter, to: [t1, t2])

        #expect(result.isEmpty)
    }

    @Test("Tag filter uses OR logic across multiple selected tags")
    func tagFilterOrLogic() throws {
        let service = try makeFilterService()

        let work = makeServiceTask(title: "Work Only", tags: ["work"])
        let personal = makeServiceTask(title: "Personal Only", tags: ["personal"])
        let both = makeServiceTask(title: "Both", tags: ["work", "personal"])
        let neither = makeServiceTask(title: "Neither", tags: ["other"])

        var filter = TaskFilter()
        filter.selectedTagIds = ["work", "personal"]
        let result = service.apply(filter: filter, to: [work, personal, both, neither])

        #expect(result.count == 3)
        let titles = result.map(\.title)
        #expect(titles.contains("Work Only"))
        #expect(titles.contains("Personal Only"))
        #expect(titles.contains("Both"))
        #expect(!titles.contains("Neither"))
    }

    @Test("Task with empty tags array is excluded by tag filter")
    func taskWithNoTagsExcluded() throws {
        let service = try makeFilterService()

        let tagged = makeServiceTask(title: "Tagged", tags: ["work"])
        let untagged = makeServiceTask(title: "Untagged", tags: [])

        var filter = TaskFilter()
        filter.selectedTagIds = ["work"]
        let result = service.apply(filter: filter, to: [tagged, untagged])

        #expect(result.count == 1)
        #expect(result[0].title == "Tagged")
    }
}
