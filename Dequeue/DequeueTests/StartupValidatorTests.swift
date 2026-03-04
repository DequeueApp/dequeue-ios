//
//  StartupValidatorTests.swift
//  DequeueTests
//
//  Tests for EnvironmentConfiguration.validate() and StartupValidator.
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - EnvironmentValidationIssue Tests

@Suite("EnvironmentConfiguration.validate()")
@MainActor
struct EnvironmentValidationTests {

    // MARK: - Helpers

    /// Minimal valid development configuration — should produce zero issues.
    private func validDevConfig(
        clerkKey: String = "pk_test_abc123",
        sentryDSN: String = "https://abc@sentry.io/123",
        apiURL: String = "https://api.dequeue.app/v1",
        syncURL: String = "https://sync.ardonos.com",
        syncAppId: String = "dequeue-development"
    ) -> EnvironmentConfiguration {
        // swiftlint:disable:next force_unwrapping
        EnvironmentConfiguration(
            environment: .development,
            clerkPublishableKey: clerkKey,
            sentryDSN: sentryDSN,
            // swiftlint:disable:next force_unwrapping
            dequeueAPIBaseURL: URL(string: apiURL)!,
            // swiftlint:disable:next force_unwrapping
            syncServiceBaseURL: URL(string: syncURL)!,
            syncAppId: syncAppId
        )
    }

    /// Minimal valid production configuration.
    private func validProdConfig(
        clerkKey: String = "pk_live_abc123"
    ) -> EnvironmentConfiguration {
        EnvironmentConfiguration(
            environment: .production,
            clerkPublishableKey: clerkKey,
            sentryDSN: "https://abc@sentry.io/123",
            // swiftlint:disable:next force_unwrapping
            dequeueAPIBaseURL: URL(string: "https://api.dequeue.app/v1")!,
            // swiftlint:disable:next force_unwrapping
            syncServiceBaseURL: URL(string: "https://sync.ardonos.com")!,
            syncAppId: "dequeue"
        )
    }

    // MARK: - Happy Path

    @Test("Valid dev config produces no issues")
    func validDevConfigProducesNoIssues() {
        let issues = validDevConfig().validate()
        #expect(issues.isEmpty, "Expected no issues for valid dev config, got: \(issues)")
    }

    @Test("Valid prod config with live key produces no issues")
    func validProdConfigProducesNoIssues() {
        let issues = validProdConfig(clerkKey: "pk_live_abc123").validate()
        #expect(issues.isEmpty, "Expected no issues for valid prod config, got: \(issues)")
    }

    @Test("Predefined development configuration is valid")
    func predefinedDevConfigIsValid() {
        let issues = EnvironmentConfiguration.development.validate()
        // Development config intentionally uses pk_test_ — only warnings allowed, no errors
        let errors = issues.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Predefined dev config should have no errors, got: \(errors)")
    }

    @Test("Predefined staging configuration is valid")
    func predefinedStagingConfigIsValid() {
        let issues = EnvironmentConfiguration.staging.validate()
        let errors = issues.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Predefined staging config should have no errors, got: \(errors)")
    }

    @Test("Predefined production configuration warns about test Clerk key")
    func predefinedProdConfigWarnsAboutTestKey() {
        // Currently all envs share the same test Clerk key — production should warn
        let issues = EnvironmentConfiguration.production.validate()
        let errors = issues.filter { $0.severity == .error }
        let warnings = issues.filter { $0.severity == .warning }
        #expect(errors.isEmpty, "Predefined prod config should have no errors, got: \(errors)")
        // If a test key is used in production, we expect at least one warning
        if EnvironmentConfiguration.production.clerkPublishableKey.hasPrefix("pk_test_") {
            let clerkWarning = warnings.first(where: { $0.key == "clerkPublishableKey" })
            #expect(clerkWarning != nil, "Expected clerkPublishableKey warning for test key in production")
        }
    }

    // MARK: - Clerk Key Validation

    @Test("Empty Clerk key is an error")
    func emptyClerkKeyIsError() {
        let issues = validDevConfig(clerkKey: "").validate()
        let match = issues.first(where: { $0.key == "clerkPublishableKey" && $0.severity == .error })
        #expect(match != nil, "Expected error for empty Clerk key")
    }

    @Test("Clerk key without pk_ prefix is an error")
    func clerkKeyWithoutPrefixIsError() {
        let issues = validDevConfig(clerkKey: "bad_key_value").validate()
        let match = issues.first(where: { $0.key == "clerkPublishableKey" && $0.severity == .error })
        #expect(match != nil, "Expected error for Clerk key missing pk_ prefix")
    }

