//
//  ConfigurationTests.swift
//  DequeueTests
//
//  Tests for Configuration values
//

import Testing
import Foundation
@testable import Dequeue

@Suite("Configuration Tests")
@MainActor
struct ConfigurationTests {
    // MARK: - Trace Propagation Targets

    @Test("tracePropagationTargets contains api.dequeue.app")
    func tracePropagationContainsAPI() {
        #expect(Configuration.tracePropagationTargets.contains("api.dequeue.app"))
    }

    @Test("tracePropagationTargets contains sync.ardonos.com")
    func tracePropagationContainsSync() {
        #expect(Configuration.tracePropagationTargets.contains("sync.ardonos.com"))
    }

    @Test("tracePropagationTargets contains localhost")
    func tracePropagationContainsLocalhost() {
        #expect(Configuration.tracePropagationTargets.contains("localhost"))
    }

    @Test("tracePropagationTargets contains 127.0.0.1")
    func tracePropagationContainsLoopback() {
        #expect(Configuration.tracePropagationTargets.contains("127.0.0.1"))
    }

    @Test("tracePropagationTargets has exactly 4 entries")
    func tracePropagationTargetCount() {
        #expect(Configuration.tracePropagationTargets.count == 4)
    }

    // MARK: - App Info

    @Test("appVersion is non-empty")
    func appVersionIsNonEmpty() {
        #expect(!Configuration.appVersion.isEmpty)
    }

    @Test("buildNumber is non-empty")
    func buildNumberIsNonEmpty() {
        #expect(!Configuration.buildNumber.isEmpty)
    }

    @Test("bundleIdentifier is non-empty")
    func bundleIdentifierIsNonEmpty() {
        #expect(!Configuration.bundleIdentifier.isEmpty)
    }

    // MARK: - Debug Mode

    @Test("isDebugMode reflects build configuration")
    func isDebugModeReflectsBuild() {
        // In test builds (which are debug), this should be true
        #if DEBUG
        #expect(Configuration.isDebugMode == true)
        #else
        #expect(Configuration.isDebugMode == false)
        #endif
    }

    // MARK: - Environment-Dependent Values

    @Test("clerkPublishableKey is non-empty")
    func clerkPublishableKeyIsNonEmpty() {
        #expect(!Configuration.clerkPublishableKey.isEmpty)
    }

    @Test("clerkPublishableKey starts with pk_")
    func clerkPublishableKeyHasCorrectPrefix() {
        #expect(Configuration.clerkPublishableKey.hasPrefix("pk_"),
                "Clerk key should start with pk_, got: \(Configuration.clerkPublishableKey)")
    }

    @Test("sentryDSN is non-empty")
    func sentryDSNIsNonEmpty() {
        #expect(!Configuration.sentryDSN.isEmpty)
    }

    @Test("sentryDSN starts with https")
    func sentryDSNIsHTTPS() {
        #expect(Configuration.sentryDSN.hasPrefix("https://"),
                "Sentry DSN should be HTTPS, got: \(Configuration.sentryDSN)")
    }

    @Test("dequeueAPIBaseURL is valid")
    func dequeueAPIBaseURLIsValid() {
        let url = Configuration.dequeueAPIBaseURL
        #expect(url.scheme == "https" || url.scheme == "http")
        #expect(url.host != nil)
    }

    @Test("syncAPIBaseURL is valid")
    func syncAPIBaseURLIsValid() {
        let url = Configuration.syncAPIBaseURL
        #expect(url.scheme == "https" || url.scheme == "http")
        #expect(url.host != nil)
    }

    @Test("syncAppId is non-empty")
    func syncAppIdIsNonEmpty() {
        #expect(!Configuration.syncAppId.isEmpty)
    }
}
