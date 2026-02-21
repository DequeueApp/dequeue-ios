//
//  AttachmentUploadCoordinatorTests.swift
//  DequeueTests
//
//  Tests for AttachmentUploadCoordinator upload orchestration
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

private typealias Attachment = Dequeue.Attachment

// MARK: - Mock Upload Service

private final class MockUploadService: AttachmentUploadServiceProtocol, @unchecked Sendable {
    var requestPresignedCallCount = 0
    var uploadDataCallCount = 0
    var uploadFileCallCount = 0
    var shouldFailPresigned = false
    var shouldFailUpload = false

    func requestPresignedUploadURL(
        filename: String,
        mimeType: String,
        sizeBytes: Int64
    ) async throws -> PresignedUploadResponse {
        requestPresignedCallCount += 1
        if shouldFailPresigned {
            throw AttachmentUploadError.serverError(statusCode: 500, message: "Mock server error")
        }
        return PresignedUploadResponse(
            uploadUrl: URL(string: "https://upload.example.com/presigned")!,
            downloadUrl: URL(string: "https://cdn.example.com/file.pdf")!,
            attachmentId: "server-attachment-id",
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    func uploadToPresignedURL(
        data: Data,
        presignedURL: URL,
        mimeType: String
    ) async throws {
        uploadDataCallCount += 1
        if shouldFailUpload {
            throw AttachmentUploadError.uploadFailed("Mock upload failure")
        }
    }

    func uploadToPresignedURL(
        fromFile fileURL: URL,
        presignedURL: URL,
        mimeType: String,
        fileSize: Int64
    ) async throws {
        uploadFileCallCount += 1
        if shouldFailUpload {
            throw AttachmentUploadError.uploadFailed("Mock upload failure")
        }
    }
}

// MARK: - Helpers

private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Attachment.self,
        Tag.self,
        Device.self,
        SyncConflict.self,
        configurations: config
    )
}

/// Creates a temporary file for upload testing
private func createTempFile(named: String = "upload-test.pdf", content: String = "PDF content") throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let fileURL = tempDir.appendingPathComponent(named)
    try content.data(using: .utf8)?.write(to: fileURL)
    return fileURL
}

// MARK: - Tests

@Suite("AttachmentUploadCoordinator Tests", .serialized)
@MainActor
struct AttachmentUploadCoordinatorTests {

    // MARK: - Successful Upload Tests

    @Test("uploadAttachment completes full upload flow")
    func uploadAttachmentSuccess() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()

        let fileURL = try createTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "upload-test.pdf",
            mimeType: "application/pdf",
            sizeBytes: Int64("PDF content".count),
            localPath: fileURL.path
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        try await coordinator.uploadAttachment(attachment)

        // Verify upload service was called correctly
        #expect(mockService.requestPresignedCallCount == 1)
        #expect(mockService.uploadFileCallCount == 1)

        // Verify attachment state updated
        #expect(attachment.uploadState == .completed)
        #expect(attachment.remoteUrl == "https://cdn.example.com/file.pdf")
    }

    @Test("uploadAttachment transitions through states correctly")
    func uploadAttachmentStateTransitions() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()

        let fileURL = try createTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: fileURL.path,
            uploadState: .pending
        )
        context.insert(attachment)
        try context.save()

        #expect(attachment.uploadState == .pending)

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        try await coordinator.uploadAttachment(attachment)

        #expect(attachment.uploadState == .completed)
    }

    // MARK: - Error Handling Tests

    @Test("uploadAttachment throws noLocalFile when localPath is nil")
    func uploadNoLocalPath() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: nil  // No local file
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        await #expect(throws: AttachmentUploadError.self) {
            try await coordinator.uploadAttachment(attachment)
        }

        #expect(mockService.requestPresignedCallCount == 0)
    }

    @Test("uploadAttachment throws fileNotFound when file doesn't exist")
    func uploadFileMissing() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "nonexistent.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: "/tmp/this-file-does-not-exist-\(UUID().uuidString).pdf"
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        await #expect(throws: AttachmentUploadError.self) {
            try await coordinator.uploadAttachment(attachment)
        }

        #expect(mockService.requestPresignedCallCount == 0)
    }

    @Test("uploadAttachment marks as failed on presigned URL error")
    func uploadPresignedFailure() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()
        mockService.shouldFailPresigned = true

        let fileURL = try createTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: fileURL.path
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        await #expect(throws: AttachmentUploadError.self) {
            try await coordinator.uploadAttachment(attachment)
        }

        // Should be marked as failed
        #expect(attachment.uploadState == .failed)
    }

    @Test("uploadAttachment marks as failed on upload error")
    func uploadUploadFailure() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()
        mockService.shouldFailUpload = true

        let fileURL = try createTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: fileURL.path
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        await #expect(throws: AttachmentUploadError.self) {
            try await coordinator.uploadAttachment(attachment)
        }

        #expect(attachment.uploadState == .failed)
        #expect(attachment.remoteUrl == nil)
    }

    // MARK: - Duplicate Upload Prevention Tests

    @Test("uploadAttachment prevents duplicate uploads for same attachment")
    func preventDuplicateUploads() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()

        let fileURL = try createTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: fileURL.path
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        // Upload once - should succeed
        try await coordinator.uploadAttachment(attachment)
        #expect(mockService.requestPresignedCallCount == 1)

        // uploadingAttachments set should be empty after completion (defer removes it)
        #expect(coordinator.uploadingAttachments.isEmpty)
    }

    // MARK: - Retry Tests

    @Test("retryUpload works for failed attachments")
    func retryFailedUpload() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()

        let fileURL = try createTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: fileURL.path,
            uploadState: .failed  // Pre-set to failed
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        try await coordinator.retryUpload(attachment)

        // Should have been retried
        #expect(mockService.requestPresignedCallCount == 1)
        #expect(mockService.uploadFileCallCount == 1)
        #expect(attachment.uploadState == .completed)
    }

    @Test("retryUpload does nothing for non-failed attachments")
    func retryNonFailedUpload() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()

        let fileURL = try createTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: fileURL.path,
            uploadState: .pending  // Not failed
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        try await coordinator.retryUpload(attachment)

        // Should NOT have been retried
        #expect(mockService.requestPresignedCallCount == 0)
    }

    @Test("retryUpload does nothing for completed attachments")
    func retryCompletedUpload() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            uploadState: .completed
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        try await coordinator.retryUpload(attachment)

        #expect(mockService.requestPresignedCallCount == 0)
    }

    // MARK: - updatedAt Tracking Tests

    @Test("uploadAttachment updates updatedAt timestamp on success")
    func updatesTimestampOnSuccess() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()

        let fileURL = try createTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let originalDate = Date(timeIntervalSince1970: 1000)
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: fileURL.path,
            updatedAt: originalDate
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        try await coordinator.uploadAttachment(attachment)

        #expect(attachment.updatedAt > originalDate)
    }

    @Test("uploadAttachment updates updatedAt timestamp on failure")
    func updatesTimestampOnFailure() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let mockService = MockUploadService()
        mockService.shouldFailPresigned = true

        let fileURL = try createTempFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let originalDate = Date(timeIntervalSince1970: 1000)
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 100,
            localPath: fileURL.path,
            updatedAt: originalDate
        )
        context.insert(attachment)
        try context.save()

        let coordinator = AttachmentUploadCoordinator(
            modelContext: context,
            uploadService: mockService
        )

        _ = try? await coordinator.uploadAttachment(attachment)

        #expect(attachment.updatedAt > originalDate)
    }
}
