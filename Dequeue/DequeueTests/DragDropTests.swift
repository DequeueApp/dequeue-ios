//
//  DragDropTests.swift
//  DequeueTests
//
//  Tests for drag and drop transferable models
//

import XCTest
import UniformTypeIdentifiers
@testable import Dequeue

final class DragDropTests: XCTestCase {

    // MARK: - TaskTransferItem Tests

    func testTaskTransferItemEncoding() throws {
        let item = TaskTransferItem(taskId: "task-123", title: "Buy groceries", stackId: "stack-456")

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(TaskTransferItem.self, from: data)

        XCTAssertEqual(decoded.taskId, "task-123")
        XCTAssertEqual(decoded.title, "Buy groceries")
        XCTAssertEqual(decoded.stackId, "stack-456")
    }

    func testTaskTransferItemWithoutStack() throws {
        let item = TaskTransferItem(taskId: "task-123", title: "Orphan task", stackId: nil)

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(TaskTransferItem.self, from: data)

        XCTAssertNil(decoded.stackId)
    }

    // MARK: - StackTransferItem Tests

    func testStackTransferItemEncoding() throws {
        let item = StackTransferItem(stackId: "stack-456", title: "Work Tasks")

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(StackTransferItem.self, from: data)

        XCTAssertEqual(decoded.stackId, "stack-456")
        XCTAssertEqual(decoded.title, "Work Tasks")
    }

    // MARK: - UTType Tests

    func testDequeueTaskUTType() {
        XCTAssertEqual(UTType.dequeueTask.identifier, "app.dequeue.task")
    }

    func testDequeueStackUTType() {
        XCTAssertEqual(UTType.dequeueStack.identifier, "app.dequeue.stack")
    }

    // MARK: - Transfer Item Equality

    func testTaskTransferItemsEqual() throws {
        let item1 = TaskTransferItem(taskId: "task-1", title: "Task", stackId: nil)
        let item2 = TaskTransferItem(taskId: "task-1", title: "Task", stackId: nil)

        let data1 = try JSONEncoder().encode(item1)
        let data2 = try JSONEncoder().encode(item2)
        let decoded1 = try JSONDecoder().decode(TaskTransferItem.self, from: data1)
        let decoded2 = try JSONDecoder().decode(TaskTransferItem.self, from: data2)

        XCTAssertEqual(decoded1.taskId, decoded2.taskId)
        XCTAssertEqual(decoded1.title, decoded2.title)
    }

    // MARK: - JSON Roundtrip

    func testTaskTransferRoundtrip() throws {
        let original = TaskTransferItem(
            taskId: "cuid-abc123",
            title: "Review PR #322",
            stackId: "cuid-stack-789"
        )

        let json = try JSONEncoder().encode(original)
        let jsonString = String(data: json, encoding: .utf8)
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("cuid-abc123"))

        let decoded = try JSONDecoder().decode(TaskTransferItem.self, from: json)
        XCTAssertEqual(decoded.taskId, original.taskId)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.stackId, original.stackId)
    }

    func testStackTransferRoundtrip() throws {
        let original = StackTransferItem(
            stackId: "cuid-stack-xyz",
            title: "Sprint 14"
        )

        let json = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StackTransferItem.self, from: json)
        XCTAssertEqual(decoded.stackId, original.stackId)
        XCTAssertEqual(decoded.title, original.title)
    }
}
