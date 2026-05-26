//
//  AuthService.swift
//  Dequeue
//
//  Authentication service wrapping Clerk SDK
//

import Foundation
import SwiftUI
import ClerkKit

// MARK: - Session State Change

/// Describes a change in authentication session state
enum SessionStateChange: Sendable {
    /// Session was restored (e.g., after network reconnection validated cached session)
    case sessionRestored(userId: String)
    /// Session was invalidated unexpectedly (not by user sign-out)
    /// This can happen in multi-device scenarios when another device's action affects this session
    case sessionInvalidated(reason: SessionInvalidationReason)
}

/// Reasons why a session might be invalidated
enum SessionInvalidationReason: Sendable, Equatable {
    /// Session expired on server
    case expired
    /// Session was revoked (e.g., password change, admin action)
    case revoked
    /// Network error during validation
    case networkError
    /// Unknown reason
    case unknown
    /// Clerk's token endpoint returned 422 twice in a row in the foreground —
    /// session ID is unrecoverable and the user must sign in again.
    case clerk422Confirmed
}

// MARK: - Auth Context

/// Identifies whether an auth-related operation is happening because the user
/// is actively driving the app (foreground) or because of background work
/// (silent push, BG fetch, WebSocket reconnect, app-launch session validation
/// before the user has interacted).
///
/// The auth layer uses this to decide how aggressively to react to errors —
/// most importantly, **never** sign the user out from a background context.
/// Clerk's token endpoint sometimes flakes with 422 during token rotation;
/// in the foreground we retry once with a fresh token before giving up, and
/// in the background we never sign out — we set `needsReauthentication` and
/// let the next foreground entry present the sign-in UI.
enum AuthContext: Sendable, Equatable {
    /// User is actively driving the app (scene `.active`, explicit user action).
    case foreground
    /// App is doing background work without active user attention.
    case background
}

// MARK: - Auth Service Protocol

protocol AuthServiceProtocol {
    /// Whether the user is currently authenticated with a valid session
    @MainActor var isAuthenticated: Bool { get }
    /// Whether the auth state is still being determined during app launch
    @MainActor var isLoading: Bool { get }
    /// The unique identifier of the currently authenticated user, if any
    @MainActor var currentUserId: String? { get }
    /// True when a background refresh confirmed the session can no longer be
    /// refreshed (e.g. two consecutive Clerk 422s) but we deliberately deferred
    /// signing out so the UI could surface re-auth on next foreground.
    ///
    /// The UI should consult this on `scenePhase == .active` and call
    /// `handleDeferredSignOut()` before refreshing. Cleared by `signOut()` or
    /// `handleDeferredSignOut()`.
    @MainActor var needsReauthentication: Bool { get }
    /// Stream of session state changes for observing unexpected auth events
    var sessionStateChanges: AsyncStream<SessionStateChange> { get }

    @MainActor func configure() async
    @MainActor func signOut() async throws
    @MainActor func getAuthToken() async throws -> String
    /// Force-fetches a fresh token from Clerk, bypassing the local cache.
    /// Use when a request returns 401 to retry with a guaranteed-fresh token.
    @MainActor func forceRefreshAuthToken() async throws -> String
    /// Refresh the session if cooldown allows. The `context` controls error
    /// handling: `.foreground` retries 422 once before signing out;
    /// `.background` never signs out and sets `needsReauthentication` instead.
    @MainActor func refreshSessionIfNeeded(context: AuthContext) async
    /// Called by the UI when the user re-foregrounds the app and we want to
    /// present sign-in because a prior background refresh confirmed the
    /// session is dead. Force-signs out so the existing Auth flow takes over,
    /// and clears `needsReauthentication`.
    @MainActor func handleDeferredSignOut() async
}

extension AuthServiceProtocol {
    /// Backwards-compatible default — most existing call sites are foreground.
    @MainActor func refreshSessionIfNeeded() async {
        await refreshSessionIfNeeded(context: .foreground)
    }
}

// MARK: - Clerk Auth Service

/// Production auth service using Clerk SDK
@Observable
final class ClerkAuthService: AuthServiceProtocol {
    private var currentSignUp: SignUp?
    private var currentSignIn: SignIn?
    private var backgroundRefreshTask: Task<Void, Never>?
    private var lastRefreshTime: Date?
    private let refreshThrottleInterval: TimeInterval = 60 // 1 minute

