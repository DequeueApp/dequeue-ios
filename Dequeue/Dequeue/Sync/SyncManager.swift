//
//  SyncManager.swift
//  Dequeue
//
//  Handles sync with the backend via WebSocket and HTTP
//

import Foundation
import SwiftData

actor SyncManager {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var token: String?
    private var userId: String?
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0

    private let modelContainer: ModelContainer
    private var getTokenFunction: (() async throws -> String)?

    private var periodicSyncTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Connection

    func connect(userId: String, token: String, getToken: @escaping () async throws -> String) async throws {
        self.userId = userId
        self.token = token
        self.getTokenFunction = getToken

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

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        token = nil
        userId = nil
    }

    private func connectWebSocket() async throws {
        guard let token = try await refreshToken() else {
            throw SyncError.notAuthenticated
        }

        let wsUrl = Configuration.syncAPIBaseURL
            .absoluteString
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")

        guard let url = URL(string: "\(wsUrl)/ws?token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)") else {
            throw SyncError.invalidURL
        }

        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        isConnected = true
        reconnectAttempts = 0

        startListening()
        startHeartbeat()

        ErrorReportingService.addBreadcrumb(
            category: "sync",
            message: "WebSocket connected"
        )
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
        guard let token = try await refreshToken() else {
            throw SyncError.notAuthenticated
        }

        let context = ModelContext(modelContainer)
        let eventService = EventService(modelContext: context)
        let pendingEvents = try eventService.fetchPendingEvents()

        guard !pendingEvents.isEmpty else { return }

        let deviceId = await DeviceService.shared.getDeviceId()
        let syncEvents = pendingEvents.map { event -> [String: Any] in
            let payload: Any
            if let payloadDict = try? JSONSerialization.jsonObject(with: event.payload) {
                payload = payloadDict
            } else {
                payload = [:]
            }

            return [
                "id": event.id.uuidString,
                "device_id": deviceId,
                "ts": ISO8601DateFormatter().string(from: event.timestamp),
                "type": event.type,
                "payload": payload
            ]
        }

        var request = URLRequest(url: Configuration.syncAPIBaseURL.appendingPathComponent("sync/push"))
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

            try await processPushResponse(retryData, events: pendingEvents, context: context)
        } else if httpResponse.statusCode == 200 {
            try await processPushResponse(data, events: pendingEvents, context: context)
        } else {
            throw SyncError.pushFailed
        }
    }

    private func processPushResponse(_ data: Data, events: [Event], context: ModelContext) async throws {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acknowledged = response["acknowledged"] as? [String] else {
            return
        }

        let eventService = EventService(modelContext: context)
        let syncedEvents = events.filter { acknowledged.contains($0.id.uuidString) }
        try eventService.markEventsSynced(syncedEvents)

        ErrorReportingService.addBreadcrumb(
            category: "sync",
            message: "Pushed \(syncedEvents.count) events",
            data: ["total": events.count, "synced": syncedEvents.count]
        )
    }

    // MARK: - Pull Events

    func pullEvents() async throws {
        guard let token = try await refreshToken() else {
            throw SyncError.notAuthenticated
        }

        let since = await getLastSyncTimestamp()

        var request = URLRequest(url: Configuration.syncAPIBaseURL.appendingPathComponent("sync/pull"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["since": since])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.pullFailed
        }

        if httpResponse.statusCode == 401 {
            guard let newToken = try await refreshToken() else {
                throw SyncError.notAuthenticated
            }
            request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await session.data(for: request)

            guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                  retryHttpResponse.statusCode == 200 else {
                throw SyncError.pullFailed
            }

            try await processPullResponse(retryData)
        } else if httpResponse.statusCode == 200 {
            try await processPullResponse(data)
        } else {
            throw SyncError.pullFailed
        }
    }

    private func processPullResponse(_ data: Data) async throws {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = response["events"] as? [[String: Any]] else {
            return
        }

        let deviceId = await DeviceService.shared.getDeviceId()
        let filteredEvents = events.filter { event in
            guard let eventDeviceId = event["device_id"] as? String else { return true }
            return eventDeviceId != deviceId
        }

        if !filteredEvents.isEmpty {
            try await processIncomingEvents(filteredEvents)
        }

        ErrorReportingService.addBreadcrumb(
            category: "sync",
            message: "Pulled \(filteredEvents.count) events",
            data: ["total": events.count, "processed": filteredEvents.count]
        )
    }

    private func getLastSyncTimestamp() async -> String {
        // For now, use a fixed initial date
        // TODO: Track last sync timestamp in UserDefaults or database
        let initialDate = Date(timeIntervalSince1970: 1737417600) // Jan 21, 2025
        return ISO8601DateFormatter().string(from: initialDate)
    }

    // MARK: - Process Incoming Events

    private func processIncomingEvents(_ events: [[String: Any]]) async throws {
        let context = ModelContext(modelContainer)

        for eventData in events {
            guard let id = eventData["id"] as? String,
                  let type = eventData["type"] as? String,
                  let ts = eventData["ts"] as? String,
                  let payload = eventData["payload"] as? [String: Any] else {
                continue
            }

            // Check if event already exists
            let eventId = UUID(uuidString: id) ?? UUID()
            let predicate = #Predicate<Event> { event in
                event.id == eventId
            }
            let descriptor = FetchDescriptor<Event>(predicate: predicate)
            let existingEvents = try context.fetch(descriptor)

            if !existingEvents.isEmpty {
                continue // Already have this event
            }

            // Create event in local database
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let timestamp = ISO8601DateFormatter().date(from: ts) ?? Date()

            let event = Event(
                id: eventId,
                type: type,
                payload: payloadData,
                timestamp: timestamp,
                isSynced: true,
                syncedAt: Date()
            )
            context.insert(event)

            // Apply event to local state via ProjectorService
            try await ProjectorService.apply(event: event, context: context)
        }

        try context.save()
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
            ErrorReportingService.capture(error: error, context: ["source": "websocket_message"])
        }
    }

    private func handleDisconnect() async {
        isConnected = false

        guard reconnectAttempts < maxReconnectAttempts,
              token != nil else { return }

        reconnectAttempts += 1
        let delay = baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1))

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
                try? await Task.sleep(for: .seconds(30))

                guard await self.isConnected,
                      let webSocketTask = await self.webSocketTask else { break }

                do {
                    try await webSocketTask.sendPing()
                } catch {
                    await self.handleDisconnect()
                    break
                }
            }
        }
    }

    // MARK: - Periodic Sync

    private func startPeriodicSync() {
        // Initial pull
        Task {
            try? await pullEvents()
        }

        periodicSyncTask = Task { [weak self] in
            while let self = self, await self.isConnected {
                try? await Task.sleep(for: .seconds(10))

                guard await self.isConnected else { break }

                do {
                    try await self.pushEvents()
                    try await self.pullEvents()
                } catch {
                    ErrorReportingService.capture(error: error, context: ["source": "periodic_sync"])
                }
            }
        }
    }

    // MARK: - Status

    var connectionStatus: ConnectionStatus {
        guard webSocketTask != nil else { return .disconnected }
        return isConnected ? .connected : .connecting
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
