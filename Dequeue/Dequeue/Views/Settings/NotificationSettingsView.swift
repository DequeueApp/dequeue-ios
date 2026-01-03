//
//  NotificationSettingsView.swift
//  Dequeue
//
//  Notification preferences and permission management (DEQ-42)
//

import SwiftUI
import SwiftData
import UserNotifications

internal struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    // Note: Sound/badge preferences are stored for future use when NotificationService
    // is updated to respect these settings. Currently they control UI state only.
    @AppStorage("notificationSoundEnabled") private var soundEnabled = true
    @AppStorage("notificationBadgeEnabled") private var badgeEnabled = true

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationService: NotificationService?

    var body: some View {
        List {
            permissionSection
            preferencesSection
        }
        .navigationTitle("Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadAuthorizationStatus()
        }
    }

    // MARK: - Permission Section

    private var permissionSection: some View {
        Section {
            HStack {
                Text("Permission")
                Spacer()
                permissionStatusBadge
            }

            permissionActionButton
        } header: {
            Text("Permission Status")
        } footer: {
            Text(permissionFooterText)
        }
    }

    @ViewBuilder
    private var permissionStatusBadge: some View {
        switch authorizationStatus {
        case .authorized:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
        case .provisional:
            Label("Provisional", systemImage: "bell.badge")
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        case .ephemeral:
            Label("Temporary", systemImage: "clock")
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        case .notDetermined:
            Label("Not Set", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        @unknown default:
            Label("Unknown", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder
    private var permissionActionButton: some View {
        switch authorizationStatus {
        case .notDetermined:
            Button {
                Task {
                    await requestPermission()
                }
            } label: {
                Label("Enable Notifications", systemImage: "bell.badge")
            }
            .accessibilityIdentifier("enableNotificationsButton")
        case .denied:
            Button {
                openSystemSettings()
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

    private var permissionFooterText: String {
        switch authorizationStatus {
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

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        Group {
            if authorizationStatus == .authorized || authorizationStatus == .provisional {
                Section {
                    Toggle(isOn: $soundEnabled) {
                        Label("Sound", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("notificationSoundToggle")

                    Toggle(isOn: $badgeEnabled) {
                        Label("Badge", systemImage: "app.badge")
                    }
                    .accessibilityIdentifier("notificationBadgeToggle")
                    .onChange(of: badgeEnabled) { _, newValue in
                        Task {
                            await handleBadgeToggle(enabled: newValue)
                        }
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Control how notifications appear on your device.")
                }
            }
        }
    }

    // MARK: - Actions

    /// Ensures NotificationService is initialized and returns it
    private func ensureService() -> NotificationService {
        if let service = notificationService {
            return service
        }
        let service = NotificationService(modelContext: modelContext)
        notificationService = service
        return service
    }

    private func loadAuthorizationStatus() async {
        let service = ensureService()
        authorizationStatus = await service.getAuthorizationStatus()
    }

    private func requestPermission() async {
        let service = ensureService()
        let granted = await service.requestPermission()
        authorizationStatus = granted ? .authorized : .denied
    }

    private func handleBadgeToggle(enabled: Bool) async {
        let service = ensureService()
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