    // Cache auth state to avoid repeated Clerk SDK calls on every view render
    private(set) var isAuthenticated: Bool = false
    private(set) var isLoading: Bool = true
    private(set) var currentUserId: String?
    /// Set when a background refresh confirmed the session is unrecoverable
    /// but we deferred sign-out. UI consults this on foreground entry.
    private(set) var needsReauthentication: Bool = false

    // Session state change stream for multi-device session handling
    // Note: continuation is nonisolated(unsafe) to allow access from deinit
    private let sessionStateChangesStream: AsyncStream<SessionStateChange>
    nonisolated(unsafe) private var sessionStateChangeContinuation: AsyncStream<SessionStateChange>.Continuation?

    /// Stream of session state changes for observing unexpected auth events
    /// Use this to react to sessions being invalidated or restored in multi-device scenarios
    var sessionStateChanges: AsyncStream<SessionStateChange> {
        sessionStateChangesStream
    }

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionStateChange.self)
        self.sessionStateChangesStream = stream
        self.sessionStateChangeContinuation = continuation
    }

    deinit {
        sessionStateChangeContinuation?.finish()
    }

    /// Configures auth service with offline-first approach.
    ///
    /// This method is designed to never block app launch, even when offline:
    /// 1. Configure Clerk SDK (no network required)
    /// 2. Immediately check for cached session state
    /// 3. Set isLoading = false so UI proceeds instantly
    /// 4. Refresh session from network in background (non-blocking)
    ///
    /// If offline, the cached session is trusted. When back online, the session
    /// will be validated and refreshed. If the session was invalidated server-side,
    /// the user will be prompted to re-login only after network is available.
    @MainActor
    func configure() async {
        // Step 1: Configure SDK (no network call)
        Clerk.configure(publishableKey: Configuration.clerkPublishableKey)

        // Step 2: Check cached session immediately (no network call)
        // Clerk SDK may have persisted session from previous app launch
        updateAuthState()

        // Step 3: Allow UI to proceed immediately - don't block on network
        isLoading = false

        // Step 4: Refresh session from network in background (non-blocking)
        // This validates the session is still valid server-side and refreshes tokens
        // Cancel any existing refresh task to prevent race conditions.
        // App-launch refresh runs in `.background` context — the user has not
        // yet interacted, so we must not throw them to sign-in if Clerk flakes.
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = Task {
            await refreshSessionInBackground(context: .background)
        }
    }

    /// Refreshes session from Clerk servers in background.
    ///
    /// This is non-blocking and respects network availability:
    /// - If offline, does nothing (trusts cached session)
    /// - If online, validates session with Clerk servers
    /// - Updates auth state if session was invalidated server-side
    /// - Emits session state changes for multi-device scenarios
    /// - Errors are logged but don't crash the app (graceful degradation)
    @MainActor
    private func refreshSessionInBackground(context: AuthContext) async {
        // Check network status - don't attempt if offline
        guard NetworkMonitor.shared.isConnected else {
            return
        }

        // Avoid spamming Clerk when we know there's no active session
        // This prevents repeated 401s from /client/sessions/.../tokens
        guard Clerk.shared.session != nil else {
            return
        }

        // Capture state before refresh to detect changes
        let wasAuthenticated = isAuthenticated
        let previousUserId = currentUserId

        // Attempt to load/refresh session from Clerk servers.
        // This validates the session is still valid and refreshes tokens.
        // For 422 specifically (Clerk's token endpoint occasionally flakes during
        // token rotation), we retry once with a fresh refresh before declaring the
        // session dead — but only in foreground. See refreshClientWithRetry below.
        //
        // The typed `RefreshClientOutcome` lets the catch-block path distinguish
        // the "422 → retry → second 422" foreground case from a plain failure,
        // without needing an `inout` flag the caller has to remember to read.
        let outcome = await refreshClientWithRetry(context: context)
        var refreshError: Error?
        var didGetConsecutive422 = false
        if let error = outcome.error {
            refreshError = error
            // Pattern match (vs. `outcome == .consecutiveClerk422(error)`) because the
            // custom `RefreshClientOutcome.==` only compares by case — the `error`
            // argument would be ignored and implying structural equality is misleading.
            if case .consecutiveClerk422 = outcome {
                didGetConsecutive422 = true
            }
            // Only report unexpected errors to Sentry — not 401s, 422s, or Clerk internal errors.
            //
            // 401 Unauthorized: When a Clerk session is revoked server-side,
            // `Clerk.shared.refreshClient()` throws an HTTPClientError with status 401.
            // This is *expected* behaviour: handled gracefully below (session invalidation
            // breadcrumb + stream emit). Capturing 401s here bypasses the
            // `failedRequestStatusCodes = [402-599]` filter and floods Sentry.
            //
            // 422 Unprocessable Entity: Clerk returns this when the session ID in the token
            // URL is permanently invalid and cannot be refreshed (distinct from a transient
            // 401). The session must be cleared and the user re-authenticated.
            // Without this guard the app retried on every app-foreground event, flooding
            // Sentry with 3,800+ identical events (DEQUEUE-APP-12, Feb–Mar 2026).
            //
            // internal_clerk_error: Clerk's own backend occasionally returns 500s
            // (POST /v1/client/sessions/.../tokens) with code "internal_clerk_error".
            // These are transient Clerk infrastructure failures entirely outside our
            // control — capturing them only generates noise (DEQUEUE-APP-T, 1,900+ events).
            let isExpected401 = error.localizedDescription.contains("401")
                || (error as NSError).code == 401
            let isExpected422 = ClerkAuthService.isClerk422Error(error)
            let isClerkInternalError = error.localizedDescription.contains("internal_clerk_error")
                || (error as NSError).domain == "Clerk.ClerkAPIError"
            if !isExpected401 && !isExpected422 && !isClerkInternalError {
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "session_refresh", "offline_mode": !NetworkMonitor.shared.isConnected]
                )
            }
            // 422 handling — see file-level docs at AuthContext.
            //
            // Foreground + didGetConsecutive422 (retry path returned 422 twice):
            //   The session is genuinely unrecoverable. Force sign-out so the
            //   existing AuthView shows. This matches the prior behaviour,
            //   just gated on the *retry* also failing.
            //
            // Any other 422 (background, or foreground non-retry path):
            //   Never sign out. Surface `needsReauthentication` so the UI
            //   re-prompts on next foreground entry. Background is the main
            //   target (silent push / BG fetch / WebSocket reconnect); the
            //   foreground non-retry path is a defensive fallback — a
            //   deferred sign-out on next foreground entry is recoverable
            //   while a spurious sign-out on a single 422 is the exact bug
            //   this PR fixes, so we refuse to re-introduce it.
            if isExpected422 {
                if context == .foreground && didGetConsecutive422 {
                    ErrorReportingService.addBreadcrumb(
                        category: "auth",
                        message: "Session permanently invalidated (422 twice) — forcing sign-out",
                        data: ["source": "refreshSessionInBackground", "context": "foreground"]
                    )
                    do {
                        try await Clerk.shared.auth.signOut()
                    } catch {
                        ErrorReportingService.addBreadcrumb(
                            category: "auth",
                            message: "Clerk signOut failed during 422 cleanup — proceeding with local teardown",
                            data: ["error": error.localizedDescription]
                        )
                    }
                    // Mirror the cleanup `signOut()` / `handleDeferredSignOut()`
                    // do so the Sentry user context and session-state stream
                    // don't leak past a 422-confirmed sign-out.
                    tearDownSignedOutState()
                } else {
                    ErrorReportingService.addBreadcrumb(
                        category: "auth",
                        message: "Session refresh 422 — deferring sign-out",
                        data: [
                            "source": "refreshSessionInBackground",
                            "context": context == .foreground ? "foreground-single-422" : "background"
                        ]
                    )
                    needsReauthentication = true
                }
            }
        }

        // Update auth state in case session was invalidated server-side
        updateAuthState()

        // Detect and emit session state changes for multi-device handling
        if wasAuthenticated && !isAuthenticated {
            // Session was invalidated - determine reason
            let reason: SessionInvalidationReason
            if didGetConsecutive422 {
                reason = .clerk422Confirmed
            } else if refreshError != nil {
                reason = .networkError
            } else {
                // Session was valid locally but invalid on server
                // This typically happens when session was revoked or expired
                reason = .revoked
            }
            sessionStateChangeContinuation?.yield(.sessionInvalidated(reason: reason))
            ErrorReportingService.addBreadcrumb(
                category: "auth",
                message: "Session invalidated during refresh",
                data: ["reason": String(describing: reason), "previousUserId": previousUserId ?? "nil"]
            )
        } else if !wasAuthenticated && isAuthenticated, let userId = currentUserId {
            // Session was restored (rare case - usually from Clerk SDK internal state)
            sessionStateChangeContinuation?.yield(.sessionRestored(userId: userId))
            ErrorReportingService.addBreadcrumb(
                category: "auth",
                message: "Session restored during refresh",
                data: ["userId": userId]
            )
        }
    }

    /// Called when app becomes active to refresh session if needed.
    ///
    /// This ensures that when returning from background or when network
    /// becomes available, we validate the session is still valid.
    /// Throttles refreshes to avoid excessive network calls on rapid app state changes.
    @MainActor
    func refreshSessionIfNeeded(context: AuthContext) async {
        // Throttle refreshes to avoid excessive network calls
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < refreshThrottleInterval {
            return
        }

        lastRefreshTime = Date()
        await refreshSessionInBackground(context: context)
    }

    /// Called by the UI on foreground entry when `needsReauthentication` is true.
    /// Performs the deferred sign-out (previously skipped to avoid kicking the
    /// user during a background context) so the standard AuthView flow takes
    /// over. Mirrors the cleanup `signOut()` does — Sentry user context, the
    /// session-state stream, and the local auth-state cache are all torn down.
    @MainActor
    func handleDeferredSignOut() async {
        guard needsReauthentication else { return }
        ErrorReportingService.addBreadcrumb(
            category: "auth",
            message: "Performing deferred sign-out on foreground entry",
            data: ["trigger": "needsReauthentication"]
        )
        do {
            try await Clerk.shared.auth.signOut()
        } catch {
            // Local teardown still has to happen — the session is confirmed
            // dead regardless of whether the Clerk SDK call itself succeeded
            // (e.g. transient network failure). Record a breadcrumb so the
            // failure is visible in Sentry without bypassing local cleanup.
            ErrorReportingService.addBreadcrumb(
                category: "auth",
                message: "Deferred Clerk signOut failed — tearing down locally",
                data: ["error": error.localizedDescription]
            )
        }
        tearDownSignedOutState()
    }

    // MARK: - 422 retry helpers

    /// Outcome of an attempted `Clerk.shared.refreshClient()` call, including
    /// the foreground 422-retry path. Used by `refreshSessionInBackground` to
    /// distinguish the three meaningful states without an `inout` flag.
    enum RefreshClientOutcome: Equatable {
        /// `refreshClient()` returned without error (possibly after one retry).
        case success
        /// Original call returned 422, the foreground retry was attempted, and
        /// the retry *also* returned 422. The session is unrecoverable.
        case consecutiveClerk422(Error)
        /// Any other failure — may or may not be a single 422 (background
        /// 422 lands here because we don't retry).
        case failed(Error)

        var error: Error? {
            switch self {
            case .success: return nil
            case .consecutiveClerk422(let error), .failed(let error): return error
            }
        }

        // Equatable: errors aren't Equatable so we compare by case only. This is
        // fine for the one usage site that just checks `outcome == .consecutiveClerk422(...)`.
        static func == (lhs: RefreshClientOutcome, rhs: RefreshClientOutcome) -> Bool {
            switch (lhs, rhs) {
            case (.success, .success):
                return true
            case (.consecutiveClerk422, .consecutiveClerk422):
                return true
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    /// Calls `Clerk.shared.refreshClient()` and, in foreground context, retries
    /// once on 422 with a fresh token before giving up. Clerk's token endpoint
    /// occasionally returns 422 during token rotation; retrying with
    /// `skipCache: true` recovers in the common flake case.
    ///
    /// Returns a `RefreshClientOutcome` describing what happened. Background
    /// context never retries — a 422 there returns `.failed(error)` and the
    /// caller defers sign-out via `needsReauthentication`.
    @MainActor
    private func refreshClientWithRetry(context: AuthContext) async -> RefreshClientOutcome {
        do {
            try await Clerk.shared.refreshClient()
            return .success
        } catch {
            // Only retry on 422 — other errors return immediately so the
            // existing classification logic runs unchanged.
            guard ClerkAuthService.isClerk422Error(error) else {
                return .failed(error)
            }

            switch context {
            case .background:
                // Never retry-and-signout in background. Surface as `.failed`
                // so the caller sets needsReauthentication.
                return .failed(error)
            case .foreground:
                ErrorReportingService.addBreadcrumb(
                    category: "auth",
                    message: "Clerk 422 on refreshClient — retrying with fresh token",
                    data: ["source": "refreshClientWithRetry"]
                )
                // Force a fresh JWT (skipCache: true). If the session is
                // healthy and Clerk just flaked, this succeeds and the next
                // refreshClient() will then succeed too.
                // Warm the token cache; on success the next refreshClient()
                // call sees a fresh JWT. If this fails we still try refreshClient()
                // — a healthy session will recover, and a dead session will 422
                // again, which we handle below by surfacing `.consecutiveClerk422`.
                do {
                    _ = try await Clerk.shared.session?.getToken(.init(skipCache: true))
                } catch {
                    ErrorReportingService.addBreadcrumb(
                        category: "auth",
                        message: "skipCache token fetch failed before 422 retry",
                        data: ["source": "refreshClientWithRetry", "error": error.localizedDescription]
                    )
                }
                do {
                    try await Clerk.shared.refreshClient()
                    // Retry succeeded — silent recovery.
                    return .success
                } catch {
                    if ClerkAuthService.isClerk422Error(error) {
                        return .consecutiveClerk422(error)
                    }
                    // Retry produced a non-422 error — treat as a plain failure.
                    return .failed(error)
                }
            }
        }
    }

    /// Centralised 422 detection so both the retry helper and the catch block
    /// agree on what counts as a Clerk 422.
    ///
    /// **Caller contract:** only invoke with errors thrown from
    /// `Clerk.shared.refreshClient()` or `Clerk.shared.session?.getToken()`.
    /// The string fallback below is intentionally broad (it matches any error
    /// whose `localizedDescription` mentions `"status code: 422"`) so it
    /// could yield false positives if used in a wider context.
    ///
    /// Detection strategy (most reliable → least):
    /// 1. `NSError.code == 422` scoped to a Clerk/HTTP-client domain. A bare
    ///    `code == 422` could collide with unrelated network errors from
    ///    other APIs, so the domain check is required.
    /// 2. `localizedDescription` matches Clerk SDK's "status code: 422"
    ///    string. Brittle but currently the only reliable signal the SDK
    ///    exposes; matches what `SyncManager+ErrorClassification` already
    ///    uses.
    static func isClerk422Error(_ error: Error) -> Bool {
        let nsError = error as NSError
        // Domain-scoped code check. We accept domains that *start with*
        // "Clerk" or "ClerkKit" (e.g. "Clerk.ClerkAPIError",
        // "ClerkKit.HTTPClientError") so an unrelated SDK with "HTTPClient"
        // somewhere in its domain string (e.g. "MyLib.HTTPClientError")
        // doesn't get misclassified as Clerk.
        if nsError.code == 422 {
            let domain = nsError.domain
            if domain.hasPrefix("Clerk") || domain.hasPrefix("ClerkKit") {
                return true
            }
        }
        // String fallback — covers the case where the SDK wraps the underlying
        // HTTP error in a struct whose code isn't surfaced through NSError.
        // We intentionally do NOT fall back to `String(describing: error)`
        // because it exposes internal Swift/ObjC representation that the SDK
        // does not document as stable; if `localizedDescription` doesn't match
        // we'd rather miss-detect and fall through than match unrelated errors
        // that happen to mention "status code: 422" in a debug description.
        return error.localizedDescription.contains("status code: 422")
    }

    @MainActor
    private func updateAuthState() {
        isAuthenticated = Clerk.shared.session != nil
        currentUserId = Clerk.shared.user?.id

        if let user = Clerk.shared.user {
            ErrorReportingService.setUser(
                id: user.id,
                email: user.primaryEmailAddress?.emailAddress
            )
        }
    }

    @MainActor
    func signOut() async throws {
        try await Clerk.shared.auth.signOut()
        tearDownSignedOutState()
    }

    /// Shared teardown invoked from both `signOut()` and `handleDeferredSignOut()`.
    /// Keeps the two paths in sync so deferred sign-out doesn't leave Sentry
    /// user context or the session-state stream dangling.
    @MainActor
    private func tearDownSignedOutState() {
        isAuthenticated = false
        currentUserId = nil
        needsReauthentication = false
        ErrorReportingService.clearUser()
        // Clean up the session state change stream
        sessionStateChangeContinuation?.finish()
        sessionStateChangeContinuation = nil
    }

    @MainActor
    func getAuthToken() async throws -> String {
        let session = await MainActor.run { Clerk.shared.session }
        guard let session else {
            throw AuthError.notAuthenticated
        }
        // Use a 30-second expiration buffer (vs the default 10s) to preemptively
        // refresh tokens before they expire during in-flight requests.
        guard let token = try await session.getToken(.init(expirationBuffer: 30)) else {
            throw AuthError.noToken
        }
        return token
    }

    @MainActor
    func forceRefreshAuthToken() async throws -> String {
        let session = await MainActor.run { Clerk.shared.session }
        guard let session else {
            throw AuthError.notAuthenticated
        }
        // Skip the cache entirely — forces a fresh JWT from Clerk's servers.
        // Use this after receiving a 401 to recover from revoked/expired sessions.
        guard let token = try await session.getToken(.init(skipCache: true)) else {
            throw AuthError.noToken
        }
        return token
    }

    // MARK: - Sign In/Up

    @MainActor
    func signIn(email: String, password: String) async throws {
        currentSignIn = try await Clerk.shared.auth.signInWithPassword(identifier: email, password: password)

        // Check if sign-in is complete
        if let sessionId = currentSignIn?.createdSessionId {
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
            updateAuthState()
            currentSignIn = nil
            return
        }

        // Handle different sign-in states
        guard let signIn = currentSignIn else {
            throw AuthError.invalidCredentials
        }

        switch signIn.status {
        case .needsSecondFactor:
            // Prepare second factor verification (Client Trust or 2FA)
            // Get email address ID from supported factors
            if let factors = signIn.supportedSecondFactors, !factors.isEmpty {
                for factor in factors {
                    if let safeIdentifier = factor.safeIdentifier, safeIdentifier.contains("@"),
                       let emailId = factor.emailAddressId {
                        _ = try? await signIn.sendMfaEmailCode(emailAddressId: emailId)
                        break
                    }
                }
            }
            throw AuthError.twoFactorRequired

        case .needsFirstFactor, .needsIdentifier:
            currentSignIn = nil
            throw AuthError.invalidCredentials
        default:
            currentSignIn = nil
            throw AuthError.invalidCredentials
        }
    }

    @MainActor
    func verify2FACode(code: String) async throws {
        guard let signIn = currentSignIn else {
            throw AuthError.verificationFailed
        }

        let result = try await signIn.verifyMfaCode(code, type: .emailCode)

        guard let sessionId = result.createdSessionId else {
            throw AuthError.verificationFailed
        }

        try await Clerk.shared.auth.setActive(sessionId: sessionId)
        currentSignIn = nil
        updateAuthState()
    }

    @MainActor
    func signUp(email: String, password: String) async throws {
        currentSignUp = try await Clerk.shared.auth.signUp(emailAddress: email, password: password)
        try await currentSignUp?.sendEmailCode()
    }

    @MainActor
    func verifyEmail(code: String) async throws {
        guard let signUp = currentSignUp else {
            throw AuthError.verificationFailed
        }
        let result = try await signUp.verifyEmailCode(code)
        if let sessionId = result.createdSessionId {
            try await Clerk.shared.auth.setActive(sessionId: sessionId)
        }
        currentSignUp = nil
        updateAuthState()
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notAuthenticated
    case noToken
    case invalidCredentials
    case verificationFailed
    case twoFactorRequired

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .noToken:
            return "Failed to retrieve authentication token."
        case .invalidCredentials:
            return "Invalid email or password."
        case .verificationFailed:
            return "Email verification failed. Please try again."
        case .twoFactorRequired:
            return "First-time device verification required. Check your email for a verification code to continue."
        }
    }
}

// MARK: - Mock Auth Service (for previews/testing)

@Observable
final class MockAuthService: AuthServiceProtocol {
    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var currentUserId: String?
    var needsReauthentication: Bool = false

    /// Tracks invocations of `refreshSessionIfNeeded(context:)` for tests.
    private(set) var refreshContexts: [AuthContext] = []
    /// Number of times `handleDeferredSignOut()` was *called* (including
    /// early-return cases where `needsReauthentication == false`). Tests use
    /// this as a call-counter, not an operation-counter.
    private(set) var deferredSignOutInvocations: Int = 0

    private let sessionStateChangesStream: AsyncStream<SessionStateChange>
    nonisolated(unsafe) private var sessionStateChangeContinuation: AsyncStream<SessionStateChange>.Continuation?

    var sessionStateChanges: AsyncStream<SessionStateChange> {
        sessionStateChangesStream
    }

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionStateChange.self)
        self.sessionStateChangesStream = stream
        self.sessionStateChangeContinuation = continuation
    }

    deinit {
        sessionStateChangeContinuation?.finish()
    }

    @MainActor
    func configure() async {
        // No-op for mock
    }

    @MainActor
    func signOut() async throws {
        isAuthenticated = false
        currentUserId = nil
        needsReauthentication = false
        sessionStateChangeContinuation?.finish()
        sessionStateChangeContinuation = nil
    }

    @MainActor
    func getAuthToken() async throws -> String {
        guard isAuthenticated else {
            throw AuthError.notAuthenticated
        }
        return "mock-token-\(UUID().uuidString)"
    }

    @MainActor
    func forceRefreshAuthToken() async throws -> String {
        // Same as getAuthToken for mock — no real cache to bypass
        return try await getAuthToken()
    }

    @MainActor
    func refreshSessionIfNeeded(context: AuthContext) async {
        refreshContexts.append(context)
        // No-op for mock
    }

    @MainActor
    func handleDeferredSignOut() async {
        deferredSignOutInvocations += 1
        guard needsReauthentication else { return }
        isAuthenticated = false
        currentUserId = nil
        needsReauthentication = false
    }

    /// For testing: simulate a background refresh deciding the session is dead.
    @MainActor
    func mockNeedsReauthentication() {
        needsReauthentication = true
    }

    // For testing
    @MainActor
    func mockSignIn(userId: String = "mock-user-id") {
        isAuthenticated = true
        currentUserId = userId
    }

    /// For testing: simulate session invalidation
    @MainActor
    func mockSessionInvalidated(reason: SessionInvalidationReason = .revoked) {
        isAuthenticated = false
        currentUserId = nil
        needsReauthentication = false
        sessionStateChangeContinuation?.yield(.sessionInvalidated(reason: reason))
    }

    /// For testing: simulate session restoration
    @MainActor
    func mockSessionRestored(userId: String = "mock-user-id") {
        isAuthenticated = true
        currentUserId = userId
        sessionStateChangeContinuation?.yield(.sessionRestored(userId: userId))
    }

    // MARK: - Auth Flow Methods (for UI testing)

    /// Mock sign in - validates fields and signs in
    @MainActor
    func signIn(email: String, password: String) async throws {
        // Simulate network delay
        try await Task.sleep(for: .milliseconds(500))

        // For testing error states, throw on specific test credentials
        if email == "error@example.com" {
            throw AuthError.invalidCredentials
        }

        // Otherwise succeed
        mockSignIn(userId: "mock-user-\(email)")
    }

    /// Mock sign up - validates fields and creates account
    @MainActor
    func signUp(email: String, password: String) async throws {
        // Simulate network delay
        try await Task.sleep(for: .milliseconds(500))

        // Mock sign up always succeeds (verification required next)
        // Don't auto-sign in - verification needed first
    }

    /// Mock email verification - completes sign up
    @MainActor
    func verifyEmail(code: String) async throws {
        // Simulate network delay
        try await Task.sleep(for: .milliseconds(300))

        // For testing error states
        if code == "000000" {
            throw AuthError.verificationFailed
        }

        // Verification succeeds - sign in
        mockSignIn(userId: "mock-verified-user")
    }

    /// Mock 2FA verification
    @MainActor
    func verify2FACode(code: String) async throws {
        // Simulate network delay
        try await Task.sleep(for: .milliseconds(300))

        // For testing error states
        if code == "000000" {
            throw AuthError.verificationFailed
        }

        // 2FA succeeds - complete sign in
        mockSignIn(userId: "mock-2fa-user")
    }
}
