//
//  AccessibilityTests.swift
//  DequeueTests
//
//  Tests for accessibility helpers and modifiers
//

import XCTest
import SwiftUI
import SwiftData
@testable import Dequeue

@MainActor
final class AccessibilityTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var stack: Stack!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self, Tag.self, Arc.self, Device.self,
            configurations: config
        )
        context = container.mainContext

        stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        stack = nil
    }

    // MARK: - Task Priority Accessibility

    func testHighPriorityText() {
        let task = QueueTask(title: "Urgent", priority: 1, sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertEqual(task.priorityAccessibilityText, "High priority")
    }

    func testMediumPriorityText() {
        let task = QueueTask(title: "Normal", priority: 2, sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertEqual(task.priorityAccessibilityText, "Medium priority")
    }

    func testLowPriorityText() {
        let task = QueueTask(title: "Low", priority: 3, sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertEqual(task.priorityAccessibilityText, "Low priority")
    }

    func testNoPriorityText() {
        let task = QueueTask(title: "None", sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertNil(task.priorityAccessibilityText)
    }

    // MARK: - Task Priority Colors

    func testHighPriorityColor() {
        let task = QueueTask(title: "Urgent", priority: 1, sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertEqual(task.accessiblePriorityColor, .red)
    }

    func testMediumPriorityColor() {
        let task = QueueTask(title: "Normal", priority: 2, sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertEqual(task.accessiblePriorityColor, .orange)
    }

    func testLowPriorityColor() {
        let task = QueueTask(title: "Low", priority: 3, sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertEqual(task.accessiblePriorityColor, .yellow)
    }

    func testDefaultPriorityColor() {
        let task = QueueTask(title: "Default", sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertEqual(task.accessiblePriorityColor, .secondary)
    }

    // MARK: - Overdue Detection

    func testTaskIsOverdue() {
        let pastDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())
        let task = QueueTask(
            title: "Overdue Task",
            dueTime: pastDate,
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(task)
        XCTAssertTrue(task.isOverdue)
    }

    func testTaskIsNotOverdue() {
        let futureDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())
        let task = QueueTask(
            title: "Future Task",
            dueTime: futureDate,
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(task)
        XCTAssertFalse(task.isOverdue)
    }

    func testCompletedTaskNotOverdue() {
        let pastDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())
        let task = QueueTask(
            title: "Done Task",
            dueTime: pastDate,
            status: .completed,
            sortOrder: 0,
            stack: stack
        )
        context.insert(task)
        XCTAssertFalse(task.isOverdue)
    }

    func testNoDueDateNotOverdue() {
        let task = QueueTask(title: "No Due", status: .pending, sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertFalse(task.isOverdue)
    }

    // MARK: - Due Date Accessibility Text

    func testOverdueDateText() {
        let pastDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())
        let task = QueueTask(
            title: "Overdue",
            dueTime: pastDate,
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(task)
        let text = task.dueDateAccessibilityText
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("Overdue"))
    }

    func testFutureDateText() {
        let futureDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())
        let task = QueueTask(
            title: "Future",
            dueTime: futureDate,
            status: .pending,
            sortOrder: 0,
            stack: stack
        )
        context.insert(task)
        let text = task.dueDateAccessibilityText
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("Due"))
        XCTAssertFalse(text!.contains("Overdue"))
    }

    func testNoDueDateText() {
        let task = QueueTask(title: "No Due", status: .pending, sortOrder: 0, stack: stack)
        context.insert(task)
        XCTAssertNil(task.dueDateAccessibilityText)
    }
}
