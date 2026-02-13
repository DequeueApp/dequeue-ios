//
//  Environment.swift
//  Dequeue
//
//  Environment configuration for different deployment targets
//

import Foundation

/// Deployment environment for the app
enum Environment: String, CaseIterable, Identifiable, Codable {
    case development
    case staging
    case production

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .development:
            return "Development"
        case .staging:
            return "Staging"
        case .production:
            return "Production"
        }
    }

    /// Badge emoji for visual distinction
    var badge: String {
        switch self {
        case .development:
            return "🛠️"
        case .staging:
            return "🧪"
        case .production:
            return "🚀"
        }
    }

    /// Configuration for this environment
    var configuration: EnvironmentConfiguration {
        switch self {
        case .development:
            return .development
        case .staging:
            return .staging
        case .production:
            return .production
        }
    }
}

/// Environment-specific configuration
struct EnvironmentConfiguration {
    let environment: Environment
    let clerkPublishableKey: String
    let sentryDSN: String
    let dequeueAPIBaseURL: URL
    let syncServiceBaseURL: URL
    let syncAppId: String

    /// Computed property for sync API base URL (includes /apps/{appId} prefix)
    var syncAPIBaseURL: URL {
        return syncServiceBaseURL.appendingPathComponent("apps/\(syncAppId)")
    }

    // MARK: - Predefined Configurations

    static let development = EnvironmentConfiguration(
        environment: .development,
        clerkPublishableKey: "pk_test_ZXhwZXJ0LWhhbGlidXQtODIuY2xlcmsuYWNjb3VudHMuZGV2JA",
        sentryDSN: "https://ac1d2ecd30098c9cc51d2148c9013cd0@o287313.ingest.us.sentry.io/4510574643773440",
        // swiftlint:disable:next force_unwrapping
        dequeueAPIBaseURL: URL(string: "https://api.dequeue.app/v1")!,
        // swiftlint:disable:next force_unwrapping
        syncServiceBaseURL: URL(string: "https://sync.ardonos.com")!,
        syncAppId: "dequeue-development"
    )

    static let staging = EnvironmentConfiguration(
        environment: .staging,
        clerkPublishableKey: "pk_test_ZXhwZXJ0LWhhbGlidXQtODIuY2xlcmsuYWNjb3VudHMuZGV2JA",
        sentryDSN: "https://ac1d2ecd30098c9cc51d2148c9013cd0@o287313.ingest.us.sentry.io/4510574643773440",
        // swiftlint:disable:next force_unwrapping
        dequeueAPIBaseURL: URL(string: "https://api.dequeue.app/v1")!,
        // swiftlint:disable:next force_unwrapping
        syncServiceBaseURL: URL(string: "https://sync.ardonos.com")!,
        syncAppId: "dequeue-staging"
    )

    static let production = EnvironmentConfiguration(
        environment: .production,
        clerkPublishableKey: "pk_test_ZXhwZXJ0LWhhbGlidXQtODIuY2xlcmsuYWNjb3VudHMuZGV2JA",
        sentryDSN: "https://ac1d2ecd30098c9cc51d2148c9013cd0@o287313.ingest.us.sentry.io/4510574643773440",
        // swiftlint:disable:next force_unwrapping
        dequeueAPIBaseURL: URL(string: "https://api.dequeue.app/v1")!,
        // swiftlint:disable:next force_unwrapping
        syncServiceBaseURL: URL(string: "https://sync.ardonos.com")!,
        syncAppId: "dequeue"
    )
}
