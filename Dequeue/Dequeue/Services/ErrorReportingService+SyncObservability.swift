//
//  ErrorReportingService+SyncObservability.swift
//  Dequeue
//
//  Remote observability for sync operations. Provides structured Sentry breadcrumbs,
//  error events, and performance transactions so sync behaviour can be diagnosed
//  and profiled without Xcode console logs.
//
//  DEQ-246: Structured Sentry breadcrumbs for all sync & network operations
//  DEQ-247: Fire Sentry error events on critical API failures (4xx/5xx)
//  DEQ-248: Sentry performance transactions for sync health metrics
//

import Foundation
import Sentry

// MARK: - Sync State Observability

extension ErrorReportingService {
    /// Log a sync state transition (e.g., disconnected → connecting → connected)
    static func logSyncStateTransition(from: String, to: String, trigger: String? = nil) {
        var data: [String: Any] = [
            "from": from,
            "to": to
        ]
        if let trigger { data["trigger"] = trigger }

        addBreadcrumb(
            category: "sync.state",
            message: "Sync state: \(from) → \(to)",
            data: data
        )
    }

    /// Log WebSocket connection attempt
    static func logWebSocketConnecting(url: String) {
        addBreadcrumb(
            category: "sync.websocket",
            message: "WebSocket connecting",
            data: [
                "url": redactToken(in: url)
            ]
        )
    }

    /// Log WebSocket connected successfully
    static func logWebSocketConnected() {
        addBreadcrumb(
            category: "sync.websocket",
            message: "WebSocket connected",
            level: .info
        )
    }

    /// Log WebSocket disconnection
    static func logWebSocketDisconnected(reason: String, code: Int? = nil) {
        var data: [String: Any] = ["reason": reason]
        if let code { data["closeCode"] = code }

        addBreadcrumb(
            category: "sync.websocket",
            message: "WebSocket disconnected",
            level: .warning,
            data: data
        )
    }

    /// Log WebSocket error — fires a Sentry error event for alerting
    static func logWebSocketError(_ error: Error, reconnectAttempt: Int) {
        let errorMessage = truncateErrorMessage(error.localizedDescription)

        addBreadcrumb(
            category: "sync.websocket",
            message: "WebSocket error",
            level: .error,
            data: [
                "error": errorMessage,
                "reconnectAttempt": reconnectAttempt
            ]
        )

        // Fire Sentry error event on repeated failures (3+)
        if reconnectAttempt >= 3 {
            SentrySDK.capture(message: "WebSocket connection failing repeatedly") { scope in
                scope.setLevel(.error)
                scope.setTag(value: "websocket_failure", key: "sync_error_type")
                scope.setExtra(value: reconnectAttempt, key: "reconnect_attempt")
                scope.setExtra(value: errorMessage, key: "last_error")
            }
        }
    }

    // MARK: - Network Request Observability

    /// Log an HTTP request to sync/API endpoints with full context
    static func logSyncNetworkRequest(
        method: String,
        url: String,
        statusCode: Int,
        responseSize: Int?,
        duration: TimeInterval,
        error: String? = nil
    ) {
        let redactedURL = redactToken(in: url)

        var data: [String: Any] = [
            "method": method,
            "url": redactedURL,
            "statusCode": statusCode,
            "durationMs": Int(duration * 1_000)
        ]
        if let responseSize { data["responseSize"] = responseSize }
        if let error { data["error"] = truncateErrorMessage(error) }

        let level: SentryLevel
        switch statusCode {
        case 200...299:
            level = .info
        case 400...499:
            level = .warning
        case 500...599:
            level = .error
        default:
            level = .warning
        }

        addBreadcrumb(
            category: "sync.http",
            message: "\(method) \(redactedURL) → \(statusCode)",
            level: level,
            data: data
        )

        // DEQ-247: Fire Sentry error events on critical failures
        if statusCode >= 400 {
            fireSyncNetworkError(
                method: method,
                url: redactedURL,
                statusCode: statusCode,
                error: error,
                duration: duration
            )
        }
    }

    /// Log a sync pull operation (event replay from stacks-sync)
    static func logSyncPull(eventCount: Int, duration: TimeInterval, checkpoint: String?) {
        addBreadcrumb(
            category: "sync.pull",
            message: "Pulled \(eventCount) events",
            data: [
                "eventCount": eventCount,
                "durationMs": Int(duration * 1_000),
                "checkpoint": checkpoint ?? "none"
            ]
        )
    }

