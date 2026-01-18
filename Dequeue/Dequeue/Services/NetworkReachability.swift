//
//  NetworkReachability.swift
//  Dequeue
//
//  Utility for classifying sync failures and checking internet reachability
//

import Foundation

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

    /// Check if we can reach the general internet (not our specific server).
    ///
    /// Uses Apple's captive portal detection endpoint which is highly reliable
    /// and returns quickly. This tells us if the device has working internet
    /// connectivity independent of our backend status.
    ///
    /// - Returns: `true` if internet is reachable, `false` otherwise
    static func canReachInternet() async -> Bool {
        guard let url = URL(string: "https://captive.apple.com") else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
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

            // Check for HTTP status code errors
            if let httpError = error as? HTTPError {
                return .httpError(httpError.statusCode)
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

        /// HTTP error with specific status code
        case httpError(Int)

        /// Whether this failure indicates a server-side problem.
        ///
        /// When `true`, this failure should be reported as an error/alert.
        /// When `false`, this is expected offline behavior.
        var isServerProblem: Bool {
            switch self {
            case .offline:
                return false
            case .serverUnreachable, .serverTimeout, .connectionLost, .serverError, .httpError:
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
            case .httpError(let code):
                return "HTTP \(code)"
            }
        }
    }
}

// MARK: - HTTP Error Helper

/// Simple HTTP error type for classification
struct HTTPError: Error {
    let statusCode: Int
    let message: String?

    init(statusCode: Int, message: String? = nil) {
        self.statusCode = statusCode
        self.message = message
    }
}
