//
//  DeploymentEnvironmentTests.swift
//  DequeueTests
//
//  Tests for DeploymentEnvironment computed properties (displayName, badge, id),
//  ValidationSeverity, and EnvironmentValidationIssue.
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - DeploymentEnvironment Tests

@Suite("DeploymentEnvironment Tests")
@MainActor
struct DeploymentEnvironmentTests {
    @Test("DeploymentEnvironment has exactly 3 cases")
    func caseCount() {
        #expect(DeploymentEnvironment.allCases.count == 3)
    }

    @Test("DeploymentEnvironment id equals rawValue (Identifiable)")
    func idEqualsRawValue() {
        for env in DeploymentEnvironment.allCases {
            #expect(env.id == env.rawValue)
        }
    }

    @Test("DeploymentEnvironment displayName is correct for each case")
    func displayNames() {
        #expect(DeploymentEnvironment.development.displayName == "Development")
        #expect(DeploymentEnvironment.staging.displayName == "Staging")
        #expect(DeploymentEnvironment.production.displayName == "Production")
    }

    @Test("DeploymentEnvironment displayName values are unique")
    func displayNamesAreUnique() {
        let names = DeploymentEnvironment.allCases.map { $0.displayName }
        #expect(Set(names).count == DeploymentEnvironment.allCases.count)
    }

    @Test("DeploymentEnvironment badge emoji is correct for each case")
    func badgeEmojis() {
        #expect(DeploymentEnvironment.development.badge == "🛠️")
        #expect(DeploymentEnvironment.staging.badge == "🧪")
        #expect(DeploymentEnvironment.production.badge == "🚀")
    }

    @Test("DeploymentEnvironment badge values are unique")
    func badgesAreUnique() {
        let badges = DeploymentEnvironment.allCases.map { $0.badge }
        #expect(Set(badges).count == DeploymentEnvironment.allCases.count)
    }

    @Test("DeploymentEnvironment configuration has matching environment property")
    func configurationEnvironmentMatches() {
        for env in DeploymentEnvironment.allCases {
            #expect(env.configuration.environment == env)
        }
    }

    @Test("DeploymentEnvironment is Codable (round-trip for all cases)")
    func codableRoundTrip() throws {
        for env in DeploymentEnvironment.allCases {
            let data = try JSONEncoder().encode(env)
            let decoded = try JSONDecoder().decode(DeploymentEnvironment.self, from: data)
            #expect(decoded == env, "Round-trip failed for \(env.rawValue)")
        }
    }

    @Test("DeploymentEnvironment returns nil for invalid raw value")
    func invalidRawValue() {
        #expect(DeploymentEnvironment(rawValue: "unknown") == nil)
        #expect(DeploymentEnvironment(rawValue: "") == nil)
        #expect(DeploymentEnvironment(rawValue: "Production") == nil) // case-sensitive
    }
}

// MARK: - ValidationSeverity Tests

@Suite("ValidationSeverity Tests")
@MainActor
struct ValidationSeverityTests {
    @Test("ValidationSeverity has correct raw values")
    func rawValues() {
        #expect(ValidationSeverity.warning.rawValue == "warning")
        #expect(ValidationSeverity.error.rawValue == "error")
    }

    @Test("ValidationSeverity Equatable works correctly")
    func equatable() {
        #expect(ValidationSeverity.warning == .warning)
        #expect(ValidationSeverity.error == .error)
        #expect(ValidationSeverity.warning != .error)
    }

    @Test("ValidationSeverity can be created from raw String")
    func fromRawValue() {
        #expect(ValidationSeverity(rawValue: "warning") == .warning)
        #expect(ValidationSeverity(rawValue: "error") == .error)
        #expect(ValidationSeverity(rawValue: "critical") == nil)
    }
}

// MARK: - EnvironmentValidationIssue Tests

@Suite("EnvironmentValidationIssue Tests")
@MainActor
struct EnvironmentValidationIssueTests {
    @Test("EnvironmentValidationIssue stores all fields correctly")
    func storesFields() {
        let issue = EnvironmentValidationIssue(
            key: "clerkPublishableKey",
            message: "Clerk key is empty",
            severity: .error
        )
        #expect(issue.key == "clerkPublishableKey")
        #expect(issue.message == "Clerk key is empty")
        #expect(issue.severity == .error)
    }

    @Test("EnvironmentValidationIssue Equatable compares all fields")
    func equatable() {
        let issue1 = EnvironmentValidationIssue(key: "key", message: "msg", severity: .warning)
        let issue2 = EnvironmentValidationIssue(key: "key", message: "msg", severity: .warning)
        let differentKey = EnvironmentValidationIssue(key: "other", message: "msg", severity: .warning)
        let differentMessage = EnvironmentValidationIssue(key: "key", message: "different", severity: .warning)
        let differentSeverity = EnvironmentValidationIssue(key: "key", message: "msg", severity: .error)

        #expect(issue1 == issue2)
        #expect(issue1 != differentKey)
        #expect(issue1 != differentMessage)
        #expect(issue1 != differentSeverity)
    }

    @Test("EnvironmentValidationIssue warning severity is not error")
    func warningSeverityIsNotError() {
        let issue = EnvironmentValidationIssue(key: "sentryDSN", message: "DSN empty", severity: .warning)
        #expect(issue.severity == .warning)
        #expect(issue.severity != .error)
    }
}
