//
//  NetworkReachability.swift
//  Dequeue
//
//  Utility for classifying sync failures and checking internet reachability
//

import Foundation
import os

/// Utility for determining network reachability and classifying sync failures.
///
/// This is distinct from `NetworkMonitor` which tracks connection status changes.
/// `NetworkReachability` actively tests connectivity to distinguish between:
/// - Device is offline (no internet)
/// - Device is online but our server is unreachable
///
/// This distinction is critical for proper error reporting - we only want
/// to alert on server issues, not expected offline behavior.
enum NetworkReachability {
    // MARK: - Internet Reachability

    // MARK: - Constants

    /// Timeout for reachability check (reduced from 5s to minimize delay on sync failures)
    private static nonisolated(unsafe) let reachabilityTimeout: TimeInterval = 2.0

    /// How long to consider a cached reachability result valid
    private static nonisolated(unsafe) let reachabilityCacheDuration: TimeInterval = 10.0

    // MARK: - Cached State

    /// Thread-safe cached reachability state to avoid blocking network calls on repeated failures.
    /// Uses OSAllocatedUnfairLock for Swift Concurrency safety - NSLock can cause thread-pool
    /// exhaustion if held across suspension points.
    private struct CachedReachability {
        var isReachable: Bool = false
        var timestamp: Date = .distantPast
    }

    /// Thread-safe lock for cached reachability state
    private static let cacheLock = OSAllocatedUnfairLock(initialState: CachedReachability())

    /// Check if we can reach the general internet (not our specific server).
    ///
    /// Uses Apple's captive portal detection endpoint which is highly reliable
    /// and returns quickly. This tells us if the device has working internet
    /// connectivity independent of our backend status.
    ///
    /// Results are cached for `reachabilityCacheDuration` to avoid blocking
    /// network calls when multiple failures occur in rapid succession.
    ///
    /// - Returns: `true` if internet is reachable, `false` otherwise
    static func canReachInternet() async -> Bool {
        // Check cache first to avoid blocking network calls on repeated failures
        let cached = getCachedReachability()
        if let cached {
            return cached
        }

        // Cache miss or expired - perform actual check
        let isReachable = await performReachabilityCheck()
        setCachedReachability(isReachable)
        return isReachable
    }

    /// Returns cached reachability if still valid, nil if expired or not yet set
    private static func getCachedReachability() -> Bool? {
        cacheLock.withLock { state in
            let age = Date().timeIntervalSince(state.timestamp)
            guard age < reachabilityCacheDuration else {
                return nil
            }
            return state.isReachable
        }
    }

    /// Updates the cached reachability value
    private static func setCachedReachability(_ isReachable: Bool) {
        cacheLock.withLock { state in
            state.isReachable = isReachable
            state.timestamp = Date()
        }
    }

    /// Performs the actual network reachability check
    private static func performReachabilityCheck() async -> Bool {
        guard let url = URL(string: "https://captive.apple.com") else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = reachabilityTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Failure Classification

    /// Classify a sync failure to determine its root cause.
    ///
    /// This is the key function for determining whether to alert on a sync failure.
    /// If the device is offline, we expect sync to fail - that's normal.
    /// If the device is online but sync still fails, that's a server issue we need to know about.
    ///
    /// - Parameter error: The error that caused the sync failure
    /// - Returns: The classified reason for the failure
    static func classifyFailure(error: Error) async -> SyncFailureReason {
        let isOnline = await canReachInternet()

        if isOnline {
            // Internet works, but our request failed - this is a server issue
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    return .serverTimeout
                case .cannotConnectToHost, .cannotFindHost:
                    return .serverUnreachable
                case .networkConnectionLost:
                    return .connectionLost
                case .notConnectedToInternet:
                    // This shouldn't happen if canReachInternet() returned true,
                    // but handle it gracefully
                    return .offline
                default:
                    return .serverError(urlError.localizedDescription)
                }
            }

            return .serverError(error.localizedDescription)
        } else {
            return .offline
        }
    }

    // MARK: - Sync Failure Reason

    /// Represents the classified reason for a sync failure.
    enum SyncFailureReason {
        /// Device appears to have no internet connectivity
        case offline

        /// Server cannot be reached (DNS or connection refused)
        case serverUnreachable

        /// Server request timed out
        case serverTimeout

        /// Connection was lost during the request
        case connectionLost

        /// Server returned an error
        case serverError(String)

        /// Whether this failure indicates a server-side problem.
        ///
        /// When `true`, this failure should be reported as an error/alert.
        /// When `false`, this is expected offline behavior.
        var isServerProblem: Bool {
            switch self {
            case .offline:
                return false
            case .serverUnreachable, .serverTimeout, .connectionLost, .serverError:
                return true
            }
        }

        /// Human-readable description of the failure reason
        var description: String {
            switch self {
            case .offline:
                return "Device appears offline"
            case .serverUnreachable:
                return "Server unreachable"
            case .serverTimeout:
                return "Server timeout"
            case .connectionLost:
                return "Connection lost during request"
            case .serverError(let msg):
                return "Server error: \(msg)"
            }
        }
    }
}
