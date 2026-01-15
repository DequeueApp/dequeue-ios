//
//  UploadRetryManager.swift
//  Dequeue
//
//  Manages automatic retry of failed uploads with exponential backoff
//

import Foundation
import SwiftData
import os.log

// MARK: - Retry Configuration

/// Configuration for upload retry behavior
struct RetryConfiguration: Sendable {
    /// Maximum number of retry attempts
    let maxAttempts: Int

    /// Base delay in seconds (doubled for each retry)
    let baseDelay: TimeInterval

    /// Maximum delay between retries
    let maxDelay: TimeInterval

    /// Default configuration with exponential backoff: 1s, 2s, 4s, 8s (max 30s)
    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 30.0
    )

    /// Calculate delay for a given attempt number (0-indexed)
    func delay(forAttempt attempt: Int) -> TimeInterval {
        let delay = baseDelay * pow(2.0, Double(attempt))
        return min(delay, maxDelay)
    }
}

// MARK: - Retry State

/// Tracks retry state for a single attachment
struct RetryState: Codable, Sendable {
    let attachmentId: String
    var attemptCount: Int
    var lastAttemptAt: Date?
    var nextRetryAt: Date?

    init(attachmentId: String) {
        self.attachmentId = attachmentId
        self.attemptCount = 0
        self.lastAttemptAt = nil
        self.nextRetryAt = nil
    }

    mutating func recordAttempt(nextDelay: TimeInterval?) {
        attemptCount += 1
        lastAttemptAt = Date()
        if let nextDelay {
            nextRetryAt = Date().addingTimeInterval(nextDelay)
        } else {
            nextRetryAt = nil
        }
    }
}

// MARK: - Upload Retry Manager

/// Manages automatic retry of failed uploads with exponential backoff.
///
/// This actor:
/// - Monitors attachments with uploadState == .failed
/// - Schedules retries with exponential backoff
/// - Triggers retries when network becomes available
/// - Allows manual retry triggers
@MainActor
final class UploadRetryManager {
    private let configuration: RetryConfiguration
    private var retryStates: [String: RetryState] = [:]
    private var retryTasks: [String: Task<Void, Never>] = [:]
    private var networkObservation: Task<Void, Never>?
    private var onRetryRequested: ((String) -> Void)?

    init(configuration: RetryConfiguration = .default) {
        self.configuration = configuration
    }

    deinit {
        networkObservation?.cancel()
        for task in retryTasks.values {
            task.cancel()
        }
    }

    /// Sets the callback to be invoked when a retry should be attempted.
    ///
    /// The callback receives the attachment ID to retry.
    func setRetryHandler(_ handler: @escaping (String) -> Void) {
        onRetryRequested = handler
    }

    /// Starts observing network connectivity for retry triggers.
    func startObservingNetwork() {
        networkObservation?.cancel()
        networkObservation = Task { [weak self] in
            var wasConnected = NetworkMonitor.shared.isConnected

            // Poll for network changes (workaround for @Observable observation in actor)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                let isConnected = NetworkMonitor.shared.isConnected
                if isConnected && !wasConnected {
                    // Network became available - trigger pending retries
                    await self?.triggerPendingRetries()
                }
                wasConnected = isConnected
            }
        }

