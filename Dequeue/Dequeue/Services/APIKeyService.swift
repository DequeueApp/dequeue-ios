//
//  APIKeyService.swift
//  Dequeue
//
//  Manages API keys for external integrations
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.dequeue", category: "APIKeyService")

// MARK: - API Key Models

/// API key returned from the server
struct APIKey: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let keyPrefix: String
    let scopes: [String]
    let createdAt: Int64
    let lastUsedAt: Int64?

    var createdAtDate: Date {
        Date(timeIntervalSince1970: Double(createdAt) / 1_000.0)
    }

    var lastUsedAtDate: Date? {
        guard let lastUsedAt else { return nil }
        return Date(timeIntervalSince1970: Double(lastUsedAt) / 1_000.0)
    }
}

/// Response when creating a new API key (includes the full key)
struct CreateAPIKeyResponse: Codable {
    let id: String
    let name: String
    let key: String // Full key, only shown once
    let keyPrefix: String
    let scopes: [String]
    let createdAt: Int64
}

/// Request body for creating an API key
struct CreateAPIKeyRequest: Codable {
    let name: String
    let scopes: [String]
}

// MARK: - API Key Error

enum APIKeyError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to manage API keys."
        case .invalidResponse:
            return "Received an invalid response from the server."
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

// MARK: - API Key Service

/// Service for managing API keys via the stacks-sync API
@MainActor
final class APIKeyService {
    private let authService: any AuthServiceProtocol

    init(authService: any AuthServiceProtocol) {
        self.authService = authService
    }

    // MARK: - List API Keys

    /// Fetches all API keys for the current user
    func listAPIKeys() async throws -> [APIKey] {
        let token = try await authService.getAuthToken()

        let url = Configuration.syncAPIBaseURL
            .appendingPathComponent("api-keys")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logger.debug("Fetching API keys from: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIKeyError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = try? JSONDecoder().decode([String: String].self, from: data)["error"]
            throw APIKeyError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            let keys = try JSONDecoder().decode([APIKey].self, from: data)
            logger.info("Fetched \(keys.count) API keys")
            return keys
        } catch {
            logger.error("Failed to decode API keys: \(error.localizedDescription)")
            throw APIKeyError.invalidResponse
        }
    }

    // MARK: - Create API Key

    /// Creates a new API key with the specified name and scopes
    /// - Returns: The created key response (includes the full key, which is only shown once)
    func createAPIKey(name: String, scopes: [String]) async throws -> CreateAPIKeyResponse {
        let token = try await authService.getAuthToken()

        let url = Configuration.syncAPIBaseURL
            .appendingPathComponent("api-keys")

        let requestBody = CreateAPIKeyRequest(name: name, scopes: scopes)
        let bodyData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        logger.debug("Creating API key '\(name)' with scopes: \(scopes.joined(separator: ", "))")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIKeyError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = try? JSONDecoder().decode([String: String].self, from: data)["error"]
            throw APIKeyError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            let keyResponse = try JSONDecoder().decode(CreateAPIKeyResponse.self, from: data)
            logger.info("Created API key '\(name)' with ID: \(keyResponse.id)")
            return keyResponse
        } catch {
            logger.error("Failed to decode create API key response: \(error.localizedDescription)")
            throw APIKeyError.invalidResponse
        }
    }

    // MARK: - Revoke API Key

    /// Revokes an API key, making it unusable for future requests
    func revokeAPIKey(id: String) async throws {
        let token = try await authService.getAuthToken()

        let url = Configuration.syncAPIBaseURL
            .appendingPathComponent("api-keys")
            .appendingPathComponent(id)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        logger.debug("Revoking API key: \(id)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIKeyError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = try? JSONDecoder().decode([String: String].self, from: data)["error"]
            throw APIKeyError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        logger.info("Revoked API key: \(id)")
    }
}

// MARK: - Environment Key

private struct APIKeyServiceKey: EnvironmentKey {
    static let defaultValue: APIKeyService? = nil
}

extension EnvironmentValues {
    var apiKeyService: APIKeyService? {
        get { self[APIKeyServiceKey.self] }
        set { self[APIKeyServiceKey.self] = newValue }
    }
}
