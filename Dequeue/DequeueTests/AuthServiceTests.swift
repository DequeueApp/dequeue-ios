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

        do {
            _ = try await mockAuth.getAuthToken()
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as AuthError {
            #expect(error == .notAuthenticated)
        } catch {
            #expect(Bool(false), "Wrong error type thrown")
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
