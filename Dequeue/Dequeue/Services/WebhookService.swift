//
//  WebhookService.swift
//  Dequeue
//
//  Client for webhook management endpoints:
//  - GET /v1/webhooks (list)
//  - POST /v1/webhooks (create)
//  - GET /v1/webhooks/{id} (get)
//  - PATCH /v1/webhooks/{id} (update)
//  - DELETE /v1/webhooks/{id} (delete)
//  - POST /v1/webhooks/{id}/rotate-secret (rotate)
//  - GET /v1/webhooks/{id}/deliveries (delivery logs)
//  - POST /v1/webhooks/{id}/test (test delivery)
//

import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.dequeue", category: "WebhookService")

// MARK: - Webhook Models

/// A webhook configuration
struct Webhook: Codable, Sendable, Identifiable {
    let id: String
    let url: String
    let events: [String]
    let secret: String?         // Only on create
    let secretPrefix: String?   // On list/get
    let status: String
    let createdAt: Int64
    let lastDeliveryAt: Int64?
    let lastDeliveryStatus: String?

    var createdAtDate: Date {
        Date(timeIntervalSince1970: Double(createdAt) / 1_000.0)
    }

    var lastDeliveryAtDate: Date? {
        guard let lastDeliveryAt else { return nil }
        return Date(timeIntervalSince1970: Double(lastDeliveryAt) / 1_000.0)
    }

    var isActive: Bool { status == "active" }
}

/// Paginated webhook list response
struct WebhookListResponse: Codable, Sendable {
    let data: [Webhook]
    let pagination: PaginationInfo
}

/// A single webhook delivery log entry
struct WebhookDelivery: Codable, Sendable, Identifiable {
    let id: String
    let webhookId: String
    let eventType: String
    let eventId: String
    let status: String
    let attempts: Int
    let lastResponseStatus: Int?
    let lastResponseBody: String?
    let lastError: String?
    let createdAt: Int64
    let completedAt: Int64?
    let nextRetryAt: Int64?
    let lastAttemptAt: Int64?

    var createdAtDate: Date {
        Date(timeIntervalSince1970: Double(createdAt) / 1_000.0)
    }

    var completedAtDate: Date? {
        guard let completedAt else { return nil }
        return Date(timeIntervalSince1970: Double(completedAt) / 1_000.0)
    }

    var nextRetryAtDate: Date? {
        guard let nextRetryAt else { return nil }
        return Date(timeIntervalSince1970: Double(nextRetryAt) / 1_000.0)
    }

    var lastAttemptAtDate: Date? {
        guard let lastAttemptAt else { return nil }
        return Date(timeIntervalSince1970: Double(lastAttemptAt) / 1_000.0)
    }

    /// Whether the delivery succeeded
    var isSuccess: Bool { status == "delivered" }

    /// Whether the delivery is still pending/retrying
    var isPending: Bool { status == "pending" || status == "retrying" }

    /// Whether the delivery failed permanently
    var isFailed: Bool { status == "failed" }
}

/// Paginated delivery list response
struct WebhookDeliveryListResponse: Codable, Sendable {
    let data: [WebhookDelivery]
    let pagination: PaginationInfo
}

/// Result of a test webhook delivery
struct WebhookTestResult: Codable, Sendable {
    let success: Bool
    let responseStatus: Int?
    let responseBody: String?
    let error: String?
    let durationMs: Int64
    let deliveredAt: Int64

    var deliveredAtDate: Date {
        Date(timeIntervalSince1970: Double(deliveredAt) / 1_000.0)
    }
}

/// Result of rotating a webhook secret
struct WebhookRotateSecretResult: Codable, Sendable {
    let id: String
    let secret: String
    let rotatedAt: Int64

    var rotatedAtDate: Date {
        Date(timeIntervalSince1970: Double(rotatedAt) / 1_000.0)
    }
}

/// Shared pagination info (used across multiple endpoints)
struct PaginationInfo: Codable, Sendable {
    let nextCursor: String?
    let hasMore: Bool
    let limit: Int
}

/// Create webhook request body
struct CreateWebhookRequest: Codable, Sendable {
    let url: String
    let events: [String]
    let secret: String?
}

/// Update webhook request body
struct UpdateWebhookRequest: Codable, Sendable {
    let url: String?
    let events: [String]?
    let status: String?
}

// MARK: - Webhook Error

