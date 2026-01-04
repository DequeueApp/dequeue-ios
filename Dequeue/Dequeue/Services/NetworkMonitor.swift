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
/// ## Design Notes
///
/// This class applies @MainActor surgically - only to observable properties that
/// drive UI updates. The NWPathMonitor infrastructure runs on a background queue.
///
/// The singleton pattern is intentional for network monitoring because:
/// - Network state is global and device-wide
/// - Multiple monitors would be wasteful and potentially inconsistent
/// - The monitor runs for the app's entire lifetime
///
/// Initial state is optimistic (isConnected = true) to avoid false offline
/// indicators during app launch. Actual state is updated within ~100ms.
///
/// ## Usage
///
/// ```swift
/// let monitor = NetworkMonitor.shared
/// if monitor.isConnected {
///     // Online
/// }
/// ```
@Observable
final class NetworkMonitor {
    /// Whether the device currently has network connectivity.
    /// Optimistic default: true (avoids false offline indicators during launch)
    @MainActor private(set) var isConnected: Bool = true

    /// The type of network interface currently in use (WiFi, Cellular, etc.)
    @MainActor private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.dequeue.networkmonitor")
    nonisolated(unsafe) private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dequeue",
        category: "NetworkMonitor"
    )

    init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    nonisolated deinit {
        // Note: The shared singleton never deallocates (intentional - runs for app lifetime)
        // This deinit only fires for test instances or custom monitors
        // NWPathMonitor.cancel() is thread-safe
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Extract values before creating Task to avoid capturing path object
            let status = path.status
            let interfaceType = path.availableInterfaces.first?.type
            let isConnected = status == .satisfied

            // Log state changes for debugging
            let ifaceStr = String(describing: interfaceType)
            Self.logger.debug("Network: connected=\(isConnected), interface=\(ifaceStr)")

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isConnected = isConnected
                self.connectionType = interfaceType
            }
        }
        monitor.start(queue: queue)
        Self.logger.info("Network monitoring started")
    }

    /// Stops monitoring network connectivity.
    ///
    /// For the shared singleton, this typically should not be called as it runs
    /// for the app's lifetime. Useful for testing cleanup or custom instances.
    func stopMonitoring() {
        monitor.cancel()
        Self.logger.info("Network monitoring stopped")
    }

    /// Shared instance for app-wide network monitoring.
    ///
    /// This singleton intentionally runs for the app's entire lifetime.
    /// The NWPathMonitor is lightweight and designed for continuous monitoring.
    @MainActor static let shared = NetworkMonitor()
}
