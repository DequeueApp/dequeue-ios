//
//  AuthServiceTests.swift
//  DequeueTests
//
//  Tests for AuthService protocol and implementations
//

import Testing
import Foundation
@testable import Dequeue

@Suite("AuthService Tests")
@MainActor
struct AuthServiceTests {
    @Test("MockAuthService initializes with default state")
    func testMockAuthServiceInitialState() async {
        let mockAuth = MockAuthService()

        #expect(mockAuth.isAuthenticated == false)
        #expect(mockAuth.isLoading == false)
        #expect(mockAuth.currentUserId == nil)
    }

    @Test("MockAuthService can mock sign in")
    func testMockAuthServiceSignIn() async {
        let mockAuth = MockAuthService()

        mockAuth.mockSignIn(userId: "test-user-123")

        #expect(mockAuth.isAuthenticated == true)
        #expect(mockAuth.currentUserId == "test-user-123")
    }

    @Test("MockAuthService can sign out")
    func testMockAuthServiceSignOut() async throws {
        let mockAuth = MockAuthService()

        // Sign in first
        mockAuth.mockSignIn(userId: "test-user-123")
        #expect(mockAuth.isAuthenticated == true)

        // Sign out
        try await mockAuth.signOut()

        #expect(mockAuth.isAuthenticated == false)
        #expect(mockAuth.currentUserId == nil)
    }

