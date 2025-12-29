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

    // MARK: - Authentication Flow Tests

    @MainActor
    func testAuthenticationScreenAppears() throws {
        app.launch()

        // Should show auth screen for unauthenticated user
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5), "Sign In button should exist")
    }

    @MainActor
    func testSignUpToggle() throws {
        app.launch()

        // Start on Sign In
        XCTAssertTrue(app.buttons["Sign In"].exists)

        // Tap toggle to Sign Up
        let toggleButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sign up'")).firstMatch
        if toggleButton.exists {
            toggleButton.tap()

            // Should now show Create Account button
            XCTAssertTrue(app.buttons["Create Account"].waitForExistence(timeout: 2))
        }
    }

    @MainActor
    func testEmailAndPasswordFieldsExist() throws {
        app.launch()

        // Use accessibility identifiers for reliable element location
        let emailField = app.textFields["emailField"]
        let passwordField = app.secureTextFields["passwordField"]

        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Email field should exist")
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "Password field should exist")
    }

    // MARK: - Performance Tests

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
