//
//  BatchServiceTests.swift
//  DequeueTests
//
//  Tests for BatchService - batch task operations client
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - Mock URL Protocol for Batch Tests

private final class BatchMockURLProtocolStorage: @unchecked Sendable {
    static let shared = BatchMockURLProtocolStorage()
    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private var capturedRequests: [URLRequest] = []

    var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); defer { lock.unlock() }; handler = newValue }
    }

    var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return capturedRequests.last
    }

    func captureRequest(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        capturedRequests.append(request)
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        handler = nil
        capturedRequests = []
    }
}

private final class BatchMockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        BatchMockURLProtocolStorage.shared.captureRequest(request)

        guard let handler = BatchMockURLProtocolStorage.shared.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "BatchMock", code: -1))
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
    config.protocolClasses = [BatchMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeSuccessResponse(
    results: [BatchResultItem],
    succeeded: Int,
    failed: Int,
    totalCount: Int
) -> Data {
    let response = BatchResponse(
        results: results,
        succeeded: succeeded,
        failed: failed,
        totalCount: totalCount
    )
    return try! JSONEncoder().encode(response)
}

private func makeHTTPResponse(statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.dequeue.app/v1/tasks/batch/complete")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

// MARK: - Batch Complete Tests

@Suite("BatchService - Batch Complete")
struct BatchCompleteTests {
    @Test("Successfully completes multiple tasks")
    @MainActor
    func testBatchCompleteSuccess() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        let taskIds = ["task-1", "task-2", "task-3"]
        let responseData = makeSuccessResponse(
            results: taskIds.map { BatchResultItem(taskId: $0, success: true, error: nil) },
            succeeded: 3,
            failed: 0,
            totalCount: 3
        )

        BatchMockURLProtocolStorage.shared.reset()
        BatchMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path.contains("tasks/batch/complete") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            return (makeHTTPResponse(), responseData)
        }

        let response = try await service.batchComplete(taskIds: taskIds)

        #expect(response.succeeded == 3)
        #expect(response.failed == 0)
        #expect(response.totalCount == 3)
        #expect(response.isFullSuccess)
        #expect(!response.isPartialSuccess)
    }

    @Test("Handles partial success")
    @MainActor
    func testBatchCompletePartialSuccess() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        let responseData = makeSuccessResponse(
            results: [
                BatchResultItem(taskId: "task-1", success: true, error: nil),
                BatchResultItem(taskId: "task-2", success: false, error: "Task not found"),
                BatchResultItem(taskId: "task-3", success: true, error: nil)
            ],
            succeeded: 2,
            failed: 1,
            totalCount: 3
        )

        BatchMockURLProtocolStorage.shared.reset()
        BatchMockURLProtocolStorage.shared.requestHandler = { _ in
            (makeHTTPResponse(), responseData)
        }

        let response = try await service.batchComplete(taskIds: ["task-1", "task-2", "task-3"])

        #expect(response.succeeded == 2)
        #expect(response.failed == 1)
        #expect(!response.isFullSuccess)
        #expect(response.isPartialSuccess)
        #expect(response.results[1].error == "Task not found")
    }

    @Test("Sends correct request body")
    @MainActor
    func testBatchCompleteRequestBody() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        let responseData = makeSuccessResponse(
            results: [BatchResultItem(taskId: "task-1", success: true, error: nil)],
            succeeded: 1,
            failed: 0,
            totalCount: 1
        )

        BatchMockURLProtocolStorage.shared.reset()
        BatchMockURLProtocolStorage.shared.requestHandler = { request in
            // Verify request body contains taskIds
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let taskIds = json["taskIds"] as? [String] {
                #expect(taskIds == ["task-1"])
            } else {
                Issue.record("Request body missing taskIds")
            }
            return (makeHTTPResponse(), responseData)
        }

        _ = try await service.batchComplete(taskIds: ["task-1"])
    }
}

// MARK: - Batch Move Tests

