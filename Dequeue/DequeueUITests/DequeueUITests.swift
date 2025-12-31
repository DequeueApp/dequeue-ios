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

    // MARK: - Authentication Screen Tests

    @MainActor
    func testAuthenticationScreenShowsSignInButton() throws {
        app.launch()

        // Should show Sign In button for unauthenticated user
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(
            signInButton.waitForExistence(timeout: 10),
            "Sign In button should exist on auth screen"
        )
    }

    @MainActor
    func testAuthenticationScreenShowsEmailField() throws {
        app.launch()

        // Wait for auth screen
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))

        // Check for email field using accessibility identifier
        let emailField = app.textFields["emailField"]
        XCTAssertTrue(emailField.exists, "Email field should exist")
    }

    @MainActor
    func testAuthenticationScreenShowsPasswordField() throws {
        app.launch()

        // Wait for auth screen
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))

        // Check for password field using accessibility identifier
        let passwordField = app.secureTextFields["passwordField"]
        XCTAssertTrue(passwordField.exists, "Password field should exist")
    }
}
