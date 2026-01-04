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
/// This class is @MainActor isolated because:
/// 1. Its sole purpose is to drive UI updates
/// 2. All property reads happen from SwiftUI views (main thread)
/// 3. The singleton pattern makes this isolation straightforward
///
/// The NWPathMonitor infrastructure uses nonisolated to operate off the main thread.
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
@MainActor
final class NetworkMonitor {
    /// Whether the device currently has network connectivity
    /// Optimistic default: true (avoids false offline indicators during launch)
    private(set) var isConnected: Bool = true

    /// The type of network interface currently in use (WiFi, Cellular, etc.)
    private(set) var connectionType: NWInterface.InterfaceType?

    nonisolated private let monitor: NWPathMonitor
    nonisolated private let queue = DispatchQueue(label: "com.dequeue.networkmonitor")
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.dequeue", category: "NetworkMonitor")

    nonisolated init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        // Cancel monitor to release network resources
        // NWPathMonitor.cancel() is thread-safe
        monitor.cancel()
    }

    nonisolated private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Extract values before creating Task to avoid capturing path object
            let status = path.status
            let interfaceType = path.availableInterfaces.first?.type
            let isConnected = status == .satisfied

            // Log state changes for debugging
            Self.logger.debug("Network state changed: connected=\(isConnected), interface=\(String(describing: interfaceType))")

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
    nonisolated func stopMonitoring() {
        monitor.cancel()
        Self.logger.info("Network monitoring stopped")
    }

    /// Shared instance for app-wide network monitoring.
    ///
    /// This singleton intentionally runs for the app's entire lifetime.
    /// The NWPathMonitor is lightweight and designed for continuous monitoring.
    static let shared = NetworkMonitor()
}
