//
//  DequeueUITests.swift
//  DequeueUITests
//
//  UI tests for critical user flows
//

import XCTest

final class DequeueUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Authentication Tests

    @MainActor
    func testAuthenticationScreenAppears() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify Sign In button exists
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(
            signInButton.waitForExistence(timeout: 10),
            "Sign In button should appear on auth screen"
        )

        // Take screenshot for verification
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Auth Screen"
        add(attachment)
    }
}
