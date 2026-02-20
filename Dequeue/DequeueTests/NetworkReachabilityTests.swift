//
//  NetworkReachabilityTests.swift
//  DequeueTests
//
//  Tests for NetworkReachability.SyncFailureReason — failure classification properties
//

import Testing
import Foundation
@testable import Dequeue

@Suite("SyncFailureReason Properties", .serialized)
@MainActor
struct SyncFailureReasonTests {

    // MARK: - isServerProblem Tests

    @Test("offline is not a server problem")
    func offlineIsNotServerProblem() {
        let reason = NetworkReachability.SyncFailureReason.offline
        #expect(reason.isServerProblem == false)
    }

    @Test("serverUnreachable is a server problem")
    func serverUnreachableIsServerProblem() {
        let reason = NetworkReachability.SyncFailureReason.serverUnreachable
        #expect(reason.isServerProblem == true)
    }

    @Test("serverTimeout is a server problem")
    func serverTimeoutIsServerProblem() {
        let reason = NetworkReachability.SyncFailureReason.serverTimeout
        #expect(reason.isServerProblem == true)
    }

    @Test("connectionLost is a server problem")
    func connectionLostIsServerProblem() {
        let reason = NetworkReachability.SyncFailureReason.connectionLost
        #expect(reason.isServerProblem == true)
    }

    @Test("serverError is a server problem")
    func serverErrorIsServerProblem() {
        let reason = NetworkReachability.SyncFailureReason.serverError("500 Internal Server Error")
        #expect(reason.isServerProblem == true)
    }

    // MARK: - description Tests

    @Test("offline description is non-empty")
    func offlineDescription() {
        let reason = NetworkReachability.SyncFailureReason.offline
        #expect(!reason.description.isEmpty)
        #expect(reason.description.contains("offline"))
    }

    @Test("serverUnreachable description is non-empty")
    func serverUnreachableDescription() {
        let reason = NetworkReachability.SyncFailureReason.serverUnreachable
        #expect(!reason.description.isEmpty)
        #expect(reason.description.lowercased().contains("unreachable"))
    }

    @Test("serverTimeout description is non-empty")
    func serverTimeoutDescription() {
        let reason = NetworkReachability.SyncFailureReason.serverTimeout
        #expect(!reason.description.isEmpty)
        #expect(reason.description.lowercased().contains("timeout"))
    }

    @Test("connectionLost description is non-empty")
    func connectionLostDescription() {
        let reason = NetworkReachability.SyncFailureReason.connectionLost
        #expect(!reason.description.isEmpty)
        #expect(reason.description.lowercased().contains("lost"))
    }

    @Test("serverError description includes error message")
    func serverErrorDescription() {
        let errorMessage = "Gateway Timeout"
        let reason = NetworkReachability.SyncFailureReason.serverError(errorMessage)
        #expect(!reason.description.isEmpty)
        #expect(reason.description.contains(errorMessage))
    }

    @Test("serverError with empty message still has non-empty description")
    func serverErrorEmptyMessage() {
        let reason = NetworkReachability.SyncFailureReason.serverError("")
        #expect(!reason.description.isEmpty)
    }
}
