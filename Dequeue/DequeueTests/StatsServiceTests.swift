//
//  StatsServiceTests.swift
//  DequeueTests
//
//  Tests for StatsService - task statistics endpoint client
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - Mock URL Protocol for Stats Tests

private final class StatsMockURLProtocolStorage: @unchecked Sendable {
    static let shared = StatsMockURLProtocolStorage()
    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); defer { lock.unlock() }; handler = newValue }
    }
}

private final class StatsMockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StatsMockURLProtocolStorage.shared.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "StatsMock", code: -1))
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
    config.protocolClasses = [StatsMockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Stats Service Tests

@Suite("StatsService")
@MainActor
struct StatsServiceTests {
    let mockAuth = MockAuthService()
    let session: URLSession

    init() {
        mockAuth.mockSignIn()
        session = makeMockSession()
    }

    private func makeService() -> StatsService {
        StatsService(authService: mockAuth, urlSession: session)
    }

    private func makeResponse(statusCode: Int, json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.dequeue.app/v1/me/stats")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, json.data(using: .utf8)!)
    }

    // MARK: - Success Cases

    @Test("GetStats returns complete statistics")
    func getStatsReturnsData() async throws {
        let json = """
        {
            "tasks": {
                "total": 50,
                "active": 15,
                "completed": 30,
                "overdue": 5,
                "completedToday": 3,
                "completedThisWeek": 12,
                "createdToday": 2,
                "createdThisWeek": 8
            },
            "priority": {
                "none": 5,
                "low": 3,
                "medium": 4,
                "high": 3
            },
            "stacks": {
                "total": 10,
                "active": 6,
                "totalArcs": 3
            },
            "completionStreak": 7
        }
        """

        StatsMockURLProtocolStorage.shared.requestHandler = { request in
            #expect(request.url?.absoluteString.contains("me/stats") == true)
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            return self.makeResponse(statusCode: 200, json: json)
        }

        let service = makeService()
        let stats = try await service.getStats()

        // Task stats
        #expect(stats.tasks.total == 50)
        #expect(stats.tasks.active == 15)
        #expect(stats.tasks.completed == 30)
        #expect(stats.tasks.overdue == 5)
        #expect(stats.tasks.completedToday == 3)
        #expect(stats.tasks.completedThisWeek == 12)
        #expect(stats.tasks.createdToday == 2)
        #expect(stats.tasks.createdThisWeek == 8)

        // Completion rate
        #expect(stats.tasks.completionRate == 0.6) // 30/50

        // Priority breakdown
        #expect(stats.priority.none == 5)
        #expect(stats.priority.low == 3)
        #expect(stats.priority.medium == 4)
        #expect(stats.priority.high == 3)
        #expect(stats.priority.total == 15)

        // Stack stats
        #expect(stats.stacks.total == 10)
        #expect(stats.stacks.active == 6)
        #expect(stats.stacks.totalArcs == 3)

        // Streak
        #expect(stats.completionStreak == 7)
    }

    @Test("GetStats handles zero tasks")
    func getStatsHandlesZeroTasks() async throws {
        let json = """
        {
            "tasks": {
                "total": 0, "active": 0, "completed": 0, "overdue": 0,
                "completedToday": 0, "completedThisWeek": 0,
                "createdToday": 0, "createdThisWeek": 0
            },
            "priority": {"none": 0, "low": 0, "medium": 0, "high": 0},
            "stacks": {"total": 0, "active": 0, "totalArcs": 0},
            "completionStreak": 0
        }
        """

        StatsMockURLProtocolStorage.shared.requestHandler = { _ in
            self.makeResponse(statusCode: 200, json: json)
        }

        let service = makeService()
        let stats = try await service.getStats()

        #expect(stats.tasks.total == 0)
        #expect(stats.tasks.completionRate == 0.0)
        #expect(stats.priority.total == 0)
    }

    // MARK: - Error Handling

    @Test("GetStats handles server error")
    func getStatsHandlesServerError() async {
        StatsMockURLProtocolStorage.shared.requestHandler = { _ in
            self.makeResponse(statusCode: 500, json: "{\"error\": \"Database unavailable\"}")
        }

        let service = makeService()
        do {
            _ = try await service.getStats()
            #expect(Bool(false), "Should have thrown")
        } catch let error as StatsError {
            if case let .serverError(statusCode, message) = error {
                #expect(statusCode == 500)
                #expect(message == "Database unavailable")
            } else {
                #expect(Bool(false), "Wrong StatsError case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("GetStats handles unauthorized")
    func getStatsHandlesUnauthorized() async {
        StatsMockURLProtocolStorage.shared.requestHandler = { _ in
            self.makeResponse(statusCode: 401, json: "{\"error\": \"Invalid token\"}")
        }

        let service = makeService()
        do {
            _ = try await service.getStats()
            #expect(Bool(false), "Should have thrown")
        } catch let error as StatsError {
            if case let .serverError(statusCode, _) = error {
                #expect(statusCode == 401)
            } else {
                #expect(Bool(false), "Wrong StatsError case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    // MARK: - Model Tests

    @Test("TaskStats completionRate calculation")
    func taskStatsCompletionRate() {
        let stats = TaskStats(
            total: 100, active: 20, completed: 80, overdue: 0,
            completedToday: 5, completedThisWeek: 20,
            createdToday: 2, createdThisWeek: 10
        )
        #expect(stats.completionRate == 0.8)
    }

    @Test("PriorityBreakdown total calculation")
    func priorityBreakdownTotal() {
        let priority = PriorityBreakdown(none: 10, low: 5, medium: 3, high: 2)
        #expect(priority.total == 20)
    }
}
