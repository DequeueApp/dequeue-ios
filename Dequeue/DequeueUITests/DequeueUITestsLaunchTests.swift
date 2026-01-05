//
//  DequeueUITestsLaunchTests.swift
//  DequeueUITests
//
//  Launch screenshot tests for App Store submissions
//
//  Note: Basic app launch testing is covered by DequeueUITests.testAppLaunches()
//  This class is specifically for generating launch screenshots.
//

import XCTest

@MainActor
final class DequeueUITestsLaunchTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        // Note: super.setUp() intentionally not called - XCTestCase.setUp() does nothing
        // and calling it breaks Swift 6 actor isolation (region isolation error)
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    func testLaunchScreenshot() throws {
        app.launch()

        // Verify app launched successfully
        XCTAssertTrue(app.state == .runningForeground)

        // Wait for app to fully settle before taking screenshot
        // This helps avoid flaky failures in slower CI environments
        _ = app.wait(for: .runningForeground, timeout: 10)

        // Take screenshot for App Store submission
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
