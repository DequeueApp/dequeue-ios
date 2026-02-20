//
//  StackCreationUITests.swift
//  DequeueUITests
//
//  UI tests for stack creation flow (DEQ-37)
//

import XCTest

@MainActor
final class StackCreationUITests: XCTestCase {
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

    // MARK: - Basic Stack Creation

    func testCreateStackWithTitleOnly() throws {
        // Navigate to Stacks tab
        app.tabBars.buttons["Stacks"].tap()

        // Tap add stack button
        let addButton = app.buttons["addStackButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))
        addButton.tap()

        // Verify stack editor sheet appeared
        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))

        // Enter title
        titleField.tap()
        titleField.typeText("Test Stack")

        // Verify Create button is enabled
        let createButton = app.buttons["createButton"]
        XCTAssertTrue(createButton.isEnabled)

        // Create stack
        createButton.tap()

        // Verify sheet dismissed (title field should not exist)
        XCTAssertFalse(titleField.exists)

        // Verify stack appears in list
        let stackCell = app.staticTexts["Test Stack"]
        XCTAssertTrue(stackCell.waitForExistence(timeout: 3))
    }

    func testCreateStackWithTitleAndDescription() throws {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Planning Project")

        let descriptionField = app.textFields["stackDescriptionField"]
        descriptionField.tap()
        descriptionField.typeText("Project planning for Q1 goals")

        app.buttons["createButton"].tap()

        // Verify stack created
        XCTAssertTrue(app.staticTexts["Planning Project"].waitForExistence(timeout: 3))
    }

    func testCreateStackAsActive() throws {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Active Stack Test")

        // Enable "Set as Active Stack" toggle
        let activeToggle = app.switches["setAsActiveToggle"]
        XCTAssertTrue(activeToggle.exists)
        XCTAssertEqual(activeToggle.value as? String, "0")
        activeToggle.tap()
        XCTAssertEqual(activeToggle.value as? String, "1")

        app.buttons["createButton"].tap()

        // Verify stack created
        XCTAssertTrue(app.staticTexts["Active Stack Test"].waitForExistence(timeout: 3))

        // TODO: Verify stack is actually active (check banner or indicator)
    }

    // MARK: - Stack Creation with Dates

    func testCreateStackWithStartDate() throws {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Dated Stack")

        // Tap start date picker
        let startDatePicker = app.datePickers["startDatePicker"]
        XCTAssertTrue(startDatePicker.exists)
        // Note: DatePicker interaction in UI tests is complex and varies by iOS version
        // This test verifies the picker exists - full date selection would require
        // more sophisticated interaction based on iOS version

        app.buttons["createButton"].tap()
        XCTAssertTrue(app.staticTexts["Dated Stack"].waitForExistence(timeout: 3))
    }

    func testCreateStackWithDueDate() throws {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Due Date Stack")

        // Verify due date picker exists
        let dueDatePicker = app.datePickers["dueDatePicker"]
        XCTAssertTrue(dueDatePicker.exists)

        app.buttons["createButton"].tap()
        XCTAssertTrue(app.staticTexts["Due Date Stack"].waitForExistence(timeout: 3))
    }

    // MARK: - Stack Creation with Tasks

    func testCreateStackWithTasks() throws {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Stack with Tasks")

        // Verify tasks section exists
        XCTAssertTrue(app.otherElements["tasksSection"].exists)

        // Verify "No Tasks" label is shown initially
        XCTAssertTrue(app.otherElements["noTasksLabel"].exists)

        // Tap add task button
        let addTaskButton = app.buttons["addTaskButton"]
        XCTAssertTrue(addTaskButton.exists)
        addTaskButton.tap()

        // Add task sheet should appear
        // Note: This requires AddTaskSheet to have accessibility identifiers
        // For now, just verify the button works
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 1))

        // Create stack
        app.buttons["createButton"].tap()
        XCTAssertTrue(app.staticTexts["Stack with Tasks"].waitForExistence(timeout: 3))
    }

    // MARK: - Stack Creation Validation

    func testCreateButtonDisabledWithoutTitle() throws {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))

        // Verify Create button is disabled when title is empty
        let createButton = app.buttons["createButton"]
        XCTAssertFalse(createButton.isEnabled)

        // Type title
        titleField.tap()
        titleField.typeText("Test")

        // Verify Create button is now enabled
        XCTAssertTrue(createButton.isEnabled)
    }

    func testCancelStackCreation() throws {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))

        // Enter title
        titleField.tap()
        titleField.typeText("Cancel Test")

        // Tap cancel
        let cancelButton = app.buttons["cancelButton"]
        XCTAssertTrue(cancelButton.exists)
        cancelButton.tap()

        // Verify sheet dismissed
        XCTAssertFalse(titleField.waitForExistence(timeout: 2))

        // Verify stack was NOT created
        XCTAssertFalse(app.staticTexts["Cancel Test"].exists)
    }

    // MARK: - Stack Creation with Arc

    func testArcSelectionButtonExists() throws {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))

        // Verify arc selection button exists
        let arcButton = app.buttons["arcSelectionButton"]
        XCTAssertTrue(arcButton.exists)

        // Tap arc selection button
        arcButton.tap()

        // Arc picker sheet should appear
        // Note: Arc picker would need its own accessibility identifiers for full testing
        XCTAssertTrue(arcButton.waitForExistence(timeout: 1))
    }

    // MARK: - Stack Creation with Tags

    func testTagsInputExists() throws {
        app.tabBars.buttons["Stacks"].tap()
        app.buttons["addStackButton"].tap()

        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))

        // Verify tags input view exists
        XCTAssertTrue(app.otherElements["tagsInputView"].exists)

        // Note: Full tag interaction testing would require TagInputView
        // to have accessibility identifiers for tag chips and input field
    }

    // MARK: - Multiple Stacks Creation

    func testCreateMultipleStacks() throws {
        app.tabBars.buttons["Stacks"].tap()

        // Create first stack
        app.buttons["addStackButton"].tap()
        let titleField = app.textFields["stackTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("First Stack")
        app.buttons["createButton"].tap()

        // Wait for sheet to dismiss
        XCTAssertFalse(titleField.waitForExistence(timeout: 2))

        // Create second stack
        app.buttons["addStackButton"].tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Second Stack")
        app.buttons["createButton"].tap()

        // Verify both stacks exist
        XCTAssertTrue(app.staticTexts["First Stack"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Second Stack"].waitForExistence(timeout: 3))
    }

    // MARK: - Stack Creation Performance

    func testStackCreationPerformance() throws {
        app.tabBars.buttons["Stacks"].tap()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            app.buttons["addStackButton"].tap()

            let titleField = app.textFields["stackTitleField"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 2))
            titleField.tap()
            titleField.typeText("Performance Test")

            app.buttons["createButton"].tap()

            // Wait for stack to appear
            XCTAssertTrue(app.staticTexts["Performance Test"].waitForExistence(timeout: 5))
        }
    }
}
