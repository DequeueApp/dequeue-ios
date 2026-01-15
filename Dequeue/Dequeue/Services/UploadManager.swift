//
//  UploadManager.swift
//  Dequeue
//
//  Manages file uploads to presigned URLs with progress tracking
//

import Foundation
import os.log

// MARK: - Upload Progress

/// Represents the progress of an upload
struct UploadProgress: Sendable {
    let attachmentId: String
    let bytesUploaded: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesUploaded) / Double(totalBytes)
    }
}

// MARK: - Upload Error

enum UploadError: LocalizedError, Equatable {
    case fileNotFound(path: String)
    case uploadCancelled
    case networkError(String)
    case serverError(statusCode: Int)
    case invalidResponse
    case alreadyUploading(attachmentId: String)

    var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            return "File not found at path: \(path)"
        case .uploadCancelled:
            return "Upload was cancelled."
        case let .networkError(message):
            return "Network error: \(message)"
        case let .serverError(statusCode):
            return "Server returned error status \(statusCode)."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case let .alreadyUploading(attachmentId):
            return "Upload already in progress for attachment \(attachmentId)."
        }
    }
}

// MARK: - Upload Manager

/// Actor that manages file uploads with progress tracking and cancellation support.
///
/// Uses URLSession upload tasks for efficient streaming uploads without loading
/// entire files into memory. Progress is reported via an AsyncStream.
actor UploadManager {
    private var activeTasks: [String: URLSessionUploadTask] = [:]
    private var progressContinuations: [String: AsyncStream<UploadProgress>.Continuation] = [:]
    private let session: URLSession
    private let delegateHandler: UploadDelegateHandler

    init() {
        self.delegateHandler = UploadDelegateHandler()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(
            configuration: configuration,
            delegate: delegateHandler,
            delegateQueue: nil
        )
    }

    /// Uploads a file to a presigned URL with progress tracking.
    ///
    /// - Parameters:
    ///   - fileURL: The local file URL to upload
    ///   - presignedURL: The presigned URL to upload to
    ///   - attachmentId: The unique identifier for this attachment
    ///   - mimeType: The MIME type of the file
    /// - Returns: An AsyncStream of UploadProgress updates
    /// - Throws: `UploadError` on failure
    func uploadFile(
        _ fileURL: URL,
        to presignedURL: URL,
        attachmentId: String,
        mimeType: String
    ) async throws -> AsyncStream<UploadProgress> {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UploadError.fileNotFound(path: fileURL.path)
        }

        // Check for existing upload
        if activeTasks[attachmentId] != nil {
            throw UploadError.alreadyUploading(attachmentId: attachmentId)
        }

        // Get file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let totalBytes = fileAttributes[.size] as? Int64 ?? 0

        // Create the stream and continuation
        let (stream, continuation) = AsyncStream<UploadProgress>.makeStream()
        progressContinuations[attachmentId] = continuation

        // Create request
        var request = URLRequest(url: presignedURL)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(totalBytes)", forHTTPHeaderField: "Content-Length")

        // Create upload task
        let task = session.uploadTask(with: request, fromFile: fileURL)

        // Set up progress tracking
        delegateHandler.registerTask(
            task,
            attachmentId: attachmentId,
            totalBytes: totalBytes,
            onProgress: { [weak self] progress in
                Task { await self?.handleProgress(progress) }
            },
            onCompletion: { [weak self] result in
                Task { await self?.handleCompletion(attachmentId: attachmentId, result: result) }
            }
        )

        activeTasks[attachmentId] = task
        task.resume()

        os_log("[UploadManager] Started upload for \(attachmentId), size: \(totalBytes) bytes")

        return stream
    }

    /// Cancels an in-progress upload.
    ///
    /// - Parameter attachmentId: The identifier of the upload to cancel
    func cancelUpload(attachmentId: String) {
        guard let task = activeTasks[attachmentId] else {
            os_log("[UploadManager] No active upload found for \(attachmentId)")
            return
        }

        task.cancel()
        cleanup(attachmentId: attachmentId)
        os_log("[UploadManager] Cancelled upload for \(attachmentId)")
    }

    /// Returns true if an upload is currently in progress for the given attachment.
    func isUploading(attachmentId: String) -> Bool {
        activeTasks[attachmentId] != nil
    }

    // MARK: - Private

    private func handleProgress(_ progress: UploadProgress) {
        progressContinuations[progress.attachmentId]?.yield(progress)
    }

    private func handleCompletion(attachmentId: String, result: Result<Void, Error>) {
        switch result {
        case .success:
            os_log("[UploadManager] Upload completed for \(attachmentId)")
        case let .failure(error):
            os_log("[UploadManager] Upload failed for \(attachmentId): \(error.localizedDescription)")
        }

        cleanup(attachmentId: attachmentId)
    }

    private func cleanup(attachmentId: String) {
        activeTasks.removeValue(forKey: attachmentId)
        progressContinuations[attachmentId]?.finish()
        progressContinuations.removeValue(forKey: attachmentId)
        delegateHandler.unregisterTask(attachmentId: attachmentId)
    }
}

