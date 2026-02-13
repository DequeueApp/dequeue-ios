//
//  EnvironmentManager.swift
//  Dequeue
//
//  Manages app environment selection and configuration
//

import Foundation
import SwiftUI

/// Manages the current app environment and allows switching in debug builds
@Observable
final class EnvironmentManager {
    /// Shared instance for app-wide environment access
    static let shared = EnvironmentManager()

    /// Key for storing environment selection in UserDefaults
    private static let environmentKey = "app.environment"

    /// Current active environment
    private(set) var currentEnvironment: DeploymentEnvironment {
        didSet {
            // Persist environment selection in debug builds only
            #if DEBUG
            if let encoded = try? JSONEncoder().encode(currentEnvironment) {
                UserDefaults.standard.set(encoded, forKey: Self.environmentKey)
            }
            #endif
        }
    }

    /// Current environment configuration
    var configuration: EnvironmentConfiguration {
        currentEnvironment.configuration
    }

    /// Whether environment switching is allowed (debug builds only)
    var canSwitchEnvironment: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private init() {
        #if DEBUG
        // In debug builds, allow environment switching via UserDefaults
        if let data = UserDefaults.standard.data(forKey: Self.environmentKey),
           let environment = try? JSONDecoder().decode(DeploymentEnvironment.self, from: data) {
            self.currentEnvironment = environment
        } else {
            // Default to development in debug builds
            self.currentEnvironment = .development
        }
        #else
        // In release builds, always use production
        self.currentEnvironment = .production
        #endif
    }

    /// Switch to a different environment (debug builds only)
    /// - Parameter environment: The environment to switch to
    /// - Returns: True if the switch was successful
    @discardableResult
    func switchEnvironment(to environment: DeploymentEnvironment) -> Bool {
        #if DEBUG
        guard currentEnvironment != environment else {
            return false
        }
        currentEnvironment = environment
        ErrorReportingService.addBreadcrumb(
            category: "environment",
            message: "Environment switched",
            data: ["from": currentEnvironment.rawValue, "to": environment.rawValue]
        )
        return true
        #else
        // Environment switching not allowed in release builds
        return false
        #endif
    }

    /// Reset environment to default for current build configuration
    func resetToDefault() {
        #if DEBUG
        currentEnvironment = .development
        #else
        currentEnvironment = .production
        #endif
    }
}
