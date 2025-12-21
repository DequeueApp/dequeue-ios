//
//  SettingsView.swift
//  Dequeue
//
//  User settings and preferences
//

import SwiftUI

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
                    Text("Version 1.0.0")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
