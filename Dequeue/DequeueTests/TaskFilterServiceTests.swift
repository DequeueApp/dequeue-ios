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

// MARK: - Helpers (scoped to this file)

// Returns (context, service). The ModelContainer is retained implicitly by
// ModelContext.container — callers must NOT hold a separate container reference.
// Holding two explicit refs (container + context) to the same @MainActor object
// causes a double-free SIGTRAP when both go out of scope together (Swift 6 bug,
// rdar://FB15432891). Letting context be the sole strong holder avoids the crash.
@MainActor
private func makeServiceTestSetup() throws -> (ModelContext, TaskFilterService) {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: QueueTask.self, Stack.self, Tag.self, Reminder.self, Arc.self,
        configurations: config
    )
    let context = container.mainContext
    let service = TaskFilterService(modelContext: context)
    return (context, service)
}

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
    updatedAt: Date = Date(),
    in context: ModelContext
) -> QueueTask {
    let task = QueueTask(
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
    context.insert(task)
    return task
}

// MARK: - Priority Filter — All Variants

@Suite("TaskFilterService — Priority Variants", .serialized)
@MainActor
struct TaskFilterServicePriorityTests {

    @Test("Priority filter .low returns only low-priority tasks")
    func priorityLow() throws {
        let (context, service) = try makeServiceTestSetup()

        let low = makeServiceTask(title: "Low", priority: 1, in: context)
        let med = makeServiceTask(title: "Medium", priority: 2, in: context)
        let high = makeServiceTask(title: "High", priority: 3, in: context)

        var filter = TaskFilter()
        filter.priorityFilter = .low
        let result = service.apply(filter: filter, to: [low, med, high])

        #expect(result.count == 1)
        #expect(result[0].title == "Low")
    }

    @Test("Priority filter .medium returns only medium-priority tasks")
    func priorityMedium() throws {
        let (context, service) = try makeServiceTestSetup()

        let low = makeServiceTask(title: "Low", priority: 1, in: context)
        let med = makeServiceTask(title: "Medium", priority: 2, in: context)
        let high = makeServiceTask(title: "High", priority: 3, in: context)

        var filter = TaskFilter()
        filter.priorityFilter = .medium
        let result = service.apply(filter: filter, to: [low, med, high])

        #expect(result.count == 1)
        #expect(result[0].title == "Medium")
    }

    @Test("Priority filter .none returns tasks with priority = 0 or nil (both map to 0)")
    func priorityNoneIsZero() throws {
        let (context, service) = try makeServiceTestSetup()

        let zeroPriority = makeServiceTask(title: "Zero", priority: 0, in: context)
        let nilPriority = makeServiceTask(title: "Nil", priority: nil, in: context)
        let lowPriority = makeServiceTask(title: "Low", priority: 1, in: context)

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
        let (context, service) = try makeServiceTestSetup()

        let low = makeServiceTask(title: "Low", priority: 1, in: context)
        let med = makeServiceTask(title: "Medium", priority: 2, in: context)
        let noPriority = makeServiceTask(title: "None", priority: nil, in: context)

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
        let (context, service) = try makeServiceTestSetup()

        let first = makeServiceTask(title: "First", sortOrder: 0, in: context)
        let second = makeServiceTask(title: "Second", sortOrder: 1, in: context)
        let third = makeServiceTask(title: "Third", sortOrder: 2, in: context)

        var filter = TaskFilter()
        filter.sortBy = .sortOrder
        filter.sortAscending = false
        let result = service.apply(filter: filter, to: [first, second, third])

        #expect(result.map(\.title) == ["Third", "Second", "First"])
    }

    @Test("Sort by createdAt ascending puts oldest first")
    func sortByCreatedAtAsc() throws {
        let (context, service) = try makeServiceTestSetup()

        let cal = Calendar.current
        let now = Date()
        let oldest = makeServiceTask(
            title: "Oldest",
            createdAt: cal.date(byAdding: .day, value: -2, to: now)!,
            in: context
        )
        let middle = makeServiceTask(
            title: "Middle",
            createdAt: cal.date(byAdding: .day, value: -1, to: now)!,
            in: context
        )
        let newest = makeServiceTask(title: "Newest", createdAt: now, in: context)

        var filter = TaskFilter()
        filter.sortBy = .createdAt
        filter.sortAscending = true
        let result = service.apply(filter: filter, to: [newest, oldest, middle])

        #expect(result.map(\.title) == ["Oldest", "Middle", "Newest"])
    }

    @Test("Sort by createdAt descending puts newest first")
    func sortByCreatedAtDesc() throws {
        let (context, service) = try makeServiceTestSetup()

        let cal = Calendar.current
        let now = Date()
        let oldest = makeServiceTask(
            title: "Oldest",
            createdAt: cal.date(byAdding: .day, value: -2, to: now)!,
            in: context
        )
        let middle = makeServiceTask(
            title: "Middle",
            createdAt: cal.date(byAdding: .day, value: -1, to: now)!,
            in: context
        )
        let newest = makeServiceTask(title: "Newest", createdAt: now, in: context)

        var filter = TaskFilter()
        filter.sortBy = .createdAt
        filter.sortAscending = false
        let result = service.apply(filter: filter, to: [oldest, middle, newest])

        #expect(result.map(\.title) == ["Newest", "Middle", "Oldest"])
    }

    @Test("Sort by updatedAt ascending puts least-recently-updated first")
    func sortByUpdatedAtAsc() throws {
        let (context, service) = try makeServiceTestSetup()

        let cal = Calendar.current
        let now = Date()
        let stale = makeServiceTask(
            title: "Stale",
            updatedAt: cal.date(byAdding: .day, value: -3, to: now)!,
            in: context
        )
        let recent = makeServiceTask(
            title: "Recent",
            updatedAt: cal.date(byAdding: .hour, value: -1, to: now)!,
            in: context
        )
        let fresh = makeServiceTask(title: "Fresh", updatedAt: now, in: context)

        var filter = TaskFilter()
        filter.sortBy = .updatedAt
        filter.sortAscending = true
        let result = service.apply(filter: filter, to: [fresh, stale, recent])

        #expect(result.map(\.title) == ["Stale", "Recent", "Fresh"])
    }

    @Test("Sort by updatedAt descending puts most-recently-updated first")
    func sortByUpdatedAtDesc() throws {
        let (context, service) = try makeServiceTestSetup()

        let cal = Calendar.current
        let now = Date()
        let stale = makeServiceTask(
            title: "Stale",
            updatedAt: cal.date(byAdding: .day, value: -3, to: now)!,
            in: context
        )
        let recent = makeServiceTask(
            title: "Recent",
            updatedAt: cal.date(byAdding: .hour, value: -1, to: now)!,
            in: context
        )
        let fresh = makeServiceTask(title: "Fresh", updatedAt: now, in: context)

        var filter = TaskFilter()
        filter.sortBy = .updatedAt
        filter.sortAscending = false
        let result = service.apply(filter: filter, to: [stale, recent, fresh])

        #expect(result.map(\.title) == ["Fresh", "Recent", "Stale"])
    }

    @Test("Sort by dueDate descending puts latest date first, nil last")
    func sortByDueDateDescNilLast() throws {
        let (context, service) = try makeServiceTestSetup()

        let cal = Calendar.current
        let now = Date()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!

        let noDue = makeServiceTask(title: "No Due", dueTime: nil, in: context)
        let dueNow = makeServiceTask(title: "Due Now", dueTime: now, in: context)
        let dueTomorrow = makeServiceTask(title: "Due Tomorrow", dueTime: tomorrow, in: context)

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
        let (context, service) = try makeServiceTestSetup()

        let high = makeServiceTask(title: "High", priority: 3, in: context)
        let med = makeServiceTask(title: "Med", priority: 2, in: context)
        let low = makeServiceTask(title: "Low", priority: 1, in: context)

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
        let (context, service) = try makeServiceTestSetup()

        let t1 = makeServiceTask(title: "Work", tags: ["work"], in: context)
        let t2 = makeServiceTask(title: "Other", tags: ["other"], in: context)

        var filter = TaskFilter()
        filter.selectedTagIds = ["personal"]
        let result = service.apply(filter: filter, to: [t1, t2])

        #expect(result.isEmpty)
    }

    @Test("Tag filter uses OR logic across multiple selected tags")
    func tagFilterOrLogic() throws {
        let (context, service) = try makeServiceTestSetup()

        let work = makeServiceTask(title: "Work Only", tags: ["work"], in: context)
        let personal = makeServiceTask(title: "Personal Only", tags: ["personal"], in: context)
        let both = makeServiceTask(title: "Both", tags: ["work", "personal"], in: context)
        let neither = makeServiceTask(title: "Neither", tags: ["other"], in: context)

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
        let (context, service) = try makeServiceTestSetup()

        let tagged = makeServiceTask(title: "Tagged", tags: ["work"], in: context)
        let untagged = makeServiceTask(title: "Untagged", tags: [], in: context)

        var filter = TaskFilter()
        filter.selectedTagIds = ["work"]
        let result = service.apply(filter: filter, to: [tagged, untagged])

        #expect(result.count == 1)
        #expect(result[0].title == "Tagged")
    }
}
