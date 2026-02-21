//
//  DownloadManager.swift
//  Dequeue
//
//  Manages file downloads from remote URLs with progress tracking
//

import Foundation
import os.log

// MARK: - Download Progress

/// Represents the progress of a download
struct DownloadProgress: Sendable {
    let attachmentId: String
    let bytesDownloaded: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }
}

// MARK: - Download Error

enum DownloadError: LocalizedError, Equatable {
    case downloadCancelled
    case networkError(String)
    case serverError(statusCode: Int)
    case invalidResponse
    case fileSystemError(String)
    case alreadyDownloading(attachmentId: String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .downloadCancelled:
            return "Download was cancelled."
        case let .networkError(message):
            return "Network error: \(message)"
        case let .serverError(statusCode):
            return "Server returned error status \(statusCode)."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case let .fileSystemError(message):
            return "File system error: \(message)"
        case let .alreadyDownloading(attachmentId):
            return "Download already in progress for attachment \(attachmentId)."
        case .invalidURL:
            return "The download URL is invalid."
        }
    }
}

// MARK: - Download Manager

/// Actor that manages file downloads with progress tracking and cancellation support.
///
/// Uses URLSession download tasks for efficient streaming downloads that write
/// directly to disk. Progress is reported via an AsyncStream.
actor DownloadManager {
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var progressContinuations: [String: AsyncStream<DownloadProgress>.Continuation] = [:]
    private var completionContinuations: [String: CheckedContinuation<URL, Error>] = [:]
    private let session: URLSession
    private let delegateHandler: DownloadDelegateHandler

    /// Directory for storing downloaded attachments
    private let attachmentsDirectory: URL

    init() {
        self.delegateHandler = DownloadDelegateHandler()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        self.session = URLSession(
            configuration: configuration,
            delegate: delegateHandler,
            delegateQueue: nil
        )

        // Set up attachments directory
        // swiftlint:disable:next force_unwrapping
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.attachmentsDirectory = documentsDirectory.appendingPathComponent("Attachments")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: attachmentsDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Downloads a file from a URL with progress tracking.
    ///
    /// - Parameters:
    ///   - remoteURL: The URL to download from
    ///   - attachmentId: The unique identifier for this attachment
    ///   - filename: The filename to save as
    /// - Returns: A tuple containing an AsyncStream of progress updates and the final local URL
    /// - Throws: `DownloadError` on failure
    func downloadFile(
        from remoteURL: URL,
        attachmentId: String,
        filename: String
    ) async throws -> (progressStream: AsyncStream<DownloadProgress>, localURL: URL) {
        // Check for existing download
        if activeTasks[attachmentId] != nil {
            throw DownloadError.alreadyDownloading(attachmentId: attachmentId)
        }

        // Create the progress stream
        let (stream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()
        progressContinuations[attachmentId] = progressContinuation

        // Determine local file path
        let localURL = attachmentsDirectory
            .appendingPathComponent(attachmentId)
            .appendingPathComponent(filename)

        // Create parent directory
        let parentDir = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Create request
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"

        // Create download task
        let task = session.downloadTask(with: request)

        // Set up progress tracking and completion handling
        delegateHandler.registerTask(
            task,
            attachmentId: attachmentId,
            destinationURL: localURL,
            onProgress: { [weak self] progress in
                Task { await self?.handleProgress(progress) }
            },
            onCompletion: { [weak self] result in
                Task { await self?.handleCompletion(attachmentId: attachmentId, result: result) }
            }
        )

        activeTasks[attachmentId] = task
        task.resume()

        os_log("[DownloadManager] Started download for \(attachmentId)")

        return (stream, localURL)
    }

    /// Waits for a download to complete.
    ///
    /// - Parameter attachmentId: The identifier of the download
    /// - Returns: The local URL where the file was saved
    /// - Throws: `DownloadError` on failure
    func waitForCompletion(attachmentId: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            completionContinuations[attachmentId] = continuation
        }
    }

    /// Cancels an in-progress download.
    ///
    /// - Parameter attachmentId: The identifier of the download to cancel
    func cancelDownload(attachmentId: String) {
        guard let task = activeTasks[attachmentId] else {
            os_log("[DownloadManager] No active download found for \(attachmentId)")
            return
        }

        task.cancel()
        cleanup(attachmentId: attachmentId, result: .failure(DownloadError.downloadCancelled))
        os_log("[DownloadManager] Cancelled download for \(attachmentId)")
    }

    /// Returns true if a download is currently in progress for the given attachment.
    func isDownloading(attachmentId: String) -> Bool {
        activeTasks[attachmentId] != nil
    }

    /// Checks if a file has been downloaded and exists locally.
    func isDownloaded(attachmentId: String, filename: String) -> Bool {
        let localURL = attachmentsDirectory
            .appendingPathComponent(attachmentId)
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: localURL.path)
    }

    /// Returns the local URL for a downloaded attachment, if it exists.
    func localURL(for attachmentId: String, filename: String) -> URL? {
        let url = attachmentsDirectory
            .appendingPathComponent(attachmentId)
            .appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Deletes a downloaded file.
    func deleteDownload(attachmentId: String) throws {
        let attachmentDir = attachmentsDirectory.appendingPathComponent(attachmentId)
        if FileManager.default.fileExists(atPath: attachmentDir.path) {
            try FileManager.default.removeItem(at: attachmentDir)
            os_log("[DownloadManager] Deleted download for \(attachmentId)")
        }
    }

    // MARK: - Private

    private func handleProgress(_ progress: DownloadProgress) {
        progressContinuations[progress.attachmentId]?.yield(progress)
    }

    private func handleCompletion(attachmentId: String, result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            os_log("[DownloadManager] Download completed for \(attachmentId) at \(url.path)")
            completionContinuations[attachmentId]?.resume(returning: url)
        case let .failure(error):
            os_log("[DownloadManager] Download failed for \(attachmentId): \(error.localizedDescription)")
            completionContinuations[attachmentId]?.resume(throwing: error)
        }

        cleanup(attachmentId: attachmentId, result: result)
    }

    private func cleanup(attachmentId: String, result: Result<URL, Error>) {
        activeTasks.removeValue(forKey: attachmentId)
        progressContinuations[attachmentId]?.finish()
        progressContinuations.removeValue(forKey: attachmentId)
        completionContinuations.removeValue(forKey: attachmentId)
        delegateHandler.unregisterTask(attachmentId: attachmentId)
    }
}

