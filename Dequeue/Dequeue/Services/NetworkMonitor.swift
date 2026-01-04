//
//  NetworkMonitor.swift
//  Dequeue
//
//  Monitors network connectivity using Network framework
//

import Foundation
import Network
import Observation

@Observable
final class NetworkMonitor {
    @MainActor private(set) var isConnected: Bool = true
    @MainActor private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.dequeue.networkmonitor")

    init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            let interfaceType = path.availableInterfaces.first?.type

            Task { @MainActor in
                guard let self = self else { return }
                self.isConnected = status == .satisfied
                self.connectionType = interfaceType
            }
        }
        monitor.start(queue: queue)
    }

    /// Stops monitoring network connectivity. Call this for testing cleanup
    /// or if you need to release the monitor. Note: For the shared instance,
    /// this typically should not be called as it runs for the app's lifetime.
    func stopMonitoring() {
        monitor.cancel()
    }

    /// Shared instance for app-wide network monitoring
    nonisolated(unsafe) static let shared = NetworkMonitor()
}
