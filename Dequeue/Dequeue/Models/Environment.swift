//
//  Environment.swift
//  Dequeue
//
//  Environment configuration for different deployment targets
//

import Foundation

/// Deployment environment for the app
enum DeploymentEnvironment: String, CaseIterable, Identifiable, Codable {
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

// MARK: - Validation Types

/// Severity of a startup environment validation issue.
enum ValidationSeverity: String, Equatable, Sendable {
    /// Non-fatal — logged and sent to Sentry, but the app can continue.
    case warning
    /// Fatal misconfiguration — could break auth, sync, or error reporting.
    case error
}

/// A single issue found during startup environment validation.
struct EnvironmentValidationIssue: Equatable, Sendable {
    /// The configuration field or check that failed (e.g. "clerkPublishableKey").
    let key: String
    /// Human-readable description of the problem.
    let message: String
    /// How serious the issue is.
    let severity: ValidationSeverity
}

// MARK: - Environment Configuration

/// Environment-specific configuration
struct EnvironmentConfiguration {
    let environment: DeploymentEnvironment
    let clerkPublishableKey: String
    let sentryDSN: String
    let dequeueAPIBaseURL: URL
    let syncServiceBaseURL: URL
    let syncAppId: String

    /// Computed property for sync API base URL (includes /apps/{appId} prefix)
    var syncAPIBaseURL: URL {
        return syncServiceBaseURL.appendingPathComponent("apps/\(syncAppId)")
    }

    // MARK: - Validation

    /// Validates this configuration and returns any detected issues.
    ///
    /// Checks performed:
    /// - URL schemes are `https` (or `http` in non-production)
    /// - URLs have non-empty hosts
    /// - Clerk publishable key starts with `pk_`
    /// - Production builds are not using `pk_test_` keys
    /// - Sentry DSN is non-empty and starts with `https://`
    /// - Sync app ID is non-empty
    ///
    /// - Returns: Array of `EnvironmentValidationIssue`; empty means all checks passed.
    func validate() -> [EnvironmentValidationIssue] {
        var issues: [EnvironmentValidationIssue] = []

        // --- URL checks ---
        let urlFields: [(String, URL)] = [
            ("dequeueAPIBaseURL", dequeueAPIBaseURL),
            ("syncServiceBaseURL", syncServiceBaseURL)
        ]
        for (field, url) in urlFields {
            guard let scheme = url.scheme, !scheme.isEmpty else {
                issues.append(.init(key: field, message: "\(field) has no URL scheme", severity: .error))
                continue
            }
            guard scheme == "https" || scheme == "http" else {
                issues.append(.init(
                    key: field,
                    message: "\(field) uses unexpected scheme '\(scheme)'",
                    severity: .error
                ))
                continue
            }
            if environment == .production && scheme != "https" {
                issues.append(.init(
                    key: field,
                    message: "\(field) must use HTTPS in production (got '\(scheme)')",
                    severity: .error
                ))
            }
            if url.host == nil || (url.host ?? "").isEmpty {
                issues.append(.init(key: field, message: "\(field) has no host", severity: .error))
            }
        }

        // --- Clerk key ---
        if clerkPublishableKey.isEmpty {
            issues.append(.init(key: "clerkPublishableKey", message: "Clerk key is empty", severity: .error))
        } else if !clerkPublishableKey.hasPrefix("pk_") {
            issues.append(.init(
                key: "clerkPublishableKey",
                message: "Clerk key must start with 'pk_' (got '\(clerkPublishableKey.prefix(8))...')",
                severity: .error
            ))
        } else if environment == .production && clerkPublishableKey.hasPrefix("pk_test_") {
            issues.append(.init(
                key: "clerkPublishableKey",
                message: "Production is using a test Clerk key (pk_test_). Switch to pk_live_ before shipping.",
                severity: .warning
            ))
        }

        // --- Sentry DSN ---
        if sentryDSN.isEmpty {
            issues.append(.init(key: "sentryDSN", message: "Sentry DSN is empty", severity: .warning))
        } else if !sentryDSN.hasPrefix("https://") {
            issues.append(.init(
                key: "sentryDSN",
                message: "Sentry DSN should start with 'https://'",
                severity: .warning
            ))
        }

        // --- Sync app ID ---
        if syncAppId.isEmpty {
            issues.append(.init(key: "syncAppId", message: "Sync app ID is empty", severity: .error))
        }

        return issues
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
