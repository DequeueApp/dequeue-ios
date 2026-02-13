//
//  TaskCreationUITests.swift
//  DequeueUITests
//
//  UI tests for task creation flow (DEQ-38)
//

import XCTest

@MainActor
final class TaskCreationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDown() async throws {
        app = nil
    }

    // MARK: - Test Helpers

    /// Creates a test stack to add tasks to
    private func createTestStack(named stackName: String = "Test Stack") {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText(stackName)

        app.buttons["createButton"].tap()
        XCTAssertFalse(titleField.waitForExistence(timeout: 2))
    }

    /// Opens a stack by tapping its name
    private func openStack(named stackName: String) {
        let stackCell = app.staticTexts[stackName]
        XCTAssertTrue(stackCell.waitForExistence(timeout: 3))
        stackCell.tap()
    }

    // MARK: - Basic Task Creation

    func testCreateTaskWithTitleOnly() throws {
        createTestStack()
        openStack(named: "Test Stack")

        // Tap add task button
        let addTaskButton = app.buttons["addTaskButton"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 2))
        addTaskButton.tap()

        // Verify AddTaskSheet appeared
        let taskTitleField = app.textFields["taskTitleField"]
        XCTAssertTrue(taskTitleField.waitForExistence(timeout: 2))

        // Enter task title
        taskTitleField.tap()
        taskTitleField.typeText("Buy groceries")

        // Verify Add button is enabled
        let addButton = app.buttons["addTaskSaveButton"]
        XCTAssertTrue(addButton.isEnabled)

        // Save task
        addButton.tap()

        // Verify sheet dismissed
        XCTAssertFalse(taskTitleField.waitForExistence(timeout: 2))

        // Verify task appears in stack
        let taskCell = app.staticTexts["Buy groceries"]
        XCTAssertTrue(taskCell.waitForExistence(timeout: 3))
    }

    func testCreateTaskWithTitleAndDescription() throws {
        createTestStack(named: "Project Stack")
        openStack(named: "Project Stack")

        app.buttons["addTaskButton"].tap()

        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Review code")

        let descriptionField = app.textFields["taskDescriptionField"]
        descriptionField.tap()
        descriptionField.typeText("Review PR #123 for new feature")

        app.buttons["addTaskSaveButton"].tap()

        // Verify task created
        XCTAssertTrue(app.staticTexts["Review code"].waitForExistence(timeout: 3))
    }

    // MARK: - Task Creation with Dates

    func testCreateTaskWithStartDate() throws {
        createTestStack()
        openStack(named: "Test Stack")

        app.buttons["addTaskButton"].tap()

        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Scheduled Task")

        // Verify start date picker exists
        let startDatePicker = app.datePickers["taskStartDatePicker"]
        XCTAssertTrue(startDatePicker.exists)
        // Note: DatePicker interaction in UI tests is complex
        // This test verifies the picker exists

        app.buttons["addTaskSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["Scheduled Task"].waitForExistence(timeout: 3))
    }

    func testCreateTaskWithDueDate() throws {
        createTestStack()
        openStack(named: "Test Stack")

        app.buttons["addTaskButton"].tap()

        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Task with Deadline")

        // Verify due date picker exists
        let dueDatePicker = app.datePickers["taskDueDatePicker"]
        XCTAssertTrue(dueDatePicker.exists)

        app.buttons["addTaskSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["Task with Deadline"].waitForExistence(timeout: 3))
    }

    func testCreateTaskWithBothDates() throws {
        createTestStack()
        openStack(named: "Test Stack")

        app.buttons["addTaskButton"].tap()

        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Full Schedule Task")

        // Verify both date pickers exist
        XCTAssertTrue(app.datePickers["taskStartDatePicker"].exists)
        XCTAssertTrue(app.datePickers["taskDueDatePicker"].exists)

        app.buttons["addTaskSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["Full Schedule Task"].waitForExistence(timeout: 3))
    }

    // MARK: - Task Creation Validation

    func testAddButtonDisabledWithoutTitle() throws {
        createTestStack()
        openStack(named: "Test Stack")

        app.buttons["addTaskButton"].tap()

        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))

        // Verify Add button is disabled when title is empty
        let addButton = app.buttons["addTaskSaveButton"]
        XCTAssertFalse(addButton.isEnabled)

        // Type title
        titleField.tap()
        titleField.typeText("Test")

        // Verify Add button is now enabled
        XCTAssertTrue(addButton.isEnabled)
    }

    func testCancelTaskCreation() throws {
        createTestStack()
        openStack(named: "Test Stack")

        app.buttons["addTaskButton"].tap()

        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))

        // Enter title
        titleField.tap()
        titleField.typeText("Cancel Test Task")

        // Tap cancel
        let cancelButton = app.buttons["addTaskCancelButton"]
        XCTAssertTrue(cancelButton.exists)
        cancelButton.tap()

        // Verify sheet dismissed
        XCTAssertFalse(titleField.waitForExistence(timeout: 2))

        // Verify task was NOT created
        XCTAssertFalse(app.staticTexts["Cancel Test Task"].exists)
    }

    // MARK: - Multiple Tasks Creation

    func testCreateMultipleTasks() throws {
        createTestStack(named: "Multi-Task Stack")
        openStack(named: "Multi-Task Stack")

        // Create first task
        app.buttons["addTaskButton"].tap()
        var titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("First Task")
        app.buttons["addTaskSaveButton"].tap()
        XCTAssertFalse(titleField.waitForExistence(timeout: 2))

        // Create second task
        app.buttons["addTaskButton"].tap()
        titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Second Task")
        app.buttons["addTaskSaveButton"].tap()
        XCTAssertFalse(titleField.waitForExistence(timeout: 2))

        // Create third task
        app.buttons["addTaskButton"].tap()
        titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Third Task")
        app.buttons["addTaskSaveButton"].tap()

        // Verify all three tasks exist
        XCTAssertTrue(app.staticTexts["First Task"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Second Task"].exists)
        XCTAssertTrue(app.staticTexts["Third Task"].exists)
    }

    func testCreateTasksInMultipleStacks() throws {
        // Create first stack with task
        createTestStack(named: "Stack One")
        openStack(named: "Stack One")
        app.buttons["addTaskButton"].tap()
        var titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Task in Stack One")
        app.buttons["addTaskSaveButton"].tap()

        // Go back to stacks list
        app.buttons["Close"].tap()

        // Create second stack with task
        app.buttons["addStackButton"].tap()
        var stackTitleField = app.textFields["stackTitleField"]
        XCTAssertTrue(stackTitleField.waitForExistence(timeout: 2))
        stackTitleField.tap()
        stackTitleField.typeText("Stack Two")
        app.buttons["createButton"].tap()

        openStack(named: "Stack Two")
        app.buttons["addTaskButton"].tap()
        titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Task in Stack Two")
        app.buttons["addTaskSaveButton"].tap()

        // Verify task in Stack Two
        XCTAssertTrue(app.staticTexts["Task in Stack Two"].waitForExistence(timeout: 3))

        // Go back and verify task in Stack One still exists
        app.buttons["Close"].tap()
        openStack(named: "Stack One")
        XCTAssertTrue(app.staticTexts["Task in Stack One"].waitForExistence(timeout: 3))
    }

    // MARK: - Task Creation During Stack Creation

    func testCreateTaskDuringStackCreation() throws {
        // This tests the create mode flow where tasks can be added before publishing
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let stackTitleField = app.textFields["stackTitleField"]
        XCTAssertTrue(stackTitleField.waitForExistence(timeout: 2))
        stackTitleField.tap()
        stackTitleField.typeText("Stack with Pending Tasks")

        // Verify tasks section exists in create mode
        XCTAssertTrue(app.otherElements["tasksSection"].exists)

        // Add task button should be available in create mode
        let addTaskButton = app.buttons["addTaskButton"]
        XCTAssertTrue(addTaskButton.exists)
        addTaskButton.tap()

        // Add task sheet should appear
        let taskTitleField = app.textFields["taskTitleField"]
        if taskTitleField.waitForExistence(timeout: 2) {
            taskTitleField.tap()
            taskTitleField.typeText("Pending Task")
            app.buttons["addTaskSaveButton"].tap()
        }

        // Create/publish the stack
        app.buttons["createButton"].tap()

        // Verify stack was created
        XCTAssertTrue(app.staticTexts["Stack with Pending Tasks"].waitForExistence(timeout: 3))
    }

    // MARK: - Task Creation with Description Field Interaction

    func testDescriptionFieldMultiLine() throws {
        createTestStack()
        openStack(named: "Test Stack")

        app.buttons["addTaskButton"].tap()

        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Multi-line Description")

        let descriptionField = app.textFields["taskDescriptionField"]
        descriptionField.tap()
        // Note: Testing multi-line input in UI tests is limited
        // This verifies the field accepts input
        descriptionField.typeText("Line 1\nLine 2\nLine 3")

        app.buttons["addTaskSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["Multi-line Description"].waitForExistence(timeout: 3))
    }

    // MARK: - Task Creation Performance

    func testTaskCreationPerformance() throws {
        createTestStack()
        openStack(named: "Test Stack")

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            app.buttons["addTaskButton"].tap()

            let titleField = app.textFields["taskTitleField"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 2))
            titleField.tap()
            titleField.typeText("Performance Test Task")

            app.buttons["addTaskSaveButton"].tap()

            // Wait for task to appear
            XCTAssertTrue(app.staticTexts["Performance Test Task"].waitForExistence(timeout: 5))
        }
    }

    // MARK: - Navigation Flow Tests

    func testAddTaskButtonAccessibility() throws {
        createTestStack()
        openStack(named: "Test Stack")

        // Verify add task button exists and is accessible
        let addTaskButton = app.buttons["addTaskButton"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 2))
        XCTAssertTrue(addTaskButton.isEnabled)
        XCTAssertTrue(addTaskButton.isHittable)
    }
}
