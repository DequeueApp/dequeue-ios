//
//  ErrorReportingService.swift
//  Dequeue
//
//  Comprehensive error tracking and observability using Sentry
//

import Foundation
import os
import Sentry
#if os(iOS)
import UIKit
#endif

enum ErrorReportingService {
    // MARK: - Configuration

    /// Thread-safe state for configuration status and cached device identifier
    private struct ConfigurationState {
        var isConfigured = false
        var cachedDeviceIdentifier: String?
    }

    /// Thread-safe lock for configuration state
    private static let configurationLock = OSAllocatedUnfairLock(initialState: ConfigurationState())

    /// Thread-safe check for whether Sentry is already configured
    private static var isConfigured: Bool {
        get { configurationLock.withLock { $0.isConfigured } }
        set { configurationLock.withLock { $0.isConfigured = newValue } }
    }

    /// Cached device identifier for thread-safe access from any context
    private static var cachedDeviceId: String? {
        get { configurationLock.withLock { $0.cachedDeviceIdentifier } }
        set { configurationLock.withLock { $0.cachedDeviceIdentifier = newValue } }
    }

    /// Returns true if Sentry should be skipped (test/CI environments)
    private static var shouldSkipConfiguration: Bool {
        if isConfigured {
            return true
        }

        if Configuration.sentryDSN == "YOUR_SENTRY_DSN_HERE" {
            return true
        }

        #if DEBUG
        // Don't initialize Sentry in test/CI environments
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
           ProcessInfo.processInfo.arguments.contains("--uitesting") ||
           ProcessInfo.processInfo.environment["CI"] != nil {
            return true
        }
        #endif

        return false
    }