enum WebhookError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case webhookNotFound
    case invalidURL
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to manage webhooks."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .webhookNotFound:
            return "Webhook not found."
        case .invalidURL:
            return "Invalid webhook URL."
        case let .serverError(statusCode, message):
            if let message {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server error: \(statusCode)"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Webhook Service

/// Service for managing webhooks and viewing delivery logs via the Dequeue API
final class WebhookService: @unchecked Sendable {
    private let authService: any AuthServiceProtocol
    private let urlSession: URLSession

    init(authService: any AuthServiceProtocol, urlSession: URLSession = .shared) {
        self.authService = authService
        self.urlSession = urlSession
    }

    // MARK: - Webhook CRUD

    /// Lists all webhooks for the authenticated user
    /// - Parameters:
    ///   - limit: Maximum results (1-100, default 50)
    ///   - cursor: Pagination cursor for next page
    /// - Returns: Paginated webhook list
    func listWebhooks(limit: Int = 50, cursor: String? = nil) async throws -> WebhookListResponse {
        let token = try await authService.getAuthToken()

        var components = URLComponents(
            url: Configuration.dequeueAPIBaseURL.appendingPathComponent("webhooks"),
            resolvingAgainstBaseURL: true
        )
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw WebhookError.invalidResponse
        }

        let data = try await performGET(url: url, token: token)
        return try JSONDecoder().decode(WebhookListResponse.self, from: data)
    }

    /// Creates a new webhook
    /// - Parameter request: Webhook creation parameters
    /// - Returns: The created webhook (includes the secret, shown only once)
    func createWebhook(_ request: CreateWebhookRequest) async throws -> Webhook {
        let token = try await authService.getAuthToken()

        let url = Configuration.dequeueAPIBaseURL.appendingPathComponent("webhooks")
        let body = try JSONEncoder().encode(request)
        let data = try await performRequest(url: url, method: "POST", token: token, body: body)
        return try JSONDecoder().decode(Webhook.self, from: data)
    }

    /// Gets a specific webhook by ID
    /// - Parameter id: Webhook ID
    /// - Returns: The webhook details
    func getWebhook(id: String) async throws -> Webhook {
        let token = try await authService.getAuthToken()

        let url = Configuration.dequeueAPIBaseURL
            .appendingPathComponent("webhooks")
            .appendingPathComponent(id)

        let data = try await performGET(url: url, token: token)
        return try JSONDecoder().decode(Webhook.self, from: data)
    }

    /// Updates a webhook
    /// - Parameters:
    ///   - id: Webhook ID
    ///   - request: Fields to update
    /// - Returns: The updated webhook
    func updateWebhook(id: String, _ request: UpdateWebhookRequest) async throws -> Webhook {
        let token = try await authService.getAuthToken()

        let url = Configuration.dequeueAPIBaseURL
            .appendingPathComponent("webhooks")
            .appendingPathComponent(id)

        let body = try JSONEncoder().encode(request)
        let data = try await performRequest(url: url, method: "PATCH", token: token, body: body)
        return try JSONDecoder().decode(Webhook.self, from: data)
    }

    /// Deletes a webhook
    /// - Parameter id: Webhook ID
    func deleteWebhook(id: String) async throws {
        let token = try await authService.getAuthToken()

        let url = Configuration.dequeueAPIBaseURL
            .appendingPathComponent("webhooks")
            .appendingPathComponent(id)

        _ = try await performRequest(url: url, method: "DELETE", token: token)
    }

    /// Rotates the signing secret for a webhook
    /// - Parameter id: Webhook ID
    /// - Returns: The new secret (shown only once)
    func rotateSecret(id: String) async throws -> WebhookRotateSecretResult {
        let token = try await authService.getAuthToken()

        let url = Configuration.dequeueAPIBaseURL
            .appendingPathComponent("webhooks")
            .appendingPathComponent(id)
            .appendingPathComponent("rotate-secret")

        let data = try await performRequest(url: url, method: "POST", token: token)
        return try JSONDecoder().decode(WebhookRotateSecretResult.self, from: data)
    }

    // MARK: - Delivery Logs

    /// Lists delivery logs for a specific webhook
    /// - Parameters:
    ///   - webhookId: The webhook ID
    ///   - limit: Maximum results (1-100, default 50)
    ///   - cursor: Pagination cursor for next page
    /// - Returns: Paginated delivery list
    func listDeliveries(
        webhookId: String, limit: Int = 50, cursor: String? = nil
    ) async throws -> WebhookDeliveryListResponse {
        let token = try await authService.getAuthToken()

        var components = URLComponents(
            url: Configuration.dequeueAPIBaseURL
                .appendingPathComponent("webhooks")
                .appendingPathComponent(webhookId)
                .appendingPathComponent("deliveries"),
            resolvingAgainstBaseURL: true
        )
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw WebhookError.invalidResponse
        }

        let data = try await performGET(url: url, token: token)
        return try JSONDecoder().decode(WebhookDeliveryListResponse.self, from: data)
    }

    // MARK: - Test Delivery

    /// Sends a test event to the webhook and returns the result
    /// - Parameter webhookId: The webhook ID to test
    /// - Returns: Test delivery result with response details
    func testDelivery(webhookId: String) async throws -> WebhookTestResult {
        let token = try await authService.getAuthToken()

        let url = Configuration.dequeueAPIBaseURL
            .appendingPathComponent("webhooks")
            .appendingPathComponent(webhookId)
            .appendingPathComponent("test")

        let data = try await performRequest(url: url, method: "POST", token: token)
        return try JSONDecoder().decode(WebhookTestResult.self, from: data)
    }

    // MARK: - Private Helpers

    private func performGET(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await executeRequest(request)
    }

    private func performRequest(url: URL, method: String, token: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        return try await executeRequest(request)
    }

    private func executeRequest(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebhookError.invalidResponse
            }

            // 204 No Content (e.g., successful delete)
            if httpResponse.statusCode == 204 {
                return Data()
            }

            if httpResponse.statusCode == 401 {
                throw WebhookError.notAuthenticated
            }

            if httpResponse.statusCode == 404 {
                throw WebhookError.webhookNotFound
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                throw WebhookError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }

            return data
        } catch let error as WebhookError {
            throw error
        } catch {
            throw WebhookError.networkError(error)
        }
    }
}

// MARK: - Environment Key

private struct WebhookServiceKey: EnvironmentKey {
    static let defaultValue: WebhookService? = nil
}

extension EnvironmentValues {
    var webhookService: WebhookService? {
        get { self[WebhookServiceKey.self] }
        set { self[WebhookServiceKey.self] = newValue }
    }
}
