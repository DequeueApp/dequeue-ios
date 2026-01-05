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

    // MARK: - Persistence Tests

    /// Creates a test-isolated UserDefaults suite to avoid state contamination between parallel tests
    private static func makeTestDefaults() -> UserDefaults {
        // Use a UUID-based suite name to ensure complete isolation between test runs
        UserDefaults(suiteName: "AppThemeTests-\(UUID().uuidString)")!
    }

    @Test("AppTheme persists to UserDefaults correctly")
    func appThemePersistsToUserDefaults() {
        let key = "appTheme"
        let defaults = Self.makeTestDefaults()

        // Test each theme persists correctly
        for theme in AppTheme.allCases {
            defaults.set(theme.rawValue, forKey: key)
            let storedValue = defaults.string(forKey: key)
            #expect(storedValue == theme.rawValue)

            // Verify we can reconstruct the theme from stored value
            let reconstructed = AppTheme(rawValue: storedValue ?? "")
            #expect(reconstructed == theme)
        }
    }

    @Test("AppTheme defaults to system when no value stored")
    func appThemeDefaultsToSystem() {
        let key = "appTheme"
        let defaults = Self.makeTestDefaults()

        // Clean up any previous test data for this specific key
        defaults.removeObject(forKey: key)

        // When no value exists, attempting to create from nil should fail
        let storedValue = defaults.string(forKey: key)
        #expect(storedValue == nil)

        // Default behavior should use .system
        let theme = AppTheme(rawValue: storedValue ?? "") ?? .system
        #expect(theme == .system)
    }

    @Test("AppTheme colorScheme mapping is correct for persistence")
    func appThemeColorSchemeMappingForPersistence() {
        // Verify the complete flow: rawValue -> AppTheme -> ColorScheme
        for theme in AppTheme.allCases {
            let reconstructed = AppTheme(rawValue: theme.rawValue)
            #expect(reconstructed != nil)
            #expect(reconstructed?.colorScheme == theme.colorScheme)
        }
    }
}
