//
//  SyncManager.swift
//  Dequeue
//
//  Handles sync with the backend via WebSocket and HTTP
//

// swiftlint:disable file_length

import Foundation
import SwiftData
import os.log

/// Sendable representation of Event data for cross-actor communication
private struct EventData: Sendable {
    let id: String
    let timestamp: Date
    let type: String
    let payload: Data
    let userId: String
    let deviceId: String
    let appId: String
    let payloadVersion: Int
}

/// Result of processing a pull response, used for pagination
private struct PullResult {
    let eventsProcessed: Int
    let nextCheckpoint: String?
    let hasMore: Bool
}

// swiftlint:disable:next type_body_length
actor SyncManager {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var token: String?
    private var userId: String?
    private var deviceId: String?  // Cached at connection time to avoid actor hops
    private var isConnected = false
    private var isConnecting = false  // Guard against concurrent connection attempts
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0

    /// Push interval for pending events. This is a fallback - immediate push after each
    /// save handles the common case, but this catches any events that slip through.
    private let periodicPushIntervalSeconds: UInt64 = 5

    /// Fallback pull interval when WebSocket is healthy. This is a safety net for edge cases
    /// where WebSocket might miss an event. Normal operation relies on WebSocket for real-time
    /// updates - this is NOT the primary sync mechanism.
    private let fallbackPullIntervalMinutes: UInt64 = 5

    /// Heartbeat interval for WebSocket keep-alive
    private let heartbeatIntervalSeconds: UInt64 = 30

    private let modelContainer: ModelContainer

    /// Closure for refreshing authentication tokens when they expire.
    /// Must be @Sendable to allow safe capture across actor boundaries.
    /// Typically provided by AuthService and runs on MainActor.
    /// See DequeueApp.swift:178 for usage example with @MainActor closure.
    private var getTokenFunction: (@Sendable () async throws -> String)?

    private var periodicPushTask: Task<Void, Never>?
    private var fallbackPullTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var networkMonitorTask: Task<Void, Never>?

    /// Flag to enable/disable WebSocket push optimization.
    /// When enabled, events are sent via WebSocket for immediate delivery to other devices,
    /// in addition to HTTP which remains authoritative for acknowledgment.
    /// This can be disabled via remote config if issues arise.
    private var webSocketPushEnabled = true

    // Health monitoring
    private var consecutiveHeartbeatFailures = 0
    private let maxConsecutiveHeartbeatFailures = 3
    private var lastSuccessfulHeartbeat: Date?

    // Initial sync tracking
    private var _isInitialSyncInProgress = false
    private var _initialSyncEventsProcessed = 0
    private var _initialSyncTotalEvents = 0

    /// Whether an initial sync is currently in progress (fresh device downloading events)
    var isInitialSyncInProgress: Bool {
        _isInitialSyncInProgress
    }

    /// Progress of initial sync (0.0 to 1.0), or nil if total is unknown
    var initialSyncProgress: Double? {
        guard _isInitialSyncInProgress, _initialSyncTotalEvents > 0 else { return nil }
        return Double(_initialSyncEventsProcessed) / Double(_initialSyncTotalEvents)
    }

    /// Number of events processed during initial sync
    var initialSyncEventsProcessed: Int {
        _initialSyncEventsProcessed
    }

    // Key for storing last sync checkpoint in UserDefaults
    private let lastSyncCheckpointKey = "com.dequeue.lastSyncCheckpoint"

    // ISO8601 formatter that supports fractional seconds (Go's RFC3339Nano format)
    // Note: ISO8601DateFormatter is thread-safe but not marked Sendable in current SDK
    nonisolated(unsafe) private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Standard ISO8601 formatter without fractional seconds
    // Note: ISO8601DateFormatter is thread-safe but not marked Sendable in current SDK
    nonisolated(unsafe) private static let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // Pre-compiled regex patterns for timestamp parsing (compiled once, reused for performance)
    // SAFETY: Force unwrap is safe because:
    // 1. Patterns are compile-time constants (hardcoded string literals)
    // 2. Patterns are valid regex syntax (verified by tests and manual inspection)
    // 3. Compilation only happens once at static initialization, not at runtime
    // swiftlint:disable force_try
    private static let nanosecondsRegex: NSRegularExpression = {
        // Matches ISO8601 timestamps with nanosecond precision, captures first 3 decimal places
        try! NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.(\d{3})\d*(Z|[+-]\d{2}:\d{2})"#)
    }()

    private static let fractionalSecondsRegex: NSRegularExpression = {
        // Matches ISO8601 timestamps with any fractional seconds (for removal)
        try! NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.\d+(Z|[+-]\d{2}:\d{2})"#)
    }()
    // swiftlint:enable force_try

    /// Generates a short sync ID for tracking sync operations in logs.
    /// Uses first 8 characters of a UUID for brevity while maintaining uniqueness.
    private static func generateSyncId() -> String {
        String(UUID().uuidString.prefix(8))
    }

    /// Parses ISO8601 timestamp, handling Go's RFC3339Nano format with nanosecond precision.
    /// Go sends timestamps like "2024-01-15T10:30:45.123456789Z" but Swift's ISO8601DateFormatter
    /// only handles milliseconds (3 decimal places). We truncate to milliseconds for parsing.
    private static func parseISO8601(_ string: String) -> Date? {
        // First, try parsing as-is with fractional seconds
        if let date = iso8601WithFractionalSeconds.date(from: string) {
            return date
        }

        // If that fails, try truncating nanoseconds to milliseconds
        // Go sends: "2024-01-15T10:30:45.123456789Z"
        // Swift needs: "2024-01-15T10:30:45.123Z"
        let truncated = truncateNanosecondsToMilliseconds(string)
        if let date = iso8601WithFractionalSeconds.date(from: truncated) {
            return date
        }

        // Fall back to standard format without fractional seconds
        if let date = iso8601Standard.date(from: string) {
            return date
        }

        // Last resort: try removing fractional seconds entirely
        let withoutFractional = removeFractionalSeconds(string)
        return iso8601Standard.date(from: withoutFractional)
    }

    /// Truncates nanosecond precision to millisecond precision for ISO8601 parsing
    /// Input:  "2024-01-15T10:30:45.123456789Z"
    /// Output: "2024-01-15T10:30:45.123Z"
    private static func truncateNanosecondsToMilliseconds(_ string: String) -> String {
        let range = NSRange(string.startIndex..., in: string)
        return nanosecondsRegex.stringByReplacingMatches(in: string, range: range, withTemplate: "$1.$2$3")
    }

    /// Removes fractional seconds entirely from ISO8601 timestamp
    /// Input:  "2024-01-15T10:30:45.123456789Z"
    /// Output: "2024-01-15T10:30:45Z"
    private static func removeFractionalSeconds(_ string: String) -> String {
        let range = NSRange(string.startIndex..., in: string)
        return fractionalSecondsRegex.stringByReplacingMatches(in: string, range: range, withTemplate: "$1$2")
    }

    /// Extracts the entity ID from an event payload for history queries.
    /// Returns the ID of the entity (stack, task, reminder, device) that this event relates to.
    private static func extractEntityId(from payload: [String: Any], eventType: String) -> String? {
        // Check for direct ID fields first (used in most payloads)
        if eventType.hasPrefix("stack.") {
            if let stackId = payload["stackId"] as? String {
                return stackId
            }
        } else if eventType.hasPrefix("task.") {
            if let taskId = payload["taskId"] as? String {
                return taskId
            }
        } else if eventType.hasPrefix("reminder.") {
            if let reminderId = payload["reminderId"] as? String {
                return reminderId
            }
        } else if eventType.hasPrefix("device.") {
            // Device events use state.id for entity ID (not deviceId which is the hardware ID)
            if let state = payload["state"] as? [String: Any],
               let entityId = state["id"] as? String {
                return entityId
            }
        }

        // Fallback: check for state.id (used in created/updated events)
        if let state = payload["state"] as? [String: Any],
           let entityId = state["id"] as? String {
            return entityId
        }

        // Fallback: check for fullState.id (used in updated events)
        if let fullState = payload["fullState"] as? [String: Any],
           let entityId = fullState["id"] as? String {
            return entityId
        }

        return nil
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Checkpoint Persistence

    private func saveLastSyncCheckpoint(_ checkpoint: String) {
        UserDefaults.standard.set(checkpoint, forKey: lastSyncCheckpointKey)
    }

    private func getLastSyncCheckpoint() -> String {
        if let checkpoint = UserDefaults.standard.string(forKey: lastSyncCheckpointKey) {
            return checkpoint
        }
        // Default to Unix epoch for initial sync (pull all events)
        return Self.iso8601Standard.string(from: Date(timeIntervalSince1970: 0))
    }

    /// Checks if this is a fresh device that needs initial sync (no checkpoint saved)
    private func isInitialSync() -> Bool {
        return UserDefaults.standard.string(forKey: lastSyncCheckpointKey) == nil
    }

    // MARK: - Connection

    func connect(userId: String, token: String, getToken: @escaping @Sendable () async throws -> String) async throws {
        // Disconnect any existing connection first to ensure clean state
        if isConnected || webSocketTask != nil {
            os_log("[Sync] Disconnecting existing connection before reconnecting")
            disconnectInternal()
        }

        self.userId = userId
        self.token = token
        self.getTokenFunction = getToken
        // Cache deviceId at connection time to avoid actor hops during push
        self.deviceId = await DeviceService.shared.getDeviceId()

        try await connectWebSocket()
        startSyncTasks()
    }

    /// Ensures sync is connected with fresh credentials.
    /// Call this when app becomes active or after re-authentication to ensure sync is working.
    /// Unlike `connect()`, this is safe to call repeatedly - it's a no-op if already connected.
    func ensureConnected(
        userId: String,
        token: String,
        getToken: @escaping @Sendable () async throws -> String
    ) async throws {
        // Guard against concurrent connection attempts
        guard !isConnecting else {
            os_log("[Sync] Connection already in progress, skipping")
            return
        }

        // If already in healthy connected state, update credentials and return
        if isHealthyConnection {
            // Update credentials even if healthy (token may have refreshed)
            self.userId = userId
            self.token = token
            self.getTokenFunction = getToken
            os_log("[Sync] Already connected with healthy connection, credentials updated")
            return
        }

        os_log("[Sync] Not connected, establishing connection")
        isConnecting = true
        defer { isConnecting = false }

        // Update credentials before connecting
        self.userId = userId
        self.token = token
        self.getTokenFunction = getToken

        // Cache deviceId at connection time to avoid actor hops during push
        self.deviceId = await DeviceService.shared.getDeviceId()

        try await connectWebSocket()
        startSyncTasks()
    }

    /// Returns true if sync appears to be in a healthy connected state
    var isHealthyConnection: Bool {
        isConnected && webSocketTask != nil && getTokenFunction != nil
    }

    func disconnect() {
        disconnectInternal()
        // Clear credentials on explicit disconnect (logout)
        token = nil
        userId = nil
        getTokenFunction = nil
    }

    /// Internal disconnect that cleans up connection state but preserves credentials.
    /// Used when reconnecting to avoid losing the ability to authenticate.
    private func disconnectInternal() {
        periodicPushTask?.cancel()
        periodicPushTask = nil
        fallbackPullTask?.cancel()
        fallbackPullTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listenTask?.cancel()
        listenTask = nil
        networkMonitorTask?.cancel()
        networkMonitorTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        consecutiveHeartbeatFailures = 0
        lastSuccessfulHeartbeat = nil
    }

    private func connectWebSocket() async throws {
        guard let token = try await refreshToken() else {
            throw SyncError.notAuthenticated
        }

        let wsUrl = await MainActor.run {
            Configuration.syncAPIBaseURL
                .absoluteString
                .replacingOccurrences(of: "https://", with: "wss://")
                .replacingOccurrences(of: "http://", with: "ws://")
        }

        let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        guard let url = URL(string: "\(wsUrl)/ws?token=\(encodedToken)") else {
            throw SyncError.invalidURL
        }

        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        isConnected = true
        reconnectAttempts = 0
        consecutiveHeartbeatFailures = 0
        lastSuccessfulHeartbeat = Date()

        startListening()
        startHeartbeat()
        startNetworkMonitoring()

        await MainActor.run {
            ErrorReportingService.addBreadcrumb(
                category: "sync",
                message: "WebSocket connected"
            )
        }
    }

    private func refreshToken() async throws -> String? {
        if let getToken = getTokenFunction {
            let newToken = try await getToken()
            self.token = newToken
            return newToken
        }
        return token
    }

    // MARK: - Push Events

    func pushEvents() async throws {
        let startTime = Date()
        let syncId = Self.generateSyncId()

        guard let token = try await refreshToken() else {
            throw SyncError.notAuthenticated
        }

        let pendingEventData = try await MainActor.run {
            // Use mainContext for consistency with SwiftUI observation
            let context = modelContainer.mainContext
            let eventService = EventService.readOnly(modelContext: context)
            let events = try eventService.fetchPendingEvents()
            return events.map { event in
                EventData(
                    id: event.id,
                    timestamp: event.timestamp,
                    type: event.type,
                    payload: event.payload,
                    userId: event.userId,
                    deviceId: event.deviceId,
                    appId: event.appId,
                    payloadVersion: event.payloadVersion
                )
            }
        }

        guard !pendingEventData.isEmpty else { return }

        os_log("[Sync] Push started: syncId=\(syncId), events=\(pendingEventData.count)")

        // Use cached deviceId (falls back to fetching if not cached, e.g., during reconnect)
        let eventDeviceId: String
        if let cachedDeviceId = deviceId {
            eventDeviceId = cachedDeviceId
        } else {
            eventDeviceId = await DeviceService.shared.getDeviceId()
        }

        let syncEvents = pendingEventData.map { eventData -> [String: Any] in
            let payload: Any
            if let payloadDict = try? JSONSerialization.jsonObject(with: eventData.payload) {
                payload = payloadDict
            } else {
                payload = [:]
            }

            // Use stored userId/deviceId/appId from the event (captured at creation time)
            // Fall back to cached values for backward compatibility
            let eventUserId = !eventData.userId.isEmpty ? eventData.userId : (self.userId ?? "")
            let eventDeviceIdToUse = !eventData.deviceId.isEmpty ? eventData.deviceId : eventDeviceId

            return [
                "id": eventData.id,
                "user_id": eventUserId,
                "device_id": eventDeviceIdToUse,
                "app_id": eventData.appId,
                "ts": SyncManager.iso8601WithFractionalSeconds.string(from: eventData.timestamp),
                "type": eventData.type,
                "payload": payload,
                "payload_version": eventData.payloadVersion
            ]
        }

        // Send via WebSocket for immediate delivery to other devices (fire-and-forget optimization).
        // This runs concurrently with HTTP push - WebSocket provides low-latency broadcast while
        // HTTP remains authoritative for acknowledgment. Backend deduplicates by event ID.
        // Uses utility priority since this is a background optimization, not critical path.
        // Note: We serialize to Data here (before Task) because Data is Sendable, while [[String: Any]] is not.
        if webSocketPushEnabled && isConnected {
            let eventCount = syncEvents.count
            // Serialize before Task to avoid data race - Data is Sendable, [[String: Any]] is not
            if let wsPayloadData = try? JSONSerialization.data(withJSONObject: ["events": syncEvents]) {
                Task(priority: .utility) { [weak self, wsPayloadData] in
                    guard let self = self else { return }
                    do {
                        try await self.sendViaWebSocket(data: wsPayloadData)
                        os_log("[Sync] Sent \(eventCount) events via WebSocket (optimistic)")
                    } catch {
                        // Fire-and-forget: log but don't fail - HTTP will handle it
                        os_log("[Sync] WebSocket send failed for \(eventCount) events (HTTP will handle): \(error)")
                    }
                }
            }
        }

        // Always send via HTTP for authoritative acknowledgment and sync state management
        let pushURL = await MainActor.run { Configuration.syncAPIBaseURL.appendingPathComponent("sync/push") }
        var request = URLRequest(url: pushURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["events": syncEvents])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.pushFailed
        }

        do {
            if httpResponse.statusCode == 401 {
                // Token expired, try to refresh and retry
                guard let newToken = try await refreshToken() else {
                    throw SyncError.notAuthenticated
                }
                request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await session.data(for: request)

                guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                      retryHttpResponse.statusCode == 200 else {
                    throw SyncError.pushFailed
                }

                try await processPushResponse(retryData, eventIds: pendingEventData.map { $0.id })
            } else if httpResponse.statusCode == 200 {
                try await processPushResponse(data, eventIds: pendingEventData.map { $0.id })
            } else {
                // Log the HTTP error
                await ErrorReportingService.logAPIResponse(
                    endpoint: "/sync/push",
                    statusCode: httpResponse.statusCode,
                    responseSize: data.count,
                    error: String(data: data, encoding: .utf8)
                )
                throw SyncError.pushFailed
            }

            // Log successful push
            let duration = Date().timeIntervalSince(startTime)
            os_log("[Sync] Push completed: syncId=\(syncId), duration=\(String(format: "%.2f", duration))s")
            await ErrorReportingService.logSyncComplete(
                syncId: syncId,
                duration: duration,
                itemsUploaded: pendingEventData.count,
                itemsDownloaded: 0
            )
        } catch {
            // Capture duration immediately, then log failure in background to avoid blocking
            // The reachability check can take 2+ seconds, which would delay sync retry unnecessarily
            let duration = Date().timeIntervalSince(startTime)
            let capturedError = error
            Task.detached(priority: .utility) {
                do {
                    let failureReason = await NetworkReachability.classifyFailure(error: capturedError)
                    await ErrorReportingService.logSyncFailure(
                        syncId: syncId,
                        duration: duration,
                        error: capturedError,
                        failureReason: failureReason.description,
                        internetReachable: failureReason.isServerProblem
                    )
                } catch {
                    // Fallback to os_log if Sentry logging fails - ensures observability is never lost
                    os_log(
                        .error,
                        "[Sync] Failed to log push failure to Sentry: \(error). Original: \(capturedError)"
                    )
                }
            }
            throw error
        }
    }

    private func processPushResponse(_ data: Data, eventIds: [String]) async throws {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acknowledged = response["acknowledged"] as? [String] else {
            return
        }

        // Convert to Set for O(1) lookup instead of O(n)
        let acknowledgedSet = Set(acknowledged)
        let syncedEventIds = eventIds.filter { acknowledgedSet.contains($0) }

        try await MainActor.run {
            // Use mainContext for consistency with SwiftUI observation
            let context = modelContainer.mainContext
            let eventService = EventService.readOnly(modelContext: context)
            let syncedEvents = try eventService.fetchEventsByIds(syncedEventIds)
            try eventService.markEventsSynced(syncedEvents)
        }

        // Handle rejected events
        if let rejected = response["rejected"] as? [String],
           let errors = response["errors"] as? [String] {
            // Convert to Set for O(1) lookup instead of O(n)
            let rejectedSet = Set(rejected)
            let rejectedEventIds = eventIds.filter { rejectedSet.contains($0) }
            for (index, eventId) in rejectedEventIds.enumerated() {
                let errorMessage = index < errors.count ? errors[index] : "Unknown error"
                os_log("[Sync] Event \(eventId) rejected: \(errorMessage)")
            }

            await MainActor.run {
                ErrorReportingService.addBreadcrumb(
                    category: "sync",
                    message: "Events rejected by server",
                    data: ["rejected_count": rejected.count, "errors": errors]
                )
            }
        }

        await MainActor.run {
            ErrorReportingService.addBreadcrumb(
                category: "sync",
                message: "Pushed \(syncedEventIds.count) events",
                data: ["total": eventIds.count, "synced": syncedEventIds.count]
            )
        }
    }

    // MARK: - WebSocket Push

    /// Sends pre-serialized event data via WebSocket for immediate delivery to other devices.
    /// This is a fire-and-forget optimization - HTTP push remains authoritative for acknowledgment.
    /// - Parameter data: JSON-encoded payload with "events" array, pre-serialized to ensure Sendable compliance.
    private func sendViaWebSocket(data: Data) async throws {
        guard isConnected, let wsTask = webSocketTask else {
            throw SyncError.connectionLost
        }

        try await wsTask.send(.data(data))
    }

    // MARK: - Pull Events

    /// Maximum events to request per pull (backend max is 1000)
    private static let pullBatchSize = 1_000

    func pullEvents() async throws {
        let startTime = Date()
        let syncId = Self.generateSyncId()
        var totalEventsDownloaded = 0

        guard let token = try await refreshToken() else {
            os_log("[Sync] Pull failed: Not authenticated")
            throw SyncError.notAuthenticated
        }

        var currentCheckpoint = await getLastSyncTimestamp()
        os_log("[Sync] Pull started: syncId=\(syncId), since=\(currentCheckpoint)")

        let pullURL = await MainActor.run { Configuration.syncAPIBaseURL.appendingPathComponent("sync/pull") }
        os_log("[Sync] Pull URL: \(pullURL.absoluteString)")

        var currentToken = token
        var pageNumber = 1

        // Pagination loop - continue fetching while server indicates more events exist
        while true {
            os_log("[Sync] Fetching page \(pageNumber), checkpoint=\(currentCheckpoint)")

            var request = URLRequest(url: pullURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "since": currentCheckpoint,
                "limit": Self.pullBatchSize
            ])

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                os_log("[Sync] Pull failed: Invalid response type")
                throw SyncError.pullFailed
            }

            os_log("[Sync] Pull response status: \(httpResponse.statusCode)")

            var pullData: Data
            if httpResponse.statusCode == 401 {
                os_log("[Sync] Token expired, refreshing...")
                guard let newToken = try await refreshToken() else {
                    os_log("[Sync] Token refresh failed")
                    throw SyncError.notAuthenticated
                }
                currentToken = newToken
                request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await session.data(for: request)

                guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                      retryHttpResponse.statusCode == 200 else {
                    os_log("[Sync] Retry failed with status: \((retryResponse as? HTTPURLResponse)?.statusCode ?? -1)")
                    throw SyncError.pullFailed
                }

                pullData = retryData
            } else if httpResponse.statusCode == 200 {
                pullData = data
            } else {
                // Log the response body for debugging
                if let responseBody = String(data: data, encoding: .utf8) {
                    os_log("[Sync] Pull failed with status \(httpResponse.statusCode): \(responseBody)")
                }
                await ErrorReportingService.logAPIResponse(
                    endpoint: "/sync/pull",
                    statusCode: httpResponse.statusCode,
                    responseSize: data.count,
                    error: String(data: data, encoding: .utf8)
                )
                throw SyncError.pullFailed
            }

            do {
                let result = try await processPullResponse(pullData)
                totalEventsDownloaded += result.eventsProcessed

                os_log(
                    "[Sync] Page \(pageNumber) complete: \(result.eventsProcessed) events, hasMore=\(result.hasMore)"
                )

                // Update checkpoint for next page (or final save)
                if let nextCheckpoint = result.nextCheckpoint {
                    currentCheckpoint = nextCheckpoint
                }

                // Exit loop if no more events to fetch
                if !result.hasMore {
                    break
                }

                pageNumber += 1
            } catch {
                // Capture duration immediately, then log failure in background to avoid blocking
                // The reachability check can take 2+ seconds, which would delay sync retry unnecessarily
                let duration = Date().timeIntervalSince(startTime)
                let capturedError = error
                Task.detached(priority: .utility) {
                    do {
                        let failureReason = await NetworkReachability.classifyFailure(error: capturedError)
                        await ErrorReportingService.logSyncFailure(
                            syncId: syncId,
                            duration: duration,
                            error: capturedError,
                            failureReason: failureReason.description,
                            internetReachable: failureReason.isServerProblem
                        )
                    } catch {
                        // Fallback to os_log if Sentry logging fails - ensures observability is never lost
                        os_log(
                            .error,
                            "[Sync] Failed to log pull failure to Sentry: \(error). Original: \(capturedError)"
                        )
                    }
                }
                throw error
            }
        }

        // Log successful pull (all pages)
        let duration = Date().timeIntervalSince(startTime)
        let durationStr = String(format: "%.2f", duration)
        os_log("[Sync] Pull done: id=\(syncId), \(durationStr)s, \(totalEventsDownloaded) events, \(pageNumber) pages")
        await ErrorReportingService.logSyncComplete(
            syncId: syncId,
            duration: duration,
            itemsUploaded: 0,
            itemsDownloaded: totalEventsDownloaded
        )
    }

    /// Process the pull response and return result with event count and pagination info
    private func processPullResponse( // 
        _ data: Data
    ) async throws -> PullResult {
        // Log raw response for debugging
        if let rawResponse = String(data: data, encoding: .utf8) {
            let preview = String(rawResponse.prefix(500))
            os_log("[Sync] Raw pull response: \(preview)\(rawResponse.count > 500 ? "..." : "")")
        }

        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            os_log("[Sync] Failed to parse pull response as JSON")
            return PullResult(eventsProcessed: 0, nextCheckpoint: nil, hasMore: false)
        }

        // Handle events being null or missing - treat as empty array
        let events: [[String: Any]]
        if let eventsArray = response["events"] as? [[String: Any]] {
            events = eventsArray
        } else if response["events"] is NSNull || response["events"] == nil {
            // Server returned null or no events - this is valid, just no events to process
            os_log("[Sync] Server returned no events (null or empty)")
            events = []
        } else {
            os_log("[Sync] Response 'events' has unexpected type. Keys: \(response.keys.joined(separator: ", "))")
            return PullResult(eventsProcessed: 0, nextCheckpoint: nil, hasMore: false)
        }

        let nextCheckpoint = response["nextCheckpoint"] as? String
        let hasMore = response["hasMore"] as? Bool ?? false
        os_log("[Sync] Next checkpoint from server: \(nextCheckpoint ?? "nil"), hasMore: \(hasMore)")

        let deviceId = await DeviceService.shared.getDeviceId()
        let isInitialSync = _isInitialSyncInProgress
        os_log("[Sync] Current device ID: \(deviceId), isInitialSync: \(isInitialSync)")

        // Filter 1: Exclude events from current device (already applied locally)
        // IMPORTANT: Skip this filter during initial sync! When the local database is empty
        // (after Delete All Data or fresh install), we need ALL events including our own.
        // The same-device filter only makes sense during normal operation when our events
        // are already applied locally and would be duplicated.
        let fromOtherDevices: [[String: Any]]
        if isInitialSync {
            // During initial sync, include events from ALL devices (including our own)
            os_log("[Sync] Initial sync - including events from current device")
            fromOtherDevices = events
        } else {
            // During normal sync, exclude events from current device (already applied locally)
            fromOtherDevices = events.filter { event in
                guard let eventDeviceId = event["device_id"] as? String else { return true }
                return eventDeviceId != deviceId
            }
        }

        // Filter 2: Exclude legacy events without payloadVersion or with version < 2
        // Legacy events from old app versions don't have userId/deviceId and may have incompatible schemas
        let filteredEvents = fromOtherDevices.filter { event in
            // Events with payloadVersion >= 2 are always accepted
            if let payloadVersion = event["payload_version"] as? Int {
                return payloadVersion >= Event.currentPayloadVersion
            }
            // Events without payloadVersion are legacy (pre-DEQ-137) - skip them
            os_log("[Sync] Skipping legacy event without payload_version: \(event["id"] as? String ?? "unknown")")
            return false
        }

        let excludedSameDevice = events.count - fromOtherDevices.count
        let excludedLegacy = fromOtherDevices.count - filteredEvents.count
        let msg = "Pull received \(events.count) events, \(filteredEvents.count) after filtering"
        os_log("[Sync] \(msg) (excluded \(excludedSameDevice) from current device, \(excludedLegacy) legacy events)")

        // Log first few events for debugging
        for (index, event) in events.prefix(3).enumerated() {
            let eventType = event["type"] as? String ?? "unknown"
            let eventId = event["id"] as? String ?? "unknown"
            let eventDeviceId = event["device_id"] as? String ?? "unknown"
            os_log("[Sync] Event \(index): type=\(eventType), id=\(eventId), device_id=\(eventDeviceId)")
        }
        if events.count > 3 {
            os_log("[Sync] ... and \(events.count - 3) more events")
        }

        // Extract counts before crossing actor boundary
        let totalCount = events.count
        let processedCount = filteredEvents.count

        if !filteredEvents.isEmpty {
            try await processIncomingEvents(filteredEvents)
        }

        // Only save checkpoint AFTER successful processing
        if let nextCheckpoint = nextCheckpoint {
            saveLastSyncCheckpoint(nextCheckpoint)
            os_log("[Sync] Checkpoint updated to \(nextCheckpoint)")
        }

        await ErrorReportingService.addBreadcrumb(
            category: "sync",
            message: "Pulled \(processedCount) events",
            data: ["total": totalCount, "processed": processedCount, "hasMore": hasMore]
        )

        return PullResult(eventsProcessed: processedCount, nextCheckpoint: nextCheckpoint, hasMore: hasMore)
    }

    private func getLastSyncTimestamp() async -> String {
        return getLastSyncCheckpoint()
    }

    // MARK: - Process Incoming Events

    private struct EventProcessingStats {
        var processed = 0
        var skipped = 0
        var incompatible = 0
        var hasReminderEvents = false
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    private func processIncomingEvents(_ events: [[String: Any]]) async throws {
        os_log("[Sync] Processing \(events.count) incoming events")
        var stats = EventProcessingStats()
        // IMPORTANT: Use mainContext so SwiftUI @Query observers see changes immediately.
        // Creating a new ModelContext would persist changes to the store, but SwiftUI views
        // using @Query observe mainContext specifically and wouldn't see the updates.
        let context = modelContainer.mainContext

        // Capture initial sync state once to avoid actor hop on every iteration
        // This is safe because initial sync state only changes on connect/disconnect,
        // not during event processing
        let trackingInitialSync = await isInitialSyncInProgress

        // DEQ-143: Batch processing to avoid N+1 queries
        // Phase 1: Parse all events and filter duplicates
        var parsedEvents: [Event] = []
        for eventData in events {
            guard let id = eventData["id"] as? String,
                  let type = eventData["type"] as? String,
                  let timestamp = eventData["ts"] as? String,
                  let payload = eventData["payload"] as? [String: Any] else {
                os_log("[Sync] Skipping event - missing required fields")
                stats.incompatible += 1
                continue
            }

            if try await isDuplicateEvent(id, context: context) {
                stats.skipped += 1
                if trackingInitialSync {
                    await incrementInitialSyncProgress()
                }
                continue
            }

            do {
                let event = try createEvent(
                    id: id,
                    type: type,
                    timestamp: timestamp,
                    payload: payload,
                    eventData: eventData
                )
                parsedEvents.append(event)
                if type.hasPrefix("reminder.") {
                    stats.hasReminderEvents = true
                }
            } catch {
                os_log("[Sync] Skipping event \(id) - failed to create: \(error.localizedDescription)")
                stats.incompatible += 1
                if trackingInitialSync {
                    await incrementInitialSyncProgress()
                }
            }
        }

        // Phase 2: Apply all events using batch prefetching (DEQ-143 fix)
        if !parsedEvents.isEmpty {
            let processed = try await ProjectorService.applyBatch(events: parsedEvents, context: context)
            stats.processed = processed
            stats.incompatible += parsedEvents.count - processed

            // Insert all successfully parsed events into context
            for event in parsedEvents {
                context.insert(event)
            }

            // Update progress for all events
            if trackingInitialSync {
                for _ in parsedEvents {
                    await incrementInitialSyncProgress()
                }
            }
        }

        try context.save()
        let summary = "processed: \(stats.processed), dupes: \(stats.skipped), incompatible: \(stats.incompatible)"
        os_log("[Sync] Saved context - \(summary)")

        if stats.hasReminderEvents {
            await rescheduleNotifications(context: context)
        }
    }

    /// Increments the initial sync progress counter (actor-isolated)
    private func incrementInitialSyncProgress() {
        _initialSyncEventsProcessed += 1
    }

    @MainActor
    private func processEvent(
        _ eventData: [String: Any],
        context: ModelContext,
        stats: inout EventProcessingStats
    ) async throws {
        guard let id = eventData["id"] as? String,
              let type = eventData["type"] as? String,
              let timestamp = eventData["ts"] as? String,
              let payload = eventData["payload"] as? [String: Any] else {
            os_log("[Sync] Skipping event - missing required fields")
            stats.incompatible += 1
            return
        }

        if try await isDuplicateEvent(id, context: context) {
            stats.skipped += 1
            return
        }

        let event = try createEvent(id: id, type: type, timestamp: timestamp, payload: payload, eventData: eventData)

        if try await applyAndInsertEvent(event, context: context) {
            stats.processed += 1
            if type.hasPrefix("reminder.") {
                stats.hasReminderEvents = true
            }
        } else {
            stats.incompatible += 1
        }
    }

    @MainActor
    private func isDuplicateEvent(_ eventId: String, context: ModelContext) async throws -> Bool {
        let predicate = #Predicate<Event> { event in
            event.id == eventId
        }
        let descriptor = FetchDescriptor<Event>(predicate: predicate)
        let existingEvents = try context.fetch(descriptor)
        return !existingEvents.isEmpty
    }

    @MainActor
    private func createEvent(
        id: String,
        type: String,
        timestamp: String,
        payload: [String: Any],
        eventData: [String: Any]
    ) throws -> Event {
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let eventTimestamp: Date
        if let parsed = SyncManager.parseISO8601(timestamp) {
            eventTimestamp = parsed
        } else {
            os_log("[Sync] WARNING: Failed to parse ts '\(timestamp)' for \(id)")
            eventTimestamp = Date()
        }

        let entityId = SyncManager.extractEntityId(from: payload, eventType: type)

        // Extract userId, deviceId, appId, and payloadVersion from incoming event
        let eventUserId = eventData["user_id"] as? String ?? ""
        let eventDeviceId = eventData["device_id"] as? String ?? ""
        let eventAppId = eventData["app_id"] as? String ?? ""
        let payloadVersion = eventData["payload_version"] as? Int ?? Event.currentPayloadVersion

        return Event(
            id: id,
            type: type,
            payload: payloadData,
            timestamp: eventTimestamp,
            entityId: entityId,
            userId: eventUserId,
            deviceId: eventDeviceId,
            appId: eventAppId,
            payloadVersion: payloadVersion,
            isSynced: true,
            syncedAt: Date()
        )
    }

    @MainActor
    private func applyAndInsertEvent(_ event: Event, context: ModelContext) async throws -> Bool {
        do {
            try await ProjectorService.apply(event: event, context: context)
            context.insert(event)
            return true
        } catch {
            if let payloadString = String(data: event.payload, encoding: .utf8) {
                let preview = String(payloadString.prefix(200))
                os_log("[Sync] Skipping incompatible event \(event.id) (\(event.type)): \(error.localizedDescription)")
                os_log("[Sync] Payload preview: \(preview)")
            } else {
                os_log("[Sync] Skipping incompatible event \(event.id) (\(event.type)): \(error.localizedDescription)")
            }
            return false
        }
    }

    @MainActor
    private func rescheduleNotifications(context: ModelContext) async {
        os_log("[Sync] Reminder events detected, rescheduling notifications")
        let notificationService = NotificationService(modelContext: context)
        Task {
            await notificationService.rescheduleAllNotifications()
        }
    }

    // MARK: - WebSocket Listening

    private func startListening() {
        listenTask = Task { [weak self] in
            while let self = self, await self.isConnected {
                do {
                    guard let webSocketTask = await self.webSocketTask else { break }
                    let message = try await webSocketTask.receive()

                    switch message {
                    case .string(let text):
                        await self.handleIncomingMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleIncomingMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    await self.handleDisconnect()
                    break
                }
            }
        }
    }

    private func handleIncomingMessage(_ message: String) async {
        guard let data = message.data(using: .utf8),
              let eventData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Handle ping/pong
        if eventData["type"] as? String == "ping" {
            return
        }

        do {
            try await processIncomingEvents([eventData])
        } catch {
            await ErrorReportingService.capture(error: error, context: ["source": "websocket_message"])
        }
    }

    private func handleDisconnect() async {
        isConnected = false

        let currentAttempts = reconnectAttempts
        guard currentAttempts < maxReconnectAttempts,
              token != nil else {
            await ErrorReportingService.addBreadcrumb(
                category: "sync",
                message: "Max reconnect attempts reached",
                data: ["attempts": currentAttempts]
            )
            return
        }

        reconnectAttempts += 1
        let attemptNumber = reconnectAttempts

        // Exponential backoff with jitter: final delay ranges from 75% to 125% of base (±25%)
        let baseDelay = baseReconnectDelay * pow(2.0, Double(attemptNumber - 1))
        let jitterRange = baseDelay * 0.5
        let jitter = Double.random(in: 0...jitterRange)
        let delay = (baseDelay * 0.75) + jitter

        await ErrorReportingService.addBreadcrumb(
            category: "sync",
            message: "Reconnecting with backoff",
            data: ["attempt": attemptNumber, "delay_seconds": delay]
        )

        try? await Task.sleep(for: .seconds(delay))

        do {
            try await connectWebSocket()
            // Restart sync tasks after successful reconnection
            // This does an immediate pull to catch any events missed during disconnect
            startSyncTasks()
            os_log("[Sync] Reconnected successfully, sync tasks restarted")
        } catch {
            await handleDisconnect()
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while let self = self, await self.isConnected {
                try? await Task.sleep(for: .seconds(self.heartbeatIntervalSeconds))

                guard await self.isConnected,
                      let webSocketTask = await self.webSocketTask else { break }

                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        webSocketTask.sendPing { error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }

                    // Reset failure count on success
                    await self.resetHeartbeatFailures()
                } catch {
                    // Track consecutive failures
                    let failures = await self.recordHeartbeatFailure()

                    if failures >= self.maxConsecutiveHeartbeatFailures {
                        await ErrorReportingService.addBreadcrumb(
                            category: "sync",
                            message: "Connection health degraded",
                            data: ["consecutive_failures": failures]
                        )
                        await self.handleDisconnect()
                        break
                    }
                }
            }
        }
    }

    private func recordHeartbeatFailure() -> Int {
        consecutiveHeartbeatFailures += 1
        return consecutiveHeartbeatFailures
    }

    private func resetHeartbeatFailures() {
        consecutiveHeartbeatFailures = 0
        lastSuccessfulHeartbeat = Date()
    }

    // MARK: - Sync Tasks

    /// Performs the initial pull when connecting, handling both fresh device and incremental sync cases.
    private func performInitialPull(needsInitialSync: Bool) async {
        do {
            if needsInitialSync {
                os_log("[Sync] Fresh device detected - starting initial sync...")
                _isInitialSyncInProgress = true
                _initialSyncEventsProcessed = 0
                _initialSyncTotalEvents = 0
            } else {
                os_log("[Sync] Starting incremental sync pull...")
            }

            try await pullEvents()

            if needsInitialSync {
                os_log("[Sync] Initial sync completed successfully")
                _isInitialSyncInProgress = false
            } else {
                os_log("[Sync] Incremental pull completed successfully")
            }
        } catch {
            os_log("[Sync] Initial pull FAILED: \(error.localizedDescription)")
            if needsInitialSync {
                _isInitialSyncInProgress = false
            }
            await ErrorReportingService.capture(error: error, context: ["source": "initial_pull"])
        }
    }

    /// Starts all sync-related background tasks:
    /// - Initial pull (one-time on connect)
    /// - Periodic push task (every 5 seconds for pending events)
    /// - Fallback pull task (every 5 minutes as safety net - WebSocket is primary)
    private func startSyncTasks() {
        // Initial pull - detect if this is a fresh device
        let needsInitialSync = isInitialSync()

        Task {
            await performInitialPull(needsInitialSync: needsInitialSync)
        }

        // Periodic push task - pushes any pending events that weren't pushed immediately.
        // This is a fallback for edge cases; immediate push after save is the common path.
        // Does NOT pull - WebSocket handles incoming events in real-time.
        periodicPushTask = Task { [weak self] in
            while let self = self, await self.isConnected {
                try? await Task.sleep(for: .seconds(self.periodicPushIntervalSeconds))

                guard await self.isConnected else { break }

                do {
                    try await self.pushEvents()
                } catch {
                    await MainActor.run {
                        ErrorReportingService.capture(error: error, context: ["source": "periodic_push"])
                    }
                }
            }
        }

        // Fallback pull task - rare safety net for edge cases where WebSocket might miss events.
        // WebSocket is the primary mechanism for receiving events from other devices.
        // This runs every 5 minutes, NOT every few seconds, to avoid wasting resources.
        fallbackPullTask = Task { [weak self] in
            while let self = self, await self.isConnected {
                // Wait 5 minutes before first fallback pull (initial pull already happened)
                try? await Task.sleep(for: .seconds(self.fallbackPullIntervalMinutes * 60))

                guard await self.isConnected else { break }

                do {
                    os_log("[Sync] Fallback pull (safety net, every \(self.fallbackPullIntervalMinutes) minutes)")
                    try await self.pullEvents()
                } catch {
                    await MainActor.run {
                        ErrorReportingService.capture(error: error, context: ["source": "fallback_pull"])
                    }
                }
            }
        }
    }

    // MARK: - Network Monitoring

    /// Network monitoring will be enhanced when NetworkMonitor from DEQ-47 is available.
    /// For now, we rely on the improved backoff and health monitoring.
    private func startNetworkMonitoring() {
        // TODO: Integrate with NetworkMonitor when DEQ-47 is merged
        // This will enable immediate reconnect when network comes back online
        networkMonitorTask = nil
    }

    // MARK: - Status

    var connectionStatus: ConnectionStatus {
        guard webSocketTask != nil else { return .disconnected }
        return isConnected ? .connected : .connecting
    }

    // MARK: - Manual Sync (for debugging)

    /// Manually trigger a pull from the server (for debugging)
    func manualPull() async throws {
        os_log("[Sync] Manual pull triggered")
        try await pullEvents()
    }

    /// Manually trigger a push to the server (for debugging)
    func manualPush() async throws {
        os_log("[Sync] Manual push triggered")
        try await pushEvents()
    }

    /// Reset sync checkpoint to beginning of time (for debugging)
    func resetCheckpoint() {
        UserDefaults.standard.removeObject(forKey: lastSyncCheckpointKey)
        os_log("[Sync] Checkpoint reset - next pull will fetch all events")
    }

    /// Enable or disable WebSocket push optimization (for debugging/kill switch)
    /// When disabled, events are only sent via HTTP. When enabled (default),
    /// events are sent via both WebSocket (for low latency) and HTTP (for acknowledgment).
    func setWebSocketPushEnabled(_ enabled: Bool) {
        webSocketPushEnabled = enabled
        os_log("[Sync] WebSocket push \(enabled ? "enabled" : "disabled")")
    }

    /// Returns whether WebSocket push optimization is currently enabled
    var isWebSocketPushEnabled: Bool {
        webSocketPushEnabled
    }

    // MARK: - Immediate Sync

    /// Triggers an immediate push of pending events.
    /// Call this after recording events to sync them without waiting for the periodic interval.
    /// Errors are logged but not thrown to avoid disrupting the caller's flow.
    /// Marked nonisolated since it only spawns an actor-isolated Task internally.
    nonisolated func triggerImmediatePush() {
        Task {
            do {
                try await pushEvents()
            } catch {
                os_log("[Sync] Immediate push failed: \(error.localizedDescription)")
                // Don't propagate error - periodic sync will retry
            }
        }
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case pushFailed
    case pullFailed
    case connectionLost

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated for sync"
        case .invalidURL:
            return "Invalid sync URL"
        case .pushFailed:
            return "Failed to push events to server"
        case .pullFailed:
            return "Failed to pull events from server"
        case .connectionLost:
            return "Sync connection lost"
        }
    }
}

enum ConnectionStatus {
    case connected
    case connecting
    case disconnected
}
