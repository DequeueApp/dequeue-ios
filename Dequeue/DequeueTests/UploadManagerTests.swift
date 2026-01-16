//
//  UploadManagerTests.swift
//  DequeueTests
//
//  Tests for UploadManager progress tracking and cancellation
//

import Testing
import Foundation
@testable import Dequeue

@Suite("UploadManager Tests")
struct UploadManagerTests {

    // MARK: - UploadProgress Tests

    @Test("UploadProgress calculates fraction completed correctly")
    @MainActor
    func progressFractionCalculation() {
        let progress = UploadProgress(
            attachmentId: "test-id",
            bytesUploaded: 500,
            totalBytes: 1000
        )

        #expect(progress.fractionCompleted == 0.5)
    }

    @Test("UploadProgress handles zero total bytes")
    @MainActor
    func progressZeroTotalBytes() {
        let progress = UploadProgress(
            attachmentId: "test-id",
            bytesUploaded: 100,
            totalBytes: 0
        )

        #expect(progress.fractionCompleted == 0)
    }

    @Test("UploadProgress handles completed upload")
    @MainActor
    func progressCompletedUpload() {
        let progress = UploadProgress(
            attachmentId: "test-id",
            bytesUploaded: 1000,
            totalBytes: 1000
        )

        #expect(progress.fractionCompleted == 1.0)
    }

    // MARK: - UploadError Tests

    @Test("UploadError has descriptive messages")
    func errorHasDescriptiveMessages() {
        let errors: [UploadError] = [
            .fileNotFound(path: "/path/to/file"),
            .uploadCancelled,
            .networkError("Connection timeout"),
            .serverError(statusCode: 500),
            .invalidResponse,
            .alreadyUploading(attachmentId: "att-123")
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("UploadError equality works correctly")
    func errorEquality() {
        #expect(UploadError.uploadCancelled == UploadError.uploadCancelled)
        #expect(UploadError.fileNotFound(path: "/a") == UploadError.fileNotFound(path: "/a"))
        #expect(UploadError.fileNotFound(path: "/a") != UploadError.fileNotFound(path: "/b"))
        #expect(UploadError.serverError(statusCode: 500) == UploadError.serverError(statusCode: 500))
        #expect(UploadError.serverError(statusCode: 500) != UploadError.serverError(statusCode: 404))
        #expect(UploadError.uploadCancelled != UploadError.invalidResponse)
    }

    // MARK: - MockUploadManager Tests

    @Test("MockUploadManager tracks upload calls")
    func mockTracksUploadCalls() async throws {
        let mock = MockUploadManager()
        // swiftlint:disable:next force_unwrapping
        let fileURL = URL(fileURLWithPath: "/tmp/test.txt")
        // swiftlint:disable:next force_unwrapping
        let presignedURL = URL(string: "https://s3.example.com/upload")!

        _ = try await mock.uploadFile(
            fileURL,
            to: presignedURL,
            attachmentId: "test-123",
            mimeType: "text/plain"
        )

        let callCount = await mock.uploadCallCount
        let lastFile = await mock.lastUploadedFileURL
        let lastPresigned = await mock.lastPresignedURL

        #expect(callCount == 1)
        #expect(lastFile == fileURL)
        #expect(lastPresigned == presignedURL)
    }

    @Test("MockUploadManager throws mock error")
    func mockThrowsError() async {
        let mock = MockUploadManager()
        await mock.setMockError(.uploadCancelled)
        // swiftlint:disable:next force_unwrapping
        let fileURL = URL(fileURLWithPath: "/tmp/test.txt")
        // swiftlint:disable:next force_unwrapping
        let presignedURL = URL(string: "https://s3.example.com/upload")!

        await #expect(throws: UploadError.self) {
            _ = try await mock.uploadFile(
                fileURL,
                to: presignedURL,
                attachmentId: "test-123",
                mimeType: "text/plain"
            )
        }
    }

    @Test("MockUploadManager simulates progress")
    @MainActor
    func mockSimulatesProgress() async throws {
        let mock = MockUploadManager()
        // swiftlint:disable:next force_unwrapping
        let fileURL = URL(fileURLWithPath: "/tmp/test.txt")
        // swiftlint:disable:next force_unwrapping
        let presignedURL = URL(string: "https://s3.example.com/upload")!

        let stream = try await mock.uploadFile(
            fileURL,
            to: presignedURL,
            attachmentId: "test-123",
            mimeType: "text/plain"
        )

        var progressUpdates: [UploadProgress] = []
        for await progress in stream {
            progressUpdates.append(progress)
        }

        #expect(progressUpdates.count > 0)
        #expect(progressUpdates.last?.fractionCompleted == 1.0)
    }

    @Test("MockUploadManager tracks cancel calls")
    func mockTracksCancelCalls() async {
        let mock = MockUploadManager()

        await mock.cancelUpload(attachmentId: "test-123")

        let cancelCount = await mock.cancelCallCount
        #expect(cancelCount == 1)
    }

    // MARK: - Real UploadManager Tests

    @Test("UploadManager throws for non-existent file")
    func uploadManagerThrowsForMissingFile() async {
        let manager = UploadManager()
        let nonExistentFile = URL(fileURLWithPath: "/nonexistent/path/file.txt")
        // swiftlint:disable:next force_unwrapping
        let presignedURL = URL(string: "https://s3.example.com/upload")!

        await #expect(throws: UploadError.self) {
            _ = try await manager.uploadFile(
                nonExistentFile,
                to: presignedURL,
                attachmentId: "test-123",
                mimeType: "text/plain"
            )
        }
    }

    @Test("UploadManager reports not uploading when idle")
    func uploadManagerReportsIdleState() async {
        let manager = UploadManager()

        let isUploading = await manager.isUploading(attachmentId: "test-123")

        #expect(!isUploading)
    }

    @Test("UploadManager can cancel non-existent upload safely")
    func uploadManagerCancelNonExistent() async {
        let manager = UploadManager()

        // Should not throw or crash
        await manager.cancelUpload(attachmentId: "non-existent")

        let isUploading = await manager.isUploading(attachmentId: "non-existent")
        #expect(!isUploading)
    }
}

// MARK: - MockUploadManager Helper Extension

extension MockUploadManager {
    func setMockError(_ error: UploadError?) async {
        mockError = error
    }
}
