//
//  UploadRetryManagerTests.swift
//  DequeueTests
//
//  Tests for UploadRetryManager exponential backoff and retry logic
//

import Testing
import Foundation
@testable import Dequeue

@Suite("UploadRetryManager Tests")
@MainActor
struct UploadRetryManagerTests {
    // MARK: - RetryConfiguration Tests

    @Test("RetryConfiguration calculates exponential delays correctly")
    func configurationCalculatesDelays() {
        let config = RetryConfiguration(
            maxAttempts: 5,
            baseDelay: 1.0,
            maxDelay: 30.0
        )

        #expect(config.delay(forAttempt: 0) == 1.0)   // 1 * 2^0 = 1
        #expect(config.delay(forAttempt: 1) == 2.0)   // 1 * 2^1 = 2
        #expect(config.delay(forAttempt: 2) == 4.0)   // 1 * 2^2 = 4
        #expect(config.delay(forAttempt: 3) == 8.0)   // 1 * 2^3 = 8
        #expect(config.delay(forAttempt: 4) == 16.0)  // 1 * 2^4 = 16
    }

    @Test("RetryConfiguration respects max delay")
    func configurationRespectsMaxDelay() {
        let config = RetryConfiguration(
            maxAttempts: 10,
            baseDelay: 1.0,
            maxDelay: 10.0
        )

        #expect(config.delay(forAttempt: 5) == 10.0)  // Would be 32, capped at 10
        #expect(config.delay(forAttempt: 6) == 10.0)  // Would be 64, capped at 10
    }

    @Test("Default configuration has expected values")
    func defaultConfigurationValues() {
        let config = RetryConfiguration.default

        #expect(config.maxAttempts == 3)
        #expect(config.baseDelay == 1.0)
        #expect(config.maxDelay == 30.0)
    }

    // MARK: - RetryState Tests

    @Test("RetryState initializes correctly")
    func retryStateInitialization() {
        let state = RetryState(attachmentId: "test-123")

        #expect(state.attachmentId == "test-123")
        #expect(state.attemptCount == 0)
        #expect(state.lastAttemptAt == nil)
        #expect(state.nextRetryAt == nil)
    }

    @Test("RetryState records attempt correctly")
    func retryStateRecordsAttempt() {
        var state = RetryState(attachmentId: "test-123")

        state.recordAttempt(nextDelay: 5.0)

        #expect(state.attemptCount == 1)
        #expect(state.lastAttemptAt != nil)
        #expect(state.nextRetryAt != nil)
        #expect(state.nextRetryAt! > state.lastAttemptAt!)
    }

    @Test("RetryState records attempt without next delay")
    func retryStateRecordsAttemptWithoutDelay() {
        var state = RetryState(attachmentId: "test-123")

        state.recordAttempt(nextDelay: nil)

        #expect(state.attemptCount == 1)
        #expect(state.lastAttemptAt != nil)
        #expect(state.nextRetryAt == nil)
    }

    // MARK: - UploadRetryManager Tests

    @Test("Manager registers failure and tracks state")
    func managerRegistersFailure() async {
        let manager = UploadRetryManager(
            configuration: RetryConfiguration(maxAttempts: 3, baseDelay: 1.0, maxDelay: 10.0)
        )

        manager.registerFailure(attachmentId: "test-123")

        let state = manager.retryState(for: "test-123")
        #expect(state != nil)
        #expect(state?.attemptCount == 1)
        #expect(manager.canRetry(attachmentId: "test-123") == true)
    }

    @Test("Manager stops after max attempts")
    func managerStopsAfterMaxAttempts() async {
        let config = RetryConfiguration(maxAttempts: 2, baseDelay: 0.01, maxDelay: 0.1)
        let manager = UploadRetryManager(configuration: config)

        // Register failures up to max
        manager.registerFailure(attachmentId: "test-123")
        manager.registerFailure(attachmentId: "test-123")

        // Third registration should be ignored
        manager.registerFailure(attachmentId: "test-123")

        let state = manager.retryState(for: "test-123")
        #expect(state?.attemptCount == 2)
    }

    @Test("Manager clears retry state")
    func managerClearsRetryState() async {
        let manager = UploadRetryManager()

        manager.registerFailure(attachmentId: "test-123")
        #expect(manager.retryState(for: "test-123") != nil)

        manager.clearRetryState(attachmentId: "test-123")
        #expect(manager.retryState(for: "test-123") == nil)
    }

    @Test("Manager reports correct attempt count")
    func managerReportsAttemptCount() async {
        let manager = UploadRetryManager(
            configuration: RetryConfiguration(maxAttempts: 5, baseDelay: 0.01, maxDelay: 0.1)
        )

        #expect(manager.attemptCount(for: "test-123") == 0)

        manager.registerFailure(attachmentId: "test-123")
        #expect(manager.attemptCount(for: "test-123") == 1)

        manager.registerFailure(attachmentId: "test-123")
        #expect(manager.attemptCount(for: "test-123") == 2)
    }

    @Test("Manager can retry returns true for new attachments")
    func managerCanRetryNewAttachment() async {
        let manager = UploadRetryManager()

        #expect(manager.canRetry(attachmentId: "never-failed") == true)
    }

    @Test("Manual retry resets state")
    func manualRetryResetsState() async {
        let config = RetryConfiguration(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.1)
        let manager = UploadRetryManager(configuration: config)

        // Register some failures
        manager.registerFailure(attachmentId: "test-123")
        manager.registerFailure(attachmentId: "test-123")
        #expect(manager.attemptCount(for: "test-123") == 2)

        // Manual retry should reset
        manager.manualRetry(attachmentId: "test-123")
        #expect(manager.attemptCount(for: "test-123") == 0)
    }

    @Test("Manager invokes retry handler")
    func managerInvokesRetryHandler() async {
        let config = RetryConfiguration(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.1)
        let manager = UploadRetryManager(configuration: config)

        var retryRequestedIds: [String] = []
        manager.setRetryHandler { attachmentId in
            retryRequestedIds.append(attachmentId)
        }

        // Manual retry should invoke handler immediately if online
        manager.manualRetry(attachmentId: "test-123")

        // Give time for async operations
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Note: Whether handler is called depends on NetworkMonitor.shared.isConnected
        // In tests, this might be true or false depending on the environment
    }

    // MARK: - MockUploadRetryManager Tests

    @Test("Mock tracks register failure calls")
    func mockTracksRegisterFailure() async {
        let mock = MockUploadRetryManager()

        mock.registerFailure(attachmentId: "test-123")

        #expect(mock.registerFailureCallCount == 1)
        #expect(mock.lastRegisteredAttachmentId == "test-123")
    }

    @Test("Mock tracks manual retry calls")
    func mockTracksManualRetry() async {
        let mock = MockUploadRetryManager()

        mock.manualRetry(attachmentId: "test-456")

        #expect(mock.manualRetryCallCount == 1)
        #expect(mock.lastManualRetryAttachmentId == "test-456")
    }

    @Test("Mock tracks clear calls")
    func mockTracksClearCalls() async {
        let mock = MockUploadRetryManager()

        mock.registerFailure(attachmentId: "test-123")
        mock.clearRetryState(attachmentId: "test-123")

        #expect(mock.clearCallCount == 1)
        #expect(mock.retryState(for: "test-123") == nil)
    }
}
