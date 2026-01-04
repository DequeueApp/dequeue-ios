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

protocol AuthServiceProtocol: Sendable {
    /// Whether the user is currently authenticated with a valid session
    var isAuthenticated: Bool { get }
    /// Whether the auth state is still being determined during app launch
    var isLoading: Bool { get }
    /// The unique identifier of the currently authenticated user, if any
    var currentUserId: String? { get }

    func configure() async
    func signOut() async throws
    func getAuthToken() async throws -> String
}

// MARK: - Clerk Auth Service

/// Production auth service using Clerk SDK
@Observable
final class ClerkAuthService: AuthServiceProtocol {
    private var currentSignUp: SignUp?
    private var currentSignIn: SignIn?

    // Cache auth state to avoid repeated Clerk SDK calls on every view render
    private(set) var isAuthenticated: Bool = false
    private(set) var isLoading: Bool = true
    private(set) var currentUserId: String?

    func configure() async {
        await Clerk.shared.configure(publishableKey: Configuration.clerkPublishableKey)
        try? await Clerk.shared.load()

        await updateAuthState()
        await MainActor.run { isLoading = false }
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

    func signOut() async throws {
        try await Clerk.shared.signOut()
        isAuthenticated = false
        currentUserId = nil
        ErrorReportingService.clearUser()
    }

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

    func signIn(email: String, password: String) async throws {
        currentSignIn = try await SignIn.create(strategy: .identifier(email, password: password))

        // Check if sign-in is complete
        if let sessionId = currentSignIn?.createdSessionId {
            try await Clerk.shared.setActive(sessionId: sessionId)
            await updateAuthState()
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
        await updateAuthState()
    }

    func signUp(email: String, password: String) async throws {
        currentSignUp = try await SignUp.create(
            strategy: .standard(emailAddress: email, password: password)
        )
        try await currentSignUp?.prepareVerification(strategy: .emailCode)
    }

    func verifyEmail(code: String) async throws {
        guard let signUp = currentSignUp else {
            throw AuthError.verificationFailed
        }
        let result = try await signUp.attemptVerification(strategy: .emailCode(code: code))
        if let sessionId = result.createdSessionId {
            try await Clerk.shared.setActive(sessionId: sessionId)
        }
        currentSignUp = nil
        await updateAuthState()
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

    // For testing
    func mockSignIn(userId: String = "mock-user-id") {
        isAuthenticated = true
        currentUserId = userId
    }
}
