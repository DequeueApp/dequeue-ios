//
//  NetworkMonitor.swift
//  Dequeue
//
//  Monitors network connectivity using Network framework
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isConnected: Bool = true
    private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.dequeue.networkmonitor")

    init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        // Cancel monitor to stop path updates
        // Any in-flight Tasks will complete naturally
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            let interfaceType = path.availableInterfaces.first?.type

            // Create ephemeral task to update MainActor properties
            Task { @MainActor [weak self] in
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
    static let shared = NetworkMonitor()
}