    @Test("Production config with test Clerk key is a warning not an error")
    func productionTestClerkKeyIsWarning() {
        let issues = validProdConfig(clerkKey: "pk_test_abc123").validate()
        let warning = issues.first(where: { $0.key == "clerkPublishableKey" && $0.severity == .warning })
        let error = issues.first(where: { $0.key == "clerkPublishableKey" && $0.severity == .error })
        #expect(warning != nil, "Expected warning for pk_test_ in production")
        #expect(error == nil, "Should be a warning, not an error")
    }

    // MARK: - URL Validation

    @Test("Production HTTP API URL is an error")
    func productionHttpAPIURLIsError() {
        let issues = EnvironmentConfiguration(
            environment: .production,
            clerkPublishableKey: "pk_live_abc",
            sentryDSN: "https://abc@sentry.io/123",
            // swiftlint:disable:next force_unwrapping
            dequeueAPIBaseURL: URL(string: "http://api.dequeue.app/v1")!,
            // swiftlint:disable:next force_unwrapping
            syncServiceBaseURL: URL(string: "https://sync.ardonos.com")!,
            syncAppId: "dequeue"
        ).validate()
        let error = issues.first(where: { $0.key == "dequeueAPIBaseURL" && $0.severity == .error })
        #expect(error != nil, "Expected error for HTTP in production API URL")
    }

    @Test("Development HTTP API URL is allowed")
    func developmentHttpAPIURLIsAllowed() {
        let issues = validDevConfig(apiURL: "http://localhost:8080/v1").validate()
        let error = issues.first(where: { $0.key == "dequeueAPIBaseURL" && $0.severity == .error })
        #expect(error == nil, "HTTP should be allowed in development")
    }

    // MARK: - Sentry DSN Validation

    @Test("Empty Sentry DSN is a warning")
    func emptySentryDSNIsWarning() {
        let issues = validDevConfig(sentryDSN: "").validate()
        let warning = issues.first(where: { $0.key == "sentryDSN" && $0.severity == .warning })
        #expect(warning != nil, "Expected warning for empty Sentry DSN")
    }

    @Test("Non-HTTPS Sentry DSN is a warning")
    func nonHttpsSentryDSNIsWarning() {
        let issues = validDevConfig(sentryDSN: "http://abc@sentry.io/123").validate()
        let warning = issues.first(where: { $0.key == "sentryDSN" && $0.severity == .warning })
        #expect(warning != nil, "Expected warning for non-HTTPS Sentry DSN")
    }

    // MARK: - Sync App ID Validation

    @Test("Empty sync app ID is an error")
    func emptySyncAppIdIsError() {
        let issues = validDevConfig(syncAppId: "").validate()
        let error = issues.first(where: { $0.key == "syncAppId" && $0.severity == .error })
        #expect(error != nil, "Expected error for empty sync app ID")
    }

    // MARK: - Multiple Issues

    @Test("Multiple misconfigurations produce multiple issues")
    func multipleMisconfigurationsProduceMultipleIssues() {
        let issues = validDevConfig(clerkKey: "", syncAppId: "").validate()
        #expect(issues.count >= 2, "Expected at least 2 issues for multiple errors")
    }
}

// MARK: - StartupValidator Tests

@Suite("StartupValidator")
@MainActor
struct StartupValidatorTests {

    @Test("Returns empty array for valid configuration")
    func returnsEmptyForValidConfig() {
        let config = EnvironmentConfiguration(
            environment: .development,
            clerkPublishableKey: "pk_test_valid",
            sentryDSN: "https://abc@sentry.io/123",
            // swiftlint:disable:next force_unwrapping
            dequeueAPIBaseURL: URL(string: "https://api.dequeue.app/v1")!,
            // swiftlint:disable:next force_unwrapping
            syncServiceBaseURL: URL(string: "https://sync.ardonos.com")!,
            syncAppId: "dequeue-development"
        )
        let issues = StartupValidator.validate(configuration: config)
        #expect(issues.isEmpty)
    }

    @Test("Returns issues for misconfigured environment")
    func returnsIssuesForBadConfig() {
        let config = EnvironmentConfiguration(
            environment: .development,
            clerkPublishableKey: "",  // Invalid
            sentryDSN: "https://abc@sentry.io/123",
            // swiftlint:disable:next force_unwrapping
            dequeueAPIBaseURL: URL(string: "https://api.dequeue.app/v1")!,
            // swiftlint:disable:next force_unwrapping
            syncServiceBaseURL: URL(string: "https://sync.ardonos.com")!,
            syncAppId: "dequeue-development"
        )
        let issues = StartupValidator.validate(configuration: config)
        #expect(!issues.isEmpty)
    }
}
