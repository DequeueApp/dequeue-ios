//
//  AttachmentUploadService.swift
//  Dequeue
//
//  Handles presigned URL requests and file uploads for attachments
//

import Foundation
import os.log

// MARK: - Response Models

/// Response from the presigned upload URL endpoint
struct PresignedUploadResponse: Codable, Sendable {
    let uploadUrl: URL
    let downloadUrl: URL
    let attachmentId: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case uploadUrl = "upload_url"
        case downloadUrl = "download_url"
        case attachmentId = "attachment_id"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uploadUrl = try container.decode(URL.self, forKey: .uploadUrl)
        downloadUrl = try container.decode(URL.self, forKey: .downloadUrl)
        attachmentId = try container.decode(String.self, forKey: .attachmentId)

        // Handle ISO8601 date string
        let expiresAtString = try container.decode(String.self, forKey: .expiresAt)
        if let date = ISO8601DateFormatter().date(from: expiresAtString) {
            expiresAt = date
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .expiresAt,
                in: container,
                debugDescription: "Invalid date format: \(expiresAtString)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uploadUrl, forKey: .uploadUrl)
        try container.encode(downloadUrl, forKey: .downloadUrl)
        try container.encode(attachmentId, forKey: .attachmentId)
        try container.encode(ISO8601DateFormatter().string(from: expiresAt), forKey: .expiresAt)
    }

    /// For testing - create directly without decoding
    init(uploadUrl: URL, downloadUrl: URL, attachmentId: String, expiresAt: Date) {
        self.uploadUrl = uploadUrl
        self.downloadUrl = downloadUrl
        self.attachmentId = attachmentId
        self.expiresAt = expiresAt
    }
}

// MARK: - Errors

