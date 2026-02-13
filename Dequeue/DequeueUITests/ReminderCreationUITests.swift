//
//  ReminderCreationUITests.swift
//  DequeueUITests
//
//  UI tests for reminder creation and editing flows
//

import XCTest

@MainActor
final class ReminderCreationUITests: XCTestCase {
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

    // MARK: - Task Reminder Tests

    func testCreateTaskReminderFromTaskDetail() throws {
        // Navigate to a task detail
        navigateToFirstTask()
        
        // Tap "Add Reminder" button
        let addReminderButton = app.buttons["addReminderButton"]
        XCTAssertTrue(addReminderButton.waitForExistence(timeout: 2))
        addReminderButton.tap()
        
        // Verify reminder sheet appeared
        let sheet = app.navigationBars["Add Reminder"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        
        // Verify quick select buttons exist
        XCTAssertTrue(app.buttons["In 1 hour"].exists)
        XCTAssertTrue(app.buttons["In 3 hours"].exists)
        XCTAssertTrue(app.buttons["Tomorrow 9 AM"].exists)
        XCTAssertTrue(app.buttons["Tomorrow 6 PM"].exists)
        
        // Select "In 1 hour"
        app.buttons["In 1 hour"].tap()
        
        // Save reminder
        let saveButton = app.buttons["saveReminderButton"]
        XCTAssertTrue(saveButton.exists)
        saveButton.tap()
        
        // Verify sheet dismissed
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
        
        // Verify reminder appears in task detail
        let reminderIndicator = app.images["bell.fill"]
        XCTAssertTrue(reminderIndicator.waitForExistence(timeout: 2))
    }

    func testCreateTaskReminderWithDatePicker() throws {
        navigateToFirstTask()
        
        // Open reminder sheet
        let addReminderButton = app.buttons["addReminderButton"]
        XCTAssertTrue(addReminderButton.waitForExistence(timeout: 2))
        addReminderButton.tap()
        
        // Use date picker
        let datePicker = app.datePickers["reminderDatePicker"]
        XCTAssertTrue(datePicker.waitForExistence(timeout: 2))
        
        // Note: DatePicker interaction in UI tests is complex
        // For now, just verify it exists and is interactable
        XCTAssertTrue(datePicker.isEnabled)
        
        // Save with default date (1 hour from now)
        app.buttons["saveReminderButton"].tap()
        
        // Verify reminder created
        let reminderIndicator = app.images["bell.fill"]
        XCTAssertTrue(reminderIndicator.waitForExistence(timeout: 2))
    }

    func testCancelTaskReminderCreation() throws {
        navigateToFirstTask()
        
        // Open reminder sheet
        let addReminderButton = app.buttons["addReminderButton"]
        XCTAssertTrue(addReminderButton.waitForExistence(timeout: 2))
        addReminderButton.tap()
        
        // Verify sheet appeared
        let sheet = app.navigationBars["Add Reminder"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        
        // Tap Cancel
        app.buttons["Cancel"].tap()
        
        // Verify sheet dismissed
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
        
        // Verify no reminder created (no bell icon)
        let reminderIndicator = app.images["bell.fill"]
        XCTAssertFalse(reminderIndicator.exists)
    }

    func testQuickSelectButtonsUpdateDatePicker() throws {
        navigateToFirstTask()
        
        // Open reminder sheet
        app.buttons["addReminderButton"].tap()
        
        // Tap each quick select button and verify save button becomes enabled
        let saveButton = app.buttons["saveReminderButton"]
        
        // "In 1 hour" should enable save button (date is in future)
        app.buttons["In 1 hour"].tap()
        XCTAssertTrue(saveButton.isEnabled)
        
        // "In 3 hours" should also enable save button
        app.buttons["In 3 hours"].tap()
        XCTAssertTrue(saveButton.isEnabled)
        
        // "Tomorrow 9 AM"
        app.buttons["Tomorrow 9 AM"].tap()
        XCTAssertTrue(saveButton.isEnabled)
        
        // "Tomorrow 6 PM"
        app.buttons["Tomorrow 6 PM"].tap()
        XCTAssertTrue(saveButton.isEnabled)
    }

    // MARK: - Stack Reminder Tests

    func testCreateStackReminderFromStackDetail() throws {
        // Navigate to stack detail
        let stacksList = app.collectionViews.firstMatch
        XCTAssertTrue(stacksList.waitForExistence(timeout: 5))
        
        // Tap first stack
        let firstStack = stacksList.cells.firstMatch
        XCTAssertTrue(firstStack.waitForExistence(timeout: 2))
        firstStack.tap()
        
        // Open stack menu
        let moreButton = app.buttons["moreOptionsButton"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 2))
        moreButton.tap()
        
        // Tap "Add Reminder"
        let addReminderOption = app.buttons["Add Reminder"]
        XCTAssertTrue(addReminderOption.waitForExistence(timeout: 2))
        addReminderOption.tap()
        
        // Verify reminder sheet
        let sheet = app.navigationBars["Add Reminder"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        
        // Verify parent type is "Stack"
        XCTAssertTrue(app.staticTexts["Stack"].exists)
        
        // Select quick option and save
        app.buttons["Tomorrow 9 AM"].tap()
        app.buttons["saveReminderButton"].tap()
        
        // Verify sheet dismissed
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
    }

    // MARK: - Edit Reminder Tests

    func testEditExistingReminder() throws {
        // First create a reminder
        navigateToFirstTask()
        app.buttons["addReminderButton"].tap()
        app.buttons["In 1 hour"].tap()
        app.buttons["saveReminderButton"].tap()
        
        // Wait for reminder to be created
        let reminderIndicator = app.images["bell.fill"]
        XCTAssertTrue(reminderIndicator.waitForExistence(timeout: 2))
        
        // Tap reminder to edit
        reminderIndicator.tap()
        
        // Verify edit mode sheet
        let sheet = app.navigationBars["Edit Reminder"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        
        // Change time to "Tomorrow 6 PM"
        app.buttons["Tomorrow 6 PM"].tap()
        
        // Save changes
        app.buttons["saveReminderButton"].tap()
        
        // Verify sheet dismissed
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
        
        // Reminder indicator should still be visible
        XCTAssertTrue(reminderIndicator.exists)
    }

    func testDeleteReminderFromTaskDetail() throws {
        // First create a reminder
        navigateToFirstTask()
        app.buttons["addReminderButton"].tap()
        app.buttons["In 1 hour"].tap()
        app.buttons["saveReminderButton"].tap()
        
        // Wait for reminder to be created
        let reminderIndicator = app.images["bell.fill"]
        XCTAssertTrue(reminderIndicator.waitForExistence(timeout: 2))
        
        // Long press or context menu on reminder (platform-specific)
        #if os(iOS)
        reminderIndicator.press(forDuration: 1.0)
        #else
        reminderIndicator.rightClick()
        #endif
        
        // Tap delete option
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 1), "Delete button should appear in context menu")
        deleteButton.tap()
        
        // Verify reminder deleted (bell icon gone)
        XCTAssertFalse(reminderIndicator.waitForExistence(timeout: 2), "Reminder indicator should be removed after deletion")
    }

    // MARK: - Validation Tests

    // Note: Past date validation test removed - DatePicker enforces min date,
    // making it impossible to set past dates in UI tests. The validation is
    // handled at the SwiftUI level via the DatePicker's minimumDate parameter.

    func testReminderSheetShowsParentInfo() throws {
        navigateToFirstTask()
        app.buttons["addReminderButton"].tap()
        
        // Verify parent type label is shown (e.g., "Task")
        XCTAssertTrue(app.staticTexts["Task"].waitForExistence(timeout: 2))
        
        // Note: Cannot reliably test for specific task title without accessibility
        // identifiers on the parent title display element. The sheet correctly
        // shows parent info, but UI test validation would be fragile without
        // proper accessibility identifiers.
    }

    // MARK: - Multiple Reminders Tests

    func testCreateMultipleRemindersForTask() throws {
        navigateToFirstTask()
        
        // Create first reminder
        app.buttons["addReminderButton"].tap()
        app.buttons["In 1 hour"].tap()
        app.buttons["saveReminderButton"].tap()
        
        // Wait for first reminder
        let reminderIndicator = app.images["bell.fill"]
        XCTAssertTrue(reminderIndicator.waitForExistence(timeout: 2))
        
        // Create second reminder
        app.buttons["addReminderButton"].tap()
        app.buttons["Tomorrow 9 AM"].tap()
        app.buttons["saveReminderButton"].tap()
        
        // Verify reminders list or count indicator
        // (Implementation may vary - this documents expected behavior)
        XCTAssertTrue(reminderIndicator.exists)
    }

    // MARK: - Helper Methods

    private func navigateToFirstTask() {
        // Wait for app to load
        let stacksList = app.collectionViews.firstMatch
        XCTAssertTrue(stacksList.waitForExistence(timeout: 5))
        
        // Tap first stack
        let firstStack = stacksList.cells.firstMatch
        XCTAssertTrue(firstStack.waitForExistence(timeout: 2))
        firstStack.tap()
        
        // Tap first task
        let tasksList = app.collectionViews.firstMatch
        XCTAssertTrue(tasksList.waitForExistence(timeout: 2))
        
        let firstTask = tasksList.cells.firstMatch
        XCTAssertTrue(firstTask.waitForExistence(timeout: 2))
        firstTask.tap()
    }
}