    // swiftlint:disable function_body_length
    /// Configures Sentry SDK asynchronously to avoid blocking app launch.
    /// This should be called from a Task context, not during App init.
    ///
    /// This configuration enables maximum observability:
    /// - 100% trace sampling (single user, no cost concerns)
    /// - Session replay for visual debugging
    /// - Profiling for performance analysis
    /// - Experimental logs for custom logging
    /// - App hang detection
    /// - Distributed tracing to connect with backend
    static func configure() async {
        // Quick synchronous check to avoid async overhead in test environments
        guard !shouldSkipConfiguration else { return }

        // Cache device identifier on main actor before going to background
        // This ensures thread-safe access for logging from any context
        await MainActor.run {
            cachedDeviceId = buildDeviceIdentifier()
        }

        // Run Sentry initialization on a background thread to avoid blocking the main thread
        // Sentry SDK init can take 10+ seconds on first launch or when processing crash reports
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                // Double-check in case of race condition
                guard !isConfigured else {
                    continuation.resume()
                    return
                }

                SentrySDK.start { options in
                    options.dsn = Configuration.sentryDSN

                    // ============================================
                    // DEBUG & ENVIRONMENT
                    // ============================================
                    #if DEBUG
                    options.debug = true
                    options.environment = "development"
                    #else
                    options.debug = false
                    options.environment = "production"
                    #endif

                    // Set release version explicitly
                    let release = "\(Configuration.bundleIdentifier)@\(Configuration.appVersion)"
                    options.releaseName = "\(release)+\(Configuration.buildNumber)"

                    // ============================================
                    // TRACING & PERFORMANCE (capture everything)
                    // ============================================
                    // 100% sampling since single user - no cost concerns
                    options.tracesSampleRate = 1.0

                    // Automatic instrumentation
                    options.enableAutoPerformanceTracing = true
                    options.enableNetworkTracking = true        // HTTP request spans
                    options.enableFileIOTracing = true          // File read/write spans
                    options.enableCoreDataTracing = true        // Core Data operations
                    options.enableUserInteractionTracing = true // Taps, swipes, gestures
                    options.enableSwizzling = true              // Required for automatic instrumentation

                    // App hang detection - detect frozen UI (main thread blocked)
                    options.enableAppHangTracking = true
                    options.appHangTimeoutInterval = 2.0        // Report hangs > 2 seconds

                    // Capture HTTP errors
                    options.enableCaptureFailedRequests = true
                    options.failedRequestStatusCodes = [
                        HttpStatusCodeRange(min: 400, max: 599)  // All 4xx and 5xx
                    ]

                    // ============================================
                    // PROFILING (CPU profiling for performance issues)
                    // ============================================
                    options.configureProfiling = { profiling in
                        profiling.lifecycle = .trace            // Profile during traces
                        profiling.sessionSampleRate = 1.0       // 100% of sessions
                    }

                    // ============================================
                    // SESSION REPLAY (video-like playback of sessions)
                    // ============================================
                    options.sessionReplay.sessionSampleRate = 1.0    // Record 100% of sessions
                    options.sessionReplay.onErrorSampleRate = 1.0    // Definitely record if error occurs
                    // Note: Replay auto-masks sensitive content by default

                    // ============================================
                    // STRUCTURED LOGS (Sentry 9.x+)
                    // ============================================
                    options.enableLogs = true

                    // ============================================
                    // BREADCRUMBS (trail of events before errors)
                    // ============================================
                    options.maxBreadcrumbs = 100
                    options.enableAutoBreadcrumbTracking = true
                    options.enableNetworkBreadcrumbs = true
                    #if os(iOS)
                    options.enableUIViewControllerTracing = true
                    #endif

                    // ============================================
                    // DISTRIBUTED TRACING (connect to backend)
                    // ============================================
                    // Only send trace headers to our own backend, not third parties
                    options.tracePropagationTargets = Configuration.tracePropagationTargets

                    // ============================================
                    // ATTACHMENTS & SCREENSHOTS
                    // ============================================
                    options.attachScreenshot = true             // Capture screenshot on errors
                    options.attachViewHierarchy = true          // Capture view hierarchy on errors
                    options.attachStacktrace = true             // Attach stack traces to all events

                    // ============================================
                    // SESSION TRACKING
                    // ============================================
                    options.enableAutoSessionTracking = true
                    options.sessionTrackingIntervalMillis = 30_000  // 30 second session timeout
                }

                isConfigured = true
                continuation.resume()
            }
        }
    }
    // swiftlint:enable function_body_length

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

    // MARK: - Sentry Experimental Logs

    /// Log a debug message to Sentry's experimental logger
    static func logDebug(
        _ message: String,
        attributes: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, attributes: attributes, file: file, function: function, line: line)
    }

    /// Log an info message to Sentry's experimental logger
    static func logInfo(
        _ message: String,
        attributes: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, attributes: attributes, file: file, function: function, line: line)
    }

    /// Log a warning message to Sentry's experimental logger
    static func logWarning(
        _ message: String,
        attributes: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, attributes: attributes, file: file, function: function, line: line)
    }

    /// Log an error message to Sentry's experimental logger
    static func logError(
        _ message: String,
        attributes: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, attributes: attributes, file: file, function: function, line: line)
    }

    // MARK: - Private Logging Implementation

    private static func log(
        _ message: String,
        level: SentryLevel,
        attributes: [String: Any],
        file: String,
        function: String,
        line: Int
    ) {
        // Build enriched attributes
        var enrichedAttributes = attributes
        enrichedAttributes["file"] = URL(fileURLWithPath: file).lastPathComponent
        enrichedAttributes["function"] = function
        enrichedAttributes["line"] = line
        enrichedAttributes["device"] = deviceIdentifier
        enrichedAttributes["timestamp"] = ISO8601DateFormatter().string(from: Date())

        // Convert to string values for Sentry
        let stringAttributes = enrichedAttributes.mapValues { "\($0)" }

        // Send to Sentry's structured logger (9.x+ API)
        let logger = SentrySDK.logger
        switch level {
        case .debug:
            logger.debug(message, attributes: stringAttributes)
        case .info:
            logger.info(message, attributes: stringAttributes)
        case .warning:
            logger.warn(message, attributes: stringAttributes)
        case .error:
            logger.error(message, attributes: stringAttributes)
        case .fatal:
            logger.fatal(message, attributes: stringAttributes)
        @unknown default:
            logger.info(message, attributes: stringAttributes)
        }

        // Also add as breadcrumb for correlation with crashes
        let breadcrumb = Breadcrumb()
        breadcrumb.level = level
        breadcrumb.category = "app.log"
        breadcrumb.message = message
        breadcrumb.data = stringAttributes
        SentrySDK.addBreadcrumb(breadcrumb)

        // Console output in debug builds
        #if DEBUG
        let levelString: String
        switch level {
        case .debug: levelString = "DEBUG"
        case .info: levelString = "INFO"
        case .warning: levelString = "WARNING"
        case .error: levelString = "ERROR"
        case .fatal: levelString = "FATAL"
        default: levelString = "LOG"
        }
        let attributeString = attributes.isEmpty ? "" : " \(attributes)"
        os_log("[%{public}@] %{public}@%{public}@", levelString, message, attributeString)
        #endif
    }

    // MARK: - Device Identifier

    /// Returns cached device identifier for thread-safe access from any context.
    /// Falls back to "unknown" if not yet configured.
    private static var deviceIdentifier: String {
        cachedDeviceId ?? "unknown"
    }

    /// Builds the device identifier string. Must be called from MainActor
    /// due to UIDevice access. Called once during configure() and cached.
    @MainActor
    private static func buildDeviceIdentifier() -> String {
        #if os(iOS)
        let model = UIDevice.current.model
        let version = UIDevice.current.systemVersion
        return "\(model)-iOS\(version)"
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        return "macOS-\(version)"
        #else
        return "unknown"
        #endif
    }
}

