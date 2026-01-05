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

// swiftlint:disable:next type_body_length
actor SyncManager {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var token: String?
    private var userId: String?
    private var deviceId: String?  // Cached at connection time to avoid actor hops
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0

    /// Fallback sync interval when immediate push is unavailable or fails.
    /// Immediate push after each save handles the common case; this is a safety net.
    private let periodicSyncIntervalSeconds: UInt64 = 5

    /// Heartbeat interval for WebSocket keep-alive
    private let heartbeatIntervalSeconds: UInt64 = 30

    private let modelContainer: ModelContainer
    private var getTokenFunction: (() async throws -> String)?

    private var periodicSyncTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var networkMonitorTask: Task<Void, Never>?

    // Health monitoring
    private var consecutiveHeartbeatFailures = 0
    private let maxConsecutiveHeartbeatFailures = 3
    private var lastSuccessfulHeartbeat: Date?

    // Key for storing last sync checkpoint in UserDefaults
    private let lastSyncCheckpointKey = "com.dequeue.lastSyncCheckpoint"

    // ISO8601 formatter that supports fractional seconds (Go's RFC3339Nano format)
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Standard ISO8601 formatter without fractional seconds
    private static let iso8601Standard: ISO8601DateFormatter = {
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
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 0))
    }

    // MARK: - Connection

    func connect(userId: String, token: String, getToken: @escaping () async throws -> String) async throws {
        self.userId = userId
        self.token = token
        self.getTokenFunction = getToken
        // Cache deviceId at connection time to avoid actor hops during push
        self.deviceId = await DeviceService.shared.getDeviceId()

        try await connectWebSocket()
        startPeriodicSync()
    }

    func disconnect() {
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listenTask?.cancel()
        listenTask = nil
        networkMonitorTask?.cancel()
        networkMonitorTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        token = nil
        userId = nil
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

    // swiftlint:disable:next function_body_length
    func pushEvents() async throws {
        guard let token = try await refreshToken() else {
            throw SyncError.notAuthenticated
        }

        let pendingEvents = try await MainActor.run {
            let context = ModelContext(modelContainer)
            let eventService = EventService(modelContext: context)
            return try eventService.fetchPendingEvents()
        }

        guard !pendingEvents.isEmpty else { return }

        // Use cached deviceId (falls back to fetching if not cached, e.g., during reconnect)
        let eventDeviceId: String
        if let cachedDeviceId = deviceId {
            eventDeviceId = cachedDeviceId
        } else {
            eventDeviceId = await DeviceService.shared.getDeviceId()
        }

        let syncEvents = pendingEvents.map { event -> [String: Any] in
            let payload: Any
            if let payloadDict = try? JSONSerialization.jsonObject(with: event.payload) {
                payload = payloadDict
            } else {
                payload = [:]
            }

            // Use stored userId/deviceId from the event (captured at creation time)
            // Fall back to cached values for backward compatibility
            let eventUserId = !event.userId.isEmpty ? event.userId : (self.userId ?? "")
            let eventDeviceIdToUse = !event.deviceId.isEmpty ? event.deviceId : eventDeviceId

            return [
                "id": event.id,
                "user_id": eventUserId,
                "device_id": eventDeviceIdToUse,
                "ts": SyncManager.iso8601WithFractionalSeconds.string(from: event.timestamp),
                "type": event.type,
                "payload": payload,
                "payload_version": event.payloadVersion
            ]
        }

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

            try await processPushResponse(retryData, events: pendingEvents)
        } else if httpResponse.statusCode == 200 {
            try await processPushResponse(data, events: pendingEvents)
        } else {
            throw SyncError.pushFailed
        }
    }

    private func processPushResponse(_ data: Data, events: [Event]) async throws {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acknowledged = response["acknowledged"] as? [String] else {
            return
        }

        let syncedEvents = events.filter { acknowledged.contains($0.id) }

        try await MainActor.run {
            let context = ModelContext(modelContainer)
            let eventService = EventService(modelContext: context)
            try eventService.markEventsSynced(syncedEvents)
        }

        // Handle rejected events
        if let rejected = response["rejected"] as? [String],
           let errors = response["errors"] as? [String] {
            let rejectedEvents = events.filter { rejected.contains($0.id) }
            for (index, event) in rejectedEvents.enumerated() {
                let errorMessage = index < errors.count ? errors[index] : "Unknown error"
                os_log("[Sync] Event \(event.id) rejected: \(errorMessage)")
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
                message: "Pushed \(syncedEvents.count) events",
                data: ["total": events.count, "synced": syncedEvents.count]
            )
        }
    }

    // MARK: - Pull Events

    func pullEvents() async throws {
        guard let token = try await refreshToken() else {
            os_log("[Sync] Pull failed: Not authenticated")
            throw SyncError.notAuthenticated
        }

        let since = await getLastSyncTimestamp()
        os_log("[Sync] Pulling events since: \(since)")

        let pullURL = await MainActor.run { Configuration.syncAPIBaseURL.appendingPathComponent("sync/pull") }
        os_log("[Sync] Pull URL: \(pullURL.absoluteString)")

        var request = URLRequest(url: pullURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["since": since])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            os_log("[Sync] Pull failed: Invalid response type")
            throw SyncError.pullFailed
        }

        os_log("[Sync] Pull response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 {
            os_log("[Sync] Token expired, refreshing...")
            guard let newToken = try await refreshToken() else {
                os_log("[Sync] Token refresh failed")
                throw SyncError.notAuthenticated
            }
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await session.data(for: request)

            guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                  retryHttpResponse.statusCode == 200 else {
                os_log("[Sync] Retry failed with status: \((retryResponse as? HTTPURLResponse)?.statusCode ?? -1)")
                throw SyncError.pullFailed
            }

            try await processPullResponse(retryData)
        } else if httpResponse.statusCode == 200 {
            try await processPullResponse(data)
        } else {
            // Log the response body for debugging
            if let responseBody = String(data: data, encoding: .utf8) {
                os_log("[Sync] Pull failed with status \(httpResponse.statusCode): \(responseBody)")
            }
            throw SyncError.pullFailed
        }
    }

    // swiftlint:disable:next function_body_length
    private func processPullResponse(_ data: Data) async throws {
        // Log raw response for debugging
        if let rawResponse = String(data: data, encoding: .utf8) {
            let preview = String(rawResponse.prefix(500))
            os_log("[Sync] Raw pull response: \(preview)\(rawResponse.count > 500 ? "..." : "")")
        }

        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            os_log("[Sync] Failed to parse pull response as JSON")
            return
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
            return
        }

        let nextCheckpoint = response["nextCheckpoint"] as? String
        os_log("[Sync] Next checkpoint from server: \(nextCheckpoint ?? "nil")")

        let deviceId = await DeviceService.shared.getDeviceId()
        os_log("[Sync] Current device ID: \(deviceId)")

        // Filter 1: Exclude events from current device (already applied locally)
        let fromOtherDevices = events.filter { event in
            guard let eventDeviceId = event["device_id"] as? String else { return true }
            return eventDeviceId != deviceId
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

        if !filteredEvents.isEmpty {
            try await processIncomingEvents(filteredEvents)
        }

        // Only save checkpoint AFTER successful processing
        if let nextCheckpoint = nextCheckpoint {
            saveLastSyncCheckpoint(nextCheckpoint)
            os_log("[Sync] Checkpoint updated to \(nextCheckpoint)")
        }

        await MainActor.run {
            ErrorReportingService.addBreadcrumb(
                category: "sync",
                message: "Pulled \(filteredEvents.count) events",
                data: ["total": events.count, "processed": filteredEvents.count]
            )
        }
    }

    private func getLastSyncTimestamp() async -> String {
        return getLastSyncCheckpoint()
    }

    // MARK: - Process Incoming Events

    // swiftlint:disable:next function_body_length
    private func processIncomingEvents(_ events: [[String: Any]]) async throws {
        os_log("[Sync] Processing \(events.count) incoming events")
        var processed = 0
        var skipped = 0
        var incompatible = 0
        var hasReminderEvents = false

        try await MainActor.run {
            let context = ModelContext(modelContainer)

            for eventData in events {
                guard let id = eventData["id"] as? String,
                      let type = eventData["type"] as? String,
                      let timestamp = eventData["ts"] as? String,
                      let payload = eventData["payload"] as? [String: Any] else {
                    os_log("[Sync] Skipping event - missing required fields")
                    incompatible += 1
                    continue
                }

                // Check if event already exists (using String ID directly to handle both UUID and CUID formats)
                let eventId = id
                let predicate = #Predicate<Event> { event in
                    event.id == eventId
                }
                let descriptor = FetchDescriptor<Event>(predicate: predicate)
                let existingEvents = try context.fetch(descriptor)

                if !existingEvents.isEmpty {
                    skipped += 1
                    continue // Already have this event
                }

                // Create event in local database
                let payloadData = try JSONSerialization.data(withJSONObject: payload)
                let eventTimestamp: Date
                if let parsed = SyncManager.parseISO8601(timestamp) {
                    eventTimestamp = parsed
                } else {
                    os_log("[Sync] WARNING: Failed to parse ts '\(timestamp)' for \(id)")
                    eventTimestamp = Date()
                }

                // Extract entityId from payload for history queries
                let entityId = SyncManager.extractEntityId(from: payload, eventType: type)

                // Extract userId, deviceId, and payloadVersion from incoming event
                let eventUserId = eventData["user_id"] as? String ?? ""
                let eventDeviceId = eventData["device_id"] as? String ?? ""
                let payloadVersion = eventData["payload_version"] as? Int ?? Event.currentPayloadVersion

                let event = Event(
                    id: eventId,
                    type: type,
                    payload: payloadData,
                    timestamp: eventTimestamp,
                    entityId: entityId,
                    userId: eventUserId,
                    deviceId: eventDeviceId,
                    payloadVersion: payloadVersion,
                    isSynced: true,
                    syncedAt: Date()
                )

                // Try to apply event BEFORE inserting - skip incompatible legacy events
                do {
                    try ProjectorService.apply(event: event, context: context)
                    // Only insert if application succeeded
                    context.insert(event)
                    processed += 1

                    // Track if any reminder events were processed for notification scheduling
                    if type.hasPrefix("reminder.") {
                        hasReminderEvents = true
                    }
                } catch {
                    // Incompatible schema from legacy app - skip this event entirely
                    // Log the payload for debugging
                    if let payloadString = String(data: payloadData, encoding: .utf8) {
                        let preview = String(payloadString.prefix(200))
                        os_log("[Sync] Skipping incompatible event \(id) (\(type)): \(error.localizedDescription)")
                        os_log("[Sync] Payload preview: \(preview)")
                    } else {
                        os_log("[Sync] Skipping incompatible event \(id) (\(type)): \(error.localizedDescription)")
                    }
                    incompatible += 1
                }
            }

            try context.save()
            let stats = "processed: \(processed), dupes: \(skipped), incompatible: \(incompatible)"
            os_log("[Sync] Saved context - \(stats)")

            // Reschedule notifications for any synced reminders
            if hasReminderEvents {
                os_log("[Sync] Reminder events detected, rescheduling notifications")
                let notificationService = NotificationService(modelContext: context)
                Task {
                    await notificationService.rescheduleAllNotifications()
                }
            }
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
            await MainActor.run {
                ErrorReportingService.capture(error: error, context: ["source": "websocket_message"])
            }
        }
    }

    private func handleDisconnect() async {
        isConnected = false

        let currentAttempts = reconnectAttempts
        guard currentAttempts < maxReconnectAttempts,
              token != nil else {
            await MainActor.run {
                ErrorReportingService.addBreadcrumb(
                    category: "sync",
                    message: "Max reconnect attempts reached",
                    data: ["attempts": currentAttempts]
                )
            }
            return
        }

        reconnectAttempts += 1
        let attemptNumber = reconnectAttempts

        // Exponential backoff with jitter: final delay ranges from 75% to 125% of base (±25%)
        let baseDelay = baseReconnectDelay * pow(2.0, Double(attemptNumber - 1))
        let jitterRange = baseDelay * 0.5
        let jitter = Double.random(in: 0...jitterRange)
        let delay = (baseDelay * 0.75) + jitter

        await MainActor.run {
            ErrorReportingService.addBreadcrumb(
                category: "sync",
                message: "Reconnecting with backoff",
                data: ["attempt": attemptNumber, "delay_seconds": delay]
            )
        }

        try? await Task.sleep(for: .seconds(delay))

        do {
            try await connectWebSocket()
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
                        await MainActor.run {
                            ErrorReportingService.addBreadcrumb(
                                category: "sync",
                                message: "Connection health degraded",
                                data: ["consecutive_failures": failures]
                            )
                        }
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

    // MARK: - Periodic Sync

    private func startPeriodicSync() {
        // Initial pull
        Task {
            do {
                os_log("[Sync] Starting initial pull...")
                try await pullEvents()
                os_log("[Sync] Initial pull completed successfully")
            } catch {
                os_log("[Sync] Initial pull FAILED: \(error.localizedDescription)")
                await MainActor.run {
                    ErrorReportingService.capture(error: error, context: ["source": "initial_pull"])
                }
            }
        }

        periodicSyncTask = Task { [weak self] in
            while let self = self, await self.isConnected {
                // Periodic sync as a fallback - immediate push is triggered by services
                // after each save operation, so this mainly catches edge cases
                try? await Task.sleep(for: .seconds(self.periodicSyncIntervalSeconds))

                guard await self.isConnected else { break }

                do {
                    try await self.pushEvents()
                    try await self.pullEvents()
                } catch {
                    await MainActor.run {
                        ErrorReportingService.capture(error: error, context: ["source": "periodic_sync"])
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
