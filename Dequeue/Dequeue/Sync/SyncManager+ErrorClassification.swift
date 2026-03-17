//
//  SyncManager+ErrorClassification.swift
//  Dequeue
//
//  Error classification helpers for sync retry/reporting logic.
//  Extracted from SyncManager.swift for file-length compliance.
//

import Foundation

// MARK: - Error Classification

extension SyncManager {
    /// Returns true if the error indicates a permanent authentication failure.
    ///
    /// When auth is permanently broken (e.g. Clerk session revoked/expired), periodic sync
    /// loops should stop rather than retrying — each retry produces a Sentry event.
    static func isAuthenticationError(_ error: Error) -> Bool {
        if case SyncError.notAuthenticated = error { return true }
        if case AuthError.notAuthenticated = error { return true }
        // Clerk errors with authentication_invalid code are permanent (session revoked).
        //
        // IMPORTANT: Clerk SDK's `localizedDescription` returns the human-readable `message`
        // field ("Invalid authentication") — NOT the machine-readable `code` field
        // ("authentication_invalid"). We must check BOTH `localizedDescription` and
        // `String(describing:)` because the full ClerkAPIError struct representation
        // (which includes the code) only appears in the latter.
        //
        // This was the root cause of DEQUEUE-APP-T (2,200+ Sentry events): the auth check
        // returned false because localizedDescription lacked "authentication_invalid",
        // so the error fell through to the generic Sentry capture in the periodic push loop.
        let localizedDesc = error.localizedDescription
        let fullDesc = String(describing: error)
        if localizedDesc.contains("authentication_invalid")
            || localizedDesc.contains("Unable to authenticate")
            || fullDesc.contains("authentication_invalid")
            || fullDesc.contains("Unable to authenticate") {
            return true
        }
        return false
    }

    /// Returns true if the error originates from Clerk or Cloudflare infrastructure —
    /// not a bug in our code, and not a permanent auth failure.
    ///
    /// These include:
    /// - HTTP 530: Cloudflare can't reach Clerk's origin server
    /// - `internal_clerk_error`: Clerk backend returning 500-class responses
    ///
    /// Periodic sync loops should stop reporting these to Sentry (they're noise) and
    /// disconnect after a few retries so we don't hammer Clerk every 5 seconds.
    static func isClerkInfrastructureError(_ error: Error) -> Bool {
        let description = error.localizedDescription
        // HTTP 530 from Cloudflare (origin unreachable) and Clerk 5xx internal errors.
        // NOTE: localizedDescription string-matching is the only available signal from the Clerk SDK
        // for these error types; the SDK does not expose a structured HTTP status code in userInfo.
        // Acknowledged trade-off — see PR #398 and SonarCloud security hotspot review. // NOSONAR
        let has530StatusCode = description.contains("status code: 530")
        let has530WithServer = description.contains("530") && description.contains("server")
        if has530StatusCode || has530WithServer { // NOSONAR
            return true
        }
        if description.contains("internal_clerk_error") {
            return true
        }
        // HTTP 429 (Too Many Requests) from Clerk's token endpoint.
        // Without cooldown, the sync loop retries immediately and generates a feedback loop
        // (DEQUEUE-APP-12). Treat 429 as a transient infrastructure error so exponential
        // backoff kicks in and stops the hammering. // NOSONAR
        if description.contains("status code: 429") { // NOSONAR
            return true
        }
        // NSURLErrorDomain -1 (NSURLErrorUnknown) cascading from a 530 token-refresh failure
        // is identified by the NSError domain and code
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == -1 {
            return true
        }
        return false
    }
}
