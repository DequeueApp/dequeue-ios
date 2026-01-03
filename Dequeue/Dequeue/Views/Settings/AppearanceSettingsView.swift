//
//  AppearanceSettingsView.swift
//  Dequeue
//
//  Appearance and theme settings (DEQ-43)
//

import SwiftUI

// MARK: - Constants

private enum AppearanceConstants {
    static let themeStorageKey = "appTheme"
}

// MARK: - App Theme Enum

internal enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Appearance Settings View

internal struct AppearanceSettingsView: View {
    @AppStorage(AppearanceConstants.themeStorageKey) private var selectedTheme: String = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .system
    }

    var body: some View {
        List {
            themeSection
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
        .accessibilityIdentifier("theme\(option.displayName)Button")
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
        .background(Color(.secondarySystemGroupedBackground))
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
    @AppStorage(AppearanceConstants.themeStorageKey) private var selectedTheme: String = AppTheme.system.rawValue

    private var colorScheme: ColorScheme? {
        (AppTheme(rawValue: selectedTheme) ?? .system).colorScheme
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(colorScheme)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
