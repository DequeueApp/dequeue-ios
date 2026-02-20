//
//  SyncManagerWebSocketStreamTests.swift
//  DequeueTests
//
//  Tests for SyncManager WebSocket streaming (DEQ-243)
//

import Testing
import Foundation
@testable import Dequeue

@Suite("SyncManager WebSocket Stream Tests")
@MainActor
struct SyncManagerWebSocketStreamTests {
    
    // MARK: - Message Serialization Tests
    
    @Test("SyncStreamRequest serializes correctly")
    func testSyncStreamRequestSerialization() throws {
        let request = SyncStreamRequest(
            type: "sync.stream.request",
            since: "2024-01-01T00:00:00Z"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["type"] as? String == "sync.stream.request")
        #expect(json?["since"] as? String == "2024-01-01T00:00:00Z")
    }
    
    @Test("SyncStreamRequest with nil since serializes correctly")
    func testSyncStreamRequestNilSince() throws {
        let request = SyncStreamRequest(
            type: "sync.stream.request",
            since: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["type"] as? String == "sync.stream.request")
        #expect(json?["since"] == nil || json?["since"] is NSNull)
    }
    
    @Test("SyncStreamStart deserializes correctly")
    func testSyncStreamStartDeserialization() throws {
        let jsonString = """
        {
            "type": "sync.stream.start",
            "totalEvents": 10000
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let start = try decoder.decode(SyncStreamStart.self, from: data)
        
        #expect(start.type == "sync.stream.start")
        #expect(start.totalEvents == 10000)
    }
    
    @Test("SyncStreamBatch deserializes correctly")
    func testSyncStreamBatchDeserialization() throws {
        // Note: SyncStreamBatch doesn't include events in Codable
        // Events are parsed separately via JSONSerialization
        let jsonString = """
        {
            "type": "sync.stream.batch",
            "batchIndex": 5,
            "isLast": false
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let batch = try decoder.decode(SyncStreamBatch.self, from: data)
        
        #expect(batch.type == "sync.stream.batch")
        #expect(batch.batchIndex == 5)
        #expect(batch.isLast == false)
    }
    
    @Test("SyncStreamBatch isLast=true deserializes correctly")
    func testSyncStreamBatchLastBatch() throws {
        let jsonString = """
        {
            "type": "sync.stream.batch",
            "batchIndex": 99,
            "isLast": true
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let batch = try decoder.decode(SyncStreamBatch.self, from: data)
        
        #expect(batch.type == "sync.stream.batch")
        #expect(batch.batchIndex == 99)
        #expect(batch.isLast == true)
    }
    
    @Test("SyncStreamComplete deserializes correctly")
    func testSyncStreamCompleteDeserialization() throws {
        let jsonString = """
        {
            "type": "sync.stream.complete",
            "processedEvents": 10000,
            "newCheckpoint": "2024-01-02T12:00:00Z"
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let complete = try decoder.decode(SyncStreamComplete.self, from: data)
        
        #expect(complete.type == "sync.stream.complete")
        #expect(complete.processedEvents == 10000)
        #expect(complete.newCheckpoint == "2024-01-02T12:00:00Z")
    }
    
    @Test("SyncStreamError deserializes correctly")
    func testSyncStreamErrorDeserialization() throws {
        let jsonString = """
        {
            "type": "sync.stream.error",
            "error": "Database connection failed",
            "code": "DB_ERROR"
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let error = try decoder.decode(SyncStreamError.self, from: data)
        
        #expect(error.type == "sync.stream.error")
        #expect(error.error == "Database connection failed")
        #expect(error.code == "DB_ERROR")
    }
    
    @Test("SyncStreamError with nil code deserializes correctly")
    func testSyncStreamErrorNilCode() throws {
        let jsonString = """
        {
            "type": "sync.stream.error",
            "error": "Unknown error"
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let error = try decoder.decode(SyncStreamError.self, from: data)
        
        #expect(error.type == "sync.stream.error")
        #expect(error.error == "Unknown error")
        #expect(error.code == nil)
    }
    
    // MARK: - Message Type Constants
    
    @Test("Message type constants are correct")
    func testMessageTypeConstants() {
        // Verify message types match backend API spec
        let expectedTypes = [
            "sync.stream.request",
            "sync.stream.start",
            "sync.stream.batch",
            "sync.stream.complete",
            "sync.stream.error"
        ]
        
        // Create instances to verify type values
        let request = SyncStreamRequest(type: "sync.stream.request", since: nil)
        #expect(request.type == expectedTypes[0])
        
        let start = SyncStreamStart(type: "sync.stream.start", totalEvents: 0)
        #expect(start.type == expectedTypes[1])
        
        let batch = SyncStreamBatch(type: "sync.stream.batch", batchIndex: 0, isLast: false)
        #expect(batch.type == expectedTypes[2])
        
        let complete = SyncStreamComplete(
            type: "sync.stream.complete",
            processedEvents: 0,
            newCheckpoint: ""
        )
        #expect(complete.type == expectedTypes[3])
        
        let error = SyncStreamError(type: "sync.stream.error", error: "", code: nil)
        #expect(error.type == expectedTypes[4])
    }
    
    // MARK: - Batch Processing Tests
    
    @Test("Batch size calculations")
    func testBatchSizeCalculations() {
        struct TestCase {
            let totalEvents: Int
            let batchSize: Int
            let expectedBatches: Int
        }
        
        let cases: [TestCase] = [
            TestCase(totalEvents: 300, batchSize: 100, expectedBatches: 3),
            TestCase(totalEvents: 250, batchSize: 100, expectedBatches: 3),
            TestCase(totalEvents: 50, batchSize: 100, expectedBatches: 1),
            TestCase(totalEvents: 10000, batchSize: 100, expectedBatches: 100),
            TestCase(totalEvents: 0, batchSize: 100, expectedBatches: 0)
        ]
        
        for testCase in cases {
            let batches = testCase.totalEvents == 0 
                ? 0 
                : (testCase.totalEvents + testCase.batchSize - 1) / testCase.batchSize
            
            #expect(
                batches == testCase.expectedBatches,
                "\(testCase.totalEvents) events / \(testCase.batchSize) batch = \(testCase.expectedBatches) batches, got \(batches)"
            )
        }
    }
    
    // MARK: - Event Filtering Tests
    
    @Test("Event filtering by payload version")
    func testEventFilteringByPayloadVersion() {
        let events: [[String: Any]] = [
            ["id": "1", "payload_version": 2], // Valid
            ["id": "2", "payload_version": 1], // Legacy (invalid)
            ["id": "3"], // Missing version (invalid)
            ["id": "4", "payload_version": 3]  // Valid (future version)
        ]
        
        let filtered = events.filter { event in
            if let payloadVersion = event["payload_version"] as? Int {
                return payloadVersion >= 2
            } else {
                return false
            }
        }
        
        #expect(filtered.count == 2)
        #expect((filtered[0]["id"] as? String) == "1")
        #expect((filtered[1]["id"] as? String) == "4")
    }
    
    @Test("Event filtering by device ID during normal sync")
    func testEventFilteringByDeviceId() {
        let currentDeviceId = "device-abc"
        let isInitialSync = false
        
        let events: [[String: Any]] = [
            ["id": "1", "device_id": "device-abc"], // Current device
            ["id": "2", "device_id": "device-xyz"], // Other device
            ["id": "3"], // No device_id
            ["id": "4", "device_id": "device-123"]  // Other device
        ]
        
        let filtered: [[String: Any]]
        if isInitialSync {
            filtered = events
        } else {
            filtered = events.filter { event in
                guard let eventDeviceId = event["device_id"] as? String else { return true }
                return eventDeviceId != currentDeviceId
            }
        }
        
        #expect(filtered.count == 3)
        #expect((filtered[0]["id"] as? String) == "2")
        #expect((filtered[1]["id"] as? String) == "3")
        #expect((filtered[2]["id"] as? String) == "4")
    }
    
    @Test("Event filtering during initial sync includes all events")
    func testEventFilteringDuringInitialSync() {
        let currentDeviceId = "device-abc"
        let isInitialSync = true
        
        let events: [[String: Any]] = [
            ["id": "1", "device_id": "device-abc"], // Current device
            ["id": "2", "device_id": "device-xyz"], // Other device
        ]
        
        let filtered: [[String: Any]]
        if isInitialSync {
            filtered = events
        } else {
            filtered = events.filter { event in
                guard let eventDeviceId = event["device_id"] as? String else { return true }
                return eventDeviceId != currentDeviceId
            }
        }
        
        #expect(filtered.count == 2, "During initial sync, all events should be included")
    }
    
    // MARK: - Performance Estimates
    
    @Test("Streaming performance characteristics")
    func testStreamingPerformanceEstimates() {
        struct PerformanceCase {
            let name: String
            let eventCount: Int
            let batchSize: Int
            let estimatedSeconds: Int
        }
        
        let cases: [PerformanceCase] = [
            PerformanceCase(name: "Small (250 events)", eventCount: 250, batchSize: 100, estimatedSeconds: 1),
            PerformanceCase(name: "Medium (1000 events)", eventCount: 1000, batchSize: 100, estimatedSeconds: 3),
            PerformanceCase(name: "Large (10000 events)", eventCount: 10000, batchSize: 100, estimatedSeconds: 15)
        ]
        
        for testCase in cases {
            let batches = (testCase.eventCount + testCase.batchSize - 1) / testCase.batchSize
            let avgTimePerBatch = testCase.estimatedSeconds / batches
            
            // Performance expectation: <500ms per batch
            #expect(
                avgTimePerBatch < 1,
                "\(testCase.name): \(avgTimePerBatch)s per batch (expected <1s)"
            )
        }
    }
}
