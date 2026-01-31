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
        contentView
            .navigationTitle("API Keys")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showCreateSheet) { createKeySheet }
            .sheet(item: $newlyCreatedKey) { keyResponse in
                NewAPIKeyView(keyResponse: keyResponse) {
                    newlyCreatedKey = nil
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .task { await initializeAndLoad() }
            .refreshable { await loadAPIKeys() }
    }

    @ViewBuilder
    private var contentView: some View {
        if isLoading && apiKeys.isEmpty {
            ProgressView("Loading API keys...")
        } else if apiKeys.isEmpty && !isLoading {
            emptyStateView
        } else {
            apiKeysList
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showCreateSheet = true
            } label: {
                Label("Create API Key", systemImage: "plus")
            }
        }
    }

    private var createKeySheet: some View {
        CreateAPIKeySheet(
            apiKeyService: apiKeyService,
            onKeyCreated: { createdKey in
                newlyCreatedKey = createdKey
                Task { await loadAPIKeys() }
            }
        )
    }

    private func initializeAndLoad() async {
        if apiKeyService == nil {
            apiKeyService = APIKeyService(authService: authService)
        }
        await loadAPIKeys()
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

    // swiftlint:disable:next function_body_length
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            scopesRow
            metadataRow
        }
        .padding(.vertical, 4)
    }

    private var headerRow: some View {
        HStack {
            Text(key.name)
                .font(.headline)
            Spacer()
            Text(key.keyPrefix)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
        }
    }

    private var scopesRow: some View {
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
    }

    private var metadataRow: some View {
        HStack {
            Text("Created:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(key.createdAtDate, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("•")
                .foregroundStyle(.secondary)

            if let lastUsed = key.lastUsedAtDate {
                Text("Last used:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(lastUsed, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Never used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                nameSection
                scopesSection
            }
            .navigationTitle("Create API Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Key Name", text: $keyName)
                .autocorrectionDisabled()
        } header: {
            Text("Name")
        } footer: {
            Text("Give this key a descriptive name (e.g., 'Ardonos', 'Zapier Integration')")
        }
    }

    private var scopesSection: some View {
        Section {
            ForEach(availableScopes, id: \.0) { scope, description in
                scopeToggle(scope: scope, description: description)
            }
        } header: {
            Text("Scopes")
        } footer: {
            Text("Select the permissions this API key should have. You can always revoke keys later.")
        }
    }

    private func scopeToggle(scope: String, description: String) -> some View {
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(isCreating)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Create") {
                Task { await createKey() }
            }
            .disabled(keyName.isEmpty || selectedScopes.isEmpty || isCreating)
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
                successHeader
                apiKeyDisplaySection
                Spacer()
                doneButton
            }
            .padding()
            .navigationTitle("API Key Created")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { clearKeyAndDismiss() }
                }
            }
            .onAppear { displayedKey = keyResponse.key }
            .onDisappear { displayedKey = "" }
        }
    }

    private var successHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("API Key Created")
                .font(.title2)
                .fontWeight(.bold)

            Text("Save this key somewhere safe. You won't be able to see it again.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var apiKeyDisplaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your API Key:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                keyTextField
                copyButton
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(.controlBackgroundColor))
        #endif
        .cornerRadius(12)
    }

    private var keyTextField: some View {
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
    }

    private var copyButton: some View {
        Button {
            copyKeyToClipboard()
            showCopyConfirmation = true
        } label: {
            Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .disabled(displayedKey.isEmpty)
    }

    private func copyKeyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = displayedKey
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayedKey, forType: .string)
        #endif
    }

    private var doneButton: some View {
        Button("Done") { clearKeyAndDismiss() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
