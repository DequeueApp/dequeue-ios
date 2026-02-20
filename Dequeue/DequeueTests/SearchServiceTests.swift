//
//  SearchServiceTests.swift
//  DequeueTests
//
//  Tests for SearchService - unified search endpoint client
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - Mock URL Protocol for Search Tests

private final class SearchMockURLProtocolStorage: @unchecked Sendable {
    static let shared = SearchMockURLProtocolStorage()
    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); defer { lock.unlock() }; handler = newValue }
    }
}

private final class SearchMockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = SearchMockURLProtocolStorage.shared.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "SearchMock", code: -1))
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
    config.protocolClasses = [SearchMockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Search Service Tests

@Suite("SearchService")
@MainActor
struct SearchServiceTests {
    let mockAuth = MockAuthService()
    let session: URLSession

    init() {
        mockAuth.mockSignIn()
        session = makeMockSession()
    }

    private func makeService() -> SearchService {
        SearchService(authService: mockAuth, urlSession: session)
    }

    private func makeResponse(statusCode: Int, json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.dequeue.app/v1/search")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, json.data(using: .utf8)!)
    }

    // MARK: - Success Cases

    @Test("Search returns tasks and stacks")
    func searchReturnsResults() async throws {
        let json = """
        {
            "query": "test",
            "results": [
                {
                    "type": "task",
                    "task": {
                        "id": "task-1",
                        "stackId": "stack-1",
                        "title": "Test task",
                        "status": "active",
                        "priority": 2,
                        "sortOrder": 0,
                        "isActive": true,
                        "createdAt": 1708000000000,
                        "updatedAt": 1708000000000
                    }
                },
                {
                    "type": "stack",
                    "stack": {
                        "id": "stack-1",
                        "title": "Test stack",
                        "status": "active",
                        "sortOrder": 0,
                        "taskCount": 3,
                        "completedTaskCount": 1,
                        "isActive": true,
                        "createdAt": 1708000000000,
                        "updatedAt": 1708000000000
                    }
                }
            ],
            "total": 2
        }
        """

        SearchMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.url?.absoluteString.contains("search") == true)
            #expect(request.url?.absoluteString.contains("q=test") == true)
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            return self.makeResponse(statusCode: 200, json: json)
        }

        let service = makeService()
        let response = try await service.search(query: "test")

        #expect(response.query == "test")
        #expect(response.total == 2)
        #expect(response.results.count == 2)
        #expect(response.results[0].type == "task")
        #expect(response.results[0].task?.title == "Test task")
        #expect(response.results[0].task?.priority == 2)
        #expect(response.results[1].type == "stack")
        #expect(response.results[1].stack?.title == "Test stack")
        #expect(response.results[1].stack?.taskCount == 3)
        #expect(response.results[1].stack?.progress == 1.0 / 3.0)
    }

    @Test("Search with custom limit")
    func searchWithLimit() async throws {
        let json = """
        {"query": "test", "results": [], "total": 0}
        """

        SearchMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.url?.absoluteString.contains("limit=5") == true)
            return self.makeResponse(statusCode: 200, json: json)
        }

        let service = makeService()
        _ = try await service.search(query: "test", limit: 5)
    }

    @Test("Search returns empty results")
    func searchEmptyResults() async throws {
        let json = """
        {"query": "nonexistent", "results": [], "total": 0}
        """

        SearchMockURLProtocolStorage.shared.requestHandler = { _ in
            self.makeResponse(statusCode: 200, json: json)
        }

        let service = makeService()
        let response = try await service.search(query: "nonexistent")

        #expect(response.results.isEmpty)
        #expect(response.total == 0)
    }

    // MARK: - Validation

    @Test("Search rejects empty query")
    func searchRejectsEmptyQuery() async {
        let service = makeService()
        do {
            _ = try await service.search(query: "")
            #expect(Bool(false), "Should have thrown")
        } catch let error as SearchError {
            if case .emptyQuery = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong SearchError case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("Search rejects whitespace-only query")
    func searchRejectsWhitespaceQuery() async {
        let service = makeService()
        do {
            _ = try await service.search(query: "   ")
            #expect(Bool(false), "Should have thrown")
        } catch let error as SearchError {
            if case .emptyQuery = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong SearchError case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("Search rejects query over 200 characters")
    func searchRejectsLongQuery() async {
        let service = makeService()
        let longQuery = String(repeating: "a", count: 201)
        do {
            _ = try await service.search(query: longQuery)
            #expect(Bool(false), "Should have thrown")
        } catch let error as SearchError {
            if case .queryTooLong = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong SearchError case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    // MARK: - Error Handling

    @Test("Search handles server error")
    func searchHandlesServerError() async {
        SearchMockURLProtocolStorage.shared.requestHandler = { _ in
            self.makeResponse(statusCode: 500, json: "{\"error\": \"Internal error\"}")
        }

        let service = makeService()
        do {
            _ = try await service.search(query: "test")
            #expect(Bool(false), "Should have thrown")
        } catch let error as SearchError {
            if case let .serverError(statusCode, message) = error {
                #expect(statusCode == 500)
                #expect(message == "Internal error")
            } else {
                #expect(Bool(false), "Wrong SearchError case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    // MARK: - Model Tests

    @Test("SearchTask date conversion")
    func searchTaskDates() {
        let task = SearchTask(
            id: "t1", stackId: "s1", title: "Test", notes: nil,
            status: "active", priority: 0, sortOrder: 0, isActive: true,
            dueAt: 1708000000000, blockedReason: nil, parentTaskId: nil,
            createdAt: 1708000000000, updatedAt: 1708000000000, completedAt: nil
        )
        #expect(task.dueAtDate != nil)
        #expect(task.createdAtDate.timeIntervalSince1970 == 1_708_000_000)
    }

    @Test("SearchStack progress calculation")
    func searchStackProgress() {
        let stack = SearchStack(
            id: "s1", arcId: nil, title: "Test", status: "active",
            sortOrder: 0, taskCount: 10, completedTaskCount: 7,
            isActive: true, activeTaskId: nil,
            createdAt: 1708000000000, updatedAt: 1708000000000
        )
        #expect(stack.progress == 0.7)

        let emptyStack = SearchStack(
            id: "s2", arcId: nil, title: "Empty", status: "active",
            sortOrder: 0, taskCount: 0, completedTaskCount: 0,
            isActive: false, activeTaskId: nil,
            createdAt: 1708000000000, updatedAt: 1708000000000
        )
        #expect(emptyStack.progress == 0.0)
    }
}
