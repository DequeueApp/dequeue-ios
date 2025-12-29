//
//  DequeueUITests.swift
//  DequeueUITests
//
//  UI tests for critical user flows
//

import XCTest

final class DequeueUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    // MARK: - Launch Tests

    @MainActor
    func testAppLaunches() throws {
        app.launch()
        XCTAssertTrue(app.exists)
    }
}