        os_log("[UploadRetryManager] Started observing network")
    }

    /// Stops observing network connectivity.
    func stopObservingNetwork() {
        networkObservation?.cancel()
        networkObservation = nil
        os_log("[UploadRetryManager] Stopped observing network")
    }

    /// Registers a failed upload for retry.
    ///
    /// - Parameter attachmentId: The attachment that failed to upload
    func registerFailure(attachmentId: String) {
        var state = retryStates[attachmentId] ?? RetryState(attachmentId: attachmentId)

        guard state.attemptCount < configuration.maxAttempts else {
            os_log("[UploadRetryManager] Max attempts reached for \(attachmentId)")
            return
        }

        let delay = configuration.delay(forAttempt: state.attemptCount)
        state.recordAttempt(nextDelay: delay)
        retryStates[attachmentId] = state

        scheduleRetry(attachmentId: attachmentId, delay: delay)

        // swiftlint:disable:next line_length
        os_log("[UploadRetryManager] Scheduled retry \(state.attemptCount)/\(configuration.maxAttempts) for \(attachmentId) in \(delay)s")
    }

    /// Manually triggers a retry for an attachment.
    ///
    /// Resets the retry state and triggers immediately if network is available.
    /// - Parameter attachmentId: The attachment to retry
    func manualRetry(attachmentId: String) {
        // Cancel any pending scheduled retry
        retryTasks[attachmentId]?.cancel()
        retryTasks.removeValue(forKey: attachmentId)

        // Reset state for fresh retry
        retryStates[attachmentId] = RetryState(attachmentId: attachmentId)

        if NetworkMonitor.shared.isConnected {
            triggerRetry(attachmentId: attachmentId)
        } else {
            // Register for retry when network becomes available
            registerFailure(attachmentId: attachmentId)
        }

        os_log("[UploadRetryManager] Manual retry triggered for \(attachmentId)")
    }

    /// Clears retry state for an attachment (e.g., after successful upload).
    ///
    /// - Parameter attachmentId: The attachment to clear
    func clearRetryState(attachmentId: String) {
        retryTasks[attachmentId]?.cancel()
        retryTasks.removeValue(forKey: attachmentId)
        retryStates.removeValue(forKey: attachmentId)
        os_log("[UploadRetryManager] Cleared retry state for \(attachmentId)")
    }

    /// Returns the current retry state for an attachment.
    func retryState(for attachmentId: String) -> RetryState? {
        retryStates[attachmentId]
    }

    /// Returns true if the attachment has pending retries remaining.
    func canRetry(attachmentId: String) -> Bool {
        guard let state = retryStates[attachmentId] else {
            return true // Never failed, can retry
        }
        return state.attemptCount < configuration.maxAttempts
    }

    /// Returns the number of attempts made for an attachment.
    func attemptCount(for attachmentId: String) -> Int {
        retryStates[attachmentId]?.attemptCount ?? 0
    }

    // MARK: - Private

    private func scheduleRetry(attachmentId: String, delay: TimeInterval) {
        retryTasks[attachmentId]?.cancel()

        retryTasks[attachmentId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            // Only retry if network is available
            if NetworkMonitor.shared.isConnected {
                await self?.triggerRetry(attachmentId: attachmentId)
            } else {
                os_log("[UploadRetryManager] Skipping retry for \(attachmentId) - no network")
            }
        }
    }

    private func triggerRetry(attachmentId: String) {
        os_log("[UploadRetryManager] Triggering retry for \(attachmentId)")
        onRetryRequested?(attachmentId)
    }

    private func triggerPendingRetries() {
        os_log("[UploadRetryManager] Network available - triggering pending retries")

        for (attachmentId, state) in retryStates {
            // Only retry if we haven't exceeded max attempts and there's a pending retry
            if state.attemptCount < configuration.maxAttempts,
               state.nextRetryAt != nil {
                triggerRetry(attachmentId: attachmentId)
            }
        }
    }
}

// MARK: - Mock Implementation

/// Mock implementation for testing
@MainActor
final class MockUploadRetryManager {
    var registerFailureCallCount = 0
    var manualRetryCallCount = 0
    var clearCallCount = 0
    var lastRegisteredAttachmentId: String?
    var lastManualRetryAttachmentId: String?

    private var mockRetryStates: [String: RetryState] = [:]

    func registerFailure(attachmentId: String) {
        registerFailureCallCount += 1
        lastRegisteredAttachmentId = attachmentId
        mockRetryStates[attachmentId] = RetryState(attachmentId: attachmentId)
    }

    func manualRetry(attachmentId: String) {
        manualRetryCallCount += 1
        lastManualRetryAttachmentId = attachmentId
    }

    func clearRetryState(attachmentId: String) {
        clearCallCount += 1
        mockRetryStates.removeValue(forKey: attachmentId)
    }

    func retryState(for attachmentId: String) -> RetryState? {
        mockRetryStates[attachmentId]
    }

    func canRetry(attachmentId: String) -> Bool {
        true
    }

    func attemptCount(for attachmentId: String) -> Int {
        0
    }
}