@Suite("BatchService - Batch Move")
struct BatchMoveTests {
    @Test("Successfully moves tasks to target stack")
    @MainActor
    func testBatchMoveSuccess() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        let taskIds = ["task-1", "task-2"]
        let responseData = makeSuccessResponse(
            results: taskIds.map { BatchResultItem(taskId: $0, success: true, error: nil) },
            succeeded: 2,
            failed: 0,
            totalCount: 2
        )

        BatchMockURLProtocolStorage.shared.reset()
        BatchMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.url?.path.contains("tasks/batch/move") == true)

            // Verify toStackId in body
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                #expect(json["toStackId"] as? String == "stack-target")
                #expect((json["taskIds"] as? [String])?.count == 2)
            }
            return (makeHTTPResponse(), responseData)
        }

        let response = try await service.batchMove(taskIds: taskIds, toStackId: "stack-target")

        #expect(response.succeeded == 2)
        #expect(response.isFullSuccess)
    }

    @Test("Rejects empty toStackId")
    @MainActor
    func testBatchMoveEmptyStackId() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        BatchMockURLProtocolStorage.shared.reset()

        await #expect(throws: BatchError.self) {
            try await service.batchMove(taskIds: ["task-1"], toStackId: "")
        }
    }
}

// MARK: - Batch Delete Tests

@Suite("BatchService - Batch Delete")
struct BatchDeleteTests {
    @Test("Successfully deletes multiple tasks")
    @MainActor
    func testBatchDeleteSuccess() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        let taskIds = ["task-1", "task-2", "task-3"]
        let responseData = makeSuccessResponse(
            results: taskIds.map { BatchResultItem(taskId: $0, success: true, error: nil) },
            succeeded: 3,
            failed: 0,
            totalCount: 3
        )

        BatchMockURLProtocolStorage.shared.reset()
        BatchMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.url?.path.contains("tasks/batch/delete") == true)
            return (makeHTTPResponse(), responseData)
        }

        let response = try await service.batchDelete(taskIds: taskIds)

        #expect(response.succeeded == 3)
        #expect(response.isFullSuccess)
    }
}

// MARK: - Validation Tests

@Suite("BatchService - Validation")
struct BatchValidationTests {
    @Test("Rejects empty task IDs")
    @MainActor
    func testEmptyTaskIds() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        BatchMockURLProtocolStorage.shared.reset()

        await #expect(throws: BatchError.self) {
            try await service.batchComplete(taskIds: [])
        }
    }

    @Test("Rejects batch exceeding max size")
    @MainActor
    func testBatchTooLarge() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        let oversizedBatch = (0...100).map { "task-\($0)" } // 101 items

        BatchMockURLProtocolStorage.shared.reset()

        await #expect(throws: BatchError.self) {
            try await service.batchComplete(taskIds: oversizedBatch)
        }
    }

    @Test("Rejects duplicate task IDs")
    @MainActor
    func testDuplicateTaskIds() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        BatchMockURLProtocolStorage.shared.reset()

        await #expect(throws: BatchError.self) {
            try await service.batchComplete(taskIds: ["task-1", "task-2", "task-1"])
        }
    }

    @Test("Accepts maximum batch size (100 tasks)")
    @MainActor
    func testMaxBatchSize() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        let taskIds = (1...100).map { "task-\($0)" }
        let responseData = makeSuccessResponse(
            results: taskIds.map { BatchResultItem(taskId: $0, success: true, error: nil) },
            succeeded: 100,
            failed: 0,
            totalCount: 100
        )

        BatchMockURLProtocolStorage.shared.reset()
        BatchMockURLProtocolStorage.shared.requestHandler = { _ in
            (makeHTTPResponse(), responseData)
        }

        let response = try await service.batchComplete(taskIds: taskIds)
        #expect(response.succeeded == 100)
    }
}

// MARK: - Error Handling Tests

