//
//  AuthService.swift
//  Dequeue
//
//  Authentication service wrapping Clerk SDK
//

import Foundation
import SwiftUI
import Clerk

// MARK: - Auth Service Protocol

@MainActor
protocol AuthServiceProtocol {
    /// Whether the user is currently authenticated with a valid session
    var isAuthenticated: Bool { get }
    /// Whether the auth state is still being determined during app launch
    var isLoading: Bool { get }
    /// The unique identifier of the currently authenticated user, if any
    var currentUserId: String? { get }

    func configure() async
    func signOut() async throws
    func getAuthToken() async throws -> String
    func refreshSessionIfNeeded() async
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
        await Clerk.shared.configure(publishableKey: Configuration.clerkPublishableKey)

        // Step 2: Check cached session immediately (no network call)
        // Clerk SDK may have persisted session from previous app launch
        updateAuthState()

        // Step 3: Allow UI to proceed immediately - don't block on network
        isLoading = false

        // Step 4: Refresh session from network in background (non-blocking)
        // This validates the session is still valid server-side and refreshes tokens
        // Cancel any existing refresh task to prevent race conditions
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = Task {
            await refreshSessionInBackground()
        }
    }

    /// Refreshes session from Clerk servers in background.
    ///
    /// This is non-blocking and respects network availability:
    /// - If offline, does nothing (trusts cached session)
    /// - If online, validates session with Clerk servers
    /// - Updates auth state if session was invalidated server-side
    /// - Errors are logged but don't crash the app (graceful degradation)
    @MainActor
    private func refreshSessionInBackground() async {
        // Check network status - don't attempt if offline
        guard NetworkMonitor.shared.isConnected else {
            return
        }

        // Attempt to load/refresh session from Clerk servers
        // This validates the session is still valid and refreshes tokens
        do {
            try await Clerk.shared.load()
        } catch {
            // Log error for debugging but don't crash - degrade gracefully
            ErrorReportingService.capture(
                error: error,
                context: ["source": "session_refresh", "offline_mode": !NetworkMonitor.shared.isConnected]
            )
        }

        // Update auth state in case session was invalidated server-side
        updateAuthState()
    }

    /// Called when app becomes active to refresh session if needed.
    ///
    /// This ensures that when returning from background or when network
    /// becomes available, we validate the session is still valid.
    /// Throttles refreshes to avoid excessive network calls on rapid app state changes.
    @MainActor
    func refreshSessionIfNeeded() async {
        // Throttle refreshes to avoid excessive network calls
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < refreshThrottleInterval {
            return
        }

        lastRefreshTime = Date()
        await refreshSessionInBackground()
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
        try await Clerk.shared.signOut()
        isAuthenticated = false
        currentUserId = nil
        ErrorReportingService.clearUser()
    }

    @MainActor
    func getAuthToken() async throws -> String {
        let session = await MainActor.run { Clerk.shared.session }
        guard let session else {
            throw AuthError.notAuthenticated
        }
        guard let token = try await session.getToken()?.jwt else {
            throw AuthError.noToken
        }
        return token
    }

    // MARK: - Sign In/Up

    @MainActor
    func signIn(email: String, password: String) async throws {
        currentSignIn = try await SignIn.create(strategy: .identifier(email, password: password))

        // Check if sign-in is complete
        if let sessionId = currentSignIn?.createdSessionId {
            try await Clerk.shared.setActive(sessionId: sessionId)
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
                        try? await signIn.prepareSecondFactor(strategy: .emailCode(emailAddressId: emailId))
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

        let result = try await signIn.attemptSecondFactor(strategy: .emailCode(code: code))

        guard let sessionId = result.createdSessionId else {
            throw AuthError.verificationFailed
        }

        try await Clerk.shared.setActive(sessionId: sessionId)
        currentSignIn = nil
        updateAuthState()
    }

    @MainActor
    func signUp(email: String, password: String) async throws {
        currentSignUp = try await SignUp.create(
            strategy: .standard(emailAddress: email, password: password)
        )
        try await currentSignUp?.prepareVerification(strategy: .emailCode)
    }

    @MainActor
    func verifyEmail(code: String) async throws {
        guard let signUp = currentSignUp else {
            throw AuthError.verificationFailed
        }
        let result = try await signUp.attemptVerification(strategy: .emailCode(code: code))
        if let sessionId = result.createdSessionId {
            try await Clerk.shared.setActive(sessionId: sessionId)
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

    func configure() async {
        // No-op for mock
    }

    func signOut() async throws {
        isAuthenticated = false
        currentUserId = nil
    }

    func getAuthToken() async throws -> String {
        guard isAuthenticated else {
            throw AuthError.notAuthenticated
        }
        return "mock-token-\(UUID().uuidString)"
    }

    func refreshSessionIfNeeded() async {
        // No-op for mock
    }

    // For testing
    func mockSignIn(userId: String = "mock-user-id") {
        isAuthenticated = true
        currentUserId = userId
    }
}
