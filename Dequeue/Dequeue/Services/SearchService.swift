//
//  SearchService.swift
//  Dequeue
//
//  Client for the unified search endpoint (GET /v1/search)
//

import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.dequeue", category: "SearchService")

// MARK: - Search Models

/// A single search result that can be either a task or a stack
struct SearchResultItem: Identifiable, Codable, Sendable {
    let type: String // "task" or "stack"
    let task: SearchTask?
    let stack: SearchStack?

    var id: String {
        if let task {
            return "task-\(task.id)"
        } else if let stack {
            return "stack-\(stack.id)"
        }
        return UUID().uuidString
    }
}

/// Task data returned from search
struct SearchTask: Codable, Sendable, Identifiable {
    let id: String
    let stackId: String
    let title: String
    let notes: String?
    let status: String
    let priority: Int
    let sortOrder: Int
    let isActive: Bool
    let dueAt: Int64?
    let blockedReason: String?
    let parentTaskId: String?
    let createdAt: Int64
    let updatedAt: Int64
    let completedAt: Int64?

    var dueAtDate: Date? {
        guard let dueAt else { return nil }
        return Date(timeIntervalSince1970: Double(dueAt) / 1_000.0)
    }

    var createdAtDate: Date {
        Date(timeIntervalSince1970: Double(createdAt) / 1_000.0)
    }

    var updatedAtDate: Date {
        Date(timeIntervalSince1970: Double(updatedAt) / 1_000.0)
    }
}

/// Stack data returned from search
struct SearchStack: Codable, Sendable, Identifiable {
    let id: String
    let arcId: String?
    let title: String
    let status: String
    let sortOrder: Int
    let taskCount: Int
    let completedTaskCount: Int
    let isActive: Bool
    let activeTaskId: String?
    let createdAt: Int64
    let updatedAt: Int64

    var createdAtDate: Date {
        Date(timeIntervalSince1970: Double(createdAt) / 1_000.0)
    }

    var updatedAtDate: Date {
        Date(timeIntervalSince1970: Double(updatedAt) / 1_000.0)
    }

    /// Progress as a fraction (0.0 to 1.0)
    var progress: Double {
        guard taskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(taskCount)
    }
}

/// The complete search response from the API
struct SearchResponse: Codable, Sendable {
    let query: String
    let results: [SearchResultItem]
    let total: Int
}

// MARK: - Search Error

enum SearchError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case emptyQuery
    case queryTooLong
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to search."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .emptyQuery:
            return "Search query cannot be empty."
        case .queryTooLong:
            return "Search query must be 200 characters or fewer."
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

// MARK: - Search Service

/// Service for searching tasks and stacks via the Dequeue API
/// Network-only service - does not use @MainActor
final class SearchService: @unchecked Sendable {
    private let authService: any AuthServiceProtocol
    private let urlSession: URLSession

    init(authService: any AuthServiceProtocol, urlSession: URLSession = PinnedURLSession.shared) {
        self.authService = authService
        self.urlSession = urlSession
    }

    /// Searches across tasks and stacks
    /// - Parameters:
    ///   - query: Search text (1-200 characters)
    ///   - limit: Maximum results per type (1-100, default 20)
    /// - Returns: Search response with results
    func search(query: String, limit: Int = 20) async throws -> SearchResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw SearchError.emptyQuery
        }

        guard trimmed.count <= 200 else {
            throw SearchError.queryTooLong
        }

        let token = try await authService.getAuthToken()

        var components = URLComponents(
            url: Configuration.dequeueAPIBaseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components?.url else {
            throw SearchError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logger.debug("Searching for: \(trimmed)")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SearchError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                throw SearchError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }

            let searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
            logger.info("Search returned \(searchResponse.total) results for '\(trimmed)'")
            return searchResponse
        } catch let error as SearchError {
            throw error
        } catch {
            throw SearchError.networkError(error)
        }
    }
}

// MARK: - Environment Key

private struct SearchServiceKey: EnvironmentKey {
    static let defaultValue: SearchService? = nil
}

extension EnvironmentValues {
    var searchService: SearchService? {
        get { self[SearchServiceKey.self] }
        set { self[SearchServiceKey.self] = newValue }
    }
}
