//
//  DownloadManagerTests.swift
//  DequeueTests
//
//  Tests for DownloadManager progress tracking and cancellation
//

import Testing
import Foundation
@testable import Dequeue

@Suite("DownloadManager Tests")
struct DownloadManagerTests {

    // MARK: - DownloadProgress Tests

    @Test("DownloadProgress calculates fraction completed correctly")
    @MainActor
    func progressFractionCalculation() {
        let progress = DownloadProgress(
            attachmentId: "test-id",
            bytesDownloaded: 500,
            totalBytes: 1000
        )

        #expect(progress.fractionCompleted == 0.5)
    }

    @Test("DownloadProgress handles zero total bytes")
    @MainActor
    func progressZeroTotalBytes() {
        let progress = DownloadProgress(
            attachmentId: "test-id",
            bytesDownloaded: 100,
            totalBytes: 0
        )

        #expect(progress.fractionCompleted == 0)
    }

    @Test("DownloadProgress handles completed download")
    @MainActor
    func progressCompletedDownload() {
        let progress = DownloadProgress(
            attachmentId: "test-id",
            bytesDownloaded: 1000,
            totalBytes: 1000
        )

        #expect(progress.fractionCompleted == 1.0)
    }

    // MARK: - DownloadError Tests

    @Test("DownloadError has descriptive messages")
    func errorHasDescriptiveMessages() {
        let errors: [DownloadError] = [
            .downloadCancelled,
            .networkError("Connection timeout"),
            .serverError(statusCode: 500),
            .invalidResponse,
            .fileSystemError("Permission denied"),
            .alreadyDownloading(attachmentId: "att-123"),
            .invalidURL
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("DownloadError equality works correctly")
    func errorEquality() {
        #expect(DownloadError.downloadCancelled == DownloadError.downloadCancelled)
        #expect(DownloadError.networkError("a") == DownloadError.networkError("a"))
        #expect(DownloadError.networkError("a") != DownloadError.networkError("b"))
        #expect(DownloadError.serverError(statusCode: 500) == DownloadError.serverError(statusCode: 500))
        #expect(DownloadError.serverError(statusCode: 500) != DownloadError.serverError(statusCode: 404))
        #expect(DownloadError.downloadCancelled != DownloadError.invalidResponse)
    }

    // MARK: - MockDownloadManager Tests

    @Test("MockDownloadManager tracks download calls")
    func mockTracksDownloadCalls() async throws {
        let mock = MockDownloadManager()
        // swiftlint:disable:next force_unwrapping
        let remoteURL = URL(string: "https://cdn.example.com/files/test.pdf")!

        _ = try await mock.downloadFile(
            from: remoteURL,
            attachmentId: "test-123",
            filename: "test.pdf"
        )

        let callCount = await mock.downloadCallCount
        let lastURL = await mock.lastDownloadedURL

        #expect(callCount == 1)
        #expect(lastURL == remoteURL)
    }

    @Test("MockDownloadManager throws mock error")
    func mockThrowsError() async {
        let mock = MockDownloadManager()
        await mock.setMockError(.downloadCancelled)
        // swiftlint:disable:next force_unwrapping
        let remoteURL = URL(string: "https://cdn.example.com/files/test.pdf")!

        await #expect(throws: DownloadError.self) {
            _ = try await mock.downloadFile(
                from: remoteURL,
                attachmentId: "test-123",
                filename: "test.pdf"
            )
        }
    }

    @Test("MockDownloadManager simulates progress")
    @MainActor
    func mockSimulatesProgress() async throws {
        let mock = MockDownloadManager()
        // swiftlint:disable:next force_unwrapping
        let remoteURL = URL(string: "https://cdn.example.com/files/test.pdf")!

        let (stream, _) = try await mock.downloadFile(
            from: remoteURL,
            attachmentId: "test-123",
            filename: "test.pdf"
        )

        var progressUpdates: [DownloadProgress] = []
        for await progress in stream {
            progressUpdates.append(progress)
        }

        #expect(progressUpdates.count > 0)
        #expect(progressUpdates.last?.fractionCompleted == 1.0)
    }

    @Test("MockDownloadManager tracks cancel calls")
    func mockTracksCancelCalls() async {
        let mock = MockDownloadManager()

        await mock.cancelDownload(attachmentId: "test-123")

        let cancelCount = await mock.cancelCallCount
        #expect(cancelCount == 1)
    }

    // MARK: - Real DownloadManager Tests

    @Test("DownloadManager reports not downloading when idle")
    func downloadManagerReportsIdleState() async {
        let manager = DownloadManager()

        let isDownloading = await manager.isDownloading(attachmentId: "test-123")

        #expect(!isDownloading)
    }

    @Test("DownloadManager can cancel non-existent download safely")
    func downloadManagerCancelNonExistent() async {
        let manager = DownloadManager()

        // Should not throw or crash
        await manager.cancelDownload(attachmentId: "non-existent")

        let isDownloading = await manager.isDownloading(attachmentId: "non-existent")
        #expect(!isDownloading)
    }

    @Test("DownloadManager reports not downloaded for missing file")
    func downloadManagerReportsNotDownloaded() async {
        let manager = DownloadManager()

        let isDownloaded = await manager.isDownloaded(
            attachmentId: "non-existent",
            filename: "file.pdf"
        )

        #expect(!isDownloaded)
    }

    @Test("DownloadManager returns nil local URL for missing file")
    func downloadManagerReturnsNilForMissingFile() async {
        let manager = DownloadManager()

        let localURL = await manager.localURL(
            for: "non-existent",
            filename: "file.pdf"
        )

        #expect(localURL == nil)
    }

    @Test("DownloadManager delete handles non-existent file gracefully")
    func downloadManagerDeleteNonExistent() async throws {
        let manager = DownloadManager()

        // Should not throw
        try await manager.deleteDownload(attachmentId: "non-existent")
    }
}

// MARK: - MockDownloadManager Helper Extension

extension MockDownloadManager {
    func setMockError(_ error: DownloadError?) async {
        mockError = error
    }
}
