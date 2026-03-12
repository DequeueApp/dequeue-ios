//
//  SyncManagerAuthErrorTests.swift
//  DequeueTests
//
//  Tests for SyncManager.isAuthenticationError — the helper that classifies
//  permanent authentication failures so periodic sync loops stop retrying.
//
//  Key invariant: Clerk SDK's `localizedDescription` returns the human-readable
//  `message` field ("Invalid authentication"), NOT the machine-readable `code`
//  ("authentication_invalid"). We check BOTH localizedDescription AND
//  String(describing:) to catch both representations.
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Simulates Clerk SDK's ClerkAPIError: localizedDescription returns the human-readable
/// message, while String(describing:) includes the machine-readable error code.
private struct MockClerkAPIError: Error, CustomStringConvertible {
    let code: String
    let message: String

    var localizedDescription: String { message }
    var description: String { "ClerkAPIError(code: \"\(code)\", message: \"\(message)\")" }
}

@Suite("SyncManager isAuthenticationError Tests")
struct SyncManagerAuthErrorTests {
    // MARK: - SyncError / AuthError typed errors

    @Test("SyncError.notAuthenticated is an authentication error")
    func testSyncErrorNotAuthenticated() {
        let error = SyncError.notAuthenticated
        #expect(SyncManager.isAuthenticationError(error) == true)
    }

    @Test("AuthError.notAuthenticated is an authentication error")
    func testAuthErrorNotAuthenticated() {
        let error = AuthError.notAuthenticated
        #expect(SyncManager.isAuthenticationError(error) == true)
    }

    // MARK: - localizedDescription matching

    @Test("Error with 'authentication_invalid' in localizedDescription is an auth error")
    func testLocalizedDescriptionContainsAuthInvalid() {
        let error = NSError(
            domain: "ClerkKit.ClerkAPIError",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "authentication_invalid: session has been revoked"]
        )
        #expect(SyncManager.isAuthenticationError(error) == true)
    }

    @Test("Error with 'Unable to authenticate' in localizedDescription is an auth error")
    func testLocalizedDescriptionContainsUnableToAuthenticate() {
        let error = NSError(
            domain: "AuthError",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Unable to authenticate the user"]
        )
        #expect(SyncManager.isAuthenticationError(error) == true)
    }

    // MARK: - String(describing:) matching (the DEQUEUE-APP-T bug fix)

    /// This is the critical regression test for DEQUEUE-APP-T (2,200+ Sentry events).
    ///
    /// Clerk SDK returns localizedDescription = "Invalid authentication" (human-readable),
    /// but String(describing:) includes code = "authentication_invalid" (machine-readable).
    /// Without checking String(describing:), the periodic push loop fails to recognise
    /// the error as permanent auth failure and falls through to the Sentry capture path.
    @Test("Clerk error with code in String(describing:) but NOT in localizedDescription is an auth error")
    func testStringDescribingContainsAuthInvalid() {
        // Simulates Clerk SDK's ClerkAPIError where localizedDescription = human message
        // but String(describing:) includes the machine-readable code field.
        let error = MockClerkAPIError(
            code: "authentication_invalid",
            message: "Invalid authentication"
        )

        // Verify that localizedDescription does NOT contain "authentication_invalid"
        #expect(!error.localizedDescription.contains("authentication_invalid"),
                "Precondition: localizedDescription should only have human-readable message")

        // Verify that String(describing:) DOES contain "authentication_invalid"
        #expect(String(describing: error).contains("authentication_invalid"),
                "Precondition: full description should include the error code")

        // The critical assertion: isAuthenticationError must return true
        #expect(SyncManager.isAuthenticationError(error) == true,
                "isAuthenticationError must detect auth_invalid via String(describing:)")
    }

    @Test("Clerk error with 'Unable to authenticate' in String(describing:) is an auth error")
    func testStringDescribingContainsUnableToAuthenticate() {
        let error = MockClerkAPIError(
            code: "Unable to authenticate",
            message: "Session is no longer valid"
        )
        #expect(SyncManager.isAuthenticationError(error) == true)
    }

    // MARK: - Non-auth errors (must NOT be classified as auth)

    @Test("Network timeout error is NOT an authentication error")
    func testNetworkTimeoutNotAuth() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
        )
        #expect(SyncManager.isAuthenticationError(error) == false)
    }

    @Test("HTTP 500 server error is NOT an authentication error")
    func testHttp500NotAuth() {
        let error = NSError(
            domain: "HTTPError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Internal server error"]
        )
        #expect(SyncManager.isAuthenticationError(error) == false)
    }

    @Test("Clerk internal_clerk_error is NOT an authentication error")
    func testClerkInternalErrorNotAuth() {
        let error = NSError(
            domain: "ClerkKit.ClerkAPIError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "internal_clerk_error: backend unavailable"]
        )
        // internal_clerk_error is a transient infra error, not a permanent auth failure
        #expect(SyncManager.isAuthenticationError(error) == false)
    }

    @Test("SyncError.clerkInCooldown is NOT an authentication error")
    func testClerkCooldownNotAuth() {
        // clerkInCooldown must NOT be classified as auth error — it would
        // permanently disconnect the sync loop, preventing recovery after cooldown.
        let error = SyncError.clerkInCooldown
        #expect(SyncManager.isAuthenticationError(error) == false)
    }

    @Test("Generic error with unrelated description is NOT an authentication error")
    func testUnrelatedErrorNotAuth() {
        let error = MockClerkAPIError(
            code: "not_found",
            message: "Resource not found"
        )
        #expect(SyncManager.isAuthenticationError(error) == false)
    }

    @Test("Empty error description is NOT an authentication error")
    func testEmptyDescriptionNotAuth() {
        let error = NSError(domain: "SomeError", code: 0, userInfo: [:])
        #expect(SyncManager.isAuthenticationError(error) == false)
    }
}
