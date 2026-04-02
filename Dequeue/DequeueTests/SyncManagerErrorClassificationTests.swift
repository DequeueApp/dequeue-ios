//
//  SyncManagerErrorClassificationTests.swift
//  DequeueTests
//
//  Tests for SyncManager static error classification helpers:
//    - isAuthenticationError(_:)     — detects permanent auth failures (stops retry loops)
//    - isClerkInfrastructureError(_:) — detects transient Clerk/Cloudflare infrastructure issues
//
//  These helpers live in SyncManager+ErrorClassification.swift and had zero coverage
//  before this file was added (2026-03-19).
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - Helpers

/// An error whose localizedDescription is fully controlled.
private struct StubError: LocalizedError {
    let desc: String
    var errorDescription: String? { desc }
}

/// A struct whose String(describing:) representation will embed a structured code field,
/// simulating what the Clerk SDK's ClerkAPIError looks like when logged.
/// e.g. String(describing: ClerkLikeError(code: "authentication_invalid")) →
///      "ClerkLikeError(code: "authentication_invalid", message: "Invalid authentication")"
private struct ClerkLikeError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}

// MARK: - isAuthenticationError Tests

@Suite("SyncManager.isAuthenticationError")
struct SyncManagerIsAuthenticationErrorTests {
    // MARK: - Direct pattern matches (SyncError / AuthError)

    @Test("SyncError.notAuthenticated is an auth error")
    func syncErrorNotAuthenticated() {
        #expect(SyncManager.isAuthenticationError(SyncError.notAuthenticated))
    }

    @Test("AuthError.notAuthenticated is an auth error")
    func authErrorNotAuthenticated() {
        #expect(SyncManager.isAuthenticationError(AuthError.notAuthenticated))
    }

    // MARK: - localizedDescription string matches

    @Test("Error with 'authentication_invalid' in localizedDescription is an auth error")
    func localizedDescContainsAuthenticationInvalid() {
        let error = StubError(desc: "Clerk error: authentication_invalid code received")
        #expect(SyncManager.isAuthenticationError(error))
    }

    @Test("Error with 'Unable to authenticate' in localizedDescription is an auth error")
    func localizedDescContainsUnableToAuthenticate() {
        let error = StubError(desc: "Unable to authenticate with the server")
        #expect(SyncManager.isAuthenticationError(error))
    }

    // MARK: - String(describing:) match when localizedDescription is opaque

    @Test("ClerkAPIError with authentication_invalid code detected via String(describing:)")
    func stringDescribingContainsAuthenticationInvalid() {
        // Simulates Clerk SDK's ClerkAPIError where:
        //   localizedDescription → "Invalid authentication" (human message — no code)
        //   String(describing:)  → includes the code field "authentication_invalid"
        let error = ClerkLikeError(code: "authentication_invalid", message: "Invalid authentication")
        #expect(SyncManager.isAuthenticationError(error))
    }

    @Test("ClerkAPIError with 'Unable to authenticate' in full description detected")
    func stringDescribingContainsUnableToAuthenticate() {
        let error = ClerkLikeError(code: "some_code", message: "Unable to authenticate")
        #expect(SyncManager.isAuthenticationError(error))
    }

    // MARK: - Non-auth errors (should return false)

    @Test("SyncError.connectionLost is not an auth error")
    func syncErrorConnectionLost() {
        #expect(!SyncManager.isAuthenticationError(SyncError.connectionLost))
    }

    @Test("SyncError.pushFailed is not an auth error")
    func syncErrorPushFailed() {
        #expect(!SyncManager.isAuthenticationError(SyncError.pushFailed))
    }

    @Test("SyncError.pullFailed is not an auth error")
    func syncErrorPullFailed() {
        #expect(!SyncManager.isAuthenticationError(SyncError.pullFailed))
    }

    @Test("SyncError.invalidURL is not an auth error")
    func syncErrorInvalidURL() {
        #expect(!SyncManager.isAuthenticationError(SyncError.invalidURL))
    }

    @Test("SyncError.clerkInCooldown is not an auth error")
    func syncErrorClerkInCooldown() {
        #expect(!SyncManager.isAuthenticationError(SyncError.clerkInCooldown))
    }

    @Test("AuthError.noToken is not an auth error")
    func authErrorNoToken() {
        #expect(!SyncManager.isAuthenticationError(AuthError.noToken))
    }

    @Test("AuthError.invalidCredentials is not an auth error")
    func authErrorInvalidCredentials() {
        #expect(!SyncManager.isAuthenticationError(AuthError.invalidCredentials))
    }

    @Test("Generic NSError with unrelated description is not an auth error")
    func genericNSError() {
        let error = NSError(domain: "com.test", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Something went wrong"
        ])
        #expect(!SyncManager.isAuthenticationError(error))
    }

    @Test("Empty error description is not an auth error")
    func emptyDescription() {
        let error = StubError(desc: "")
        #expect(!SyncManager.isAuthenticationError(error))
    }

    // MARK: - Case sensitivity

    @Test("Auth error check is case-sensitive — 'AUTHENTICATION_INVALID' does not match")
    func caseSensitivity() {
        let error = StubError(desc: "AUTHENTICATION_INVALID error occurred")
        // The code checks for lowercase "authentication_invalid" only
        #expect(!SyncManager.isAuthenticationError(error))
    }
}

