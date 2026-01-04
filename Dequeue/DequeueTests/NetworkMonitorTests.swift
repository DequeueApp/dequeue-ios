//
//  NetworkMonitorTests.swift
//  DequeueTests
//
//  Tests for NetworkMonitor connectivity tracking
//

import Testing
import Foundation
import Network
@testable import Dequeue

@Suite("NetworkMonitor Tests")
@MainActor
struct NetworkMonitorTests {

    @Test("NetworkMonitor initializes with default connected state")
    func testInitialState() async {
        let monitor = NetworkMonitor()
        defer { monitor.stopMonitoring() }

        // Should start with connected state (optimistic default)
        #expect(monitor.isConnected == true)

        // Connection type is nil initially, gets populated after first path update
        #expect(monitor.connectionType == nil)
    }

    @Test("NetworkMonitor shared instance is consistent")
    func testSharedInstance() async {
        let monitor1 = NetworkMonitor.shared
        let monitor2 = NetworkMonitor.shared

        // Should be the same instance (singleton pattern)
        #expect(monitor1 === monitor2)
    }

    @Test("NetworkMonitor properties are observable")
    func testObservability() async {
        let monitor = NetworkMonitor()
        defer { monitor.stopMonitoring() }

        // Properties should be accessible without crashing
        let connected = monitor.isConnected
        let connectionType = monitor.connectionType

        // Verify initial state - connected true, connectionType nil
        #expect(connected == true)
        #expect(connectionType == nil)
    }

    @Test("NetworkMonitor can be stopped")
    func testStopMonitoring() async {
        let monitor = NetworkMonitor()

        // Should not crash when stopping
        monitor.stopMonitoring()

        // Properties should still be readable after stopping
        #expect(monitor.isConnected == true || monitor.isConnected == false)
    }

    @Test("Multiple NetworkMonitor instances are independent")
    func testMultipleInstances() async {
        let monitor1 = NetworkMonitor()
        let monitor2 = NetworkMonitor()
        defer {
            monitor1.stopMonitoring()
            monitor2.stopMonitoring()
        }

        // Should be different instances
        #expect(monitor1 !== monitor2)

        // Both should have valid initial state
        #expect(monitor1.isConnected == true)
        #expect(monitor2.isConnected == true)
    }

    @Test("NetworkMonitor cleanup does not crash")
    func testCleanup() async {
        // Create and immediately stop multiple monitors
        // If this loop completes without crashing, cleanup works correctly
        for _ in 0..<10 {
            let monitor = NetworkMonitor()
            monitor.stopMonitoring()
        }
    }

    // MARK: - Integration Test Notes
    //
    // The following scenarios require actual network changes and cannot be
    // unit tested reliably:
    // - Network state transitions (online -> offline -> online)
    // - Connection type changes (WiFi -> Cellular)
    // - Rapid network flapping
    //
    // These should be tested manually or via UI tests on physical devices.
}
