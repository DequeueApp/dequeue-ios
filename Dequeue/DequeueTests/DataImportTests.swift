//
//  DataImportTests.swift
//  DequeueTests
//
//  Tests for data import parsers and format handling.
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - ImportFormat Tests

@Suite("ImportFormat")
struct ImportFormatTests {

    @Test("All formats have extensions")
    func formatsHaveExtensions() {
        for format in ImportFormat.allCases {
            #expect(!format.fileExtension.isEmpty)
        }
    }

    @Test("All formats have descriptions")
    func formatsHaveDescriptions() {
        for format in ImportFormat.allCases {
            #expect(!format.description.isEmpty)
        }
    }

    @Test("Format count is 3")
    func formatCount() {
        #expect(ImportFormat.allCases.count == 3)
    }
}

// MARK: - CSV Parser Tests

@Suite("CSV Parser")
struct CSVParserTests {

    @Test("Basic CSV with title column")
    func basicCSV() throws {
        let csv = """
        title,description,priority
        Buy groceries,Get milk and eggs,2
        Call dentist,,1
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks.count == 2)
        #expect(tasks[0].title == "Buy groceries")
        #expect(tasks[0].description == "Get milk and eggs")
        #expect(tasks[0].priority == 2)
        #expect(tasks[1].title == "Call dentist")
        #expect(tasks[1].description == nil)
        #expect(tasks[1].priority == 1)
    }

    @Test("CSV with name column instead of title")
    func csvWithNameColumn() throws {
        let csv = """
        name,notes
        Task one,Some notes
        Task two,
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks.count == 2)
        #expect(tasks[0].title == "Task one")
        #expect(tasks[0].description == "Some notes")
    }

    @Test("CSV with tags")
    func csvWithTags() throws {
        let csv = """
        title,tags
        Task A,work;urgent
        Task B,personal;health
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].tags == ["work", "urgent"])
        #expect(tasks[1].tags == ["personal", "health"])
    }

    @Test("CSV with quoted fields")
    func csvWithQuotedFields() throws {
        let csv = """
        title,description
        "Task with, comma","Description with, comma"
        Normal task,Normal description
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks.count == 2)
        #expect(tasks[0].title == "Task with, comma")
        #expect(tasks[0].description == "Description with, comma")
    }

    @Test("Empty CSV throws error")
    func emptyCSV() throws {
        #expect(throws: ImportError.self) {
            try CSVParser.parse("")
        }
    }

    @Test("CSV without title column throws error")
    func csvNoTitleColumn() throws {
        let csv = """
        priority,status
        1,pending
        """
        #expect(throws: ImportError.self) {
            try CSVParser.parse(csv)
        }
    }

    @Test("CSV with due dates")
    func csvWithDueDates() throws {
        let csv = """
        title,due_date
        Task A,2026-03-15
        Task B,03/20/2026
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].dueDate != nil)
        #expect(tasks[1].dueDate != nil)
    }

    @Test("CSV with status column")
    func csvWithStatus() throws {
        let csv = """
        title,status
        Done task,completed
        Open task,pending
        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks[0].status == "completed")
        #expect(tasks[1].status == "pending")
    }

    @Test("CSV skips empty rows")
    func csvSkipsEmptyRows() throws {
        let csv = """
        title

        Task one

        Task two

        """
        let tasks = try CSVParser.parse(csv)
        #expect(tasks.count == 2)
    }

    @Test("CSV row parser handles basic row")
    func csvRowParser() {
        let fields = CSVParser.parseCSVRow("one,two,three")
        #expect(fields == ["one", "two", "three"])
    }

    @Test("CSV row parser handles quoted commas")
    func csvRowParserQuoted() {
        let fields = CSVParser.parseCSVRow("\"a,b\",c,\"d,e\"")
        #expect(fields == ["a,b", "c", "d,e"])
    }
}

// MARK: - JSON Parser Tests

@Suite("JSON Parser")
struct JSONParserTests {

    @Test("Parse JSON array of tasks")
    func parseJSONArray() throws {
        let json = """
        [
            {"title": "Task 1", "priority": 2},
            {"title": "Task 2", "description": "Details"}
        ]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks.count == 2)
        #expect(tasks[0].title == "Task 1")
        #expect(tasks[0].priority == 2)
        #expect(tasks[1].title == "Task 2")
        #expect(tasks[1].description == "Details")
    }

    @Test("Parse single JSON object")
    func parseSingleJSON() throws {
        let json = """
        {"title": "Solo task", "tags": ["work", "important"]}
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Solo task")
        #expect(tasks[0].tags == ["work", "important"])
    }

    @Test("JSON with name field instead of title")
    func jsonWithNameField() throws {
        let json = """
        [{"name": "Named task"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].title == "Named task")
    }

    @Test("JSON with string priority")
    func jsonWithStringPriority() throws {
        let json = """
        [{"title": "Task", "priority": "high"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].priority == 3)
    }