// MARK: - URLSession Delegate Handler

/// Handles URLSession delegate callbacks for download progress tracking.
final class DownloadDelegateHandler: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct TaskInfo: Sendable {
        let attachmentId: String
        let destinationURL: URL
        let onProgress: @Sendable (DownloadProgress) -> Void
        let onCompletion: @Sendable (Result<URL, Error>) -> Void
    }

    // Protected by taskInfoLock - @unchecked Sendable on class handles thread safety
    private let taskInfoLock = NSLock()
    private var taskInfo: [Int: TaskInfo] = [:]

    func registerTask(
        _ task: URLSessionTask,
        attachmentId: String,
        destinationURL: URL,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void,
        onCompletion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        taskInfoLock.lock()
        defer { taskInfoLock.unlock() }
        taskInfo[task.taskIdentifier] = TaskInfo(
            attachmentId: attachmentId,
            destinationURL: destinationURL,
            onProgress: onProgress,
            onCompletion: onCompletion
        )
    }

    func unregisterTask(attachmentId: String) {
        taskInfoLock.lock()
        defer { taskInfoLock.unlock() }
        taskInfo = taskInfo.filter { $0.value.attachmentId != attachmentId }
    }

    // MARK: - URLSessionDelegate (Certificate Pinning)

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Delegate pinning to the shared validator; fall through if not a pinned domain
        if !CertificatePinningValidator.handle(challenge: challenge, completionHandler: completionHandler) {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        taskInfoLock.lock()
        let info = taskInfo[downloadTask.taskIdentifier]
        taskInfoLock.unlock()

        guard let info else { return }

        let progress = DownloadProgress(
            attachmentId: info.attachmentId,
            bytesDownloaded: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : totalBytesWritten
        )
        info.onProgress(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        taskInfoLock.lock()
        let info = taskInfo[downloadTask.taskIdentifier]
        taskInfoLock.unlock()

        guard let info else { return }

        // Move file to final destination
        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: info.destinationURL.path) {
                try FileManager.default.removeItem(at: info.destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: info.destinationURL)
            info.onCompletion(.success(info.destinationURL))
        } catch {
            info.onCompletion(.failure(DownloadError.fileSystemError(error.localizedDescription)))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // Only handle errors here - success is handled in didFinishDownloadingTo
        guard let error else { return }

        taskInfoLock.lock()
        let info = taskInfo.removeValue(forKey: task.taskIdentifier)
        taskInfoLock.unlock()

        guard let info else { return }

        if (error as NSError).code == NSURLErrorCancelled {
            info.onCompletion(.failure(DownloadError.downloadCancelled))
        } else {
            info.onCompletion(.failure(DownloadError.networkError(error.localizedDescription)))
        }
    }
}

// MARK: - Mock Download Manager

/// Mock implementation for testing
actor MockDownloadManager {
    var downloadCallCount = 0
    var cancelCallCount = 0
    var lastDownloadedURL: URL?
    var mockError: DownloadError?
    var simulateProgress: Bool = true

    func downloadFile(
        from remoteURL: URL,
        attachmentId: String,
        filename: String
    ) async throws -> (progressStream: AsyncStream<DownloadProgress>, localURL: URL) {
        downloadCallCount += 1
        lastDownloadedURL = remoteURL

        if let error = mockError {
            throw error
        }

        let (stream, continuation) = AsyncStream<DownloadProgress>.makeStream()
        let localURL = URL(fileURLWithPath: "/tmp/mock-downloads/\(attachmentId)/\(filename)")

        if simulateProgress {
            // Simulate progress updates
            Task {
                let totalBytes: Int64 = 1_000
                for i in stride(from: 0, through: 100, by: 25) {
                    continuation.yield(DownloadProgress(
                        attachmentId: attachmentId,
                        bytesDownloaded: Int64(i) * 10,
                        totalBytes: totalBytes
                    ))
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
                continuation.finish()
            }
        } else {
            continuation.finish()
        }

        return (stream, localURL)
    }

    func cancelDownload(attachmentId: String) {
        cancelCallCount += 1
    }

    func isDownloading(attachmentId: String) -> Bool {
        false
    }

    func isDownloaded(attachmentId: String, filename: String) -> Bool {
        false
    }
}