    /// Log a sync push operation (sending local events to stacks-sync)
    static func logSyncPush(eventCount: Int, duration: TimeInterval, success: Bool) {
        addBreadcrumb(
            category: "sync.push",
            message: success ? "Pushed \(eventCount) events" : "Push failed (\(eventCount) events)",
            level: success ? .info : .warning,
            data: [
                "eventCount": eventCount,
                "durationMs": Int(duration * 1_000),
                "success": success
            ]
        )
    }

    // MARK: - Projection Sync Observability

    /// Log projection sync start
    static func logProjectionSyncStart() {
        addBreadcrumb(
            category: "sync.projection",
            message: "Projection sync started",
            data: [:]
        )
    }

    /// Log projection sync completion with entity counts
    static func logProjectionSyncComplete(
        stacks: Int,
        tasks: Int,
        arcs: Int,
        tags: Int,
        reminders: Int,
        duration: TimeInterval
    ) {
        addBreadcrumb(
            category: "sync.projection",
            message: "Projection sync complete",
            data: [
                "stacks": stacks,
                "tasks": tasks,
                "arcs": arcs,
                "tags": tags,
                "reminders": reminders,
                "totalEntities": stacks + tasks + arcs + tags + reminders,
                "durationMs": Int(duration * 1_000)
            ]
        )
    }

