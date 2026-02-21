//
//  QuickActionServiceTests.swift
//  DequeueTests
//
//  Tests for QuickActionService and QuickActionType
//

import XCTest
@testable import Dequeue

@MainActor
final class QuickActionTypeTests: XCTestCase {

    // MARK: - Raw Values

    func testRawValues() {
        XCTAssertEqual(QuickActionType.addTask.rawValue, "com.ardonos.Dequeue.addTask")
        XCTAssertEqual(QuickActionType.viewActiveStack.rawValue, "com.ardonos.Dequeue.viewActiveStack")
        XCTAssertEqual(QuickActionType.search.rawValue, "com.ardonos.Dequeue.search")
        XCTAssertEqual(QuickActionType.newStack.rawValue, "com.ardonos.Dequeue.newStack")
    }

    // MARK: - Titles

    func testTitles() {
        XCTAssertEqual(QuickActionType.addTask.title, "Add Task")
        XCTAssertEqual(QuickActionType.viewActiveStack.title, "Active Stack")
        XCTAssertEqual(QuickActionType.search.title, "Search")
        XCTAssertEqual(QuickActionType.newStack.title, "New Stack")
    }

    // MARK: - Icon Names

    func testIconNames() {
        XCTAssertEqual(QuickActionType.addTask.iconName, "plus.circle")
        XCTAssertEqual(QuickActionType.viewActiveStack.iconName, "tray.fill")
        XCTAssertEqual(QuickActionType.search.iconName, "magnifyingglass")
        XCTAssertEqual(QuickActionType.newStack.iconName, "folder.badge.plus")
    }

    // MARK: - Deep Link URLs

    func testDeepLinkURLs() {
        XCTAssertEqual(QuickActionType.addTask.deepLinkURL?.absoluteString, "dequeue://action/add-task")
        XCTAssertEqual(QuickActionType.viewActiveStack.deepLinkURL?.absoluteString, "dequeue://action/active-stack")
        XCTAssertEqual(QuickActionType.search.deepLinkURL?.absoluteString, "dequeue://action/search")
        XCTAssertEqual(QuickActionType.newStack.deepLinkURL?.absoluteString, "dequeue://action/new-stack")
    }

    // MARK: - Init from Raw Value

    func testInitFromRawValue() {
        XCTAssertEqual(QuickActionType(rawValue: "com.ardonos.Dequeue.addTask"), .addTask)
        XCTAssertEqual(QuickActionType(rawValue: "com.ardonos.Dequeue.viewActiveStack"), .viewActiveStack)
        XCTAssertEqual(QuickActionType(rawValue: "com.ardonos.Dequeue.search"), .search)
        XCTAssertEqual(QuickActionType(rawValue: "com.ardonos.Dequeue.newStack"), .newStack)
        XCTAssertNil(QuickActionType(rawValue: "unknown.action"))
    }

    // MARK: - Subtitles

    func testSubtitles() {
        XCTAssertNotNil(QuickActionType.addTask.subtitle)
        XCTAssertNil(QuickActionType.viewActiveStack.subtitle)
        XCTAssertNotNil(QuickActionType.search.subtitle)
        XCTAssertNotNil(QuickActionType.newStack.subtitle)
    }
}
