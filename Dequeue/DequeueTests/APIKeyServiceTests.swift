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

/// Thread-safe storage for the mock request handler
/// Uses a lock to ensure visibility across threads (MainActor -> URLSession background thread)
private final class MockURLProtocolStorage: @unchecked Sendable {
    static let shared = MockURLProtocolStorage()
    
    private let lock = NSLock()
    private var _requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _requestHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _requestHandler = newValue
        }
    }
}

/// Mock URLProtocol for intercepting network requests in tests
private final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocolStorage.shared.requestHandler else {
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

    @Test("APIKeyService accepts custom URLSession for testing")
    func testAPIKeyServiceCustomURLSession() {
        let mockAuth = MockAuthService()
        let customSession = makeMockURLSession()
        let service = APIKeyService(authService: mockAuth, urlSession: customSession)

        // Service should initialize with custom URLSession without error
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

    // MARK: - Input Validation Tests

    @Test("createAPIKey throws error for empty name")
    func testCreateAPIKeyEmptyNameThrows() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let service = APIKeyService(authService: mockAuth, urlSession: makeMockURLSession())

        await #expect(throws: APIKeyError.self) {
            _ = try await service.createAPIKey(name: "", scopes: ["read"])
        }
    }

    @Test("createAPIKey throws error for name exceeding max length")
    func testCreateAPIKeyNameTooLongThrows() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let service = APIKeyService(authService: mockAuth, urlSession: makeMockURLSession())

        let longName = String(repeating: "a", count: 65)

        await #expect(throws: APIKeyError.self) {
            _ = try await service.createAPIKey(name: longName, scopes: ["read"])
        }
    }

    @Test("createAPIKey throws error for invalid characters in name")
    func testCreateAPIKeyInvalidCharactersThrows() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let service = APIKeyService(authService: mockAuth, urlSession: makeMockURLSession())

        await #expect(throws: APIKeyError.self) {
            _ = try await service.createAPIKey(name: "test<script>", scopes: ["read"])
        }
    }

    @Test("createAPIKey throws error for empty scopes")
    func testCreateAPIKeyEmptyScopesThrows() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let service = APIKeyService(authService: mockAuth, urlSession: makeMockURLSession())

        await #expect(throws: APIKeyError.self) {
            _ = try await service.createAPIKey(name: "Test Key", scopes: [])
        }
    }

    @Test("createAPIKey throws error for invalid scope values")
    func testCreateAPIKeyInvalidScopesThrows() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let service = APIKeyService(authService: mockAuth, urlSession: makeMockURLSession())

        await #expect(throws: APIKeyError.self) {
            _ = try await service.createAPIKey(name: "Test Key", scopes: ["read", "delete"])
        }
    }

    @Test("createAPIKey accepts valid name and scopes")
    func testCreateAPIKeyValidInput() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let json = """
            {
                "id": "key-123",
                "name": "Valid Key",
                "key": "sk_live_abc123",
                "keyPrefix": "sk_live_",
                "scopes": ["read", "write"],
                "createdAt": 1704067200000
            }
            """
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)
        let result = try await service.createAPIKey(name: "Valid Key", scopes: ["read", "write"])

        #expect(result.id == "key-123")
        #expect(result.name == "Valid Key")
    }

    // MARK: - Network Tests

    @Test("listAPIKeys returns keys on success")
    func testListAPIKeysSuccess() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let json = """
            [
                {
                    "id": "key-1",
                    "name": "First Key",
                    "keyPrefix": "sk_test_",
                    "scopes": ["read"],
                    "createdAt": 1704067200000,
                    "lastUsedAt": null
                },
                {
                    "id": "key-2",
                    "name": "Second Key",
                    "keyPrefix": "sk_live_",
                    "scopes": ["read", "write"],
                    "createdAt": 1704153600000,
                    "lastUsedAt": 1704240000000
                }
            ]
            """
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)
        let keys = try await service.listAPIKeys()

        #expect(keys.count == 2)
        #expect(keys[0].id == "key-1")
        #expect(keys[0].name == "First Key")
        #expect(keys[1].id == "key-2")
        #expect(keys[1].scopes == ["read", "write"])
    }

    @Test("listAPIKeys handles 401 unauthorized")
    func testListAPIKeysUnauthorized() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let json = """
            {"error": "Invalid token"}
            """
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)

        do {
            _ = try await service.listAPIKeys()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as APIKeyError {
            if case let .serverError(statusCode, message) = error {
                #expect(statusCode == 401)
                #expect(message == "Invalid token")
            } else {
                #expect(Bool(false), "Expected serverError, got \(error)")
            }
        }
    }

    @Test("listAPIKeys handles 403 forbidden")
    func testListAPIKeysForbidden() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let json = """
            {"error": "Access denied"}
            """
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)

        do {
            _ = try await service.listAPIKeys()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as APIKeyError {
            if case let .serverError(statusCode, message) = error {
                #expect(statusCode == 403)
                #expect(message == "Access denied")
            } else {
                #expect(Bool(false), "Expected serverError, got \(error)")
            }
        }
    }

    @Test("listAPIKeys handles 500 server error")
    func testListAPIKeysServerError() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let json = """
            {"error": "Internal server error"}
            """
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)

        do {
            _ = try await service.listAPIKeys()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as APIKeyError {
            if case let .serverError(statusCode, _) = error {
                #expect(statusCode == 500)
            } else {
                #expect(Bool(false), "Expected serverError, got \(error)")
            }
        }
    }

    @Test("createAPIKey returns key response on success")
    func testCreateAPIKeySuccess() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let json = """
            {
                "id": "key-new",
                "name": "My New Key",
                "key": "sk_live_secretkey123456",
                "keyPrefix": "sk_live_",
                "scopes": ["read", "write"],
                "createdAt": 1704067200000
            }
            """
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)
        let result = try await service.createAPIKey(name: "My New Key", scopes: ["read", "write"])

        #expect(result.id == "key-new")
        #expect(result.name == "My New Key")
        #expect(result.key == "sk_live_secretkey123456")
        #expect(result.keyPrefix == "sk_live_")
        #expect(result.scopes == ["read", "write"])
    }

    @Test("createAPIKey handles 401 unauthorized")
    func testCreateAPIKeyUnauthorized() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let json = """
            {"error": "Authentication required"}
            """
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)

        do {
            _ = try await service.createAPIKey(name: "Test Key", scopes: ["read"])
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as APIKeyError {
            if case let .serverError(statusCode, message) = error {
                #expect(statusCode == 401)
                #expect(message == "Authentication required")
            } else {
                #expect(Bool(false), "Expected serverError, got \(error)")
            }
        }
    }

    @Test("revokeAPIKey succeeds with 200 response")
    func testRevokeAPIKeySuccess() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)

        // Should not throw
        try await service.revokeAPIKey(id: "key-to-revoke")
    }

    @Test("revokeAPIKey succeeds with 204 no content")
    func testRevokeAPIKeyNoContent() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)

        // Should not throw
        try await service.revokeAPIKey(id: "key-123")
    }

    @Test("revokeAPIKey handles 404 not found")
    func testRevokeAPIKeyNotFound() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let json = """
            {"error": "API key not found"}
            """
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)

        do {
            try await service.revokeAPIKey(id: "nonexistent-key")
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as APIKeyError {
            if case let .serverError(statusCode, message) = error {
                #expect(statusCode == 404)
                #expect(message == "API key not found")
            } else {
                #expect(Bool(false), "Expected serverError, got \(error)")
            }
        }
    }

    @Test("revokeAPIKey handles 403 forbidden")
    func testRevokeAPIKeyForbidden() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn()
        let mockSession = makeMockURLSession()

        MockURLProtocolStorage.shared.requestHandler = { _ in
            let json = """
            {"error": "Cannot revoke this key"}
            """
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let service = APIKeyService(authService: mockAuth, urlSession: mockSession)

        do {
            try await service.revokeAPIKey(id: "protected-key")
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as APIKeyError {
            if case let .serverError(statusCode, _) = error {
                #expect(statusCode == 403)
            } else {
                #expect(Bool(false), "Expected serverError, got \(error)")
            }
        }
    }

    @Test("APIKeyError invalidKeyName has correct description")
    func testAPIKeyErrorInvalidKeyNameDescription() {
        let error = APIKeyError.invalidKeyName("Name cannot be empty")
        #expect(error.errorDescription == "Invalid key name: Name cannot be empty")
    }

    @Test("APIKeyError invalidScopes has correct description")
    func testAPIKeyErrorInvalidScopesDescription() {
        let error = APIKeyError.invalidScopes("Invalid scopes: delete")
        #expect(error.errorDescription == "Invalid scopes: Invalid scopes: delete")
    }

    @Test("APIKeyService.validScopes contains expected values")
    func testValidScopesContainsExpectedValues() {
        #expect(APIKeyService.validScopes.contains("read"))
        #expect(APIKeyService.validScopes.contains("write"))
        #expect(APIKeyService.validScopes.contains("admin"))
        #expect(APIKeyService.validScopes.count == 3)
    }
}
