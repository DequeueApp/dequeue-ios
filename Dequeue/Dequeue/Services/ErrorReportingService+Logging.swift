//
//  ErrorReportingService+Logging.swift
//  Dequeue
//
//  Domain-specific logging extensions for ErrorReportingService
//

import Foundation
import Sentry

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
                warningAttrs["error"] = truncateErrorMessage(error)
            }
            logWarning("API client error", attributes: warningAttrs)
        } else if (500...599).contains(statusCode) {
            var errorAttrs = attributes
            if let error = error {
                errorAttrs["error"] = truncateErrorMessage(error)
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
