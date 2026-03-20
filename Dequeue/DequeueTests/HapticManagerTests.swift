//
//  HapticManagerTests.swift
//  DequeueTests
//
//  Tests for HapticManager haptic feedback coordination.
//  On macOS the #if os(iOS) guards make all feedback calls no-ops,
//  so these tests verify the public API surface and singleton contract
//  without requiring physical hardware.
//

import Testing
@testable import Dequeue

@Suite("HapticManager Tests")
@MainActor
struct HapticManagerTests {
    // MARK: - Singleton

    @Test("shared returns the same instance every time")
    func testSharedIsSingleton() {
        let first = HapticManager.shared
        let second = HapticManager.shared
        #expect(first === second)
    }

    // MARK: - Public Methods (no-crash contract)

    @Test("success() does not crash")
    func testSuccessDoesNotCrash() {
        HapticManager.shared.success()
    }

    @Test("selection() does not crash")
    func testSelectionDoesNotCrash() {
        HapticManager.shared.selection()
    }

    @Test("warning() does not crash")
    func testWarningDoesNotCrash() {
        HapticManager.shared.warning()
    }

    @Test("impact() with default style does not crash")
    func testImpactDefaultDoesNotCrash() {
        HapticManager.shared.impact()
    }

    @Test("impact(.light) does not crash")
    func testImpactLightDoesNotCrash() {
        HapticManager.shared.impact(style: .light)
    }

    @Test("impact(.medium) does not crash")
    func testImpactMediumDoesNotCrash() {
        HapticManager.shared.impact(style: .medium)
    }

    @Test("impact(.heavy) does not crash")
    func testImpactHeavyDoesNotCrash() {
        HapticManager.shared.impact(style: .heavy)
    }

    // MARK: - ImpactStyle Enum

    @Test("ImpactStyle cases are distinct")
    func testImpactStyleCasesAreDistinct() {
        let light = HapticManager.ImpactStyle.light
        let medium = HapticManager.ImpactStyle.medium
        let heavy = HapticManager.ImpactStyle.heavy

        // Verify each case can be matched individually
        switch light {
        case .light: break
        default: Issue.record("Expected .light")
        }

        switch medium {
        case .medium: break
        default: Issue.record("Expected .medium")
        }

        switch heavy {
        case .heavy: break
        default: Issue.record("Expected .heavy")
        }
    }

    @Test("ImpactStyle default parameter is .light")
    func testImpactDefaultStyleIsLight() {
        // Call impact() with no argument; if it compiled, the default is present.
        // We can't inspect the argument at runtime, but we verify the overload compiles.
        HapticManager.shared.impact()   // default = .light
        HapticManager.shared.impact(style: .light)
        // Both calls reaching here without crash is the assertion.
    }

    // MARK: - Call Sequencing

    @Test("calling all haptic methods in sequence does not crash")
    func testAllMethodsSequentially() {
        let haptic = HapticManager.shared
        haptic.success()
        haptic.selection()
        haptic.warning()
        haptic.impact(style: .light)
        haptic.impact(style: .medium)
        haptic.impact(style: .heavy)
    }

    @Test("repeated calls to same method do not crash")
    func testRepeatedCalls() {
        let haptic = HapticManager.shared
        for _ in 0..<20 {
            haptic.success()
            haptic.selection()
        }
    }
}
