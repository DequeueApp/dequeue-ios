//
//  SettingsView.swift
//  Dequeue
//
//  User settings and preferences
//

import SwiftUI
import Sentry

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Text("Sign In")
                }

                Section("Preferences") {
                    Text("Notifications")
                    Text("Appearance")
                }

                Section("About") {
                    Text("Version \(Configuration.appVersion)")
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
        }
    }
}

#Preview {
    SettingsView()
}