@Suite("BatchService - Error Handling")
struct BatchErrorHandlingTests {
    @Test("Handles server error responses")
    @MainActor
    func testServerError() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        BatchMockURLProtocolStorage.shared.reset()
        BatchMockURLProtocolStorage.shared.requestHandler = { _ in
            let errorBody = try! JSONSerialization.data(withJSONObject: ["error": "Internal server error"])
            return (makeHTTPResponse(statusCode: 500), errorBody)
        }

        await #expect(throws: BatchError.self) {
            try await service.batchComplete(taskIds: ["task-1"])
        }
    }

    @Test("Handles 401 unauthorized")
    @MainActor
    func testUnauthorized() async throws {
        let mockAuth = MockAuthService()
        // Not signed in
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        BatchMockURLProtocolStorage.shared.reset()

        do {
            _ = try await service.batchComplete(taskIds: ["task-1"])
            Issue.record("Expected auth error")
        } catch {
            // Expected: auth error from getAuthToken()
            #expect(error is AuthError)
        }
    }

    @Test("Handles network errors")
    @MainActor
    func testNetworkError() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        BatchMockURLProtocolStorage.shared.reset()
        BatchMockURLProtocolStorage.shared.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        await #expect(throws: BatchError.self) {
            try await service.batchComplete(taskIds: ["task-1"])
        }
    }

    @Test("Handles 400 bad request")
    @MainActor
    func testBadRequest() async throws {
        let mockAuth = MockAuthService()
        mockAuth.mockSignIn(userId: "user-1")
        let session = makeMockSession()
        let service = BatchService(authService: mockAuth, urlSession: session)

        BatchMockURLProtocolStorage.shared.reset()
        BatchMockURLProtocolStorage.shared.requestHandler = { _ in
            let errorBody = try! JSONSerialization.data(withJSONObject: ["error": "taskIds must not be empty"])
            return (makeHTTPResponse(statusCode: 400), errorBody)
        }

        await #expect(throws: BatchError.self) {
            try await service.batchComplete(taskIds: ["task-1"])
        }
    }
}

// MARK: - Model Tests

@Suite("BatchService - Models")
struct BatchModelTests {
    @Test("BatchResponse correctly identifies full success")
    func testFullSuccess() {
        let response = BatchResponse(
            results: [BatchResultItem(taskId: "t1", success: true, error: nil)],
            succeeded: 1,
            failed: 0,
            totalCount: 1
        )
        #expect(response.isFullSuccess)
        #expect(!response.isPartialSuccess)
    }

    @Test("BatchResponse correctly identifies partial success")
    func testPartialSuccess() {
        let response = BatchResponse(
            results: [
                BatchResultItem(taskId: "t1", success: true, error: nil),
                BatchResultItem(taskId: "t2", success: false, error: "Not found")
            ],
            succeeded: 1,
            failed: 1,
            totalCount: 2
        )
        #expect(!response.isFullSuccess)
        #expect(response.isPartialSuccess)
    }

    @Test("BatchResponse correctly identifies full failure")
    func testFullFailure() {
        let response = BatchResponse(
            results: [
                BatchResultItem(taskId: "t1", success: false, error: "Error")
            ],
            succeeded: 0,
            failed: 1,
            totalCount: 1
        )
        #expect(!response.isFullSuccess)
        #expect(!response.isPartialSuccess) // Not partial if none succeeded
    }

    @Test("BatchResultItem is identifiable by taskId")
    func testResultItemIdentity() {
        let item = BatchResultItem(taskId: "task-42", success: true, error: nil)
        #expect(item.id == "task-42")
    }

    @Test("BatchError provides meaningful descriptions")
    func testErrorDescriptions() {
        let errors: [BatchError] = [
            .emptyTaskIds,
            .batchTooLarge(count: 150, max: 100),
            .duplicateTaskIds,
            .missingTargetStack,
            .serverError(statusCode: 500, message: "Internal error"),
            .serverError(statusCode: 503, message: nil),
            .notAuthenticated,
            .invalidResponse,
        ]

        for error in errors {
            #expect(error.errorDescription != nil, "Error \(error) should have a description")
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}
