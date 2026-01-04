//
//  NetworkMonitor.swift
//  Dequeue
//
//  Monitors network connectivity using Network framework
//

import Foundation
import Network
import Observation
import os

/// Monitors network connectivity and provides reactive updates for UI.
///
/// Uses Apple's Network framework (NWPathMonitor) to detect connectivity changes.
/// The shared instance runs for the app's lifetime - this is intentional as network
/// monitoring should be continuous.
///
/// Properties are @MainActor isolated for SwiftUI observation. The monitoring
/// infrastructure (NWPathMonitor, DispatchQueue) operates off the main thread.
///
/// Note: Initial state is optimistic (isConnected = true) to avoid false offline
/// indicators during app launch. Actual state is updated within ~100ms.
///
/// Usage:
/// ```swift
/// let monitor = NetworkMonitor.shared
/// if monitor.isConnected {
///     // Online
/// }
/// ```
@Observable
final class NetworkMonitor: @unchecked Sendable {
    /// Whether the device currently has network connectivity
    /// Optimistic default: true (avoids false offline indicators during launch)
    @MainActor private(set) var isConnected: Bool = true

    /// The type of network interface currently in use (WiFi, Cellular, etc.)
    @MainActor private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.dequeue.networkmonitor")
    private let logger = Logger(subsystem: "com.dequeue", category: "NetworkMonitor")

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
            guard let self = self else { return }

            // Extract values before creating Task to avoid capturing path object
            let status = path.status
            let interfaceType = path.availableInterfaces.first?.type
            let isConnected = status == .satisfied

            // Log state changes for debugging
            self.logger.debug("Network state changed: connected=\(isConnected), interface=\(String(describing: interfaceType))")

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isConnected = isConnected
                self.connectionType = interfaceType
            }
        }
        monitor.start(queue: queue)
        logger.info("Network monitoring started")
    }

    /// Stops monitoring network connectivity.
    ///
    /// For the shared singleton, this typically should not be called as it runs
    /// for the app's lifetime. Useful for testing cleanup or custom instances.
    func stopMonitoring() {
        monitor.cancel()
        logger.info("Network monitoring stopped")
    }

    /// Shared instance for app-wide network monitoring.
    ///
    /// This singleton intentionally runs for the app's entire lifetime.
    /// The NWPathMonitor is lightweight and designed for continuous monitoring.
    nonisolated(unsafe) static let shared = NetworkMonitor()
}
