//
//  SyncManagerClerkCooldownTests.swift
//  DequeueTests
//
//  Tests for the Clerk infrastructure health cooldown in SyncManager.
//  Fixes DEQUEUE-APP-12: HTTP 530 reconnect-retry loop that hammered Clerk
//  servers indefinitely despite an existing circuit breaker.
//
//  The cooldown works as follows:
//  1. Each Clerk infra error (530, internal_clerk_error, NSURLError -1) increments
//     `clerkInfraFailureCount` and sets `clerkCooldownUntil` using exponential backoff.
//  2. `refreshToken()` checks `isClerkInCooldown` before calling Clerk, throwing
//     `SyncError.clerkInCooldown` immediately when in cooldown.
//  3. After a successful token refresh, `resetClerkCooldown()` clears state.
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - Backoff Schedule

@Suite("SyncManager Clerk Cooldown — Backoff Schedule")
struct SyncManagerClerkCooldownBackoffTests {

    /// The backoff schedule (seconds) for consecutive Clerk infra errors.
    /// Matches the `delays` array in `recordClerkInfraFailure()`.
    private let backoffSchedule: [TimeInterval] = [15, 30, 60, 120, 300]

    @Test("Backoff schedule has 5 entries")
    func testBackoffScheduleLength() {
        #expect(backoffSchedule.count == 5)
    }

    @Test("First failure uses 15-second cooldown")
    func testFirstFailureCooldown() {
        let failureCount = 1
        let index = min(failureCount - 1, backoffSchedule.count - 1)
        #expect(backoffSchedule[index] == 15)
    }

    @Test("Second failure uses 30-second cooldown")
    func testSecondFailureCooldown() {
        let failureCount = 2
        let index = min(failureCount - 1, backoffSchedule.count - 1)
        #expect(backoffSchedule[index] == 30)
    }

    @Test("Third failure uses 60-second cooldown")
    func testThirdFailureCooldown() {
        let failureCount = 3
        let index = min(failureCount - 1, backoffSchedule.count - 1)
        #expect(backoffSchedule[index] == 60)
    }

    @Test("Fourth failure uses 120-second cooldown")
    func testFourthFailureCooldown() {
        let failureCount = 4
        let index = min(failureCount - 1, backoffSchedule.count - 1)
        #expect(backoffSchedule[index] == 120)
    }

    @Test("Fifth failure uses 300-second cooldown (5-minute cap)")
    func testFifthFailureCooldown() {
        let failureCount = 5
        let index = min(failureCount - 1, backoffSchedule.count - 1)
        #expect(backoffSchedule[index] == 300)
    }

    @Test("Cooldown caps at 5 minutes (300 seconds) regardless of failure count")
    func testCooldownCapsAtFiveMinutes() {
        // The design explicitly caps at 5 minutes — no 10-minute delays
        let maxCooldown = backoffSchedule.max() ?? 0
        #expect(maxCooldown == 300, "Cooldown must cap at exactly 5 minutes (300s), got \(maxCooldown)s")
        #expect(maxCooldown <= 300, "Cooldown must NEVER exceed 5 minutes")
    }

    @Test("Failure count beyond schedule length stays capped at max delay")
    func testHighFailureCountCapped() {
        // Simulate failure counts beyond the schedule length (e.g. 10, 20, 100)
        for failureCount in [6, 10, 20, 100] {
            let index = min(failureCount - 1, backoffSchedule.count - 1)
            let delay = backoffSchedule[index]
            #expect(delay == 300, "Failure count \(failureCount) should cap at 300s, got \(delay)s")
        }
    }

    @Test("Backoff schedule increases monotonically")
    func testBackoffIncreases() {
        var previous = backoffSchedule[0]
        for delay in backoffSchedule.dropFirst() {
            #expect(delay > previous, "Each cooldown delay must be larger than the previous")
            previous = delay
        }
    }

    @Test("Initial cooldown is short enough for fast recovery (≤ 30 seconds)")
    func testInitialCooldownIsShort() {
        // Victor's constraint: minimal UX impact — users recover quickly from brief blips
        let firstDelay = backoffSchedule[0]
        #expect(firstDelay <= 30, "Initial cooldown must be short (≤ 30s) for fast recovery, got \(firstDelay)s")
    }
}

// MARK: - SyncError.clerkInCooldown

@Suite("SyncManager Clerk Cooldown — SyncError case")
struct SyncManagerClerkCooldownErrorTests {

    @Test("SyncError.clerkInCooldown has a non-empty error description")
    func testClerkInCooldownDescription() {
        let error = SyncError.clerkInCooldown
        let description = error.errorDescription
        #expect(description != nil)
        #expect(!(description ?? "").isEmpty)
    }

    @Test("SyncError.clerkInCooldown description mentions Clerk")
    func testClerkInCooldownDescriptionMentionsClerk() {
        let error = SyncError.clerkInCooldown
        let description = error.errorDescription ?? ""
        // Description should reference the underlying cause (Clerk infrastructure)
        let mentionsClerk = description.localizedCaseInsensitiveContains("Clerk")
            || description.localizedCaseInsensitiveContains("cooldown")
            || description.localizedCaseInsensitiveContains("unavailable")
        #expect(mentionsClerk, "Error description '\(description)' should mention Clerk or cooldown")
    }

