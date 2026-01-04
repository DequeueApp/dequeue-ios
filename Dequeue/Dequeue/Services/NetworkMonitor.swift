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
/// This class is @MainActor isolated because:
/// 1. Its sole purpose is to drive UI updates
/// 2. All property reads should happen on the main thread for SwiftUI
/// 3. The singleton pattern makes isolation straightforward
///
/// Usage:
/// ```swift
/// if await NetworkMonitor.shared.isConnected {
///     // Online
/// }
/// ```
@MainActor
@Observable
final class NetworkMonitor {
    /// Whether the device currently has network connectivity
    private(set) var isConnected: Bool = true

    /// The type of network interface currently in use (WiFi, Cellular, etc.)
    private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.dequeue.networkmonitor")

    init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        // Cancel monitor to release network resources
        // NWPathMonitor.cancel() is thread-safe
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Extract values before creating Task to avoid capturing path object
            let status = path.status
            let interfaceType = path.availableInterfaces.first?.type

            Task { @MainActor in
                // Use weak self to allow cleanup if monitor is deallocated during async gap
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
    static let shared = NetworkMonitor()
}
