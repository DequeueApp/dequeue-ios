//
//  BatchService.swift
//  Dequeue
//
//  Client for batch task operations API endpoints:
//  - POST /v1/tasks/batch/complete
//  - POST /v1/tasks/batch/move
//  - POST /v1/tasks/batch/delete
//

import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.dequeue", category: "BatchService")

// MARK: - Batch Models

/// Result for a single item in a batch operation
struct BatchResultItem: Codable, Sendable, Identifiable {
    let taskId: String
    let success: Bool
    let error: String?

    var id: String { taskId }
}

/// Response from a batch operation
struct BatchResponse: Codable, Sendable {
    let results: [BatchResultItem]
    let succeeded: Int
    let failed: Int
    let totalCount: Int

    /// Whether all items in the batch succeeded
    var isFullSuccess: Bool { failed == 0 }

    /// Whether some but not all items succeeded
    var isPartialSuccess: Bool { succeeded > 0 && failed > 0 }
}

// MARK: - Batch Errors

enum BatchError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case emptyTaskIds
    case batchTooLarge(count: Int, max: Int)
    case duplicateTaskIds
    case missingTargetStack
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)

    /// Maximum number of tasks in a single batch operation
    static let maxBatchSize = 100

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform batch operations."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .emptyTaskIds:
            return "No tasks selected for batch operation."
        case let .batchTooLarge(count, max):
            return "Too many tasks selected (\(count)). Maximum is \(max)."
        case .duplicateTaskIds:
            return "Duplicate tasks detected in selection."
        case .missingTargetStack:
            return "A target stack is required for the move operation."
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

// MARK: - Batch Service

/// Service for performing batch operations on tasks via the Dequeue API.
///
/// Supports batch complete, move, and delete operations with up to 100 tasks per request.
/// All operations return detailed per-task results indicating success or failure.
final class BatchService: @unchecked Sendable {
    private let authService: any AuthServiceProtocol
    private let urlSession: URLSession

    init(authService: any AuthServiceProtocol, urlSession: URLSession = .shared) {
        self.authService = authService
        self.urlSession = urlSession
    }

    // MARK: - Batch Complete

    /// Marks multiple tasks as completed in a single request.
    ///
    /// - Parameter taskIds: Array of task IDs to complete (1-100)
    /// - Returns: Batch response with per-task results
    /// - Throws: `BatchError` if validation fails or the request encounters an error
    func batchComplete(taskIds: [String]) async throws -> BatchResponse {
        try validateTaskIds(taskIds)

        let body: [String: Any] = ["taskIds": taskIds]
        logger.info("Batch completing \(taskIds.count) tasks")

        return try await performRequest(
            path: "tasks/batch/complete",
            body: body
        )
    }

    // MARK: - Batch Move

    /// Moves multiple tasks to a different stack in a single request.
    ///
    /// Tasks maintain their order from the `taskIds` array in the target stack.
    ///
    /// - Parameters:
    ///   - taskIds: Array of task IDs to move (1-100)
    ///   - toStackId: ID of the target stack
    /// - Returns: Batch response with per-task results
    /// - Throws: `BatchError` if validation fails or the request encounters an error
    func batchMove(taskIds: [String], toStackId: String) async throws -> BatchResponse {
        try validateTaskIds(taskIds)

        guard !toStackId.isEmpty else {
            throw BatchError.missingTargetStack
        }

        let body: [String: Any] = [
            "taskIds": taskIds,
            "toStackId": toStackId
        ]
        logger.info("Batch moving \(taskIds.count) tasks to stack \(toStackId)")

        return try await performRequest(
            path: "tasks/batch/move",
            body: body
        )
    }

    // MARK: - Batch Delete

    /// Deletes multiple tasks in a single request.
    ///
    /// - Parameter taskIds: Array of task IDs to delete (1-100)
    /// - Returns: Batch response with per-task results
    /// - Throws: `BatchError` if validation fails or the request encounters an error
    func batchDelete(taskIds: [String]) async throws -> BatchResponse {
        try validateTaskIds(taskIds)

        let body: [String: Any] = ["taskIds": taskIds]
        logger.info("Batch deleting \(taskIds.count) tasks")

        return try await performRequest(
            path: "tasks/batch/delete",
            body: body
        )
    }

    // MARK: - Validation

    /// Validates task IDs for batch operations
    private func validateTaskIds(_ taskIds: [String]) throws {
        guard !taskIds.isEmpty else {
            throw BatchError.emptyTaskIds
        }

        guard taskIds.count <= BatchError.maxBatchSize else {
            throw BatchError.batchTooLarge(count: taskIds.count, max: BatchError.maxBatchSize)
        }

        // Check for duplicates
        let uniqueIds = Set(taskIds)
        guard uniqueIds.count == taskIds.count else {
            throw BatchError.duplicateTaskIds
        }
    }

    // MARK: - Network

    /// Performs an authenticated POST request to the batch API
    private func performRequest(path: String, body: [String: Any]) async throws -> BatchResponse {
        let token = try await authService.getAuthToken()

        let url = Configuration.dequeueAPIBaseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BatchError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                throw BatchError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }

            let batchResponse = try JSONDecoder().decode(BatchResponse.self, from: data)
            logger.info("Batch operation: \(batchResponse.succeeded)/\(batchResponse.totalCount) succeeded")
            return batchResponse
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.networkError(error)
        }
    }
}

// MARK: - Environment Key

private struct BatchServiceKey: EnvironmentKey {
    static let defaultValue: BatchService? = nil
}

extension EnvironmentValues {
    var batchService: BatchService? {
        get { self[BatchServiceKey.self] }
        set { self[BatchServiceKey.self] = newValue }
    }
}
