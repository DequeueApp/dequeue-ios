//
//  DequeueUITestsLaunchTests.swift
//  DequeueUITests
//
//  Created by Victor Quinn on 12/21/25.
//

import XCTest

final class DequeueUITestsLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify app launched successfully
        XCTAssertTrue(app.state == .runningForeground)

        // Wait for app to fully settle before taking screenshot
        // This helps avoid flaky failures in slower CI environments
        _ = app.wait(for: .runningForeground, timeout: 5)

        // Take screenshot
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
