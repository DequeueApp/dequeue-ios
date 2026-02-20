//
//  ExportService.swift
//  Dequeue
//
//  Client for the data export endpoint (GET /v1/export)
//

import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.dequeue", category: "ExportService")

// MARK: - Export Models

/// Complete data export from the API
struct ExportResponse: Codable, Sendable {
    let exportedAt: Int64 // Unix milliseconds
    let version: String   // Export format version
    let arcs: [ArcExport]
    let stacks: [StackExport]
    let tasks: [TaskExport]
    let tags: [TagExport]
    let reminders: [ReminderExport]

    var exportedAtDate: Date {
        Date(timeIntervalSince1970: Double(exportedAt) / 1_000.0)
    }

    /// Total number of items in the export
    var totalItems: Int {
        arcs.count + stacks.count + tasks.count + tags.count + reminders.count
    }
}

/// Arc data in the export
struct ArcExport: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let colorHex: String?
    let sortOrder: Int
    let stackCount: Int
    let completedStackCount: Int
    let createdAt: Int64
    let updatedAt: Int64
    let completedAt: Int64?
}

/// Stack data in the export
struct StackExport: Codable, Sendable, Identifiable {
    let id: String
    let arcId: String?
    let title: String
    let status: String
    let sortOrder: Int
    let taskCount: Int
    let completedTaskCount: Int
    let tags: [String]
    let isActive: Bool
    let activeTaskId: String?
    let createdAt: Int64
    let updatedAt: Int64
}

/// Task data in the export
struct TaskExport: Codable, Sendable, Identifiable {
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
}

/// Tag data in the export
struct TagExport: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let colorHex: String?
    let createdAt: Int64
    let updatedAt: Int64
}

/// Reminder data in the export
struct ReminderExport: Codable, Sendable, Identifiable {
    let id: String
    let parentType: String // "stack" or "arc"
    let parentId: String
    let remindAt: Int64
    let createdAt: Int64
    let updatedAt: Int64

    var remindAtDate: Date {
        Date(timeIntervalSince1970: Double(remindAt) / 1_000.0)
    }
}

// MARK: - Export Error

enum ExportError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)
    case fileWriteError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to export data."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case let .serverError(statusCode, message):
            if let message {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server error: \(statusCode)"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        case let .fileWriteError(error):
            return "Failed to save export: \(error.localizedDescription)"
        }
    }
}

// MARK: - Export Service

/// Service for exporting user data via the Dequeue API
/// Network-only service - does not use @MainActor
final class ExportService: @unchecked Sendable {
    private let authService: any AuthServiceProtocol
    private let urlSession: URLSession

    init(authService: any AuthServiceProtocol, urlSession: URLSession = .shared) {
        self.authService = authService
        self.urlSession = urlSession
    }

    /// Fetches all user data as a structured export
    /// - Returns: Complete export response
    func exportData() async throws -> ExportResponse {
        let token = try await authService.getAuthToken()

        let url = Configuration.dequeueAPIBaseURL
            .appendingPathComponent("export")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logger.debug("Exporting data from: \(url.absoluteString)")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ExportError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                throw ExportError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }

            let export = try JSONDecoder().decode(ExportResponse.self, from: data)
            logger.info("Export complete: \(export.totalItems) total items")
            return export
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.networkError(error)
        }
    }

    /// Exports data and saves to a temporary JSON file for sharing
    /// - Returns: URL of the saved file
    func exportToFile() async throws -> URL {
        let export = try await exportData()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "dequeue-export-\(timestamp).json"

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            logger.info("Export saved to: \(fileURL.path)")
            return fileURL
        } catch {
            throw ExportError.fileWriteError(error)
        }
    }
}

// MARK: - Environment Key

private struct ExportServiceKey: EnvironmentKey {
    static let defaultValue: ExportService? = nil
}

extension EnvironmentValues {
    var exportService: ExportService? {
        get { self[ExportServiceKey.self] }
        set { self[ExportServiceKey.self] = newValue }
    }
}
