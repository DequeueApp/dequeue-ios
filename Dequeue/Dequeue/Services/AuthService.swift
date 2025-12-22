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

protocol AuthServiceProtocol {
    var isAuthenticated: Bool { get }
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

    // Cache auth state to avoid repeated Clerk SDK calls on every view render
    private(set) var isAuthenticated: Bool = false
    private(set) var currentUserId: String?

    func configure() async {
        Clerk.shared.configure(publishableKey: Configuration.clerkPublishableKey)
        try? await Clerk.shared.load()

        updateAuthState()
    }

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
        guard let session = Clerk.shared.session else {
            throw AuthError.notAuthenticated
        }
        guard let token = try await session.getToken()?.jwt else {
            throw AuthError.noToken
        }
        return token
    }

    // MARK: - Sign In/Up

    func signIn(email: String, password: String) async throws {
        let signIn = try await SignIn.create(strategy: .identifier(email, password: password))
        if let sessionId = signIn.createdSessionId {
            try await Clerk.shared.setActive(sessionId: sessionId)
        }
        updateAuthState()
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
        updateAuthState()
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notAuthenticated
    case noToken
    case invalidCredentials
    case verificationFailed

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
        }
    }
}

// MARK: - Mock Auth Service (for previews/testing)

@Observable
final class MockAuthService: AuthServiceProtocol {
    var isAuthenticated: Bool = false
    var currentUserId: String? = nil

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
