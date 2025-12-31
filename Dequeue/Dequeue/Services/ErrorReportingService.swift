//
//  ErrorReportingService.swift
//  Dequeue
//
//  Error tracking and reporting using Sentry
//

import Foundation
import Sentry

enum ErrorReportingService {
    // MARK: - Configuration

    static func configure() {
        guard Configuration.sentryDSN != "YOUR_SENTRY_DSN_HERE" else {
            return
        }

        // Don't initialize Sentry in test/CI environments
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
           ProcessInfo.processInfo.arguments.contains("--uitesting") ||
           ProcessInfo.processInfo.environment["CI"] != nil {
            return
        }
        #endif

        SentrySDK.start { options in
            options.dsn = Configuration.sentryDSN

            #if DEBUG
            options.debug = true
            options.environment = "development"
            #else
            options.debug = false
            options.environment = "production"
            #endif

            let release = "\(Configuration.bundleIdentifier)@\(Configuration.appVersion)"
            options.releaseName = "\(release)+\(Configuration.buildNumber)"

            options.enableAutoSessionTracking = true
            options.enableAutoBreadcrumbTracking = true
            options.attachStacktrace = true
            options.maxBreadcrumbs = 100

            #if DEBUG
            options.tracesSampleRate = 1.0
            #else
            options.tracesSampleRate = 0.2
            #endif
        }
    }

    // MARK: - User Context

    static func setUser(id: String, email: String? = nil) {
        let user = User()
        user.userId = id
        user.email = email
        SentrySDK.setUser(user)

        addBreadcrumb(
            category: "auth",
            message: "User authenticated",
            data: ["user_id": id]
        )
    }

    static func clearUser() {
        SentrySDK.setUser(nil)
        addBreadcrumb(category: "auth", message: "User logged out")
    }

    // MARK: - Error Capture

    static func capture(error: Error, context: [String: Any]? = nil) {
        if let context {
            SentrySDK.capture(error: error) { scope in
                scope.setContext(value: context, key: "custom")
            }
        } else {
            SentrySDK.capture(error: error)
        }
    }

    static func capture(message: String, level: SentryLevel = .info) {
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
        }
    }

    // MARK: - Breadcrumbs

    static func addBreadcrumb(
        category: String,
        message: String,
        level: SentryLevel = .info,
        data: [String: Any]? = nil
    ) {
        let breadcrumb = Breadcrumb()
        breadcrumb.category = category
        breadcrumb.message = message
        breadcrumb.level = level
        if let data {
            breadcrumb.data = data
        }
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    // MARK: - Performance

    static func startTransaction(name: String, operation: String) -> any Span {
        SentrySDK.startTransaction(name: name, operation: operation)
    }
}
