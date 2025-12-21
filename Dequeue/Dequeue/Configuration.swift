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
        // TODO: Replace with your actual Clerk publishable key
        // For production, consider using environment variables or a secrets manager
        #if DEBUG
        return "pk_test_ZXhwZXJ0LWhhbGlidXQtODIuY2xlcmsuYWNjb3VudHMuZGV2JA"
        #else
        return "pk_test_ZXhwZXJ0LWhhbGlidXQtODIuY2xlcmsuYWNjb3VudHMuZGV2JA"
        #endif
    }()

    // MARK: - Sync Backend

    /// Base URL for the sync API
    static let syncAPIBaseURL: URL = {
        #if DEBUG
        return URL(string: "https://stacks-sync-staging.fly.dev")!
        #else
        return URL(string: "https://stacks-sync.fly.dev")!
        #endif
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
