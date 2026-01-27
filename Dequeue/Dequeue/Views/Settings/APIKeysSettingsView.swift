//
//  APIKeysSettingsView.swift
//  Dequeue
//
//  Manage API keys for external integrations
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct APIKeysSettingsView: View {
    @Environment(\.authService) private var authService
    @State private var apiKeyService: APIKeyService?
    @State private var apiKeys: [APIKey] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showCreateSheet = false
    @State private var newlyCreatedKey: CreateAPIKeyResponse?

    var body: some View {
        Group {
            if isLoading && apiKeys.isEmpty {
                ProgressView("Loading API keys...")
            } else if apiKeys.isEmpty && !isLoading {
                emptyStateView
            } else {
                apiKeysList
            }
        }
        .navigationTitle("API Keys")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create API Key", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateAPIKeySheet(
                apiKeyService: apiKeyService,
                onKeyCreated: { createdKey in
                    newlyCreatedKey = createdKey
                    Task {
                        await loadAPIKeys()
                    }
                }
            )
        }
        .sheet(item: $newlyCreatedKey) { keyResponse in
            NewAPIKeyView(keyResponse: keyResponse) {
                newlyCreatedKey = nil
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                // Dismisses alert; no additional action needed
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .task {
            if apiKeyService == nil {
                apiKeyService = APIKeyService(authService: authService)
            }
            await loadAPIKeys()
        }
        .refreshable {
            await loadAPIKeys()
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No API Keys", systemImage: "key")
        } description: {
            Text("Create an API key to enable external integrations with Dequeue.")
        } actions: {
            Button("Create API Key") {
                showCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var apiKeysList: some View {
        List {
            Section {
                ForEach(apiKeys) { key in
                    APIKeyRow(key: key)
                }
                .onDelete { indexSet in
                    Task {
                        await deleteKeys(at: indexSet)
                    }
                }
            } header: {
                Text("Active Keys")
            } footer: {
                // swiftlint:disable:next line_length
                Text("API keys allow external services to access your Dequeue data. Keep them secure and revoke any keys you're no longer using.")
            }
        }
    }

    private func loadAPIKeys() async {
        guard let service = apiKeyService else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            apiKeys = try await service.listAPIKeys()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deleteKeys(at indexSet: IndexSet) async {
        guard let service = apiKeyService else { return }

        for index in indexSet {
            let key = apiKeys[index]

            do {
                try await service.revokeAPIKey(id: key.id)
                await loadAPIKeys()
            } catch {
                errorMessage = "Failed to revoke key: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

// MARK: - API Key Row

private struct APIKeyRow: View {
    let key: APIKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(key.name)
                    .font(.headline)
                Spacer()
                Text(key.keyPrefix)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Scopes:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(key.scopes, id: \.self) { scope in
                    Text(scope)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(4)
                }
            }

            HStack {
                Text("Created:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(key.createdAtDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastUsed = key.lastUsedAtDate {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("Last used:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lastUsed, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("Never used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create API Key Sheet

private struct CreateAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let apiKeyService: APIKeyService?
    let onKeyCreated: (CreateAPIKeyResponse) -> Void

    @State private var keyName = ""
    @State private var selectedScopes: Set<String> = ["read", "write"]
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let availableScopes = [
        ("read", "Read access to arcs, stacks, tasks, and reminders"),
        ("write", "Create, update, and delete arcs, stacks, tasks, and reminders"),
        ("admin", "Manage API keys and account settings")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Key Name", text: $keyName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Name")
                } footer: {
                    Text("Give this key a descriptive name (e.g., 'Ardonos', 'Zapier Integration')")
                }

                Section {
                    ForEach(availableScopes, id: \.0) { scope, description in
                        Toggle(isOn: Binding(
                            get: { selectedScopes.contains(scope) },
                            set: { isSelected in
                                if isSelected {
                                    selectedScopes.insert(scope)
                                } else {
                                    selectedScopes.remove(scope)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scope.capitalized)
                                    .font(.body)
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Scopes")
                } footer: {
                    Text("Select the permissions this API key should have. You can always revoke keys later.")
                }
            }
            .navigationTitle("Create API Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createKey()
                        }
                    }
                    .disabled(keyName.isEmpty || selectedScopes.isEmpty || isCreating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    // Dismisses alert; no additional action needed
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }

    private func createKey() async {
        guard let service = apiKeyService else { return }

        isCreating = true
        defer { isCreating = false }

        do {
            let createdKey = try await service.createAPIKey(
                name: keyName,
                scopes: Array(selectedScopes)
            )
            dismiss()
            onKeyCreated(createdKey)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - New API Key View

private struct NewAPIKeyView: View {
    let keyResponse: CreateAPIKeyResponse
    let onDismiss: () -> Void

    @State private var showCopyConfirmation = false
    @State private var displayedKey: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text("API Key Created")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Save this key somewhere safe. You won't be able to see it again.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your API Key:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(displayedKey)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            #if os(iOS)
                            .background(Color(.secondarySystemBackground))
                            #else
                            .background(Color(.windowBackgroundColor))
                            #endif
                            .cornerRadius(8)

                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = displayedKey
                            #elseif os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(displayedKey, forType: .string)
                            #endif
                            showCopyConfirmation = true
                        } label: {
                            Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(displayedKey.isEmpty)
                    }
                }
                .padding()
                #if os(iOS)
                .background(Color(.systemGroupedBackground))
                #else
                .background(Color(.controlBackgroundColor))
                #endif
                .cornerRadius(12)

                Spacer()

                Button("Done") {
                    clearKeyAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("API Key Created")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        clearKeyAndDismiss()
                    }
                }
            }
            .onAppear {
                // Copy the key to local state for display
                displayedKey = keyResponse.key
            }
            .onDisappear {
                // Security: Clear the sensitive key from memory when view disappears
                displayedKey = ""
            }
        }
    }

    /// Clears the sensitive key from memory before dismissing
    private func clearKeyAndDismiss() {
        displayedKey = ""
        onDismiss()
    }
}

#Preview {
    NavigationStack {
        APIKeysSettingsView()
            .environment(\.authService, {
                let mock = MockAuthService()
                mock.mockSignIn()
                return mock
            }())
    }
}