// MARK: - Sync-Specific Logging

extension ErrorReportingService {
    /// Log a sync operation start
    static func logSyncStart(syncId: String, trigger: String) {
        logInfo("Sync started", attributes: [
            "syncId": syncId,
            "trigger": trigger
        ])
    }

    /// Log a sync operation completion
    static func logSyncComplete(syncId: String, duration: TimeInterval, itemsUploaded: Int, itemsDownloaded: Int) {
        logInfo("Sync completed", attributes: [
            "syncId": syncId,
            "duration": String(format: "%.2f", duration),
            "itemsUploaded": itemsUploaded,
            "itemsDownloaded": itemsDownloaded
        ])
    }

    /// Log a sync failure with server issue detection
    static func logSyncFailure(
        syncId: String,
        duration: TimeInterval,
        error: Error,
        failureReason: String,
        internetReachable: Bool
    ) {
        if internetReachable {
            // Server issue - this is critical, internet works but sync failed
            logError("SYNC FAILED - SERVER ISSUE", attributes: [
                "syncId": syncId,
                "duration": String(format: "%.2f", duration),
                "reason": failureReason,
                "error": error.localizedDescription,
                "internetReachable": true
            ])

            // Also capture as Sentry event for alerting
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "server_issue", key: "sync_failure_type")
                scope.setExtra(value: failureReason, key: "failure_reason")
                scope.setExtra(value: syncId, key: "sync_id")
            }
        } else {
            // Expected offline behavior - info level
            logInfo("Sync skipped - offline", attributes: [
                "syncId": syncId,
                "duration": String(format: "%.2f", duration),
                "reason": failureReason,
                "internetReachable": false
            ])
        }
    }

    // MARK: - API Response Logging

    /// Log an API response for observability
    static func logAPIResponse(endpoint: String, statusCode: Int, responseSize: Int?, error: String? = nil) {
        let attributes: [String: Any] = [
            "endpoint": endpoint,
            "status": statusCode,
            "responseSize": responseSize ?? 0
        ]

        if (200...299).contains(statusCode) {
            logDebug("API success", attributes: attributes)
        } else if (400...499).contains(statusCode) {
            var warningAttrs = attributes
            if let error = error {
                warningAttrs["error"] = String(error.prefix(500))
            }
            logWarning("API client error", attributes: warningAttrs)
        } else if (500...599).contains(statusCode) {
            var errorAttrs = attributes
            if let error = error {
                errorAttrs["error"] = String(error.prefix(500))
            }
            logError("API server error", attributes: errorAttrs)
        }
    }

    // MARK: - App Lifecycle Logging

    /// Log app launch
    static func logAppLaunch(isWarmLaunch: Bool) {
        logInfo("App launched", attributes: [
            "launchType": isWarmLaunch ? "warm" : "cold"
        ])
    }

    /// Log app entering foreground
    static func logAppForeground() {
        logInfo("App entered foreground")
    }

    /// Log app entering background
    static func logAppBackground(pendingSyncItems: Int) {
        logInfo("App entered background", attributes: [
            "pendingSyncItems": pendingSyncItems
        ])
    }
}
