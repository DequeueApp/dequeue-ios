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
    @State private var isSigningOut = false
    @State private var showSignOutError = false
    @State private var signOutError: String?

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

                #if DEBUG
                Section("Debug") {
                    Button("Test Sentry Error") {
                        ErrorReportingService.capture(message: "Test error from Settings", level: .error)
                    }

                    Button("Test Sentry Crash") {
                        fatalError("Test crash from Settings")
                    }
                    .foregroundStyle(.red)
                }
                #endif
            }
            .navigationTitle("Settings")
            .alert("Sign Out Failed", isPresented: $showSignOutError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(signOutError ?? "An unknown error occurred")
            }
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
