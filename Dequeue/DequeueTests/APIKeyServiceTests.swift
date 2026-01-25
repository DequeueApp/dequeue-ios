//
//  APIKeyServiceTests.swift
//  DequeueTests
//
//  Tests for APIKeyService - API key management for external integrations
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - Mock URLSession for Network Tests

/// Mock URLProtocol for intercepting network requests in tests
private class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler not set")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Creates a URLSession configured to use MockURLProtocol
private func makeMockURLSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

@Suite("APIKeyService Tests")
@MainActor
struct APIKeyServiceTests {
    // MARK: - Model Tests

    @Test("APIKey timestamp conversion - createdAtDate converts milliseconds to Date")
    func testAPIKeyCreatedAtDateConversion() {
        let timestamp: Int64 = 1_704_067_200_000 // 2024-01-01 00:00:00 UTC in milliseconds
        let apiKey = APIKey(
            id: "key-123",
            name: "Test Key",
            keyPrefix: "sk_test_",
            scopes: ["read", "write"],
            createdAt: timestamp,
            lastUsedAt: nil
        )

        let expectedDate = Date(timeIntervalSince1970: 1_704_067_200.0)

        // Allow 1ms tolerance for floating point precision
        let difference = abs(apiKey.createdAtDate.timeIntervalSince1970 - expectedDate.timeIntervalSince1970)
        #expect(difference < 0.001)
    }

    @Test("APIKey timestamp conversion - lastUsedAtDate converts milliseconds to Date")
    func testAPIKeyLastUsedAtDateConversion() {
        let createdAt: Int64 = 1_704_067_200_000
        let lastUsedAt: Int64 = 1_704_153_600_000 // 2024-01-02 00:00:00 UTC in milliseconds

        let apiKey = APIKey(
            id: "key-123",
            name: "Test Key",
            keyPrefix: "sk_test_",
            scopes: ["read", "write"],
            createdAt: createdAt,
            lastUsedAt: lastUsedAt
        )

        let expectedDate = Date(timeIntervalSince1970: 1_704_153_600.0)

        guard let lastUsedDate = apiKey.lastUsedAtDate else {
            #expect(Bool(false), "Expected lastUsedAtDate to be non-nil")
            return
        }

        let difference = abs(lastUsedDate.timeIntervalSince1970 - expectedDate.timeIntervalSince1970)
        #expect(difference < 0.001)
    }

    @Test("APIKey timestamp conversion - lastUsedAtDate returns nil when lastUsedAt is nil")
    func testAPIKeyLastUsedAtDateNil() {
        let apiKey = APIKey(
            id: "key-123",
            name: "Test Key",
            keyPrefix: "sk_test_",
            scopes: ["read", "write"],
            createdAt: 1_704_067_200_000,
            lastUsedAt: nil
        )

        #expect(apiKey.lastUsedAtDate == nil)
    }