// MARK: - isClerkInfrastructureError Tests

@Suite("SyncManager.isClerkInfrastructureError")
struct SyncManagerIsClerkInfrastructureErrorTests {
    // MARK: - HTTP 530 (Cloudflare origin unreachable)

    @Test("'status code: 530' triggers Clerk infra error")
    func statusCode530() {
        let error = NSError(domain: "com.test", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Request failed with status code: 530"
        ])
        #expect(SyncManager.isClerkInfrastructureError(error))
    }

    @Test("'530' with 'server' triggers Clerk infra error")
    func statusCode530WithServer() {
        let error = NSError(domain: "com.test", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "The server returned status 530"
        ])
        #expect(SyncManager.isClerkInfrastructureError(error))
    }

    @Test("'530' without 'server' does NOT trigger infra error")
    func statusCode530WithoutServer() {
        // The check requires EITHER "status code: 530" OR ("530" AND "server")
        let error = NSError(domain: "com.test", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Error code 530 occurred"
        ])
        #expect(!SyncManager.isClerkInfrastructureError(error))
    }

    // MARK: - internal_clerk_error (Clerk 5xx backend errors)

    @Test("'internal_clerk_error' triggers Clerk infra error")
    func internalClerkError() {
        let error = StubError(desc: "Clerk backend returned internal_clerk_error response")
        #expect(SyncManager.isClerkInfrastructureError(error))
    }

    // MARK: - HTTP 429 (Clerk rate limiting)

    @Test("'status code: 429' triggers Clerk infra error")
    func statusCode429() {
        let error = NSError(domain: "com.test", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Token refresh failed with status code: 429"
        ])
        #expect(SyncManager.isClerkInfrastructureError(error))
    }

    // MARK: - NSURLErrorDomain / -1 (cascading 530 failure)

    @Test("NSURLErrorDomain with code -1 triggers Clerk infra error")
    func nsURLErrorDomainCodeNegativeOne() {
        let error = NSError(domain: NSURLErrorDomain, code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Unknown network error"
        ])
        #expect(SyncManager.isClerkInfrastructureError(error))
    }

    @Test("NSURLErrorDomain with a different code does NOT trigger infra error")
    func nsURLErrorDomainDifferentCode() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        #expect(!SyncManager.isClerkInfrastructureError(error))
    }

    @Test("Different domain with code -1 does NOT trigger infra error")
    func differentDomainCodeNegativeOne() {
        let error = NSError(domain: "com.some.other", code: -1, userInfo: nil)
        #expect(!SyncManager.isClerkInfrastructureError(error))
    }

    // MARK: - Non-infrastructure errors (should return false)

    @Test("SyncError.notAuthenticated is not a Clerk infra error")
    func syncErrorNotAuthenticated() {
        #expect(!SyncManager.isClerkInfrastructureError(SyncError.notAuthenticated))
    }

    @Test("SyncError.connectionLost is not a Clerk infra error")
    func syncErrorConnectionLost() {
        #expect(!SyncManager.isClerkInfrastructureError(SyncError.connectionLost))
    }

    @Test("AuthError.notAuthenticated is not a Clerk infra error")
    func authErrorNotAuthenticated() {
        #expect(!SyncManager.isClerkInfrastructureError(AuthError.notAuthenticated))
    }

    @Test("Generic NSError with unrelated description is not a Clerk infra error")
    func genericNSError() {
        let error = NSError(domain: "com.test", code: 500, userInfo: [
            NSLocalizedDescriptionKey: "Something went wrong"
        ])
        #expect(!SyncManager.isClerkInfrastructureError(error))
    }

    @Test("Empty error description is not a Clerk infra error")
    func emptyDescription() {
        let error = StubError(desc: "")
        #expect(!SyncManager.isClerkInfrastructureError(error))
    }

    // MARK: - Boundary cases

    @Test("HTTP 531 does not trigger infra error")
    func statusCode531() {
        let error = NSError(domain: "com.test", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Request failed with status code: 531"
        ])
        #expect(!SyncManager.isClerkInfrastructureError(error))
    }

    @Test("HTTP 428 does not trigger infra error")
    func statusCode428() {
        let error = NSError(domain: "com.test", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Request failed with status code: 428"
        ])
        #expect(!SyncManager.isClerkInfrastructureError(error))
    }

    @Test("Multiple conditions: 530 + internal_clerk_error both match independently")
    func multipleConditionsMatch() {
        let error530 = NSError(domain: "com.test", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "status code: 530"
        ])
        let errorClerk = StubError(desc: "internal_clerk_error occurred")

        // Both should independently qualify as infra errors
        #expect(SyncManager.isClerkInfrastructureError(error530))
        #expect(SyncManager.isClerkInfrastructureError(errorClerk))
    }
}
