//
//  ExportServiceTests.swift
//  DequeueTests
//
//  Tests for ExportService - data export endpoint client
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - Mock URL Protocol for Export Tests
// Uses a per-session UUID key to avoid shared-state races when tests run in parallel.

private final class ExportMockRegistry: @unchecked Sendable {
    static let shared = ExportMockRegistry()
    private let lock = NSLock()
    private var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    func set(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data), forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        handlers[key] = handler
    }

    func get(forKey key: String) -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock(); defer { lock.unlock() }
        return handlers[key]
    }

    func remove(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        handlers.removeValue(forKey: key)
    }
}

private let exportMockSessionKey = "X-Export-Mock-Session-ID"

private final class ExportMockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let sessionID = request.value(forHTTPHeaderField: exportMockSessionKey) ?? ""
        guard let handler = ExportMockRegistry.shared.get(forKey: sessionID) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "ExportMock", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No handler for session \(sessionID)"]))
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

private func makeMockSession(id: String) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ExportMockURLProtocol.self]
    config.httpAdditionalHeaders = [exportMockSessionKey: id]
    return URLSession(configuration: config)
}

// MARK: - Export Service Tests

@Suite("ExportService")
@MainActor
struct ExportServiceTests {
    let mockAuth = MockAuthService()
    let session: URLSession
    let sessionID: String

    init() {
        mockAuth.mockSignIn()
        sessionID = UUID().uuidString
        session = makeMockSession(id: sessionID)
    }

    private func makeService() -> ExportService {
        ExportService(authService: mockAuth, urlSession: session)
    }

    private func makeResponse(statusCode: Int, json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.dequeue.app/v1/export")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, json.data(using: .utf8)!)
    }

    // MARK: - Success Cases

    @Test("ExportData returns complete export")
    func exportDataReturnsAll() async throws {
        let json = """
        {
            "exportedAt": 1708000000000,
            "version": "1.0",
            "arcs": [
                {
                    "id": "arc-1",
                    "title": "My Arc",
                    "status": "active",
                    "sortOrder": 0,
                    "stackCount": 3,
                    "completedStackCount": 1,
                    "createdAt": 1708000000000,
                    "updatedAt": 1708000000000
                }
            ],
            "stacks": [
                {
                    "id": "stack-1",
                    "title": "My Stack",
                    "status": "active",
                    "sortOrder": 0,
                    "taskCount": 5,
                    "completedTaskCount": 2,
                    "tags": ["tag-1"],
                    "isActive": true,
                    "createdAt": 1708000000000,
                    "updatedAt": 1708000000000
                }
            ],
            "tasks": [
                {
                    "id": "task-1",
                    "stackId": "stack-1",
                    "title": "My Task",
                    "status": "active",
                    "priority": 2,
                    "sortOrder": 0,
                    "isActive": true,
                    "createdAt": 1708000000000,
                    "updatedAt": 1708000000000
                }
            ],
            "tags": [
                {
                    "id": "tag-1",
                    "name": "Important",
                    "colorHex": "#FF0000",
                    "createdAt": 1708000000000,
                    "updatedAt": 1708000000000
                }
            ],
            "reminders": [
                {
                    "id": "rem-1",
                    "parentType": "stack",
                    "parentId": "stack-1",
                    "status": "pending",
                    "remindAt": 1709000000000,
                    "createdAt": 1708000000000,
                    "updatedAt": 1708000000000
                }
            ]
        }
        """

        ExportMockRegistry.shared.set({ request in
            #expect(request.url?.absoluteString.contains("export") == true)
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            return self.makeResponse(statusCode: 200, json: json)
        }, forKey: sessionID)
        defer { ExportMockRegistry.shared.remove(forKey: sessionID) }

        let service = makeService()
        let export = try await service.exportData()

        #expect(export.version == "1.0")
        #expect(export.arcs.count == 1)
        #expect(export.stacks.count == 1)
        #expect(export.tasks.count == 1)
        #expect(export.tags.count == 1)
        #expect(export.reminders.count == 1)
        #expect(export.totalItems == 5)

        // Verify arc data
        #expect(export.arcs[0].title == "My Arc")
        #expect(export.arcs[0].stackCount == 3)

        // Verify stack data
        #expect(export.stacks[0].title == "My Stack")
        #expect(export.stacks[0].tags == ["tag-1"])

        // Verify task data
        #expect(export.tasks[0].title == "My Task")
        #expect(export.tasks[0].priority == 2)

        // Verify tag data
        #expect(export.tags[0].name == "Important")
        #expect(export.tags[0].colorHex == "#FF0000")

        // Verify reminder data
        #expect(export.reminders[0].parentType == "stack")
        #expect(export.reminders[0].parentId == "stack-1")
        #expect(export.reminders[0].status == "pending")
        #expect(export.reminders[0].snoozedFrom == nil)
    }

