//
//  Configuration.swift
//  Dequeue
//
//  App configuration and environment settings
//

import Foundation

enum Configuration {
    // MARK: - Environment

    /// Current environment manager
    private static var environmentManager: EnvironmentManager {
        EnvironmentManager.shared
    }

    /// Current environment configuration
    private static var currentConfig: EnvironmentConfiguration {
        environmentManager.configuration
    }

    // MARK: - Clerk Authentication

    /// Clerk Publishable Key
    /// Get this from: Clerk Dashboard > API Keys
    /// Format: pk_test_xxx or pk_live_xxx
    static var clerkPublishableKey: String {
        currentConfig.clerkPublishableKey
    }

    // MARK: - Sentry Error Tracking

    /// Sentry DSN
    /// Get this from: Sentry Dashboard > Project Settings > Client Keys (DSN)
    static var sentryDSN: String {
        currentConfig.sentryDSN
    }

    /// Distributed tracing targets - only send trace headers to our own backend
    /// This enables connecting mobile traces to backend traces in Sentry
    /// Explicitly nonisolated: accessed from background threads during Sentry configuration
    nonisolated static let tracePropagationTargets: [String] = [
        "api.dequeue.app",
        "sync.ardonos.com",
        "localhost",
        "127.0.0.1"
    ]

    // MARK: - Dequeue API

    /// Base URL for the Dequeue API (API key management, etc.)
    static var dequeueAPIBaseURL: URL {
        currentConfig.dequeueAPIBaseURL
    }

    // MARK: - Sync Backend

    /// App ID for the sync service
    static var syncAppId: String {
        currentConfig.syncAppId
    }

    /// Base URL for the sync API (includes /apps/{appId} prefix)
    static var syncAPIBaseURL: URL {
        currentConfig.syncAPIBaseURL
    }

    // MARK: - Feature Flags

    static let isDebugMode: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    // MARK: - App Info

    /// Explicitly nonisolated: accessed from background threads during Sentry configuration
    nonisolated static let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()

    /// Explicitly nonisolated: accessed from background threads during Sentry configuration
    nonisolated static let buildNumber: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }()

    /// Explicitly nonisolated: accessed from background threads during Sentry configuration
    nonisolated static let bundleIdentifier: String = {
        Bundle.main.bundleIdentifier ?? "com.ardonos.Dequeue"
    }()
}
