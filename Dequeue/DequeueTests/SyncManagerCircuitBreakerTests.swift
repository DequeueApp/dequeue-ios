//
//  SyncManagerCircuitBreakerTests.swift
//  DequeueTests
//
//  Tests for SyncManager.isClerkInfrastructureError — the circuit-breaker
//  helper that classifies transient Clerk/Cloudflare infrastructure errors
//  so periodic push loops can skip Sentry reporting and disconnect cleanly.
//

import Testing
import Foundation
@testable import Dequeue

@Suite("SyncManager Circuit Breaker Tests")
struct SyncManagerCircuitBreakerTests {

    // MARK: - HTTP 530 (Cloudflare origin unreachable)

    @Test("HTTP 530 via status code string is a Clerk infra error")
    func testHttp530StatusCode() {
        let error = NSError(
            domain: "NSURLErrorDomain",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Request failed with status code: 530"]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == true)
    }

    @Test("530 with 'server' in description is a Clerk infra error")
    func testHttp530WithServer() {
        let error = NSError(
            domain: "ClerkError",
            code: 530,
            userInfo: [NSLocalizedDescriptionKey: "Server error: 530 origin server unreachable"]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == true)
    }

    @Test("530 without 'server' in description is NOT a Clerk infra error")
    func testHttp530WithoutServer() {
        // The classifier requires BOTH "530" AND "server" when "status code:" is absent
        let error = NSError(
            domain: "SomeError",
            code: 530,
            userInfo: [NSLocalizedDescriptionKey: "Error 530 occurred"]
        )
        // "530" is present but "server" is NOT → not classified as infra error via the 530 branch.
        // However, the NSURLErrorDomain/-1 branch would still catch NSURLError unknown.
        // This bare string only matches if neither branch fires:
        #expect(SyncManager.isClerkInfrastructureError(error) == false)
    }

    // MARK: - internal_clerk_error

    @Test("internal_clerk_error in description is a Clerk infra error")
    func testInternalClerkError() {
        let error = NSError(
            domain: "Clerk.ClerkAPIError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "POST /v1/client/sessions/tokens: internal_clerk_error"]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == true)
    }

    @Test("internal_clerk_error substring anywhere in description is matched")
    func testInternalClerkErrorSubstring() {
        let error = NSError(
            domain: "APIError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "{\"code\":\"internal_clerk_error\",\"message\":\"Internal error\"}"]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == true)
    }

    // MARK: - NSURLError unknown (-1)

    @Test("NSURLErrorDomain with code -1 is a Clerk infra error")
    func testNSURLErrorUnknown() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn't be completed."]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == true)
    }

    @Test("NSURLErrorDomain with code -1009 (no internet) is NOT a Clerk infra error")
    func testNSURLErrorNoInternet() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The internet connection appears to be offline."]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == false)
    }

    @Test("NSURLErrorDomain with code -1001 (timeout) is NOT a Clerk infra error")
    func testNSURLErrorTimeout() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == false)
    }

    // MARK: - Auth errors that should NOT be classified as infra errors

    @Test("HTTP 401 is NOT a Clerk infra error")
    func testHttp401() {
        let error = NSError(
            domain: "HTTPError",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Request failed with status code: 401"]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == false)
    }

    @Test("HTTP 403 is NOT a Clerk infra error")
    func testHttp403() {
        let error = NSError(
            domain: "HTTPError",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "Request failed with status code: 403"]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == false)
    }

    @Test("AuthError.notAuthenticated is NOT a Clerk infra error")
    func testAuthErrorNotAuthenticated() {
        let error = AuthError.notAuthenticated
        #expect(SyncManager.isClerkInfrastructureError(error) == false)
    }

    @Test("AuthError.noToken is NOT a Clerk infra error")
    func testAuthErrorNoToken() {
        let error = AuthError.noToken
        #expect(SyncManager.isClerkInfrastructureError(error) == false)
    }

    @Test("Generic network error is NOT a Clerk infra error")
    func testGenericNetworkError() {
        let error = NSError(
            domain: "NSURLErrorDomain",
            code: NSURLErrorCannotConnectToHost,
            userInfo: [NSLocalizedDescriptionKey: "Could not connect to the server."]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == false)
    }

    @Test("Random error with no matching patterns is NOT a Clerk infra error")
    func testRandomError() {
        let error = NSError(
            domain: "com.example",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Something went wrong"]
        )
        #expect(SyncManager.isClerkInfrastructureError(error) == false)
    }
}
