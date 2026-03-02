//
//  DataImportServiceTests.swift
//  DequeueTests
//
//  Integration tests for DataImportService and additional parser edge cases.
//  See also: DataImportTests.swift for core parser unit tests.
//

import Testing
import Foundation
import SwiftData
@testable import Dequeue

// MARK: - Test Container

private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Tag.self,
        Attachment.self,
        Arc.self,
        Device.self,
        SyncConflict.self,
        configurations: config
    )
}

// MARK: - CSV Parser Edge Cases

@Suite("CSV Parser Edge Cases")
@MainActor
struct CSVParserEdgeCaseTests {

    @Test("Parse CSV with 'task' column alias")
    func taskColumnAlias() throws {
        let csv = """
        task,notes
        Do laundry,Use cold water
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Do laundry")
        #expect(tasks[0].description == "Use cold water")
    }

    @Test("Parse CSV with 'deadline' date alias")
    func deadlineAlias() throws {
        let csv = """
        title,deadline
        Task,2026-03-20
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].dueDate != nil)
    }

    @Test("Parse CSV with 'state' status alias")
    func stateAlias() throws {
        let csv = """
        title,state
        Active,in_progress
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].status == "in_progress")
    }

    @Test("Parse CSV with 'labels' tags alias")
    func labelsAlias() throws {
        let csv = """
        title,labels
        Task A,bug;critical
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].tags == ["bug", "critical"])
    }

    @Test("Parse CSV with 'details' description alias")
    func detailsAlias() throws {
        let csv = """
        title,details
        Task,Some details here
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].description == "Some details here")
    }

    @Test("Empty description not stored")
    func emptyDescription() throws {
        let csv = """
        title,description
        Task,
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].description == nil)
    }

    @Test("Empty tags not stored")
    func emptyTags() throws {
        let csv = """
        title,tags
        Task,
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].tags.isEmpty)
    }

    @Test("Rows with empty title are skipped")
    func skipEmptyTitles() throws {
        let csv = """
        title,description
        ,Only description
        Real task,Has both
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Real task")
    }

    @Test("Case-insensitive headers")
    func caseInsensitiveHeaders() throws {
        let csv = """
        Title,DESCRIPTION,Priority
        Task A,Notes,high
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].title == "Task A")
        #expect(tasks[0].description == "Notes")
        #expect(tasks[0].priority == 3)
    }
}

// MARK: - JSON Parser Edge Cases

@Suite("JSON Parser Edge Cases")
@MainActor
struct JSONParserEdgeCaseTests {

    @Test("Parse with 'task' field alias")
    func taskAlias() throws {
        let json = """
        [{"task": "Task field"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].title == "Task field")
    }

    @Test("Parse with 'content' field alias")
    func contentAlias() throws {
        let json = """
        [{"content": "Content field"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].title == "Content field")
    }

    @Test("Parse with 'notes' description alias")
    func notesAlias() throws {
        let json = """
        [{"title": "Task", "notes": "Extra info"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].description == "Extra info")
    }

    @Test("Integer priority clamped to 0-3")
    func intPriorityClamped() throws {
        let json = """
        [
            {"title": "T1", "priority": 5},
            {"title": "T2", "priority": -1}
        ]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].priority == 3)
        #expect(tasks[1].priority == 0)
    }

    @Test("Parse 'due' alias")
    func dueAlias() throws {
        let json = """
        [{"title": "Task", "due": "2026-03-15"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].dueDate != nil)
    }

    @Test("Parse 'deadline' alias")
    func deadlineAlias() throws {
        let json = """
        [{"title": "Task", "deadline": "2026-03-15"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].dueDate != nil)
    }

    @Test("Parse 'labels' alias for tags")
    func labelsAlias() throws {
        let json = """
        [{"title": "Task", "labels": ["bug", "p1"]}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].tags == ["bug", "p1"])
    }

    @Test("Parse 'state' alias for status")
    func stateAlias() throws {
        let json = """
        [{"title": "Task", "state": "blocked"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].status == "blocked")
    }

    @Test("Throw on empty title")
    func emptyTitle() {
        let json = """
        [{"title": ""}]
        """
        #expect(throws: ImportError.self) {
            try JSONTaskParser.parse(json)
        }
    }

    @Test("Throw on invalid JSON structure (plain string)")
    func invalidStructure() {
        #expect(throws: (any Error).self) {
            try JSONTaskParser.parse("\"just a string\"")
        }
    }
}

// MARK: - Plain Text Parser Edge Cases

@Suite("Plain Text Parser Edge Cases")
@MainActor
struct PlainTextParserEdgeCaseTests {

    @Test("Strip unicode checkbox prefixes")
    func unicodeCheckboxes() {
        let text = """
        □ Unchecked box
        ☐ Another unchecked
        """
        let tasks = PlainTextParser.parse(text)
        #expect(tasks[0].title == "Unchecked box")
        #expect(tasks[1].title == "Another unchecked")
    }

    @Test("Uppercase [X] marks completed")
    func uppercaseCheckbox() {
        let tasks = PlainTextParser.parse("[X] Done task")
        #expect(tasks[0].status == "completed")
        #expect(tasks[0].title == "Done task")
    }

    @Test("Whitespace-only lines are skipped")
    func whitespaceOnlyLines() {
        let text = "  \n   \n  Task  \n  "
        let tasks = PlainTextParser.parse(text)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Task")
    }

    @Test("Tags are always empty for plain text")
    func noTags() {
        let tasks = PlainTextParser.parse("Task with #tag")
        #expect(tasks[0].tags.isEmpty)
    }

    @Test("Multi-digit numbered list")
    func multiDigitNumbers() {
        let tasks = PlainTextParser.parse("10. Tenth task")
        #expect(tasks[0].title == "Tenth task")
    }
}

// MARK: - Priority Parser Edge Cases

@Suite("Priority Parser Edge Cases")
@MainActor
struct PriorityParserEdgeCaseTests {

    @Test("'med' alias")
    func medAlias() {
        #expect(parsePriority("med") == 2)
    }

    @Test("Case insensitive")
    func caseInsensitive() {
        #expect(parsePriority("HIGH") == 3)
        #expect(parsePriority("Low") == 1)
        #expect(parsePriority("MEDIUM") == 2)
    }

    @Test("Whitespace trimmed")
    func whitespaceTrimmed() {
        #expect(parsePriority("  high  ") == 3)
        #expect(parsePriority(" 2 ") == 2)
    }

    @Test("Unknown string returns nil")
    func unknownString() {
        #expect(parsePriority("asap") == nil)
        #expect(parsePriority("critical") == nil)
    }

    @Test("'0' returns nil")
    func zeroReturnsNil() {
        #expect(parsePriority("0") == nil)
    }
}

// MARK: - Date Parser Edge Cases

@Suite("Date Parser Edge Cases")
@MainActor
struct DateParserEdgeCaseTests {

    @Test("ISO 8601 with timezone")
    func iso8601() {
        #expect(parseDate("2026-03-15T10:30:00Z") != nil)
    }

    @Test("d MMM yyyy format")
    func dMmmYyyy() {
        #expect(parseDate("15 Mar 2026") != nil)
    }

    @Test("yyyy-MM-dd HH:mm format")
    func dateWithTime() {
        #expect(parseDate("2026-03-15 14:30") != nil)
    }

    @Test("MMMM d, yyyy format")
    func fullMonthName() {
        #expect(parseDate("March 15, 2026") != nil)
    }

    @Test("Invalid date returns nil")
    func invalidDate() {
        #expect(parseDate("not-a-date") == nil)
        #expect(parseDate("abc123") == nil)
    }

    @Test("Whitespace-only returns nil")
    func whitespaceOnly() {
        #expect(parseDate("   ") == nil)
    }
}

// MARK: - DataImportService Integration Tests

@Suite("DataImportService", .serialized)
@MainActor
struct DataImportServiceIntegrationTests {

    @Test("Import CSV tasks into stack")
    func importCSV() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let csv = """
        title,priority,tags
        Buy milk,high,groceries;food
        Fix bug,medium,dev
        """

        let result = try await service.importTasks(
            content: csv, format: .csv, targetStack: stack
        )

        #expect(result.imported == 2)
        #expect(result.errors.isEmpty)
        #expect(result.isSuccess)

        // Verify persisted field values
        let descriptor = FetchDescriptor<QueueTask>()
        let tasks = try context.fetch(descriptor)
        let byTitle = Dictionary(uniqueKeysWithValues: tasks.map { ($0.title, $0) })
        #expect(byTitle["Buy milk"]?.priority == 3)       // "high" → 3
        #expect(byTitle["Buy milk"]?.tags.contains("groceries") == true)
        #expect(byTitle["Fix bug"]?.priority == 2)        // "medium" → 2
    }

    @Test("Import JSON tasks into stack")
    func importJSON() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let json = """
        [
            {"title": "Task 1", "priority": 3, "tags": ["work"]},
            {"title": "Task 2", "status": "completed"}
        ]
        """

        let result = try await service.importTasks(
            content: json, format: .json, targetStack: stack
        )

        #expect(result.imported == 2)
        #expect(result.isSuccess)
    }

    @Test("Import plain text tasks into stack")
    func importPlainText() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let text = """
        - Buy groceries
        - Fix the gate
        - [x] Already done
        """

        let result = try await service.importTasks(
            content: text, format: .plainText, targetStack: stack
        )

        #expect(result.imported == 3)
        #expect(result.isSuccess)
    }

    @Test("Skip completed tasks when requested")
    func skipCompleted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let csv = """
        title,status
        Active task,pending
        Done task,completed
        Closed task,closed
        """

        let result = try await service.importTasks(
            content: csv, format: .csv, targetStack: stack,
            skipCompleted: true
        )

        #expect(result.imported == 1)
        #expect(result.skipped == 2)
    }

    @Test("Throw on empty parsed result")
    func emptyResult() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        await #expect(throws: ImportError.self) {
            try await service.importTasks(
                content: "", format: .plainText, targetStack: stack
            )
        }
    }

    @Test("Imported tasks get sequential sort orders")
    func sortOrders() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        _ = try await service.importTasks(
            content: "First\nSecond\nThird",
            format: .plainText, targetStack: stack
        )

        let descriptor = FetchDescriptor<QueueTask>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let tasks = try context.fetch(descriptor)
        #expect(tasks.count == 3)
        #expect(tasks[0].sortOrder < tasks[1].sortOrder)
        #expect(tasks[1].sortOrder < tasks[2].sortOrder)

        // Verify sort order matches input order
        #expect(tasks[0].title == "First")
        #expect(tasks[1].title == "Second")
        #expect(tasks[2].title == "Third")
    }

    @Test("Import creates events for each task")
    func createsEvents() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        _ = try await service.importTasks(
            content: "Task 1\nTask 2", format: .plainText, targetStack: stack
        )

        let descriptor = FetchDescriptor<Event>()
        let events = try context.fetch(descriptor)
        let taskCreatedEvents = events.filter { $0.eventType == .taskCreated }
        #expect(taskCreatedEvents.count == 2, "Expected exactly 2 task.created events")
    }

    @Test("Import maps status values correctly")
    func statusMapping() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let json = """
        [
            {"title": "Pending", "status": "pending"},
            {"title": "Done", "status": "done"},
            {"title": "Blocked", "status": "waiting"},
            {"title": "Closed", "status": "cancelled"},
            {"title": "Unknown", "status": "something"}
        ]
        """

        let result = try await service.importTasks(
            content: json, format: .json, targetStack: stack
        )
        #expect(result.imported == 5)

        // Look up tasks by title for resilience against sort order changes
        let descriptor = FetchDescriptor<QueueTask>()
        let tasks = try context.fetch(descriptor)
        let byTitle = Dictionary(uniqueKeysWithValues: tasks.map { ($0.title, $0) })

        #expect(byTitle["Pending"]?.status == .pending)
        #expect(byTitle["Done"]?.status == .completed)     // "done" → completed
        #expect(byTitle["Blocked"]?.status == .blocked)    // "waiting" → blocked
        #expect(byTitle["Closed"]?.status == .closed)      // "cancelled" → closed
        #expect(byTitle["Unknown"]?.status == .pending)    // unknown → pending (default)
    }

    @Test("Skip completed includes 'done' and 'closed' variants")
    func skipCompletedVariants() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let json = """
        [
            {"title": "Active", "status": "pending"},
            {"title": "Done", "status": "done"},
            {"title": "Closed", "status": "closed"}
        ]
        """

        let result = try await service.importTasks(
            content: json, format: .json, targetStack: stack,
            skipCompleted: true
        )

        #expect(result.imported == 1)
        #expect(result.skipped == 2)
    }

    @Test("CSV import persists field values through full pipeline")
    func csvFieldsPersistThroughPipeline() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Import Target")
        context.insert(stack)
        try context.save()

        let service = DataImportService(
            modelContext: context, userId: "test", deviceId: "test"
        )

        let csv = """
        title,description,priority,tags,due
        Ship feature,Update the widget,high,frontend;release,2026-06-15
        """

        let result = try await service.importTasks(
            content: csv, format: .csv, targetStack: stack
        )
        #expect(result.imported == 1)

        let descriptor = FetchDescriptor<QueueTask>()
        let tasks = try context.fetch(descriptor)
        let task = try #require(tasks.first)

        #expect(task.title == "Ship feature")
        #expect(task.taskDescription == "Update the widget")
        #expect(task.priority == 3)      // "high" → 3
        #expect(task.dueTime != nil)     // due date parsed
        #expect(task.status == .pending) // default status
        #expect(task.stack?.id == stack.id)

        // Verify tags were persisted
        #expect(task.tags.sorted() == ["frontend", "release"])
    }
}