// MARK: - URLSession Delegate Handler

/// Handles URLSession delegate callbacks for upload progress tracking.
///
/// This class bridges the delegate-based URLSession API to the async/await world.
/// It tracks progress for multiple concurrent uploads and routes callbacks to
/// the appropriate handlers.
final class UploadDelegateHandler: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private struct TaskInfo: Sendable {
        let attachmentId: String
        let totalBytes: Int64
        let onProgress: @Sendable (UploadProgress) -> Void
        let onCompletion: @Sendable (Result<Void, Error>) -> Void
    }

    // Protected by taskInfoLock - @unchecked Sendable on class handles thread safety
    private let taskInfoLock = NSLock()
    private var taskInfo: [Int: TaskInfo] = [:]

    func registerTask(
        _ task: URLSessionTask,
        attachmentId: String,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (UploadProgress) -> Void,
        onCompletion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        taskInfoLock.lock()
        defer { taskInfoLock.unlock() }
        taskInfo[task.taskIdentifier] = TaskInfo(
            attachmentId: attachmentId,
            totalBytes: totalBytes,
            onProgress: onProgress,
            onCompletion: onCompletion
        )
    }

    func unregisterTask(attachmentId: String) {
        taskInfoLock.lock()
        defer { taskInfoLock.unlock() }
        taskInfo = taskInfo.filter { $0.value.attachmentId != attachmentId }
    }

    // MARK: - URLSessionTaskDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        taskInfoLock.lock()
        let info = taskInfo[task.taskIdentifier]
        taskInfoLock.unlock()

        guard let info else { return }

        let progress = UploadProgress(
            attachmentId: info.attachmentId,
            bytesUploaded: totalBytesSent,
            totalBytes: info.totalBytes
        )
        info.onProgress(progress)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        taskInfoLock.lock()
        let info = taskInfo.removeValue(forKey: task.taskIdentifier)
        taskInfoLock.unlock()

        guard let info else { return }

        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                info.onCompletion(.failure(UploadError.uploadCancelled))
            } else {
                info.onCompletion(.failure(UploadError.networkError(error.localizedDescription)))
            }
            return
        }

        // Check HTTP response
        if let httpResponse = task.response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                info.onCompletion(.failure(UploadError.serverError(statusCode: httpResponse.statusCode)))
                return
            }
        }

        info.onCompletion(.success(()))
    }
}

// MARK: - Mock Upload Manager

/// Mock implementation for testing
actor MockUploadManager {
    var uploadCallCount = 0
    var cancelCallCount = 0
    var lastUploadedFileURL: URL?
    var lastPresignedURL: URL?
    var mockError: UploadError?
    var simulateProgress: Bool = true

    func uploadFile(
        _ fileURL: URL,
        to presignedURL: URL,
        attachmentId: String,
        mimeType: String
    ) async throws -> AsyncStream<UploadProgress> {
        uploadCallCount += 1
        lastUploadedFileURL = fileURL
        lastPresignedURL = presignedURL

        if let error = mockError {
            throw error
        }

        let (stream, continuation) = AsyncStream<UploadProgress>.makeStream()

        if simulateProgress {
            // Simulate progress updates
            Task {
                let totalBytes: Int64 = 1_000
                for i in stride(from: 0, through: 100, by: 25) {
                    continuation.yield(UploadProgress(
                        attachmentId: attachmentId,
                        bytesUploaded: Int64(i) * 10,
                        totalBytes: totalBytes
                    ))
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
                continuation.finish()
            }
        } else {
            continuation.finish()
        }

        return stream
    }

    func cancelUpload(attachmentId: String) {
        cancelCallCount += 1
    }

    func isUploading(attachmentId: String) -> Bool {
        false
    }
}