enum AttachmentUploadError: LocalizedError, Equatable {
    case notAuthenticated
    case quotaExceeded(usedBytes: Int64, limitBytes: Int64)
    case fileTooLarge(sizeBytes: Int64, maxBytes: Int64)
    case invalidResponse
    case networkError(String)
    case serverError(statusCode: Int, message: String?)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to upload files."
        case let .quotaExceeded(used, limit):
            let usedMB = Double(used) / 1_024 / 1_024
            let limitMB = Double(limit) / 1_024 / 1_024
            return String(format: "Storage quota exceeded. Using %.1f MB of %.1f MB.", usedMB, limitMB)
        case let .fileTooLarge(size, max):
            let sizeMB = Double(size) / 1_024 / 1_024
            let maxMB = Double(max) / 1_024 / 1_024
            return String(format: "File too large (%.1f MB). Maximum size is %.1f MB.", sizeMB, maxMB)
        case .invalidResponse:
            return "Received an invalid response from the server."
        case let .networkError(message):
            return "Network error: \(message)"
        case let .serverError(statusCode, message):
            if let message {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server error (\(statusCode))"
        case let .uploadFailed(message):
            return "Upload failed: \(message)"
        }
    }

    static func == (lhs: AttachmentUploadError, rhs: AttachmentUploadError) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthenticated, .notAuthenticated):
            return true
        case let (.quotaExceeded(u1, l1), .quotaExceeded(u2, l2)):
            return u1 == u2 && l1 == l2
        case let (.fileTooLarge(s1, m1), .fileTooLarge(s2, m2)):
            return s1 == s2 && m1 == m2
        case (.invalidResponse, .invalidResponse):
            return true
        case let (.networkError(m1), .networkError(m2)):
            return m1 == m2
        case let (.serverError(c1, m1), .serverError(c2, m2)):
            return c1 == c2 && m1 == m2
        case let (.uploadFailed(m1), .uploadFailed(m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

// MARK: - Service Protocol

@MainActor
protocol AttachmentUploadServiceProtocol {
    /// Requests a presigned URL for uploading an attachment
    /// - Parameters:
    ///   - filename: The original filename
    ///   - mimeType: The MIME type of the file
    ///   - sizeBytes: The size of the file in bytes
    /// - Returns: A presigned upload response with URLs and attachment ID
    /// - Throws: `AttachmentUploadError` on failure
    func requestPresignedUploadURL(
        filename: String,
        mimeType: String,
        sizeBytes: Int64
    ) async throws -> PresignedUploadResponse

    /// Uploads file data to a presigned URL
    /// - Parameters:
    ///   - data: The file data to upload
    ///   - presignedURL: The presigned upload URL
    ///   - mimeType: The MIME type of the file
    /// - Throws: `AttachmentUploadError` on failure
    func uploadToPresignedURL(
        data: Data,
        presignedURL: URL,
        mimeType: String
    ) async throws
}

// MARK: - Implementation

@MainActor
final class AttachmentUploadService: AttachmentUploadServiceProtocol {
    private let session: URLSession
    private let authService: AuthServiceProtocol
    private let maxRetryAttempts = 3
    private let retryDelayBase: TimeInterval = 1.0

    init(authService: AuthServiceProtocol, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    func requestPresignedUploadURL(
        filename: String,
        mimeType: String,
        sizeBytes: Int64
    ) async throws -> PresignedUploadResponse {
        let token = try await getAuthToken()

        let url = Configuration.syncAPIBaseURL.appendingPathComponent("attachments/presign")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "filename": filename,
            "mime_type": mimeType,
            "size_bytes": sizeBytes
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await executeWithRetry(request: request) { data, response in
            try self.parsePresignedResponse(data: data, response: response)
        }
    }

    func uploadToPresignedURL(
        data: Data,
        presignedURL: URL,
        mimeType: String
    ) async throws {
        var request = URLRequest(url: presignedURL)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = data

        // S3 presigned URLs don't use our auth token - they're self-authenticating
        try await executeWithRetry(request: request) { _, response in
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AttachmentUploadError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw AttachmentUploadError.uploadFailed(
                    "Upload returned status \(httpResponse.statusCode)"
                )
            }
        }
    }

    // MARK: - Private Helpers

    private func getAuthToken() async throws -> String {
        do {
            return try await authService.getAuthToken()
        } catch {
            throw AttachmentUploadError.notAuthenticated
        }
    }

    private func parsePresignedResponse(data: Data, response: URLResponse) throws -> PresignedUploadResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AttachmentUploadError.invalidResponse
        }

        // Handle error responses
        if httpResponse.statusCode != 200 {
            try handleErrorResponse(data: data, statusCode: httpResponse.statusCode)
        }

        // Parse successful response
        do {
            return try JSONDecoder().decode(PresignedUploadResponse.self, from: data)
        } catch {
            os_log("[AttachmentUpload] Failed to decode response: \(error)")
            throw AttachmentUploadError.invalidResponse
        }
    }

    private func handleErrorResponse(data: Data, statusCode: Int) throws {
        // Try to parse error details from response
        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let errorCode = errorJson["error_code"] as? String
            let message = errorJson["message"] as? String

            switch errorCode {
            case "quota_exceeded":
                let usedBytes = errorJson["used_bytes"] as? Int64 ?? 0
                let limitBytes = errorJson["limit_bytes"] as? Int64 ?? 0
                throw AttachmentUploadError.quotaExceeded(usedBytes: usedBytes, limitBytes: limitBytes)

            case "file_too_large":
                let sizeBytes = errorJson["size_bytes"] as? Int64 ?? 0
                let maxBytes = errorJson["max_bytes"] as? Int64 ?? 0
                throw AttachmentUploadError.fileTooLarge(sizeBytes: sizeBytes, maxBytes: maxBytes)

            default:
                throw AttachmentUploadError.serverError(statusCode: statusCode, message: message)
            }
        }

        // Generic error if we can't parse the response
        switch statusCode {
        case 401:
            throw AttachmentUploadError.notAuthenticated
        case 413:
            throw AttachmentUploadError.fileTooLarge(sizeBytes: 0, maxBytes: 0)
        default:
            throw AttachmentUploadError.serverError(statusCode: statusCode, message: nil)
        }
    }

    /// Executes a request with exponential backoff retry for transient failures
    private func executeWithRetry<T>(
        request: URLRequest,
        parse: (Data, URLResponse) throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetryAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                return try parse(data, response)
            } catch let error as AttachmentUploadError {
                // Don't retry for non-transient errors
                switch error {
                case .notAuthenticated, .quotaExceeded, .fileTooLarge, .invalidResponse:
                    throw error
                case .networkError, .serverError, .uploadFailed:
                    lastError = error
                }
            } catch let urlError as URLError {
                // Retry for network-related errors
                lastError = AttachmentUploadError.networkError(urlError.localizedDescription)
            } catch {
                lastError = error
            }

            // Exponential backoff
            if attempt < maxRetryAttempts - 1 {
                let delay = retryDelayBase * pow(2.0, Double(attempt))
                os_log("[AttachmentUpload] Retry attempt \(attempt + 1) after \(delay)s delay")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        if let uploadError = lastError as? AttachmentUploadError {
            throw uploadError
        }
        throw AttachmentUploadError.networkError(lastError?.localizedDescription ?? "Unknown error")
    }
}

// MARK: - Mock Implementation

@MainActor
final class MockAttachmentUploadService: AttachmentUploadServiceProtocol {
    var mockResponse: PresignedUploadResponse?
    var mockError: AttachmentUploadError?
    var requestPresignedURLCallCount = 0
    var uploadCallCount = 0
    var lastRequestedFilename: String?
    var lastRequestedMimeType: String?
    var lastRequestedSizeBytes: Int64?

    func requestPresignedUploadURL(
        filename: String,
        mimeType: String,
        sizeBytes: Int64
    ) async throws -> PresignedUploadResponse {
        requestPresignedURLCallCount += 1
        lastRequestedFilename = filename
        lastRequestedMimeType = mimeType
        lastRequestedSizeBytes = sizeBytes

        if let error = mockError {
            throw error
        }

        if let response = mockResponse {
            return response
        }

        // Return a default mock response
        // swiftlint:disable:next force_unwrapping
        return PresignedUploadResponse(
            uploadUrl: URL(string: "https://s3.example.com/upload/\(CUID.generate())")!,
            downloadUrl: URL(string: "https://cdn.example.com/files/\(CUID.generate())")!,
            attachmentId: CUID.generate(),
            expiresAt: Date().addingTimeInterval(3_600)
        )
    }

    func uploadToPresignedURL(
        data: Data,
        presignedURL: URL,
        mimeType: String
    ) async throws {
        uploadCallCount += 1

        if let error = mockError {
            throw error
        }
    }
}
