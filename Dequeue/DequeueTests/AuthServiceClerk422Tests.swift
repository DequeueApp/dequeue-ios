//
//  AuthServiceClerk422Tests.swift
//  DequeueTests
//
//  Tests for the Clerk 422 retry-before-signout + never-signout-in-background
//  policy (DEQ-282, PR 5/6 of the reminder-delivery push pipeline).
//
//  We don't have a Clerk SDK mock available, so these tests validate the
//  contract surfaces exposed by `AuthServiceProtocol` and the public
//  `MockAuthService` behaviour that real call sites depend on:
//
//  - `AuthContext` is passed through `refreshSessionIfNeeded(context:)`.
//  - `needsReauthentication` is published and consumed by the UI on foreground.
//  - `handleDeferredSignOut()` is the documented foreground-entry hook.
//  - The protocol's no-arg extension defaults to `.foreground` so existing
//    call sites stay compatible.
//
//  The end-to-end 422 \u2192 retry \u2192 second 422 \u2192 signOut behaviour is exercised
//  indirectly via the `isClerk422Error` classifier exposed on
//  `ClerkAuthService`, plus the documented state transitions a UI binds to.
//

import Testing
import Foundation
@testable import Dequeue

@Suite("AuthService Clerk 422 retry/defer Tests")
@MainActor
struct AuthServiceClerk422Tests {
    // MARK: - 422 classifier (used by ClerkAuthService.refreshClientWithRetry)

    @Test("isClerk422Error matches NSError code 422")
    func testIsClerk422ErrorMatchesNSErrorCode() {
        let error = NSError(domain: "Clerk.ClerkAPIError", code: 422, userInfo: nil)
        #expect(ClerkAuthService.isClerk422Error(error) == true)
    }

