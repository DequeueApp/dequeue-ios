//
//  NotificationSettingsView.swift
//  Dequeue
//
//  Notification preferences and permission management (DEQ-42)
//

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - UserDefaults Keys

private enum UserDefaultsKey {
    static let notificationBadgeEnabled = "notificationBadgeEnabled"
}

// MARK: - Main View

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(UserDefaultsKey.notificationBadgeEnabled) private var badgeEnabled = true

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPermissionError = false
    @State private var permissionErrorMessage: String?
    @State private var notificationService: NotificationService?

    var body: some View {
        List {
            PermissionSection(
                status: authorizationStatus,
                onRequestPermission: requestPermission,
                onOpenSettings: openSystemSettings
            )
            PreferencesSection(
                isVisible: authorizationStatus == .authorized || authorizationStatus == .provisional,
                badgeEnabled: $badgeEnabled,
                onBadgeToggle: handleBadgeToggle
            )
        }
        .navigationTitle("Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await initializeAndLoadStatus()
        }
        .alert("Permission Error", isPresented: $showPermissionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(permissionErrorMessage ?? "Failed to request notification permission.")
        }
    }

    // MARK: - Actions

    private func initializeAndLoadStatus() async {
        let service = NotificationService(modelContext: modelContext)
        notificationService = service
        authorizationStatus = await service.getAuthorizationStatus()
    }

    private func requestPermission() async {
        guard let service = notificationService else { return }
        do {
            let granted = try await service.requestPermissionWithError()
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            permissionErrorMessage = error.localizedDescription
            showPermissionError = true
            ErrorReportingService.capture(
                error: error,
                context: ["action": "request_notification_permission"]
            )
            authorizationStatus = await service.getAuthorizationStatus()
        }
    }

    private func handleBadgeToggle(enabled: Bool) async {
        guard let service = notificationService else { return }
        if !enabled {
            await service.clearAppBadge()
        } else {
            await service.updateAppBadge()
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        // macOS Ventura+ uses the new Notifications extension URL
        // Falls back to the legacy URL for older macOS versions
        let modernURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        let legacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")

        if let url = modernURL ?? legacyURL {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

// MARK: - Permission Section

private struct PermissionSection: View {
    let status: UNAuthorizationStatus
    let onRequestPermission: () async -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Section {
            HStack {
                Text("Permission")
                Spacer()
                PermissionStatusBadge(status: status)
            }

            permissionActionButton
        } header: {
            Text("Permission Status")
        } footer: {
            Text(footerText)
        }
    }

    @ViewBuilder
    private var permissionActionButton: some View {
        switch status {
        case .notDetermined:
            Button {
                Task {
                    await onRequestPermission()
                }
            } label: {
                Label("Enable Notifications", systemImage: "bell.badge")
            }
            .accessibilityIdentifier("enableNotificationsButton")
        case .denied:
            Button {
                onOpenSettings()
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .accessibilityIdentifier("openSettingsButton")
        case .authorized, .provisional, .ephemeral:
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }

    private var footerText: String {
        switch status {
        case .authorized:
            return "Notifications are enabled. You'll receive alerts for reminders."
        case .denied:
            return "Notifications are disabled. Open Settings to enable them."
        case .provisional:
            return "Notifications are delivered quietly. Enable full alerts in Settings."
        case .ephemeral:
            return "Notifications are temporarily enabled for this session."
        case .notDetermined:
            return "Enable notifications to receive reminder alerts."
        @unknown default:
            return "Unable to determine notification status."
        }
    }
}

// MARK: - Permission Status Badge

private struct PermissionStatusBadge: View {
    let status: UNAuthorizationStatus

    var body: some View {
        Label(labelText, systemImage: iconName)
            .foregroundStyle(iconColor)
            .labelStyle(.titleAndIcon)
    }

    private var labelText: String {
        switch status {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .provisional: return "Provisional"
        case .ephemeral: return "Temporary"
        case .notDetermined: return "Not Set"
        @unknown default: return "Unknown"
        }
    }

    private var iconName: String {
        switch status {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .provisional: return "bell.badge"
        case .ephemeral: return "clock"
        case .notDetermined: return "questionmark.circle"
        @unknown default: return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch status {
        case .authorized: return .green
        case .denied: return .red
        case .provisional, .ephemeral: return .orange
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }
}

// MARK: - Preferences Section

private struct PreferencesSection: View {
    let isVisible: Bool
    @Binding var badgeEnabled: Bool
    let onBadgeToggle: (Bool) async -> Void

    /// Tracks whether the initial load has occurred to prevent triggering on first appear
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if isVisible {
                Section {
                    Toggle(isOn: $badgeEnabled) {
                        Label("Badge", systemImage: "app.badge")
                    }
                    .accessibilityIdentifier("notificationBadgeToggle")
                    // Use .task(id:) for structured concurrency - automatically cancels on view disappear
                    .task(id: badgeEnabled) {
                        // Skip the initial task run when view first appears
                        guard hasLoaded else {
                            hasLoaded = true
                            return
                        }
                        await onBadgeToggle(badgeEnabled)
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Show the number of overdue reminders on the app icon.")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
