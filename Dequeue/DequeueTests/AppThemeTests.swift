//
//  AppThemeTests.swift
//  DequeueTests
//
//  Tests for AppTheme enum
//

import Testing
import SwiftUI
@testable import Dequeue

@Suite("AppTheme Tests")
struct AppThemeTests {

    // MARK: - Raw Value Tests

    @Test("AppTheme has correct raw values")
    func appThemeHasCorrectRawValues() {
        #expect(AppTheme.system.rawValue == "system")
        #expect(AppTheme.light.rawValue == "light")
        #expect(AppTheme.dark.rawValue == "dark")
    }

    @Test("AppTheme can be created from raw values")
    func appThemeCanBeCreatedFromRawValues() {
        #expect(AppTheme(rawValue: "system") == .system)
        #expect(AppTheme(rawValue: "light") == .light)
        #expect(AppTheme(rawValue: "dark") == .dark)
        #expect(AppTheme(rawValue: "invalid") == nil)
    }

    // MARK: - Display Name Tests

    @Test("AppTheme has correct display names")
    func appThemeHasCorrectDisplayNames() {
        #expect(AppTheme.system.displayName == "System")
        #expect(AppTheme.light.displayName == "Light")
        #expect(AppTheme.dark.displayName == "Dark")
    }

    // MARK: - Icon Tests

    @Test("AppTheme has correct SF Symbol icons")
    func appThemeHasCorrectIcons() {
        #expect(AppTheme.system.icon == "circle.lefthalf.filled")
        #expect(AppTheme.light.icon == "sun.max.fill")
        #expect(AppTheme.dark.icon == "moon.fill")
    }

    // MARK: - ColorScheme Tests

    @Test("System theme returns nil ColorScheme")
    func systemThemeReturnsNilColorScheme() {
        #expect(AppTheme.system.colorScheme == nil)
    }

    @Test("Light theme returns light ColorScheme")
    func lightThemeReturnsLightColorScheme() {
        #expect(AppTheme.light.colorScheme == .light)
    }

    @Test("Dark theme returns dark ColorScheme")
    func darkThemeReturnsDarkColorScheme() {
        #expect(AppTheme.dark.colorScheme == .dark)
    }

    // MARK: - CaseIterable Tests

    @Test("AppTheme has all expected cases")
    func appThemeHasAllExpectedCases() {
        let allCases = AppTheme.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.system))
        #expect(allCases.contains(.light))
        #expect(allCases.contains(.dark))
    }

    // MARK: - Identifiable Tests

    @Test("AppTheme id matches rawValue")
    func appThemeIdMatchesRawValue() {
        for theme in AppTheme.allCases {
            #expect(theme.id == theme.rawValue)
        }
    }
}
