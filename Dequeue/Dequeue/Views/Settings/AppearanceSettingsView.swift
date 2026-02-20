//
//  AppearanceSettingsView.swift
//  Dequeue
//
//  Appearance and theme settings (DEQ-43)
//

import SwiftUI

// MARK: - UserDefaults Keys

private enum UserDefaultsKey {
    static let appTheme = "appTheme"
    static let datePickerStyle = "datePickerStyle"
    static let timePickerStyle = "timePickerStyle"
}

// MARK: - Accessibility Identifiers

private enum AccessibilityIdentifier {
    static func themeButton(_ theme: AppTheme) -> String {
        "theme\(theme.displayName)Button"
    }
}

// MARK: - App Theme Enum

/// Represents the app's theme preference for controlling light/dark appearance.
///
/// The theme is persisted to UserDefaults and applied app-wide using the
/// `applyAppTheme()` view modifier.
internal enum AppTheme: String, CaseIterable, Identifiable {
    /// Follow the system's appearance settings (light or dark mode)
    case system
    /// Always use light appearance regardless of system settings
    case light
    /// Always use dark appearance regardless of system settings
    case dark

    nonisolated var id: String { rawValue }

    /// Human-readable name for display in the UI
    nonisolated var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// SF Symbol name representing this theme option
    nonisolated var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// The SwiftUI ColorScheme to apply, or nil to follow system
    nonisolated var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Date Picker Style Preference

/// Represents the date picker style preference
internal enum DatePickerStylePreference: String, CaseIterable, Identifiable {
    case automatic
    case graphical
    case compact
    case wheel

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .graphical: return "Calendar"
        case .compact: return "Compact"
        case .wheel: return "Wheel"
        }
    }

    nonisolated var icon: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .graphical: return "calendar"
        case .compact: return "arrow.down.circle"
        case .wheel: return "circle.circle"
        }
    }

    nonisolated var description: String {
        switch self {
        case .automatic: return "Let the system choose the best style"
        case .graphical: return "Full calendar grid view"
        case .compact: return "Compact button with popup"
        case .wheel: return "Scrollable wheel picker"
        }
    }
}

// MARK: - Time Picker Style Preference

/// Represents the time picker style preference
internal enum TimePickerStylePreference: String, CaseIterable, Identifiable {
    case automatic
    case wheel

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .wheel: return "Wheel"
        }
    }

    nonisolated var icon: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .wheel: return "circle.circle"
        }
    }

    nonisolated var description: String {
        switch self {
        case .automatic: return "Let the system choose the best style"
        case .wheel: return "Scrollable wheel picker"
        }
    }
}

// MARK: - Appearance Settings View

