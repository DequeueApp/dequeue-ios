//
//  NetworkMonitor.swift
//  Dequeue
//
//  Monitors network connectivity using Network framework
//

import Foundation
import Network
import Observation

/// Monitors network connectivity and provides reactive updates for UI.
///
/// Uses Apple's Network framework (NWPathMonitor) to detect connectivity changes.
/// The shared instance runs for the app's lifetime - this is intentional as network
/// monitoring should be continuous.
///
/// Usage:
/// ```swift
/// let networkMonitor = NetworkMonitor.shared
/// if networkMonitor.isConnected {
///     // Online
/// }
/// ```
@Observable
final class NetworkMonitor: @unchecked Sendable {
    /// Whether the device currently has network connectivity
    @MainActor private(set) var isConnected: Bool = true

    /// The type of network interface currently in use (WiFi, Cellular, etc.)
    @MainActor private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.dequeue.networkmonitor")

    init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Extract values before creating Task to avoid capturing path
            let status = path.status
            let interfaceType = path.availableInterfaces.first?.type

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isConnected = status == .satisfied
                self.connectionType = interfaceType
            }
        }
        monitor.start(queue: queue)
    }

    /// Stops monitoring network connectivity.
    ///
    /// For the shared singleton, this typically should not be called as it runs
    /// for the app's lifetime. Useful for testing cleanup or custom instances.
    func stopMonitoring() {
        monitor.cancel()
    }

    /// Shared instance for app-wide network monitoring.
    ///
    /// This singleton intentionally runs for the app's entire lifetime.
    /// The NWPathMonitor is lightweight and designed for continuous monitoring.
    nonisolated(unsafe) static let shared = NetworkMonitor()
}
