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
    @AppStorage("developerModeEnabled") private var developerModeEnabled = false
    @State private var isSigningOut = false
    @State private var showSignOutError = false
    @State private var signOutError: String?
    @State private var showDeleteDataConfirmation = false

    private var userEmail: String? {
        Clerk.shared.user?.primaryEmailAddress?.emailAddress
    }

    var body: some View {
        NavigationStack {
            List {
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

                    Button(role: .destructive) {
                        Task {
                            await signOut()
                        }
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

                Section("Preferences") {
                    Text("Notifications")
                    Text("Appearance")
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Configuration.appVersion) (\(Configuration.buildNumber))")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Advanced") {
                    Toggle("Developer Mode", isOn: $developerModeEnabled)
                }

                if developerModeEnabled {
                    Section("Developer") {
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

                        #if DEBUG
                        Button("Test Sentry Error") {
                            ErrorReportingService.capture(message: "Test error from Settings", level: .error)
                        }

                        Button("Test Sentry Crash") {
                            fatalError("Test crash from Settings")
                        }
                        .foregroundStyle(.red)

                        Button("Delete All Data & Restart") {
                            showDeleteDataConfirmation = true
                        }
                        .foregroundStyle(.red)
                        #endif
                    }
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
                Button("Delete & Restart", role: .destructive) {
                    deleteAllDataAndRestart()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(
                    """
                    This will delete all local data including stacks, tasks, events, and sync state. \
                    The app will crash and you'll need to relaunch it. \
                    Data will be re-synced from the server on next launch.
                    """
                )
            }
        }
    }

    private func deleteAllDataAndRestart() {
        // Delete SwiftData store files
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

            // Clear sync checkpoint
            UserDefaults.standard.removeObject(forKey: "com.dequeue.lastSyncCheckpoint")

            // Crash the app to force restart with fresh data
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

#Preview {
    SettingsView()
}
