//
//  AuthService.swift
//  Dequeue
//
//  Authentication service wrapping Clerk SDK
//

import Foundation
import SwiftUI

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
/// Uncomment ClerkSDK import and implementation after adding the package
@Observable
final class ClerkAuthService: AuthServiceProtocol {
    // import ClerkSDK

    var isAuthenticated: Bool {
        // return Clerk.shared.session != nil
        return _isAuthenticated
    }

    var currentUserId: String? {
        // return Clerk.shared.user?.id
        return _currentUserId
    }

    // Temporary state until Clerk SDK is added
    private var _isAuthenticated = false
    private var _currentUserId: String?

    func configure() async {
        // Clerk.shared.configure(publishableKey: Configuration.clerkPublishableKey)
        // try? await Clerk.shared.load()
    }

    func signOut() async throws {
        // try await Clerk.shared.signOut()
        _isAuthenticated = false
        _currentUserId = nil
    }

    func getAuthToken() async throws -> String {
        // guard let session = Clerk.shared.session else {
        //     throw AuthError.notAuthenticated
        // }
        // guard let token = try await session.getToken()?.jwt else {
        //     throw AuthError.noToken
        // }
        // return token
        throw AuthError.notAuthenticated
    }

    // MARK: - Sign In/Up (to be implemented with Clerk)

    func signIn(email: String, password: String) async throws {
        // let signIn = try await SignIn.create(strategy: .identifier(email, password: password))
        // if let session = signIn.createdSession {
        //     try await Clerk.shared.setSession(session)
        // }
        throw AuthError.notImplemented
    }

    func signUp(email: String, password: String) async throws {
        // let signUp = try await SignUp.create(strategy: .standard(emailAddress: email, password: password))
        // try await signUp.prepareVerification(strategy: .emailCode)
        throw AuthError.notImplemented
    }

    func verifyEmail(code: String) async throws {
        // let session = try await currentSignUp?.attemptVerification(.emailCode(code: code))
        // if let session {
        //     try await Clerk.shared.setSession(session)
        // }
        throw AuthError.notImplemented
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notAuthenticated
    case noToken
    case invalidCredentials
    case verificationFailed
    case notImplemented

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
        case .notImplemented:
            return "This feature requires Clerk SDK to be configured."
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
