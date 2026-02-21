//
//  StatsService.swift
//  Dequeue
//
//  Client for the task statistics endpoint (GET /v1/me/stats)
//

import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.dequeue", category: "StatsService")

// MARK: - Stats Models

/// Complete statistics response from the API
struct StatsResponse: Codable, Sendable {
    let tasks: TaskStats
    let priority: PriorityBreakdown
    let stacks: StackStats
    let completionStreak: Int
}

/// Task count statistics
struct TaskStats: Codable, Sendable {
    let total: Int
    let active: Int
    let completed: Int
    let overdue: Int
    let completedToday: Int
    let completedThisWeek: Int
    let createdToday: Int
    let createdThisWeek: Int

    /// Completion rate as a fraction (0.0 to 1.0)
    var completionRate: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

/// Active tasks broken down by priority level
struct PriorityBreakdown: Codable, Sendable {
    let none: Int   // priority = 0
    let low: Int    // priority = 1
    let medium: Int // priority = 2
    let high: Int   // priority = 3

    /// Total active tasks across all priorities
    var total: Int {
        none + low + medium + high
    }
}

/// Stack and arc count statistics
struct StackStats: Codable, Sendable {
    let total: Int
    let active: Int
    let totalArcs: Int
}

// MARK: - Stats Error

enum StatsError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to view statistics."
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

// MARK: - Stats Service

/// Service for fetching task statistics via the Dequeue API
/// Network-only service - does not use @MainActor
final class StatsService: @unchecked Sendable {
    private let authService: any AuthServiceProtocol
    private let urlSession: URLSession

    init(authService: any AuthServiceProtocol, urlSession: URLSession = PinnedURLSession.shared) {
        self.authService = authService
        self.urlSession = urlSession
    }

    /// Fetches aggregate statistics for the current user
    /// - Returns: Complete statistics response
    func getStats() async throws -> StatsResponse {
        let token = try await authService.getAuthToken()

        let url = Configuration.dequeueAPIBaseURL
            .appendingPathComponent("me")
            .appendingPathComponent("stats")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logger.debug("Fetching stats from: \(url.absoluteString)")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw StatsError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                throw StatsError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }

            let stats = try JSONDecoder().decode(StatsResponse.self, from: data)
            logger.info("Fetched stats: \(stats.tasks.total) tasks, \(stats.stacks.total) stacks")
            return stats
        } catch let error as StatsError {
            throw error
        } catch {
            throw StatsError.networkError(error)
        }
    }
}

// MARK: - Environment Key

private struct StatsServiceKey: EnvironmentKey {
    static let defaultValue: StatsService? = nil
}

extension EnvironmentValues {
    var statsService: StatsService? {
        get { self[StatsServiceKey.self] }
        set { self[StatsServiceKey.self] = newValue }
    }
}