    /// Log projection sync failure
    static func logProjectionSyncFailed(error: Error, duration: TimeInterval) {
        let errorMessage = truncateErrorMessage(error.localizedDescription)

        addBreadcrumb(
            category: "sync.projection",
            message: "Projection sync failed",
            level: .error,
            data: [
                "error": errorMessage,
                "durationMs": Int(duration * 1_000)
            ]
        )

        // Fire Sentry error event — projection sync failure is critical
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: "projection_sync_failure", key: "sync_error_type")
            scope.setExtra(value: Int(duration * 1_000), key: "duration_ms")
        }
    }

    // MARK: - Auth Observability

    /// Log auth token refresh
    static func logAuthTokenRefresh(success: Bool, error: String? = nil) {
        var data: [String: Any] = ["success": success]
        if let error { data["error"] = truncateErrorMessage(error) }

        addBreadcrumb(
            category: "sync.auth",
            message: success ? "Token refresh succeeded" : "Token refresh failed",
            level: success ? .info : .error,
            data: data
        )

        // Fire Sentry error on auth failure — means sync will break
        if !success {
            SentrySDK.capture(message: "Auth token refresh failed") { scope in
                scope.setLevel(.error)
                scope.setTag(value: "auth_failure", key: "sync_error_type")
                if let error { scope.setExtra(value: error, key: "error") }
            }
        }
    }

    // MARK: - Certificate Pinning Observability

    /// Log certificate pinning validation result.
    /// nonisolated because CertificatePinningDelegate calls this from a nonisolated URLSession delegate context.
    nonisolated static func logCertPinningResult(domain: String, matched: Bool, hashes: [String]) {
        // Dispatch to MainActor since addBreadcrumb and SentrySDK are MainActor-isolated
        Task { @MainActor in
            addBreadcrumb(
                category: "sync.tls",
                message: matched ? "Cert pinning passed for \(domain)" : "Cert pinning FAILED for \(domain)",
                level: matched ? .info : .error,
                data: [
                    "domain": domain,
                    "matched": matched,
                    "actualHashes": hashes.joined(separator: ", ")
                ]
            )

            if !matched {
                SentrySDK.capture(message: "Certificate pinning validation failed") { scope in
                    scope.setLevel(.error)
                    scope.setTag(value: "cert_pinning_failure", key: "sync_error_type")
                    scope.setTag(value: domain, key: "domain")
                    scope.setExtra(value: hashes, key: "actual_hashes")
                }
            }
        }
    }

    // MARK: - Performance Transactions (DEQ-248)
    //
    // Design note: The Sentry `Span` protocol is @MainActor-isolated in strict Swift 6
    // concurrency mode, so all Sentry performance API calls must happen on MainActor.
    // SyncManager (a custom actor) therefore records plain `Date` values for timing,
    // then calls these @MainActor methods at operation completion to create and
    // immediately finish a transaction with a retroactive startTimestamp.
    //
    // This gives accurate total-duration traces in Sentry Performance without
    // any Span objects ever crossing actor boundaries.

    /// Timing and entity-count metrics captured by `SyncManager` during a projection sync.
    struct ProjectionSyncMetrics {
        let syncId: String
        let syncStart: Date
        let fetchDurationMs: Int
        let populateDurationMs: Int
        let stacks: Int
        let tasks: Int
        let arcs: Int
        let tags: Int
        let reminders: Int
        let success: Bool
    }

    /// Records a completed projection sync as a Sentry performance transaction.
    ///
    /// The transaction's start timestamp is set retroactively to `metrics.syncStart`,
    /// so the duration visible in Sentry Performance matches the actual wall-clock time.
    @MainActor
    static func recordProjectionSyncTransaction(_ metrics: ProjectionSyncMetrics) {
        let tx = SentrySDK.startTransaction(name: "Projection Sync", operation: "sync.projection")
        tx.startTimestamp = metrics.syncStart
        tx.setData(value: metrics.syncId, key: "sync_id")

        let totalEntities = metrics.stacks + metrics.tasks + metrics.arcs + metrics.tags + metrics.reminders
        tx.setData(value: totalEntities, key: "entity_count")
        tx.setData(value: metrics.stacks, key: "stacks")
        tx.setData(value: metrics.tasks, key: "tasks")
        tx.setData(value: metrics.arcs, key: "arcs")
        tx.setData(value: metrics.tags, key: "tags")
        tx.setData(value: metrics.reminders, key: "reminders")

        // Sub-operation durations as Sentry measurements (visible alongside the transaction)
        tx.setMeasurement(name: "fetch_duration_ms", value: NSNumber(value: metrics.fetchDurationMs))
        tx.setMeasurement(name: "populate_duration_ms", value: NSNumber(value: metrics.populateDurationMs))

        tx.finish(status: metrics.success ? .ok : .internalError)
    }

    /// Timing metrics captured by `SyncManager` during an event push cycle.
    struct EventPushMetrics {
        let syncId: String
        let pushStart: Date
        let httpDurationMs: Int
        let eventCount: Int
        let httpStatusCode: Int
        let success: Bool
    }

    /// Records a completed event push cycle as a Sentry performance transaction.
    ///
    /// The transaction's start timestamp is set retroactively to `metrics.pushStart`.
    @MainActor
    static func recordEventPushTransaction(_ metrics: EventPushMetrics) {
        let tx = SentrySDK.startTransaction(name: "Event Push", operation: "sync.push")
        tx.startTimestamp = metrics.pushStart
        tx.setData(value: metrics.syncId, key: "sync_id")
        tx.setData(value: metrics.eventCount, key: "event_count")
        tx.setData(value: metrics.httpStatusCode, key: "http.status_code")
        tx.setMeasurement(name: "http_duration_ms", value: NSNumber(value: metrics.httpDurationMs))
        tx.finish(status: metrics.success ? .ok : .internalError)
    }

    // MARK: - Private Helpers

    /// Fire a Sentry error event for critical API failures
    private static func fireSyncNetworkError(
        method: String,
        url: String,
        statusCode: Int,
        error: String?,
        duration: TimeInterval
    ) {
        let severity: SentryLevel
        let errorType: String

        switch statusCode {
        case 401:
            severity = .error
            errorType = "auth_rejected"
        case 404:
            severity = .error
            errorType = "endpoint_not_found"
        case 500...599:
            severity = .error
            errorType = "server_error"
        default:
            severity = .warning
            errorType = "client_error_\(statusCode)"
        }

        SentrySDK.capture(message: "Sync API error: \(method) \(url) → \(statusCode)") { scope in
            scope.setLevel(severity)
            scope.setTag(value: errorType, key: "sync_error_type")
            scope.setTag(value: "\(statusCode)", key: "http_status")
            scope.setTag(value: method, key: "http_method")
            scope.setExtra(value: url, key: "url")
            scope.setExtra(value: Int(duration * 1_000), key: "duration_ms")
            if let error { scope.setExtra(value: error, key: "response_body") }
        }
    }

    /// Redact auth tokens from URLs for safe logging
    private static func redactToken(in url: String) -> String {
        // Redact token= query parameter
        guard let range = url.range(of: "token=") else { return url }
        let afterToken = url[range.upperBound...]
        if let ampersand = afterToken.firstIndex(of: "&") {
            return String(url[..<range.upperBound]) + "[REDACTED]" + String(url[ampersand...])
        }
        return String(url[..<range.upperBound]) + "[REDACTED]"
    }
}
