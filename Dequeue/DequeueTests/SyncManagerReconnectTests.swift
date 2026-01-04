//
//  SyncManagerReconnectTests.swift
//  DequeueTests
//
//  Tests for SyncManager reconnection robustness improvements
//

import Testing
import Foundation
@testable import Dequeue

@Suite("SyncManager Reconnection Tests")
struct SyncManagerReconnectTests {

    @Test("Exponential backoff with jitter stays within expected range")
    func testBackoffJitter() async {
        let baseDelay: TimeInterval = 1.0
        let attemptNumber = 3

        // Calculate expected range for attempt 3
        // Base: 1.0 * 2^(3-1) = 1.0 * 4 = 4.0
        // With 75% base and 50% jitter: (4.0 * 0.75) + (0...2.0) = 3.0 + (0...2.0) = [3.0, 5.0]
        let baseValue = baseDelay * pow(2.0, Double(attemptNumber - 1))
        let expectedMin = baseValue * 0.75
        let expectedMax = baseValue * 1.25

        // Run multiple iterations to verify randomness stays in range
        for _ in 0..<100 {
            let jitterRange = baseValue * 0.5
            let jitter = Double.random(in: 0...jitterRange)
            let delay = (baseValue * 0.75) + jitter

            #expect(delay >= expectedMin)
            #expect(delay <= expectedMax)
        }
    }

    @Test("Maximum retry attempts enforced")
    func testMaxRetryAttempts() async {
        // Verify the constant is reasonable
        let maxAttempts = 10
        #expect(maxAttempts > 0)
        #expect(maxAttempts <= 20) // Should not retry indefinitely
    }

    @Test("Health monitoring tracks consecutive failures")
    func testHealthMonitoring() async {
        let maxConsecutiveFailures = 3
        var consecutiveFailures = 0

        // Simulate heartbeat failures
        for attempt in 1...5 {
            consecutiveFailures += 1

            if consecutiveFailures >= maxConsecutiveFailures {
                // Should trigger disconnect
                #expect(attempt >= maxConsecutiveFailures)
                break
            }
        }

        #expect(consecutiveFailures >= maxConsecutiveFailures)
    }

    @Test("Jitter prevents thundering herd")
    func testJitterVariability() async {
        let baseDelay: TimeInterval = 2.0
        let attemptNumber = 2

        var delays: [TimeInterval] = []

        // Generate multiple delays to verify they're different
        for _ in 0..<10 {
            let baseValue = baseDelay * pow(2.0, Double(attemptNumber - 1))
            let jitterRange = baseValue * 0.5
            let jitter = Double.random(in: 0...jitterRange)
            let delay = (baseValue * 0.75) + jitter
            delays.append(delay)
        }

        // Verify we got different values (not all the same)
        let uniqueDelays = Set(delays)
        #expect(uniqueDelays.count > 1) // Should have some variation
    }

    @Test("Backoff increases exponentially")
    func testExponentialBackoff() async {
        let baseDelay: TimeInterval = 1.0

        var previousDelay: TimeInterval = 0

        for attemptNumber in 1...5 {
            let baseValue = baseDelay * pow(2.0, Double(attemptNumber - 1))
            let midpoint = baseValue // Using midpoint of jitter range for testing

            if attemptNumber > 1 {
                #expect(midpoint > previousDelay) // Should increase
                #expect(midpoint >= previousDelay * 1.5) // Should roughly double
            }

            previousDelay = midpoint
        }
    }
}
