//
//  SettingsView.swift
//  Dequeue
//
//  User settings and preferences
//

import SwiftUI
import Sentry
import Clerk

struct SettingsView: View {
    @Environment(\.authService) private var authService
    @Environment(\.syncManager) private var syncManager
    @AppStorage("developerModeEnabled") private var developerModeEnabled = false
    @State private var isSigningOut = false
    @State private var showSignOutError = false
    @State private var signOutError: String?
    @State private var showDeleteDataConfirmation = false
    @State private var connectionStatus: ConnectionStatus = .disconnected

    private var userEmail: String? {
        Clerk.shared.user?.primaryEmailAddress?.emailAddress
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                preferencesSection
                dataSection
                aboutSection
                advancedSection
                if developerModeEnabled {
                    developerSection
                }
            }
            .navigationTitle("Settings")
            .alert("Sign Out Failed", isPresented: $showSignOutError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(signOutError ?? "An unknown error occurred")
            }
            .confirmationDialog(
                "Delete All Data?",
                isPresented: $showDeleteDataConfirmation,
                titleVisibility: .visible
            ) {
                deleteDataDialogButtons
            } message: {
                deleteDataDialogMessage
            }
            .task { await refreshConnectionStatus() }
            .task(id: developerModeEnabled) { await pollConnectionStatus() }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            if let email = userEmail {
                Text(email)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                DevicesView()
            } label: {
                Label("Devices", systemImage: "laptopcomputer.and.iphone")
            }

            NavigationLink {
                APIKeysSettingsView()
            } label: {
                Label("API Keys", systemImage: "key")
            }

            Button(role: .destructive) {
                Task { await signOut() }
            } label: {
                HStack {
                    Text("Sign Out")
                    if isSigningOut {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isSigningOut)
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            NavigationLink {
                TagsListView()
            } label: {
                Label("Tags", systemImage: "tag")
            }
            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label("Notifications", systemImage: "bell.badge")
            }
            NavigationLink {
                AttachmentSettingsView()
            } label: {
                Label("Attachments", systemImage: "paperclip")
            }
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Label("Appearance", systemImage: "paintbrush")
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            NavigationLink {
                StatsView()
            } label: {
                Label("Statistics", systemImage: "chart.bar")
            }
            NavigationLink {
                ExportView()
            } label: {
                Label("Export Data", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("\(Configuration.appVersion) (\(Configuration.buildNumber))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Developer Mode", isOn: $developerModeEnabled)
        }
    }

    private var developerSection: some View {
        Section("Developer") {
            ConnectionStatusRow(status: connectionStatus)

            #if DEBUG
            NavigationLink {
                EnvironmentSwitcherView()
            } label: {
                HStack {
                    Label("Environment", systemImage: "globe")
                    Spacer()
                    Text(EnvironmentManager.shared.currentEnvironment.badge)
                        .font(.title3)
                }
            }
            #endif

            NavigationLink {
                EventLogView()
            } label: {
                Label("Event Log", systemImage: "list.bullet.rectangle")
            }

            NavigationLink {
                SyncDebugView()
            } label: {
                Label("Sync Debug", systemImage: "arrow.triangle.2.circlepath")
            }

            Button("Delete All Data & Restart") {
                showDeleteDataConfirmation = true
            }
            .foregroundStyle(.red)

            #if DEBUG
            Button("Test Sentry Error") {
                ErrorReportingService.capture(message: "Test error from Settings", level: .error)
            }

            Button("Test Sentry Crash") {
                fatalError("Test crash from Settings")
            }
            .foregroundStyle(.red)
            #endif
        }
    }

    // MARK: - Dialog Content

    @ViewBuilder
    private var deleteDataDialogButtons: some View {
        Button("Delete & Restart", role: .destructive) {
            deleteAllDataAndRestart()
        }
        Button("Cancel", role: .cancel) { }
    }

    private var deleteDataDialogMessage: some View {
        Text(
            """
            This will delete all local data including stacks, tasks, events, and sync state. \
            The app will crash and you'll need to relaunch it. \
            Data will be re-synced from the server on next launch.
            """
        )
    }

    // MARK: - Actions

    private func refreshConnectionStatus() async {
        guard let syncManager = syncManager else {
            connectionStatus = .disconnected
            return
        }
        connectionStatus = await syncManager.connectionStatus
    }

    private func pollConnectionStatus() async {
        guard developerModeEnabled else { return }
        while !Task.isCancelled {
            await refreshConnectionStatus()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func deleteAllDataAndRestart() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find Application Support directory")
        }

        let storeURL = appSupport.appendingPathComponent("default.store")
        let storeShmURL = appSupport.appendingPathComponent("default.store-shm")
        let storeWalURL = appSupport.appendingPathComponent("default.store-wal")

        do {
            if fileManager.fileExists(atPath: storeURL.path) {
                try fileManager.removeItem(at: storeURL)
            }
            if fileManager.fileExists(atPath: storeShmURL.path) {
                try fileManager.removeItem(at: storeShmURL)
            }
            if fileManager.fileExists(atPath: storeWalURL.path) {
                try fileManager.removeItem(at: storeWalURL)
            }

            UserDefaults.standard.removeObject(forKey: "com.dequeue.lastSyncCheckpoint")
            fatalError("Data deleted - restart app to resync")
        } catch {
            ErrorReportingService.capture(error: error, context: ["action": "delete_all_data"])
            fatalError("Failed to delete data: \(error.localizedDescription)")
        }
    }

    private func signOut() async {
        isSigningOut = true
        do {
            try await authService.signOut()
        } catch {
            signOutError = error.localizedDescription
            showSignOutError = true
            ErrorReportingService.capture(error: error, context: ["action": "sign_out"])
        }
        isSigningOut = false
    }
}

// MARK: - Connection Status Row

private struct ConnectionStatusRow: View {
    let status: ConnectionStatus
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator
            Text(statusLabel)
                .foregroundStyle(status == .connected ? .primary : .secondary)
        }
        .onAppear { isPulsing = true }
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .scaleEffect(isPulsing && status == .connected ? 1.2 : 1.0)
            .opacity(isPulsing && status == .connected ? 0.7 : 1.0)
            .animation(
                status == .connected
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
    }

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var statusLabel: String {
        switch status {
        case .connected: return "Live Connection"
        case .connecting: return "Connecting..."
        case .disconnected: return "No Live Connection"
        }
    }
}

#Preview {
    SettingsView()
}
