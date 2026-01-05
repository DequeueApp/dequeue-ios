//
//  Configuration.swift
//  Dequeue
//
//  App configuration and environment settings
//

import Foundation

enum Configuration {
    // MARK: - Clerk Authentication

    /// Clerk Publishable Key
    /// Get this from: Clerk Dashboard > API Keys
    /// Format: pk_test_xxx or pk_live_xxx
    static let clerkPublishableKey: String = {
        // swiftlint:disable:next todo
        // FIXME: Replace with your actual Clerk publishable key
        // For production, consider using environment variables or a secrets manager
        #if DEBUG
        return "pk_test_ZXhwZXJ0LWhhbGlidXQtODIuY2xlcmsuYWNjb3VudHMuZGV2JA"
        #else
        return "pk_test_ZXhwZXJ0LWhhbGlidXQtODIuY2xlcmsuYWNjb3VudHMuZGV2JA"
        #endif
    }()

    // MARK: - Sentry Error Tracking

    /// Sentry DSN
    /// Get this from: Sentry Dashboard > Project Settings > Client Keys (DSN)
    static let sentryDSN: String = {
        return "https://ac1d2ecd30098c9cc51d2148c9013cd0@o287313.ingest.us.sentry.io/4510574643773440"
    }()

    // MARK: - Sync Backend

    // App ID for the sync service
    // swiftlint:disable:next todo
    // FIXME: Use "dequeue-development" for DEBUG when backend supports it
    static let syncAppId: String = "dequeue"

    /// Base URL for the sync service (without app path)
    private static let syncServiceBaseURL: URL = {
        // swiftlint:disable:next force_unwrapping
        return URL(string: "https://sync.ardonos.com")!
    }()

    /// Base URL for the sync API (includes /apps/{appId} prefix)
    static let syncAPIBaseURL: URL = {
        return syncServiceBaseURL.appendingPathComponent("apps/\(syncAppId)")
    }()

    // MARK: - Feature Flags

    static let isDebugMode: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    // MARK: - App Info

    static let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()

    static let buildNumber: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }()

    static let bundleIdentifier: String = {
        Bundle.main.bundleIdentifier ?? "com.ardonos.Dequeue"
    }()
}
