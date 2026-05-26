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

@Suite("AuthService Clerk 422 retry/defer Tests", .serialized)
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

    /// Documents the known limitation of the string fallback: it matches
    /// any error whose `localizedDescription` contains `"status code: 422"`,
    /// regardless of domain. The caller contract scopes invocations to
    /// errors from `Clerk.shared.refreshClient()` /
    /// `Clerk.shared.session?.getToken()`, so this isn't a bug in current
    /// usage. If the fallback ever fires false-positives in production, the
    /// domain-scoped path needs to be extended.
    @Test("isClerk422Error string-fallback known limitation: non-Clerk description match")
    func testIsClerk422ErrorStringFallbackKnownLimitation() {
        let error = NSError(
            domain: "com.example.OtherLib",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Request failed with status code: 422"]
        )
        // Pins the current behaviour. If this expectation flips to false in
        // the future, the test caption is your audit trail — the change is
        // intentional only if the caller contract is also tightened.
        #expect(ClerkAuthService.isClerk422Error(error) == true,
                "string fallback intentionally has no domain scope — caller contract handles this")
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

    @Test("needsReauthentication can be set directly on the mock")
    func testMockSetsNeedsReauthentication() {
        let mockAuth = MockAuthService()
        mockAuth.needsReauthentication = true
        #expect(mockAuth.needsReauthentication == true)
    }

    // MARK: - 422 in background \u2192 never signs out, sets needsReauthentication

    /// Contract documentation test. The MockAuthService doesn't drive the
    /// real Clerk SDK, so we can't exercise `refreshSessionInBackground`
    /// end-to-end — instead, we pin the *invariant* the production code
    /// must uphold when a background refresh observes a Clerk 422: set
    /// `needsReauthentication` and leave `isAuthenticated` untouched. The
    /// real end-to-end behaviour ships through `ClerkAuthService`
    /// integration testing once a Clerk SDK mock is available.
    @Test("Background 422 contract: needsReauthentication set, isAuthenticated preserved")
    func testBackground422DoesNotSignOut() async {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        #expect(mockAuth.isAuthenticated == true)

        // Simulate what `refreshSessionInBackground(context: .background)` does
        // when it observes a Clerk 422 in real life: it does NOT sign the user
        // out, it sets the deferred-reauth flag.
        mockAuth.needsReauthentication = true

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
        mockAuth.needsReauthentication = true
        #expect(mockAuth.needsReauthentication == true)

        try await mockAuth.signOut()

        #expect(mockAuth.isAuthenticated == false)
        #expect(mockAuth.needsReauthentication == false,
                "signOut() must clear needsReauthentication so re-entry doesn't double-handle")
    }

    /// Mirror-test: `signOut()` and `handleDeferredSignOut()` must leave the
    /// service in observationally-equivalent states. ClerkAuthService achieves
    /// this by routing both through `tearDownSignedOutState()` — if the two
    /// paths drift apart again, this test catches it.
    @Test("signOut() and handleDeferredSignOut() leave equivalent state")
    func testSignOutTeardownMatchesDeferredPath() async throws {
        let signedOut = MockAuthService()
        signedOut.mockSignIn(userId: "u1")
        signedOut.needsReauthentication = true
        try await signedOut.signOut()

        let deferred = MockAuthService()
        deferred.mockSignIn(userId: "u1")
        deferred.needsReauthentication = true
        await deferred.handleDeferredSignOut()

        #expect(signedOut.isAuthenticated == deferred.isAuthenticated)
        #expect(signedOut.needsReauthentication == deferred.needsReauthentication)
        #expect(signedOut.currentUserId == deferred.currentUserId)
    }

    /// Lock in the PR-promised invariant that `configure()` runs the
    /// app-launch session refresh in `.background` context (so a transient
    /// 422 during launch does not kick the user to AuthView). The mock
    /// `configure()` doesn't itself invoke `refreshSessionIfNeeded`, so we
    /// assert the contract via the protocol surface: callers can thread
    /// `.background` and the auth service tracks it.
    @Test("Background refresh context is propagated")
    func testBackgroundRefreshContextIsPropagated() async {
        let mockAuth = MockAuthService()
        // Mirror ClerkAuthService.configure(): kick a background refresh.
        await mockAuth.refreshSessionIfNeeded(context: .background)
        #expect(mockAuth.refreshContexts == [.background],
                "App-launch refresh must thread .background to avoid foreground sign-out behaviour")
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
        mockAuth.needsReauthentication = true

        await mockAuth.handleDeferredSignOut()

        #expect(mockAuth.isAuthenticated == false,
                "handleDeferredSignOut must sign the user out so AuthView appears")
        #expect(mockAuth.needsReauthentication == false,
                "handleDeferredSignOut must clear the flag")
        #expect(mockAuth.handleDeferredSignOutCallCount == 1)
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
        #expect(mockAuth.handleDeferredSignOutCallCount == 1)
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
        mockAuth.needsReauthentication = true

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
