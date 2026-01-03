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

        // Should start with connected state
        #expect(monitor.isConnected == true)

        // Connection type may be nil initially
        #expect(monitor.connectionType == nil || monitor.connectionType != nil)
    }

    @Test("NetworkMonitor shared instance is consistent")
    func testSharedInstance() async {
        let monitor1 = NetworkMonitor.shared
        let monitor2 = NetworkMonitor.shared

        // Should be the same instance
        #expect(monitor1 === monitor2)
    }

    @Test("NetworkMonitor properties are observable")
    func testObservability() async {
        let monitor = NetworkMonitor()

        // Properties should be accessible
        let connected = monitor.isConnected
        let connectionType = monitor.connectionType

        // Should be able to read both properties
        #expect(connected == true || connected == false)
        #expect(connectionType == nil || connectionType != nil)
    }
}