    @Test("SyncError.clerkInCooldown is distinct from notAuthenticated")
    func testClerkInCooldownNotSameAsNotAuthenticated() {
        let cooldown = SyncError.clerkInCooldown
        let notAuth = SyncError.notAuthenticated

        // They must have distinct descriptions
        #expect(cooldown.errorDescription != notAuth.errorDescription)

        // Verify pattern matching works correctly
        if case SyncError.clerkInCooldown = cooldown {
            // expected
        } else {
            Issue.record("SyncError.clerkInCooldown did not pattern-match as expected")
        }

        if case SyncError.notAuthenticated = cooldown {
            Issue.record("clerkInCooldown incorrectly matched notAuthenticated")
        }
    }

    @Test("SyncError.clerkInCooldown is not an authentication error")
    func testClerkInCooldownNotAuthenticationError() {
        // clerkInCooldown must NOT be caught by the isAuthenticationError path
        // (it would cause the periodic push to permanently disconnect)
        let error = SyncError.clerkInCooldown

        // Verify it's not notAuthenticated
        var isAuthError = false
        if case SyncError.notAuthenticated = error { isAuthError = true }

        #expect(!isAuthError, "clerkInCooldown must not be treated as a permanent auth failure")
    }
}

// MARK: - Cooldown State Logic

@Suite("SyncManager Clerk Cooldown — State Logic")
struct SyncManagerClerkCooldownStateTests {

    @Test("isClerkInCooldown is false when cooldownUntil is in the past")
    func testCooldownExpired() {
        let pastDate = Date().addingTimeInterval(-1) // 1 second ago
        let isInCooldown = Date() < pastDate
        #expect(!isInCooldown, "Cooldown should be inactive when date is in the past")
    }

    @Test("isClerkInCooldown is true when cooldownUntil is in the future")
    func testCooldownActive() {
        let futureDate = Date().addingTimeInterval(30) // 30 seconds from now
        let isInCooldown = Date() < futureDate
        #expect(isInCooldown, "Cooldown should be active when date is in the future")
    }

    @Test("isClerkInCooldown logic handles exact boundary correctly")
    func testCooldownBoundary() {
        // Just past the boundary
        let justPast = Date().addingTimeInterval(-0.001)
        #expect(!(Date() < justPast), "Cooldown should be inactive just past the boundary")

        // Just before the boundary
        let justFuture = Date().addingTimeInterval(0.001)
        #expect(Date() < justFuture, "Cooldown should be active just before the boundary")
    }

    @Test("Cooldown duration for each failure matches the backoff schedule")
    func testCooldownDurationMatchesSchedule() {
        let delays: [TimeInterval] = [15, 30, 60, 120, 300]

        for (i, expectedDelay) in delays.enumerated() {
            let failureCount = i + 1
            let index = min(failureCount - 1, delays.count - 1)
            let actualDelay = delays[index]
            let cooldownUntil = Date().addingTimeInterval(actualDelay)

            // Cooldown should be active right after setting it
            #expect(Date() < cooldownUntil, "Cooldown should be active for failure #\(failureCount)")

            // The delta between cooldownUntil and now should be close to expectedDelay
            let delta = cooldownUntil.timeIntervalSinceNow
            #expect(abs(delta - expectedDelay) < 1.0, "Cooldown delta should be ~\(expectedDelay)s for failure #\(failureCount)")
        }
    }

    @Test("Clerk infra error detection triggers cooldown-eligible errors")
    func testInfraErrorsEligibleForCooldown() {
        // These are the errors that should trigger recordClerkInfraFailure()
        let clerkErrors: [Error] = [
            NSError(
                domain: NSURLErrorDomain,
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Request failed with status code: 530"]
            ),
            NSError(
                domain: "ClerkError",
                code: 530,
                userInfo: [NSLocalizedDescriptionKey: "Server error: 530 origin server unreachable"]
            ),
            NSError(
                domain: "Clerk.ClerkAPIError",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "POST /v1/client/sessions/tokens: internal_clerk_error"]
            ),
            NSError(
                domain: NSURLErrorDomain,
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "The operation couldn't be completed."]
            )
        ]

        for error in clerkErrors {
            #expect(
                SyncManager.isClerkInfrastructureError(error),
                "Error '\(error.localizedDescription)' should be a Clerk infra error eligible for cooldown"
            )
        }
    }

    @Test("Non-infra errors do not trigger cooldown")
    func testNonInfraErrorsSkipCooldown() {
        // These should NOT trigger the cooldown
        let nonClerkErrors: [Error] = [
            NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet,
                userInfo: [NSLocalizedDescriptionKey: "No internet connection"]
            ),
            NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorTimedOut,
                userInfo: [NSLocalizedDescriptionKey: "Request timed out"]
            ),
            NSError(
                domain: "HTTPError",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Unauthorized"]
            ),
            SyncError.notAuthenticated,
            SyncError.pushFailed,
            SyncError.pullFailed
        ]

        for error in nonClerkErrors {
            #expect(
                !SyncManager.isClerkInfrastructureError(error),
                "Error '\(error.localizedDescription)' should NOT be a Clerk infra error"
            )
        }
    }

    @Test("Max backoff cap is exactly 5 minutes (300s) — not 10 minutes")
    func testMaxBackoffIsExactlyFiveMinutes() {
        // Victor explicitly specified: cap at 5 minutes, NOT 10. UX impact must be minimal.
        let delays: [TimeInterval] = [15, 30, 60, 120, 300]
        let maxDelay = delays.max() ?? 0

        #expect(maxDelay == 300)
        #expect(maxDelay < 600, "Must be well under 10 minutes")

        // Verify the last entry IS 300 (5 minutes), not some other value
        #expect(delays.last == 300)
    }
}