internal struct AppearanceSettingsView: View {
    @AppStorage(UserDefaultsKey.appTheme) private var selectedTheme: String = AppTheme.system.rawValue
    @AppStorage(UserDefaultsKey.datePickerStyle)
    private var selectedDatePickerStyle: String = DatePickerStylePreference.automatic.rawValue
    @AppStorage(UserDefaultsKey.timePickerStyle)
    private var selectedTimePickerStyle: String = TimePickerStylePreference.automatic.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .system
    }

    private var datePickerStylePreference: DatePickerStylePreference {
        DatePickerStylePreference(rawValue: selectedDatePickerStyle) ?? .automatic
    }

    private var timePickerStylePreference: TimePickerStylePreference {
        TimePickerStylePreference(rawValue: selectedTimePickerStyle) ?? .automatic
    }

    var body: some View {
        List {
            themeSection
            dateTimePickersSection
            previewSection
        }
        .navigationTitle("Appearance")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        Section {
            ForEach(AppTheme.allCases) { option in
                themeRow(for: option)
            }
        } header: {
            Text("Theme")
        } footer: {
            Text("Choose how Dequeue appears. System uses your device's appearance settings.")
        }
    }

    private func themeRow(for option: AppTheme) -> some View {
        Button {
            selectedTheme = option.rawValue
        } label: {
            HStack {
                Label(option.displayName, systemImage: option.icon)
                    .foregroundStyle(.primary)
                Spacer()
                if theme == option {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifier.themeButton(option))
        .accessibilityLabel("\(option.displayName) theme")
        .accessibilityHint(
            theme == option
                ? "Currently selected"
                : "Double tap to select \(option.displayName) theme"
        )
    }

    // MARK: - Date & Time Pickers Section

    private var dateTimePickersSection: some View {
        Section {
            ForEach(DatePickerStylePreference.allCases) { option in
                datePickerStyleRow(for: option)
            }

            Divider()
                .padding(.vertical, 4)

            ForEach(TimePickerStylePreference.allCases) { option in
                timePickerStyleRow(for: option)
            }
        } header: {
            Text("Date & Time Pickers")
        } footer: {
            Text("Choose how date and time pickers appear throughout the app.")
        }
    }

    private func datePickerStyleRow(for option: DatePickerStylePreference) -> some View {
        Button {
            selectedDatePickerStyle = option.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(option.displayName, systemImage: option.icon)
                        .foregroundStyle(.primary)
                    Spacer()
                    if datePickerStylePreference == option {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    }
                }
                Text(option.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Date picker: \(option.displayName)")
        .accessibilityHint(
            datePickerStylePreference == option
                ? "Currently selected"
                : "Double tap to select \(option.displayName) date picker style"
        )
    }

    private func timePickerStyleRow(for option: TimePickerStylePreference) -> some View {
        Button {
            selectedTimePickerStyle = option.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(option.displayName, systemImage: option.icon)
                        .foregroundStyle(.primary)
                    Spacer()
                    if timePickerStylePreference == option {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    }
                }
                Text(option.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Time picker: \(option.displayName)")
        .accessibilityHint(
            timePickerStylePreference == option
                ? "Currently selected"
                : "Double tap to select \(option.displayName) time picker style"
        )
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Section {
            themePreview
        } header: {
            Text("Preview")
        }
    }

    private var themePreview: some View {
        HStack(spacing: 16) {
            previewCard(title: "Stack", subtitle: "3 tasks", isActive: true)
            previewCard(title: "Task", subtitle: "Pending", isActive: false)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
    }

    private func previewCard(title: String, subtitle: String, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #else
        .background(Color(.windowBackgroundColor).opacity(0.5))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Theme Environment Modifier

extension View {
    /// Applies the user's selected theme preference to the view
    func applyAppTheme() -> some View {
        modifier(AppThemeModifier())
    }
}

private struct AppThemeModifier: ViewModifier {
    @AppStorage(UserDefaultsKey.appTheme) private var selectedTheme: String = AppTheme.system.rawValue

    private var colorScheme: ColorScheme? {
        (AppTheme(rawValue: selectedTheme) ?? .system).colorScheme
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(colorScheme)
    }
}

// MARK: - Date/Time Picker Style Helpers

extension View {
    /// Applies the user's preferred date picker style
    func applyDatePickerStyle() -> some View {
        modifier(DatePickerStyleModifier())
    }

    /// Applies the user's preferred time picker style (for time-only pickers)
    func applyTimePickerStyle() -> some View {
        modifier(TimePickerStyleModifier())
    }
}

private struct DatePickerStyleModifier: ViewModifier {
    @AppStorage(UserDefaultsKey.datePickerStyle)
    private var selectedStyle: String = DatePickerStylePreference.automatic.rawValue

    private var preference: DatePickerStylePreference {
        DatePickerStylePreference(rawValue: selectedStyle) ?? .automatic
    }

    func body(content: Content) -> some View {
        Group {
            switch preference {
            case .automatic:
                content
            case .graphical:
                content.datePickerStyle(.graphical)
            case .compact:
                content.datePickerStyle(.compact)
            case .wheel:
                #if os(iOS)
                content.datePickerStyle(.wheel)
                #else
                // Wheel style unavailable on macOS, fall back to graphical
                content.datePickerStyle(.graphical)
                #endif
            }
        }
    }
}

private struct TimePickerStyleModifier: ViewModifier {
    @AppStorage(UserDefaultsKey.timePickerStyle)
    private var selectedStyle: String = TimePickerStylePreference.automatic.rawValue

    private var preference: TimePickerStylePreference {
        TimePickerStylePreference(rawValue: selectedStyle) ?? .automatic
    }

    func body(content: Content) -> some View {
        Group {
            switch preference {
            case .automatic:
                content
            case .wheel:
                #if os(iOS)
                content.datePickerStyle(.wheel)
                #else
                // Wheel style unavailable on macOS, fall back to automatic
                content
                #endif
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