    @Test("CreateAPIKeyResponse decodes correctly")
    func testCreateAPIKeyResponseDecoding() throws {
        let json = """
        {
            "id": "key-456",
            "name": "Integration Key",
            "key": "sk_live_abc123xyz789",
            "keyPrefix": "sk_live_",
            "scopes": ["read", "write", "admin"],
            "createdAt": 1704067200000
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(CreateAPIKeyResponse.self, from: data)

        #expect(response.id == "key-456")
        #expect(response.name == "Integration Key")
        #expect(response.key == "sk_live_abc123xyz789")
        #expect(response.keyPrefix == "sk_live_")
        #expect(response.scopes == ["read", "write", "admin"])
        #expect(response.createdAt == 1_704_067_200_000)
    }

    @Test("APIKey decodes correctly")
    func testAPIKeyDecoding() throws {
        let json = """
        {
            "id": "key-789",
            "name": "Read Only Key",
            "keyPrefix": "sk_test_",
            "scopes": ["read"],
            "createdAt": 1704067200000,
            "lastUsedAt": 1704153600000
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let apiKey = try decoder.decode(APIKey.self, from: data)

        #expect(apiKey.id == "key-789")
        #expect(apiKey.name == "Read Only Key")
        #expect(apiKey.keyPrefix == "sk_test_")
        #expect(apiKey.scopes == ["read"])
        #expect(apiKey.createdAt == 1_704_067_200_000)
        #expect(apiKey.lastUsedAt == 1_704_153_600_000)
    }

    @Test("APIKey with nil lastUsedAt decodes correctly")
    func testAPIKeyDecodingWithNilLastUsedAt() throws {
        let json = """
        {
            "id": "key-999",
            "name": "Unused Key",
            "keyPrefix": "sk_test_",
            "scopes": ["read"],
            "createdAt": 1704067200000,
            "lastUsedAt": null
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let apiKey = try decoder.decode(APIKey.self, from: data)

        #expect(apiKey.id == "key-999")
        #expect(apiKey.lastUsedAt == nil)
        #expect(apiKey.lastUsedAtDate == nil)
    }

    // MARK: - Service Tests

    @Test("APIKeyService initializes with AuthService")
    func testAPIKeyServiceInitialization() {
        let mockAuth = MockAuthService()
        let service = APIKeyService(authService: mockAuth)

        // Service should initialize without error
        #expect(service != nil)
    }

    // MARK: - Error Tests

    @Test("APIKeyError notAuthenticated has correct description")
    func testAPIKeyErrorNotAuthenticatedDescription() {
        let error = APIKeyError.notAuthenticated
        #expect(error.errorDescription == "You must be signed in to manage API keys.")
    }

    @Test("APIKeyError invalidResponse has correct description")
    func testAPIKeyErrorInvalidResponseDescription() {
        let error = APIKeyError.invalidResponse
        #expect(error.errorDescription == "Received an invalid response from the server.")
    }

    @Test("APIKeyError serverError with message has correct description")
    func testAPIKeyErrorServerErrorWithMessageDescription() {
        let error = APIKeyError.serverError(statusCode: 403, message: "Forbidden")
        #expect(error.errorDescription == "Server error (403): Forbidden")
    }

    @Test("APIKeyError serverError without message has correct description")
    func testAPIKeyErrorServerErrorWithoutMessageDescription() {
        let error = APIKeyError.serverError(statusCode: 500, message: nil)
        #expect(error.errorDescription == "Server error: 500")
    }

    @Test("APIKeyError networkError has correct description")
    func testAPIKeyErrorNetworkErrorDescription() {
        enum TestError: Error {
            case testFailure
        }
        let error = APIKeyError.networkError(TestError.testFailure)
        #expect(error.errorDescription?.contains("Network error") == true)
    }

    // MARK: - Scope Validation Tests

    @Test("APIKey supports multiple scopes")
    func testAPIKeyMultipleScopes() {
        let apiKey = APIKey(
            id: "key-123",
            name: "Multi-scope Key",
            keyPrefix: "sk_test_",
            scopes: ["read", "write", "admin"],
            createdAt: 1_704_067_200_000,
            lastUsedAt: nil
        )

        #expect(apiKey.scopes.count == 3)
        #expect(apiKey.scopes.contains("read"))
        #expect(apiKey.scopes.contains("write"))
        #expect(apiKey.scopes.contains("admin"))
    }

    @Test("APIKey supports single scope")
    func testAPIKeySingleScope() {
        let apiKey = APIKey(
            id: "key-123",
            name: "Read-only Key",
            keyPrefix: "sk_test_",
            scopes: ["read"],
            createdAt: 1_704_067_200_000,
            lastUsedAt: nil
        )

        #expect(apiKey.scopes.count == 1)
        #expect(apiKey.scopes == ["read"])
    }

    @Test("CreateAPIKeyRequest encodes correctly")
    func testCreateAPIKeyRequestEncoding() throws {
        let request = CreateAPIKeyRequest(
            name: "New Integration",
            scopes: ["read", "write"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"name\":\"New Integration\""))
        #expect(json.contains("\"scopes\""))
        #expect(json.contains("\"read\""))
        #expect(json.contains("\"write\""))
    }

    // MARK: - Integration Notes
    //
    // The following scenarios require actual network calls and cannot be reliably
    // unit tested without more complex mocking infrastructure:
    // - listAPIKeys() with real API responses
    // - createAPIKey() with real API responses
    // - revokeAPIKey() with real API responses
    // - Error handling for various HTTP status codes
    // - Authorization header validation
    //
    // These should be tested via:
    // 1. Integration tests with a test backend
    // 2. UI tests that exercise the full flow
    // 3. Manual testing with the staging/production API
    //
    // For comprehensive network testing, we would need to:
    // 1. Create a protocol wrapper for URLSession
    // 2. Inject the wrapper into APIKeyService
    // 3. Create mock implementations for testing
    // 4. Test all HTTP status codes and error cases
}