    @Test("ExportData decodes snoozed reminder with snoozedFrom")
    func exportDataDecodesSnoozedReminder() async throws {
        let json = """
        {
            "exportedAt": 1708000000000,
            "version": "1.0",
            "arcs": [],
            "stacks": [],
            "tasks": [],
            "tags": [],
            "reminders": [
                {
                    "id": "rem-2",
                    "parentType": "task",
                    "parentId": "task-1",
                    "status": "snoozed",
                    "remindAt": 1709100000000,
                    "snoozedFrom": 1709000000000,
                    "createdAt": 1708000000000,
                    "updatedAt": 1709000000000
                }
            ]
        }
        """

        ExportMockRegistry.shared.set({ _ in self.makeResponse(statusCode: 200, json: json) }, forKey: sessionID)
        defer { ExportMockRegistry.shared.remove(forKey: sessionID) }

        let service = makeService()
        let export = try await service.exportData()

        #expect(export.reminders.count == 1)
        let reminder = export.reminders[0]
        #expect(reminder.status == "snoozed")
        #expect(reminder.parentType == "task")
        #expect(reminder.snoozedFrom == 1_709_000_000_000)
        #expect(reminder.snoozedFromDate?.timeIntervalSince1970 == 1_709_000_000)
    }

    @Test("ExportData handles empty export")
    func exportDataHandlesEmpty() async throws {
        let json = """
        {
            "exportedAt": 1708000000000,
            "version": "1.0",
            "arcs": [],
            "stacks": [],
            "tasks": [],
            "tags": [],
            "reminders": []
        }
        """

        ExportMockRegistry.shared.set({ _ in self.makeResponse(statusCode: 200, json: json) }, forKey: sessionID)
        defer { ExportMockRegistry.shared.remove(forKey: sessionID) }

        let service = makeService()
        let export = try await service.exportData()

        #expect(export.arcs.isEmpty)
        #expect(export.stacks.isEmpty)
        #expect(export.tasks.isEmpty)
        #expect(export.tags.isEmpty)
        #expect(export.reminders.isEmpty)
        #expect(export.totalItems == 0)
    }

    @Test("ExportToFile creates JSON file")
    func exportToFileCreatesFile() async throws {
        let json = """
        {
            "exportedAt": 1708000000000,
            "version": "1.0",
            "arcs": [],
            "stacks": [],
            "tasks": [],
            "tags": [],
            "reminders": []
        }
        """

        ExportMockRegistry.shared.set({ _ in self.makeResponse(statusCode: 200, json: json) }, forKey: sessionID)
        defer { ExportMockRegistry.shared.remove(forKey: sessionID) }

        let service = makeService()
        let fileURL = try await service.exportToFile()

        #expect(fileURL.pathExtension == "json")
        #expect(fileURL.lastPathComponent.hasPrefix("dequeue-export-"))
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Verify file content is valid JSON
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(ExportResponse.self, from: data)
        #expect(decoded.version == "1.0")

        // Clean up
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Error Handling

    @Test("ExportData handles server error")
    func exportDataHandlesServerError() async {
        ExportMockRegistry.shared.set({ _ in
            self.makeResponse(statusCode: 500, json: "{\"error\": \"Export failed\"}")
        }, forKey: sessionID)
        defer { ExportMockRegistry.shared.remove(forKey: sessionID) }

        let service = makeService()
        do {
            _ = try await service.exportData()
            #expect(Bool(false), "Should have thrown")
        } catch let error as ExportError {
            if case let .serverError(statusCode, message) = error {
                #expect(statusCode == 500)
                #expect(message == "Export failed")
            } else {
                #expect(Bool(false), "Wrong ExportError case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    // MARK: - Model Tests

    @Test("ExportResponse date conversion")
    func exportResponseDate() {
        let timestamp: Int64 = 1708000000000
        let export = ExportResponse(
            exportedAt: timestamp, version: "1.0",
            arcs: [], stacks: [], tasks: [], tags: [], reminders: []
        )
        #expect(export.exportedAtDate.timeIntervalSince1970 == 1_708_000_000)
    }

    @Test("ReminderExport date conversion")
    func reminderExportDate() {
        let reminder = ReminderExport(
            id: "r1", parentType: "stack", parentId: "s1",
            status: "pending", remindAt: 1709000000000, snoozedFrom: nil,
            createdAt: 1708000000000, updatedAt: 1708000000000
        )
        #expect(reminder.remindAtDate.timeIntervalSince1970 == 1_709_000_000)
        #expect(reminder.snoozedFromDate == nil)
    }

    @Test("ReminderExport snoozedFrom date conversion")
    func reminderExportSnoozedFromDate() {
        let reminder = ReminderExport(
            id: "r2", parentType: "task", parentId: "t1",
            status: "snoozed", remindAt: 1709100000000, snoozedFrom: 1709000000000,
            createdAt: 1708000000000, updatedAt: 1709000000000
        )
        #expect(reminder.snoozedFromDate?.timeIntervalSince1970 == 1_709_000_000)
    }
}
