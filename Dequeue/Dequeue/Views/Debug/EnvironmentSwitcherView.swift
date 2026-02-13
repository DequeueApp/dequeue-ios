//
//  EnvironmentSwitcherView.swift
//  Dequeue
//
//  Debug menu for switching app environment (debug builds only)
//

import SwiftUI

/// Environment switcher view for debug builds
/// Allows switching between development, staging, and production environments
struct EnvironmentSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var environmentManager = EnvironmentManager.shared
    @State private var showingRestartAlert = false
    @State private var selectedEnvironment: Environment

    init() {
        _selectedEnvironment = State(initialValue: EnvironmentManager.shared.currentEnvironment)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Environment.allCases) { environment in
                        Button {
                            selectedEnvironment = environment
                        } label: {
                            HStack {
                                Text(environment.badge)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(environment.displayName)
                                        .font(.headline)
                                    Text(environment.configuration.syncAppId)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(environment.configuration.syncServiceBaseURL.absoluteString)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if environment == environmentManager.currentEnvironment {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .foregroundStyle(environment == environmentManager.currentEnvironment ? .primary : .secondary)
                    }
                } header: {
                    Text("Select Environment")
                } footer: {
                    Text("Switching environments will sign you out and clear local data. This feature is only available in debug builds.")
                }

                if selectedEnvironment != environmentManager.currentEnvironment {
                    Section {
                        Button {
                            showingRestartAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Switch to \(selectedEnvironment.displayName)")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section {
                    LabeledContent("Current Environment", value: environmentManager.currentEnvironment.displayName)
                    LabeledContent("App ID", value: environmentManager.configuration.syncAppId)
                    LabeledContent("Sync URL", value: environmentManager.configuration.syncServiceBaseURL.absoluteString)
                    LabeledContent("API URL", value: environmentManager.configuration.dequeueAPIBaseURL.absoluteString)
                } header: {
                    Text("Current Configuration")
                }
            }
            .navigationTitle("Environment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Restart Required", isPresented: $showingRestartAlert) {
                Button("Cancel", role: .cancel) {
                    selectedEnvironment = environmentManager.currentEnvironment
                }
                Button("Switch & Restart", role: .destructive) {
                    switchEnvironment()
                }
            } message: {
                Text("Switching to \(selectedEnvironment.displayName) will sign you out, clear all local data, and restart the app.")
            }
        }
    }

    private func switchEnvironment() {
        // Switch environment
        if environmentManager.switchEnvironment(to: selectedEnvironment) {
            // In a real app, you would:
            // 1. Sign out user
            // 2. Clear local database
            // 3. Restart the app or reset navigation state
            // For now, just dismiss
            dismiss()

            // Add breadcrumb for debugging
            ErrorReportingService.addBreadcrumb(
                category: "environment",
                message: "Environment switched",
                data: [
                    "from": environmentManager.currentEnvironment.rawValue,
                    "to": selectedEnvironment.rawValue
                ]
            )
        }
    }
}

#if DEBUG
#Preview {
    EnvironmentSwitcherView()
}
#endif
