//
//  FocusFilterTests.swift
//  DequeueTests
//
//  Tests for FocusFilterConfig
//

import XCTest
@testable import Dequeue

@MainActor
final class FocusFilterConfigTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up UserDefaults before each test
        UserDefaults.standard.removeObject(forKey: "com.dequeue.focusFilter")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "com.dequeue.focusFilter")
        super.tearDown()
    }

    // MARK: - Inactive Filter

    func testInactiveFilter_ShowsAllStacks() {
        let config = FocusFilterConfig.inactive
        XCTAssertFalse(config.isActive)
        XCTAssertTrue(config.shouldShowStack(stackId: "any-stack", isActive: false))
        XCTAssertTrue(config.shouldShowStack(stackId: "any-stack", isActive: true))
    }

    func testInactiveFilter_DoesNotMuteAnything() {
        let config = FocusFilterConfig.inactive
        XCTAssertFalse(config.shouldMuteStack(stackId: "any-stack", isActive: false))
        XCTAssertFalse(config.shouldMuteStack(stackId: "any-stack", isActive: true))
    }

    // MARK: - Active Stack Only

    func testActiveStackOnly_ShowsOnlyActiveStack() {
        let config = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: true,
            visibleStackIds: [],
            muteOtherStacks: false
        )

        XCTAssertTrue(config.shouldShowStack(stackId: "active-stack", isActive: true))
        XCTAssertFalse(config.shouldShowStack(stackId: "other-stack", isActive: false))
    }

    func testActiveStackOnly_WithMute() {
        let config = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: true,
            visibleStackIds: [],
            muteOtherStacks: true
        )

        XCTAssertFalse(config.shouldMuteStack(stackId: "active-stack", isActive: true))
        XCTAssertTrue(config.shouldMuteStack(stackId: "other-stack", isActive: false))
    }

    // MARK: - Specific Stacks

    func testSpecificStacks_ShowsOnlySelected() {
        let config = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: false,
            visibleStackIds: ["stack-1", "stack-2"],
            muteOtherStacks: false
        )

        XCTAssertTrue(config.shouldShowStack(stackId: "stack-1", isActive: false))
        XCTAssertTrue(config.shouldShowStack(stackId: "stack-2", isActive: true))
        XCTAssertFalse(config.shouldShowStack(stackId: "stack-3", isActive: false))
    }

    func testSpecificStacks_WithMute() {
        let config = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: false,
            visibleStackIds: ["stack-1"],
            muteOtherStacks: true
        )

        XCTAssertFalse(config.shouldMuteStack(stackId: "stack-1", isActive: false))
        XCTAssertTrue(config.shouldMuteStack(stackId: "stack-2", isActive: false))
    }

    // MARK: - No Filter (Active but Empty)

    func testActiveEmptyFilter_ShowsAll() {
        let config = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: false,
            visibleStackIds: [],
            muteOtherStacks: false
        )

        XCTAssertTrue(config.shouldShowStack(stackId: "any-stack", isActive: false))
        XCTAssertTrue(config.shouldShowStack(stackId: "any-stack", isActive: true))
    }

    // MARK: - Persistence

    func testSaveAndLoad() {
        let config = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: true,
            visibleStackIds: ["stack-1", "stack-2"],
            muteOtherStacks: true
        )

        FocusFilterConfig.save(config)
        let loaded = FocusFilterConfig.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded, config)
    }

    func testLoadWhenEmpty_ReturnsNil() {
        let loaded = FocusFilterConfig.load()
        XCTAssertNil(loaded)
    }

    func testClear() {
        let config = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: false,
            visibleStackIds: [],
            muteOtherStacks: false
        )
        FocusFilterConfig.save(config)
        XCTAssertNotNil(FocusFilterConfig.load())

        FocusFilterConfig.clear()
        XCTAssertNil(FocusFilterConfig.load())
    }

    // MARK: - Equatable

    func testEquatable() {
        let config1 = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: true,
            visibleStackIds: ["a", "b"],
            muteOtherStacks: true
        )
        let config2 = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: true,
            visibleStackIds: ["a", "b"],
            muteOtherStacks: true
        )
        let config3 = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: false,
            visibleStackIds: ["a", "b"],
            muteOtherStacks: true
        )

        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }

    // MARK: - Deep Link Action

    func testDeepLinkAction_RawValues() {
        XCTAssertEqual(DeepLinkAction.addTask.rawValue, "add-task")
        XCTAssertEqual(DeepLinkAction.activeStack.rawValue, "active-stack")
        XCTAssertEqual(DeepLinkAction.search.rawValue, "search")
        XCTAssertEqual(DeepLinkAction.newStack.rawValue, "new-stack")
    }

    func testDeepLinkAction_InitFromRawValue() {
        XCTAssertEqual(DeepLinkAction(rawValue: "add-task"), .addTask)
        XCTAssertEqual(DeepLinkAction(rawValue: "active-stack"), .activeStack)
        XCTAssertEqual(DeepLinkAction(rawValue: "search"), .search)
        XCTAssertEqual(DeepLinkAction(rawValue: "new-stack"), .newStack)
        XCTAssertNil(DeepLinkAction(rawValue: "unknown"))
    }
}
