//
//  StartupValidator.swift
//  Dequeue
//
//  Validates app configuration at launch and reports issues to Sentry.
//

import Foundation
import os.log

// MARK: - StartupValidator

/// Validates the active environment configuration at app startup.
///
/// Call `StartupValidator.validate(configuration:)` once in `DequeueApp.init()`,
/// after `ErrorReportingService.configure()` is called.
/// Issues are logged via `os_log` and sent to Sentry as breadcrumbs (or errors).
enum StartupValidator {
    // MARK: - Public API

    /// Validate the given configuration and report any issues.
    ///
    /// - Warning: Must be called **after** `ErrorReportingService.configure()` so
    ///   Sentry is ready to receive events.
    /// - Parameter configuration: The environment configuration to validate.
    /// - Returns: Array of issues found. Empty means all checks passed.
    @discardableResult
    static func validate(configuration: EnvironmentConfiguration) -> [EnvironmentValidationIssue] {
        let issues = configuration.validate()
        let env = configuration.environment.rawValue

        if issues.isEmpty {
            os_log("[StartupValidator] ✅ Environment '%{public}s' — all checks passed", env)
            return []
        }

        // Log each issue individually
        for issue in issues {
            let tag = issue.severity == .error ? "🚨 ERROR" : "⚠️ WARNING"
            os_log(
                "[StartupValidator] %{public}s [%{public}s] %{public}s",
                tag,
                issue.key,
                issue.message
            )

            ErrorReportingService.addBreadcrumb(
                category: "startup_validation",
                message: "[\(issue.severity.rawValue)] \(issue.key): \(issue.message)",
                data: [
                    "key": issue.key,
                    "severity": issue.severity.rawValue,
                    "environment": env
                ]
            )
        }

        // Report error-level issues as a single Sentry event so they appear in the inbox
        let errors = issues.filter { $0.severity == .error }
        if !errors.isEmpty {
            let summary = errors.map { "\($0.key): \($0.message)" }.joined(separator: "; ")
            ErrorReportingService.capture(
                error: StartupValidationError.configurationInvalid(summary),
                context: [
                    "environment": env,
                    "errorCount": errors.count,
                    "warningCount": issues.count - errors.count
                ]
            )
        }

        return issues
    }
}

// MARK: - StartupValidationError

/// Concrete error type for startup configuration failures (captured in Sentry).
enum StartupValidationError: Error, LocalizedError {
    case configurationInvalid(String)

    var errorDescription: String? {
        switch self {
        case .configurationInvalid(let details):
            return "App startup configuration is invalid: \(details)"
        }
    }
}