    @Test("MockAuthService getAuthToken throws when not authenticated")
    func testMockAuthServiceTokenWhenNotAuthenticated() async {
        let mockAuth = MockAuthService()

        await #expect(throws: AuthError.notAuthenticated) {
            try await mockAuth.getAuthToken()
        }
    }

    @Test("MockAuthService getAuthToken returns token when authenticated")
    func testMockAuthServiceTokenWhenAuthenticated() async throws {
        let mockAuth = MockAuthService()

        mockAuth.mockSignIn(userId: "test-user-123")

        let token = try await mockAuth.getAuthToken()

        #expect(token.starts(with: "mock-token-"))
    }

    @Test("MockAuthService configure does not throw")
    func testMockAuthServiceConfigure() async {
        let mockAuth = MockAuthService()

        await mockAuth.configure()

        // Should complete without error
        #expect(mockAuth.isLoading == false)
    }

    @Test("MockAuthService refreshSessionIfNeeded does not throw")
    func testMockAuthServiceRefreshSession() async {
        let mockAuth = MockAuthService()

        await mockAuth.refreshSessionIfNeeded()

        // Should complete without error - no-op for mock
        #expect(mockAuth.isAuthenticated == false)
    }

    @Test("MockAuthService can simulate session invalidation")
    func testMockAuthServiceSessionInvalidation() async {
        let mockAuth = MockAuthService()

        // Sign in first
        mockAuth.mockSignIn(userId: "test-user-123")
        #expect(mockAuth.isAuthenticated == true)

        // Simulate session invalidation
        mockAuth.mockSessionInvalidated(reason: .revoked)

        #expect(mockAuth.isAuthenticated == false)
        #expect(mockAuth.currentUserId == nil)
    }

    @Test("MockAuthService can simulate session restoration")
    func testMockAuthServiceSessionRestoration() async {
        let mockAuth = MockAuthService()

        // Start unauthenticated
        #expect(mockAuth.isAuthenticated == false)

        // Simulate session restoration
        mockAuth.mockSessionRestored(userId: "restored-user-456")

        #expect(mockAuth.isAuthenticated == true)
        #expect(mockAuth.currentUserId == "restored-user-456")
    }

    @Test("MockAuthService forceRefreshAuthToken returns token when authenticated")
    func testMockAuthServiceForceRefreshTokenWhenAuthenticated() async throws {
        let mockAuth = MockAuthService()

        mockAuth.mockSignIn(userId: "test-user-123")

        let token = try await mockAuth.forceRefreshAuthToken()

        #expect(token.starts(with: "mock-token-"))
    }

    @Test("MockAuthService forceRefreshAuthToken throws when not authenticated")
    func testMockAuthServiceForceRefreshTokenWhenNotAuthenticated() async {
        let mockAuth = MockAuthService()

        await #expect(throws: AuthError.notAuthenticated) {
            try await mockAuth.forceRefreshAuthToken()
        }
    }

    // MARK: - Sign In / Sign Up Flow Tests

    @Test("MockAuthService signIn with valid credentials succeeds")
    func testMockAuthServiceSignInSuccess() async throws {
        let mockAuth = MockAuthService()

        try await mockAuth.signIn(email: "user@example.com", password: "password123")

        #expect(mockAuth.isAuthenticated == true)
        #expect(mockAuth.currentUserId != nil)
    }

    @Test("MockAuthService signIn with error credentials throws invalidCredentials")
    func testMockAuthServiceSignInError() async {
        let mockAuth = MockAuthService()

        await #expect(throws: AuthError.invalidCredentials) {
            try await mockAuth.signIn(email: "error@example.com", password: "any")
        }

        #expect(mockAuth.isAuthenticated == false)
    }

    @Test("MockAuthService signUp does not auto-sign-in (requires verification)")
    func testMockAuthServiceSignUpDoesNotAutoSignIn() async throws {
        let mockAuth = MockAuthService()

        // signUp should not throw, and should NOT auto-authenticate —
        // email verification is required before the session is created.
        try await mockAuth.signUp(email: "new@example.com", password: "password123")

        #expect(mockAuth.isAuthenticated == false)
    }

    @Test("MockAuthService verifyEmail with valid code completes sign-up and signs in")
    func testMockAuthServiceVerifyEmailSuccess() async throws {
        let mockAuth = MockAuthService()

        // First sign up to initialize pending state
        try await mockAuth.signUp(email: "new@example.com", password: "password123")
        #expect(mockAuth.isAuthenticated == false)

        // Verify with any non-error code
        try await mockAuth.verifyEmail(code: "123456")

        #expect(mockAuth.isAuthenticated == true)
        #expect(mockAuth.currentUserId != nil)
    }

    @Test("MockAuthService verifyEmail with error code '000000' throws verificationFailed")
    func testMockAuthServiceVerifyEmailError() async {
        let mockAuth = MockAuthService()

        await #expect(throws: AuthError.verificationFailed) {
            try await mockAuth.verifyEmail(code: "000000")
        }
    }

    @Test("MockAuthService verify2FACode with valid code signs in")
    func testMockAuthServiceVerify2FACodeSuccess() async throws {
        let mockAuth = MockAuthService()

        try await mockAuth.verify2FACode(code: "654321")

        #expect(mockAuth.isAuthenticated == true)
        #expect(mockAuth.currentUserId != nil)
    }

    @Test("MockAuthService verify2FACode with error code '000000' throws verificationFailed")
    func testMockAuthServiceVerify2FACodeError() async {
        let mockAuth = MockAuthService()

        await #expect(throws: AuthError.verificationFailed) {
            try await mockAuth.verify2FACode(code: "000000")
        }
    }

    // MARK: - AuthError Description Tests

    @Test("AuthError.notAuthenticated has descriptive message")
    func testAuthErrorNotAuthenticatedDescription() {
        let error = AuthError.notAuthenticated
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("AuthError.noToken has descriptive message")
    func testAuthErrorNoTokenDescription() {
        let error = AuthError.noToken
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("AuthError.invalidCredentials has descriptive message")
    func testAuthErrorInvalidCredentialsDescription() {
        let error = AuthError.invalidCredentials
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test("AuthError.twoFactorRequired mentions verification")
    func testAuthErrorTwoFactorRequiredDescription() {
        let error = AuthError.twoFactorRequired
        #expect(error.errorDescription?.contains("verification") == true)
    }

    @Test("AuthError cases are distinct from each other")
    func testAuthErrorEquality() {
        // Verify each case is distinguishable from the others (enum Equatable semantics)
        #expect(AuthError.notAuthenticated != AuthError.noToken)
        #expect(AuthError.notAuthenticated != AuthError.invalidCredentials)
        #expect(AuthError.notAuthenticated != AuthError.verificationFailed)
        #expect(AuthError.notAuthenticated != AuthError.twoFactorRequired)
        #expect(AuthError.noToken != AuthError.invalidCredentials)
        #expect(AuthError.invalidCredentials != AuthError.verificationFailed)
        #expect(AuthError.verificationFailed != AuthError.twoFactorRequired)
    }

    // MARK: - Session State Changes Stream

    @Test("MockAuthService sessionStateChanges stream emits invalidation event")
    func testMockAuthServiceSessionStateChangesInvalidation() async {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "test-user")

        // Start listening to session changes
        let changesTask = Task { () -> SessionStateChange? in
            for await change in mockAuth.sessionStateChanges {
                return change
            }
            return nil
        }

        // Give the stream time to start
        try? await Task.sleep(for: .milliseconds(10))

        // Trigger invalidation
        mockAuth.mockSessionInvalidated(reason: .expired)

        // Wait for the event
        let change = await changesTask.value

        guard let change else {
            Issue.record("Expected to receive a session state change")
            return
        }

        if case .sessionInvalidated(let reason) = change {
            #expect(reason == .expired)
        } else {
            Issue.record("Expected sessionInvalidated event, got: \(change)")
        }
    }

    @Test("MockAuthService sessionStateChanges stream emits restoration event")
    func testMockAuthServiceSessionStateChangesRestoration() async {
        let mockAuth = MockAuthService()
        // Start unauthenticated

        // Start listening to session changes
        let changesTask = Task { () -> SessionStateChange? in
            for await change in mockAuth.sessionStateChanges {
                return change
            }
            return nil
        }

        // Give the stream time to start
        try? await Task.sleep(for: .milliseconds(10))

        // Trigger restoration
        mockAuth.mockSessionRestored(userId: "restored-user-789")

        // Wait for the event
        let change = await changesTask.value

        guard let change else {
            Issue.record("Expected to receive a session state change")
            return
        }

        if case .sessionRestored(let userId) = change {
            #expect(userId == "restored-user-789")
        } else {
            Issue.record("Expected sessionRestored event, got: \(change)")
        }
    }

    @Test("MockAuthService signOut finishes session state changes stream")
    func testMockAuthServiceSignOutFinishesStream() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")

        var receivedChanges: [SessionStateChange] = []
        let streamTask = Task {
            for await change in mockAuth.sessionStateChanges {
                receivedChanges.append(change)
            }
        }

        // Give stream time to start
        try? await Task.sleep(for: .milliseconds(10))

        // Sign out — should finish the stream
        try await mockAuth.signOut()

        // Wait for stream to complete
        await streamTask.value

        // Stream ended (signOut calls continuation?.finish())
        #expect(mockAuth.isAuthenticated == false)
        // signOut finishes the stream without emitting a state-change event
        #expect(receivedChanges.isEmpty, "Expected no state-change events during signOut")
    }

    // MARK: - ClerkAuthService Integration Test Notes
    //
    // The following scenarios require Clerk SDK configuration and network access,
    // and cannot be unit tested reliably without mocking the Clerk SDK:
    // - configure() with real Clerk SDK
    // - refreshSessionInBackground() network calls
    // - Session refresh throttling behavior
    // - Race condition handling with backgroundRefreshTask
    // - Error logging via ErrorReportingService
    //
    // These should be tested via integration tests or manual testing with a
    // configured Clerk environment. To add these tests, we would need to:
    // 1. Create a protocol wrapper for Clerk SDK
    // 2. Inject the wrapper into ClerkAuthService
    // 3. Create mock implementations for testing
    //
    // For now, the offline-first behavior can be validated through:
    // - Manual testing with network on/off
    // - UI tests that simulate offline/online scenarios
}