    @Test("JSON with tags as comma-separated string")
    func jsonWithStringTags() throws {
        let json = """
        [{"title": "Task", "tags": "work, review, urgent"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].tags == ["work", "review", "urgent"])
    }

    @Test("JSON with due_date")
    func jsonWithDueDate() throws {
        let json = """
        [{"title": "Task", "due_date": "2026-03-15"}]
        """
        let tasks = try JSONTaskParser.parse(json)
        #expect(tasks[0].dueDate != nil)
    }

    @Test("Invalid JSON throws error")
    func invalidJSON() throws {
        #expect(throws: Error.self) {
            try JSONTaskParser.parse("not json at all")
        }
    }

    @Test("JSON with missing title throws error")
    func jsonMissingTitle() throws {
        let json = """
        [{"priority": 1}]
        """
        #expect(throws: ImportError.self) {
            try JSONTaskParser.parse(json)
        }
    }
}

// MARK: - Plain Text Parser Tests

@Suite("Plain Text Parser")
struct PlainTextParserTests {

    @Test("Parse simple lines")
    func parseSimpleLines() {
        let text = """
        Buy groceries
        Call dentist
        Fix the bug
        """
        let tasks = PlainTextParser.parse(text)
        #expect(tasks.count == 3)
        #expect(tasks[0].title == "Buy groceries")
        #expect(tasks[1].title == "Call dentist")
    }

    @Test("Parse with dash prefix")
    func parseWithDash() {
        let text = """
        - Task one
        - Task two
        """
        let tasks = PlainTextParser.parse(text)
        #expect(tasks[0].title == "Task one")
        #expect(tasks[1].title == "Task two")
    }

    @Test("Parse with bullet prefix")
    func parseWithBullets() {
        let text = """
        • Task alpha
        * Task beta
        """
        let tasks = PlainTextParser.parse(text)
        #expect(tasks[0].title == "Task alpha")
        #expect(tasks[1].title == "Task beta")
    }

    @Test("Parse with numbered list")
    func parseNumberedList() {
        let text = """
        1. First task
        2. Second task
        3. Third task
        """
        let tasks = PlainTextParser.parse(text)
        #expect(tasks.count == 3)
        #expect(tasks[0].title == "First task")
        #expect(tasks[2].title == "Third task")
    }

    @Test("Parse with checkbox — incomplete")
    func parseCheckboxIncomplete() {
        let text = "[ ] Incomplete task"
        let tasks = PlainTextParser.parse(text)
        #expect(tasks[0].title == "Incomplete task")
        #expect(tasks[0].status == nil)
    }

    @Test("Parse with checkbox — completed")
    func parseCheckboxCompleted() {
        let text = "[x] Completed task"
        let tasks = PlainTextParser.parse(text)
        #expect(tasks[0].title == "Completed task")
        #expect(tasks[0].status == "completed")
    }

    @Test("Skips empty lines")
    func skipsEmptyLines() {
        let text = """
        Task one

        Task two


        Task three
        """
        let tasks = PlainTextParser.parse(text)
        #expect(tasks.count == 3)
    }

    @Test("Empty input returns empty array")
    func emptyInput() {
        let tasks = PlainTextParser.parse("")
        #expect(tasks.isEmpty)
    }
}

// MARK: - Helper Function Tests

@Suite("Import Helpers")
struct ImportHelperTests {

    @Test("Parse priority strings")
    func parsePriorityStrings() {
        #expect(parsePriority("high") == 3)
        #expect(parsePriority("medium") == 2)
        #expect(parsePriority("low") == 1)
        #expect(parsePriority("none") == nil)
        #expect(parsePriority("") == nil)
        #expect(parsePriority("3") == 3)
        #expect(parsePriority("urgent") == 3)
        #expect(parsePriority("p1") == 3)
        #expect(parsePriority("p2") == 2)
        #expect(parsePriority("p3") == 1)
    }

    @Test("Parse date strings")
    func parseDateStrings() {
        #expect(parseDate("2026-03-15") != nil)
        #expect(parseDate("03/15/2026") != nil)
        #expect(parseDate("Mar 15, 2026") != nil)
        #expect(parseDate("") == nil)
        #expect(parseDate("not a date") == nil)
    }

    @Test("Priority clamped to 0-3")
    func priorityClamped() {
        #expect(parsePriority("10") == 3)
        #expect(parsePriority("-1") == 0)
    }
}

// MARK: - ImportResult Tests

@Suite("ImportResult")
struct ImportResultTests {

    @Test("Success result")
    func successResult() {
        let result = ImportResult(
            format: .csv,
            totalParsed: 5,
            imported: 5,
            skipped: 0,
            errors: []
        )
        #expect(result.isSuccess)
        #expect(result.summary == "Imported 5 tasks")
    }

    @Test("Single task result")
    func singleTaskResult() {
        let result = ImportResult(
            format: .json,
            totalParsed: 1,
            imported: 1,
            skipped: 0,
            errors: []
        )
        #expect(result.summary == "Imported 1 task")
    }

    @Test("Partial failure result")
    func partialFailure() {
        let result = ImportResult(
            format: .csv,
            totalParsed: 5,
            imported: 3,
            skipped: 1,
            errors: ["error 1"]
        )
        #expect(result.isSuccess) // Some imported
        #expect(result.summary.contains("3"))
        #expect(result.summary.contains("1 error"))
    }

    @Test("Total failure result")
    func totalFailure() {
        let result = ImportResult(
            format: .csv,
            totalParsed: 5,
            imported: 0,
            skipped: 0,
            errors: ["a", "b", "c", "d", "e"]
        )
        #expect(!result.isSuccess)
    }
}

// MARK: - ImportError Tests

@Suite("ImportError")
struct ImportErrorTests {

    @Test("All errors have descriptions")
    func errorsHaveDescriptions() {
        let errors: [ImportError] = [
            .emptyFile, .missingTitleColumn, .invalidEncoding,
            .invalidJSONStructure, .missingTitle, .noTasksParsed, .fileReadFailed
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
