//
//  EnvironmentManagerTests.swift
//  DequeueTests
//
//  Tests for EnvironmentManager
//

import XCTest
@testable import Dequeue

final class EnvironmentManagerTests: XCTestCase {
    var sut: EnvironmentManager!

    override func setUp() {
        super.setUp()
        // Reset UserDefaults for clean test state
        UserDefaults.standard.removeObject(forKey: "app.environment")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "app.environment")
        super.tearDown()
    }

    func testDefaultEnvironmentInDebugBuild() {
        #if DEBUG
        // In debug builds, should default to development
        XCTAssertEqual(
            EnvironmentManager.shared.currentEnvironment,
            .development,
            "Debug builds should default to development environment"
        )
        #else
        // In release builds, should always be production
        XCTAssertEqual(
            EnvironmentManager.shared.currentEnvironment,
            .production,
            "Release builds should always use production environment"
        )
        #endif
    }

    func testCanSwitchEnvironmentInDebugOnly() {
        #if DEBUG
        XCTAssertTrue(
            EnvironmentManager.shared.canSwitchEnvironment,
            "Debug builds should allow environment switching"
        )
        #else
        XCTAssertFalse(
            EnvironmentManager.shared.canSwitchEnvironment,
            "Release builds should not allow environment switching"
        )
        #endif
    }

    func testEnvironmentSwitchingInDebugBuild() {
        #if DEBUG
        // Switch to staging
        let switched = EnvironmentManager.shared.switchEnvironment(to: .staging)
        XCTAssertTrue(switched, "Environment switch should succeed in debug builds")
        XCTAssertEqual(
            EnvironmentManager.shared.currentEnvironment,
            .staging,
            "Current environment should be updated"
        )

        // Switch to production
        EnvironmentManager.shared.switchEnvironment(to: .production)
        XCTAssertEqual(
            EnvironmentManager.shared.currentEnvironment,
            .production,
            "Should be able to switch to production"
        )

        // Switching to same environment should return false
        let sameSwitched = EnvironmentManager.shared.switchEnvironment(to: .production)
        XCTAssertFalse(sameSwitched, "Switching to same environment should return false")
        #endif
    }

    func testEnvironmentPersistenceInDebugBuild() {
        #if DEBUG
        // Create new manager instance (will load from UserDefaults)
        EnvironmentManager.shared.switchEnvironment(to: .staging)

        // Verify persistence by checking UserDefaults directly
        if let data = UserDefaults.standard.data(forKey: "app.environment"),
           let environment = try? JSONDecoder().decode(Environment.self, from: data) {
            XCTAssertEqual(
                environment,
                .staging,
                "Environment should be persisted to UserDefaults"
            )
        } else {
            XCTFail("Environment was not persisted to UserDefaults")
        }
        #endif
    }

    func testResetToDefault() {
        #if DEBUG
        // Switch to production
        EnvironmentManager.shared.switchEnvironment(to: .production)
        XCTAssertEqual(EnvironmentManager.shared.currentEnvironment, .production)

        // Reset
        EnvironmentManager.shared.resetToDefault()
        XCTAssertEqual(
            EnvironmentManager.shared.currentEnvironment,
            .development,
            "Reset should return to development in debug builds"
        )
        #else
        // In release, reset should still be production
        EnvironmentManager.shared.resetToDefault()
        XCTAssertEqual(
            EnvironmentManager.shared.currentEnvironment,
            .production,
            "Reset should remain production in release builds"
        )
        #endif
    }

    func testConfiguration() {
        // Test that configuration is accessible
        let config = EnvironmentManager.shared.configuration
        XCTAssertNotNil(config.clerkPublishableKey, "Configuration should have Clerk key")
        XCTAssertNotNil(config.sentryDSN, "Configuration should have Sentry DSN")
        XCTAssertNotNil(config.dequeueAPIBaseURL, "Configuration should have API URL")
        XCTAssertNotNil(config.syncServiceBaseURL, "Configuration should have sync URL")
        XCTAssertNotNil(config.syncAppId, "Configuration should have app ID")
    }

    func testEnvironmentConfigurations() {
        // Test development config
        let dev = Environment.development.configuration
        XCTAssertEqual(dev.syncAppId, "dequeue-development")
        XCTAssertEqual(dev.environment, .development)

        // Test staging config
        let staging = Environment.staging.configuration
        XCTAssertEqual(staging.syncAppId, "dequeue-staging")
        XCTAssertEqual(staging.environment, .staging)

        // Test production config
        let prod = Environment.production.configuration
        XCTAssertEqual(prod.syncAppId, "dequeue")
        XCTAssertEqual(prod.environment, .production)
    }

    func testSyncAPIBaseURL() {
        // Test that syncAPIBaseURL is computed correctly
        let config = EnvironmentManager.shared.configuration
        let expectedURL = config.syncServiceBaseURL.appendingPathComponent("apps/\(config.syncAppId)")
        XCTAssertEqual(
            config.syncAPIBaseURL.absoluteString,
            expectedURL.absoluteString,
            "syncAPIBaseURL should include app ID path"
        )
    }
}
