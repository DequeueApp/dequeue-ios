//
//  DequeueUITests.swift
//  DequeueUITests
//

import XCTest

final class DequeueUITests: XCTestCase {

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.state == .runningForeground)
    }
}
