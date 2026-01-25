//
//  AttachmentUploadServiceTests.swift
//  DequeueTests
//
//  Tests for AttachmentUploadService presigned URL flow
//

import Testing
import Foundation
@testable import Dequeue

@Suite("AttachmentUploadService Tests")
@MainActor
struct AttachmentUploadServiceTests {
    // MARK: - Test Helpers

    private func createMockAuthService() -> MockAuthService {
        let authService = MockAuthService()
        authService.mockSignIn(userId: "test-user")
        return authService
    }

    // MARK: - PresignedUploadResponse Decoding Tests

    @Test("PresignedUploadResponse decodes valid JSON")
    func presignedResponseDecodesValidJSON() throws {
        // Unix milliseconds for 2026-01-15T12:00:00Z
        let expiresAtMs: Int64 = 1_768_478_400_000
        let json = """
        {
            "uploadUrl": "https://s3.amazonaws.com/bucket/key?signature=abc",
            "downloadUrl": "https://cdn.example.com/files/123",
            "attachmentId": "att_123456",
            "expiresAt": \(expiresAtMs)
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(PresignedUploadResponse.self, from: json)

        #expect(response.uploadUrl.absoluteString.contains("s3.amazonaws.com"))
        #expect(response.downloadUrl.absoluteString.contains("cdn.example.com"))
        #expect(response.attachmentId == "att_123456")
        #expect(response.expiresAt > Date(timeIntervalSince1970: 0))
    }

    @Test("PresignedUploadResponse throws on invalid expiresAt type")
    func presignedResponseThrowsOnInvalidDate() {
        // expiresAt should be Int64 milliseconds, not a string
        let json = """
        {
            "uploadUrl": "https://s3.amazonaws.com/bucket/key",
            "downloadUrl": "https://cdn.example.com/files/123",
            "attachmentId": "att_123456",
            "expiresAt": "not-a-number"
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PresignedUploadResponse.self, from: json)
        }
    }

    @Test("PresignedUploadResponse encodes to JSON")
    func presignedResponseEncodesToJSON() throws {
        // swiftlint:disable:next force_unwrapping
        let response = PresignedUploadResponse(
            uploadUrl: URL(string: "https://s3.example.com/upload")!,
            downloadUrl: URL(string: "https://cdn.example.com/download")!,
            attachmentId: "att_123",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["uploadUrl"] as? String == "https://s3.example.com/upload")
        #expect(json?["downloadUrl"] as? String == "https://cdn.example.com/download")
        #expect(json?["attachmentId"] as? String == "att_123")
        // Should encode as Unix milliseconds (Int64)
        let expiresAtMs = json?["expiresAt"] as? Int64
        #expect(expiresAtMs == 1_700_000_000_000) // 1_700_000_000 seconds * 1000
    }

    // MARK: - Error Type Tests

    @Test("AttachmentUploadError has descriptive messages")
    func errorHasDescriptiveMessages() {
        let errors: [AttachmentUploadError] = [
            .notAuthenticated,
            .quotaExceeded(usedBytes: 100_000_000, limitBytes: 50_000_000),
            .fileTooLarge(sizeBytes: 60_000_000, maxBytes: 50_000_000),
            .invalidResponse,
            .networkError("Connection timeout"),
            .serverError(statusCode: 500, message: "Internal error"),
            .uploadFailed("Upload interrupted")
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("AttachmentUploadError equality works correctly")
    func errorEqualityWorks() {
        #expect(AttachmentUploadError.notAuthenticated == AttachmentUploadError.notAuthenticated)
        #expect(
            AttachmentUploadError.quotaExceeded(usedBytes: 100, limitBytes: 50)
            == AttachmentUploadError.quotaExceeded(usedBytes: 100, limitBytes: 50)
        )
        #expect(
            AttachmentUploadError.quotaExceeded(usedBytes: 100, limitBytes: 50)
            != AttachmentUploadError.quotaExceeded(usedBytes: 200, limitBytes: 50)
        )
        #expect(AttachmentUploadError.notAuthenticated != AttachmentUploadError.invalidResponse)
    }

    // MARK: - Mock Service Tests

    @Test("MockAttachmentUploadService returns mock response")
    func mockServiceReturnsMockResponse() async throws {
        let mockService = MockAttachmentUploadService()
        // swiftlint:disable:next force_unwrapping
        mockService.mockResponse = PresignedUploadResponse(
            uploadUrl: URL(string: "https://test.s3.com/upload")!,
            downloadUrl: URL(string: "https://test.cdn.com/file")!,
            attachmentId: "test-id",
            expiresAt: Date().addingTimeInterval(3_600)
        )

        let response = try await mockService.requestPresignedUploadURL(
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1_024
        )

        #expect(response.attachmentId == "test-id")
        #expect(mockService.requestPresignedURLCallCount == 1)
        #expect(mockService.lastRequestedFilename == "test.pdf")
        #expect(mockService.lastRequestedMimeType == "application/pdf")
        #expect(mockService.lastRequestedSizeBytes == 1_024)
    }

    @Test("MockAttachmentUploadService throws mock error")
    func mockServiceThrowsMockError() async throws {
        let mockService = MockAttachmentUploadService()
        mockService.mockError = .quotaExceeded(usedBytes: 100, limitBytes: 50)

        await #expect(throws: AttachmentUploadError.self) {
            _ = try await mockService.requestPresignedUploadURL(
                filename: "test.pdf",
                mimeType: "application/pdf",
                sizeBytes: 1_024
            )
        }
    }

    @Test("MockAttachmentUploadService tracks upload calls")
    func mockServiceTracksUploadCalls() async throws {
        let mockService = MockAttachmentUploadService()
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://s3.example.com/upload")!

        try await mockService.uploadToPresignedURL(
            data: Data([0x01, 0x02, 0x03]),
            presignedURL: url,
            mimeType: "application/pdf"
        )

        #expect(mockService.uploadCallCount == 1)
    }

    @Test("MockAttachmentUploadService returns default response when no mock set")
    func mockServiceReturnsDefaultResponse() async throws {
        let mockService = MockAttachmentUploadService()

        let response = try await mockService.requestPresignedUploadURL(
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1_024
        )

        // Should return a valid default response
        #expect(!response.attachmentId.isEmpty)
        #expect(response.uploadUrl.absoluteString.contains("s3.example.com"))
        #expect(response.expiresAt > Date())
    }

    // MARK: - Integration Tests (require mocked URLSession)

    @Test("AttachmentUploadService throws notAuthenticated when not signed in")
    func serviceThrowsWhenNotAuthenticated() async {
        let authService = MockAuthService()
        // Not signed in - authService.isAuthenticated is false
        let service = AttachmentUploadService(authService: authService)

        await #expect(throws: AttachmentUploadError.self) {
            _ = try await service.requestPresignedUploadURL(
                filename: "test.pdf",
                mimeType: "application/pdf",
                sizeBytes: 1_024
            )
        }
    }
}
