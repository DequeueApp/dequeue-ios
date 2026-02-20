//
//  WebhookServiceTests.swift
//  DequeueTests
//
//  Tests for WebhookService - webhook management and delivery log client
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - Mock URL Protocol for Webhook Tests

private final class WebhookMockURLProtocolStorage: @unchecked Sendable {
    static let shared = WebhookMockURLProtocolStorage()
    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); defer { lock.unlock() }; handler = newValue }
    }
}

private final class WebhookMockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = WebhookMockURLProtocolStorage.shared.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "WebhookMock", code: -1))
            return
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

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [WebhookMockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Webhook Service Tests

@Suite("WebhookService")
@MainActor
struct WebhookServiceTests {
    let mockAuth = MockAuthService()
    let session: URLSession
    let service: WebhookService

    init() {
        mockAuth.mockSignIn()
        session = makeMockSession()
        service = WebhookService(authService: mockAuth, urlSession: session)
    }

    // MARK: - List Webhooks

    @Test("List webhooks returns parsed response")
    func listWebhooksSuccess() async throws {
        let json = """
        {
            "data": [
                {
                    "id": "wh_abc123",
                    "url": "https://example.com/webhook",
                    "events": ["task.created", "task.updated"],
                    "secretPrefix": "whsec_abc",
                    "status": "active",
                    "createdAt": 1708300000000,
                    "lastDeliveryAt": 1708310000000,
                    "lastDeliveryStatus": "delivered"
                }
            ],
            "pagination": {
                "nextCursor": null,
                "hasMore": false,
                "limit": 50
            }
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path.contains("webhooks") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await service.listWebhooks()
        #expect(result.data.count == 1)
        #expect(result.data[0].id == "wh_abc123")
        #expect(result.data[0].url == "https://example.com/webhook")
        #expect(result.data[0].events.count == 2)
        #expect(result.data[0].isActive == true)
        #expect(result.data[0].secretPrefix == "whsec_abc")
        #expect(result.pagination.hasMore == false)
    }

    @Test("List webhooks with empty result")
    func listWebhooksEmpty() async throws {
        let json = """
        {
            "data": [],
            "pagination": {"nextCursor": null, "hasMore": false, "limit": 50}
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await service.listWebhooks()
        #expect(result.data.isEmpty)
    }

    @Test("List webhooks passes pagination cursor")
    func listWebhooksWithCursor() async throws {
        let json = """
        {
            "data": [],
            "pagination": {"nextCursor": null, "hasMore": false, "limit": 20}
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.url?.query?.contains("cursor=abc123") == true)
            #expect(request.url?.query?.contains("limit=20") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        _ = try await service.listWebhooks(limit: 20, cursor: "abc123")
    }

    // MARK: - Create Webhook

    @Test("Create webhook returns webhook with secret")
    func createWebhookSuccess() async throws {
        let json = """
        {
            "id": "wh_new123",
            "url": "https://example.com/hook",
            "events": ["task.created"],
            "secret": "whsec_full_secret_shown_once",
            "status": "active",
            "createdAt": 1708300000000
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            let body = try JSONDecoder().decode(CreateWebhookRequest.self, from: request.httpBody!)
            #expect(body.url == "https://example.com/hook")
            #expect(body.events == ["task.created"])
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await service.createWebhook(
            CreateWebhookRequest(url: "https://example.com/hook", events: ["task.created"], secret: nil)
        )
        #expect(result.id == "wh_new123")
        #expect(result.secret == "whsec_full_secret_shown_once")
    }

    // MARK: - Get Webhook

    @Test("Get webhook by ID")
    func getWebhookSuccess() async throws {
        let json = """
        {
            "id": "wh_get123",
            "url": "https://example.com/hook",
            "events": ["task.created", "stack.deleted"],
            "secretPrefix": "whsec_get",
            "status": "active",
            "createdAt": 1708300000000
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path.hasSuffix("wh_get123") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await service.getWebhook(id: "wh_get123")
        #expect(result.id == "wh_get123")
        #expect(result.events.count == 2)
    }

    // MARK: - Delete Webhook

    @Test("Delete webhook succeeds with 204")
    func deleteWebhookSuccess() async throws {
        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.httpMethod == "DELETE")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 204,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        try await service.deleteWebhook(id: "wh_del123")
    }

    @Test("Delete webhook throws not found for 404")
    func deleteWebhookNotFound() async throws {
        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404,
                httpVersion: nil, headerFields: nil
            )!
            return (response, "{}".data(using: .utf8)!)
        }

        await #expect(throws: WebhookError.self) {
            try await service.deleteWebhook(id: "wh_missing")
        }
    }

    // MARK: - Rotate Secret

    @Test("Rotate secret returns new secret")
    func rotateSecretSuccess() async throws {
        let json = """
        {
            "id": "wh_rot123",
            "secret": "whsec_new_rotated_secret",
            "rotatedAt": 1708310000000
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path.contains("rotate-secret") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await service.rotateSecret(id: "wh_rot123")
        #expect(result.secret == "whsec_new_rotated_secret")
        #expect(result.id == "wh_rot123")
    }

    // MARK: - List Deliveries

    @Test("List deliveries returns parsed delivery logs")
    func listDeliveriesSuccess() async throws {
        let json = """
        {
            "data": [
                {
                    "id": "del_abc123",
                    "webhookId": "wh_abc123",
                    "eventType": "task.created",
                    "eventId": "evt_xyz789",
                    "status": "delivered",
                    "attempts": 1,
                    "lastResponseStatus": 200,
                    "lastResponseBody": "OK",
                    "createdAt": 1708310000000,
                    "completedAt": 1708310001000,
                    "lastAttemptAt": 1708310001000
                },
                {
                    "id": "del_def456",
                    "webhookId": "wh_abc123",
                    "eventType": "task.updated",
                    "eventId": "evt_uvw123",
                    "status": "failed",
                    "attempts": 3,
                    "lastResponseStatus": 500,
                    "lastError": "Internal Server Error",
                    "createdAt": 1708309000000,
                    "completedAt": 1708309500000,
                    "lastAttemptAt": 1708309500000
                }
            ],
            "pagination": {
                "nextCursor": "cursor_next",
                "hasMore": true,
                "limit": 20
            }
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path.contains("deliveries") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await service.listDeliveries(webhookId: "wh_abc123", limit: 20)
        #expect(result.data.count == 2)
        #expect(result.data[0].id == "del_abc123")
        #expect(result.data[0].isSuccess == true)
        #expect(result.data[0].isPending == false)
        #expect(result.data[0].lastResponseStatus == 200)
        #expect(result.data[1].id == "del_def456")
        #expect(result.data[1].isFailed == true)
        #expect(result.data[1].attempts == 3)
        #expect(result.data[1].lastError == "Internal Server Error")
        #expect(result.pagination.hasMore == true)
        #expect(result.pagination.nextCursor == "cursor_next")
    }

    @Test("List deliveries with empty result")
    func listDeliveriesEmpty() async throws {
        let json = """
        {
            "data": [],
            "pagination": {"nextCursor": null, "hasMore": false, "limit": 50}
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await service.listDeliveries(webhookId: "wh_abc123")
        #expect(result.data.isEmpty)
    }

    @Test("List deliveries for nonexistent webhook returns 404")
    func listDeliveriesNotFound() async throws {
        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404,
                httpVersion: nil, headerFields: nil
            )!
            return (response, "{}".data(using: .utf8)!)
        }

        await #expect(throws: WebhookError.self) {
            try await service.listDeliveries(webhookId: "wh_missing")
        }
    }

    // MARK: - Test Delivery

    @Test("Test delivery returns success result")
    func testDeliverySuccess() async throws {
        let json = """
        {
            "success": true,
            "responseStatus": 200,
            "responseBody": "OK",
            "durationMs": 142,
            "deliveredAt": 1708310000000
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path.contains("test") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await service.testDelivery(webhookId: "wh_abc123")
        #expect(result.success == true)
        #expect(result.responseStatus == 200)
        #expect(result.responseBody == "OK")
        #expect(result.durationMs == 142)
    }

    @Test("Test delivery returns failure result")
    func testDeliveryFailure() async throws {
        let json = """
        {
            "success": false,
            "error": "connection refused",
            "durationMs": 5001,
            "deliveredAt": 1708310000000
        }
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let result = try await service.testDelivery(webhookId: "wh_abc123")
        #expect(result.success == false)
        #expect(result.error == "connection refused")
        #expect(result.responseStatus == nil)
    }

    // MARK: - Error Handling

    @Test("Server error returns typed error")
    func serverError() async throws {
        let json = """
        {"error": "Rate limit exceeded"}
        """

        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429,
                httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        await #expect(throws: WebhookError.self) {
            try await service.listWebhooks()
        }
    }

    @Test("Auth error when not signed in")
    func authError() async throws {
        WebhookMockURLProtocolStorage.shared.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401,
                httpVersion: nil, headerFields: nil
            )!
            return (response, "{}".data(using: .utf8)!)
        }

        await #expect(throws: WebhookError.self) {
            try await service.listWebhooks()
        }
    }

    // MARK: - Model Tests

    @Test("Webhook model computed properties")
    func webhookModelProperties() {
        let webhook = Webhook(
            id: "wh_1",
            url: "https://example.com",
            events: ["task.created"],
            secret: nil,
            secretPrefix: "whsec_",
            status: "active",
            createdAt: 1708300000000,
            lastDeliveryAt: 1708310000000,
            lastDeliveryStatus: "delivered"
        )
        #expect(webhook.isActive == true)
        #expect(webhook.lastDeliveryAtDate != nil)
        #expect(webhook.createdAtDate.timeIntervalSince1970 > 0)
    }

    @Test("WebhookDelivery model computed properties")
    func deliveryModelProperties() {
        let delivered = WebhookDelivery(
            id: "del_1", webhookId: "wh_1", eventType: "task.created",
            eventId: "evt_1", status: "delivered", attempts: 1,
            lastResponseStatus: 200, lastResponseBody: "OK", lastError: nil,
            createdAt: 1708300000000, completedAt: 1708300001000,
            nextRetryAt: nil, lastAttemptAt: 1708300001000
        )
        #expect(delivered.isSuccess == true)
        #expect(delivered.isPending == false)
        #expect(delivered.isFailed == false)

        let pending = WebhookDelivery(
            id: "del_2", webhookId: "wh_1", eventType: "task.updated",
            eventId: "evt_2", status: "pending", attempts: 0,
            lastResponseStatus: nil, lastResponseBody: nil, lastError: nil,
            createdAt: 1708300000000, completedAt: nil,
            nextRetryAt: 1708300060000, lastAttemptAt: nil
        )
        #expect(pending.isSuccess == false)
        #expect(pending.isPending == true)
        #expect(pending.isFailed == false)
        #expect(pending.nextRetryAtDate != nil)

        let failed = WebhookDelivery(
            id: "del_3", webhookId: "wh_1", eventType: "stack.deleted",
            eventId: "evt_3", status: "failed", attempts: 5,
            lastResponseStatus: 500, lastResponseBody: nil,
            lastError: "Internal Server Error",
            createdAt: 1708300000000, completedAt: 1708300300000,
            nextRetryAt: nil, lastAttemptAt: 1708300300000
        )
        #expect(failed.isSuccess == false)
        #expect(failed.isPending == false)
        #expect(failed.isFailed == true)
    }
}