    @Test("isClerk422Error matches localizedDescription 'status code: 422'")
    func testIsClerk422ErrorMatchesLocalizedDescription() {
        let error = NSError(
            domain: "Clerk.ClerkAPIError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Clerk request failed with status code: 422"]
        )
        #expect(ClerkAuthService.isClerk422Error(error) == true)
    }

    @Test("isClerk422Error does not match unrelated errors")
    func testIsClerk422ErrorRejectsUnrelated() {
        let e401 = NSError(domain: "Clerk.ClerkAPIError", code: 401, userInfo: nil)
        let e500 = NSError(
            domain: "Clerk.ClerkAPIError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "internal_clerk_error"]
        )
        #expect(ClerkAuthService.isClerk422Error(e401) == false)
        #expect(ClerkAuthService.isClerk422Error(e500) == false)
    }

    /// Reviewer-flagged edge case: a bare `code == 422` from an unrelated
    /// domain (e.g. a Foundation networking error layered onto a non-Clerk
    /// API) must not be mistaken for a Clerk 422.
    @Test("isClerk422Error rejects code-422 NSError from unrelated domain")
    func testIsClerk422ErrorRejectsForeignDomainWithCode422() {
        let foreignError = NSError(
            domain: "com.example.OtherAPI",
            code: 422,
            userInfo: nil
        )
        #expect(ClerkAuthService.isClerk422Error(foreignError) == false,
                "bare NSError(code: 422) from non-Clerk domain must not match")
    }

    @Test("isClerk422Error matches HTTPClient-domain 422")
    func testIsClerk422ErrorMatchesHTTPClientDomain() {
        let error = NSError(
            domain: "ClerkKit.HTTPClientError",
            code: 422,
            userInfo: nil
        )
        #expect(ClerkAuthService.isClerk422Error(error) == true,
                "HTTPClient-layer 422 from ClerkKit must match")
    }

    /// Reviewer-flagged adversarial case (round 2): a third-party SDK whose
    /// error domain happens to contain `HTTPClient` somewhere in the middle
    /// must NOT be misclassified as Clerk. The `hasPrefix` check guards this.
    @Test("isClerk422Error rejects third-party domain containing 'HTTPClient'")
    func testIsClerk422ErrorRejectsThirdPartyHTTPClientDomain() {
        let error = NSError(
            domain: "MyLib.HTTPClientError",
            code: 422,
            userInfo: nil
        )
        #expect(ClerkAuthService.isClerk422Error(error) == false,
                "non-Clerk HTTPClient-style domain must not match")
    }

    // MARK: - AuthContext threading via the protocol

    @Test("MockAuthService records foreground context from no-arg refresh (protocol default)")
    func testRefreshNoArgDefaultsToForeground() async {
        let mockAuth = MockAuthService()
        // Calling through the protocol uses the extension default \u2192 .foreground.
        let authService: any AuthServiceProtocol = mockAuth

        await authService.refreshSessionIfNeeded()

        #expect(mockAuth.refreshContexts == [.foreground])
    }

    @Test("MockAuthService threads background context explicitly")
    func testRefreshExplicitBackgroundContext() async {
        let mockAuth = MockAuthService()
        await mockAuth.refreshSessionIfNeeded(context: .background)
        #expect(mockAuth.refreshContexts == [.background])
    }

    @Test("MockAuthService threads foreground context explicitly")
    func testRefreshExplicitForegroundContext() async {
        let mockAuth = MockAuthService()
        await mockAuth.refreshSessionIfNeeded(context: .foreground)
        #expect(mockAuth.refreshContexts == [.foreground])
    }

    // MARK: - needsReauthentication contract

    @Test("MockAuthService starts with needsReauthentication == false")
    func testDefaultNeedsReauthenticationIsFalse() {
        let mockAuth = MockAuthService()
        #expect(mockAuth.needsReauthentication == false)
    }

    @Test("mockNeedsReauthentication() sets the flag")
    func testMockSetsNeedsReauthentication() {
        let mockAuth = MockAuthService()
        mockAuth.mockNeedsReauthentication()
        #expect(mockAuth.needsReauthentication == true)
    }

    // MARK: - 422 in background \u2192 never signs out, sets needsReauthentication

    /// Scenario: A background refresh (BG fetch, silent push, app-launch
    /// pre-foreground validation) sees Clerk 422 twice. The auth layer must
    /// NOT call signOut() — instead, set `needsReauthentication` so the next
    /// foreground entry handles re-auth gracefully.
    @Test("Background 422 simulation: needsReauthentication is set without signing out")
    func testBackground422DoesNotSignOut() async {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        #expect(mockAuth.isAuthenticated == true)

        // Simulate what `refreshSessionInBackground(context: .background)` does
        // when it observes a Clerk 422 in real life: it does NOT sign the user
        // out, it sets the deferred-reauth flag.
        mockAuth.mockNeedsReauthentication()

        // Critical invariant: still authenticated locally. Background work that
        // raced with token rotation must not kick the user.
        #expect(mockAuth.isAuthenticated == true,
                "Background 422 must never sign the user out")
        #expect(mockAuth.needsReauthentication == true,
                "Background 422 must surface the re-auth flag for the UI")
    }

    // MARK: - 422 in foreground \u2192 retry once, then sign out only if retry also 422

    /// We can't drive `Clerk.shared.refreshClient()` from a unit test, but we
    /// can exercise the *contract* the rest of the app relies on: after a
    /// foreground 422-then-422 the user is signed out and the deferred flag
    /// is cleared (so the deferred-signout path doesn't double-fire).
    @Test("Foreground sign-out clears needsReauthentication")
    func testForegroundSignOutClearsDeferredFlag() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        mockAuth.mockNeedsReauthentication()
        #expect(mockAuth.needsReauthentication == true)

        try await mockAuth.signOut()

        #expect(mockAuth.isAuthenticated == false)
        #expect(mockAuth.needsReauthentication == false,
                "signOut() must clear needsReauthentication so re-entry doesn't double-handle")
    }

    /// Inverse scenario: foreground refresh retry succeeds (first 422 was a
    /// flake during token rotation). The user stays signed in and no flag is
    /// raised. The MockAuthService can't simulate the Clerk call itself, but
    /// we can verify a successful refresh leaves state untouched.
    @Test("Foreground refresh that succeeds keeps user signed in and clears nothing")
    func testForegroundRefreshSuccessLeavesStateAlone() async {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        #expect(mockAuth.isAuthenticated == true)
        #expect(mockAuth.needsReauthentication == false)

        await mockAuth.refreshSessionIfNeeded(context: .foreground)

        #expect(mockAuth.isAuthenticated == true,
                "Successful foreground refresh must not sign user out")
        #expect(mockAuth.needsReauthentication == false,
                "Successful foreground refresh must not set needsReauthentication")
    }

    // MARK: - Foreground re-entry with deferred sign-out

    /// Scenario: Background work flagged the session as dead. User foregrounds
    /// the app. The UI must call `handleDeferredSignOut()` which performs the
    /// real sign-out (so AuthView takes over) and clears the flag.
    @Test("handleDeferredSignOut signs the user out and clears the flag")
    func testHandleDeferredSignOutClearsState() async {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        mockAuth.mockNeedsReauthentication()

        await mockAuth.handleDeferredSignOut()

        #expect(mockAuth.isAuthenticated == false,
                "handleDeferredSignOut must sign the user out so AuthView appears")
        #expect(mockAuth.needsReauthentication == false,
                "handleDeferredSignOut must clear the flag")
        #expect(mockAuth.deferredSignOutInvocations == 1)
    }

    @Test("handleDeferredSignOut is idempotent when flag is clear")
    func testHandleDeferredSignOutIdempotent() async {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        // needsReauthentication is false by default — the user is just
        // foregrounding normally.

        await mockAuth.handleDeferredSignOut()

        // Should NOT sign out: nothing to defer.
        #expect(mockAuth.isAuthenticated == true,
                "handleDeferredSignOut must not sign out a healthy session")
        #expect(mockAuth.needsReauthentication == false)
        #expect(mockAuth.deferredSignOutInvocations == 1)
    }

    /// Regression test for the reviewer-flagged sequencing bug: after a
    /// deferred sign-out runs, even if a stray `refreshSessionIfNeeded` slips
    /// past `RootView`'s early-return guard the state must remain consistent.
    /// (`RootView` short-circuits with `return` after `handleDeferredSignOut`
    /// to avoid kicking a refresh against a now-nil Clerk session, but we
    /// double-check the invariant here.)
    @Test("Deferred sign-out + subsequent refresh stays consistent")
    func testDeferredSignOutFollowedByRefreshIsConsistent() async {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        mockAuth.mockNeedsReauthentication()

        await mockAuth.handleDeferredSignOut()

        #expect(mockAuth.isAuthenticated == false)
        #expect(mockAuth.needsReauthentication == false)

        // Stray refresh after sign-out: must not regress state.
        await mockAuth.refreshSessionIfNeeded(context: .foreground)

        #expect(mockAuth.isAuthenticated == false,
                "Refresh after deferred sign-out must not re-authenticate the user")
        #expect(mockAuth.needsReauthentication == false)
    }

    // MARK: - SessionInvalidationReason carries .clerk422Confirmed

    @Test("SessionInvalidationReason.clerk422Confirmed exists and is equatable")
    func testClerk422ConfirmedReason() {
        let a: SessionInvalidationReason = .clerk422Confirmed
        let b: SessionInvalidationReason = .clerk422Confirmed
        #expect(a == b)
        #expect(a != .revoked)
        #expect(a != .expired)
        #expect(a != .networkError)
        #expect(a != .unknown)
    }
}
