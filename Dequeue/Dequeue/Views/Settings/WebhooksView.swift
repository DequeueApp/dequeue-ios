//
//  WebhooksView.swift
//  Dequeue
//
//  Webhook management UI in Settings: list, create, delete, test, and view delivery logs.
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.dequeue", category: "WebhooksView")

// MARK: - Webhooks List View

struct WebhooksView: View {
    @Environment(\.webhookService) private var webhookService

    @State private var webhooks: [Webhook] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var testingWebhookId: String?
    @State private var testResult: WebhookTestResult?
    @State private var showTestResult = false

    var body: some View {
        List {
            if isLoading && webhooks.isEmpty {
                ProgressView("Loading webhooks...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if webhooks.isEmpty {
                ContentUnavailableView {
                    Label("No Webhooks", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Webhooks let you receive real-time notifications when tasks or stacks change.")
                } actions: {
                    Button("Create Webhook") {
                        showCreateSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ForEach(webhooks) { webhook in
                    NavigationLink {
                        WebhookDetailView(webhook: webhook, onDelete: {
                            webhooks.removeAll { $0.id == webhook.id }
                        })
                    } label: {
                        WebhookRow(webhook: webhook)
                    }
                }
            }
        }
        .navigationTitle("Webhooks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await loadWebhooks()
        }
        .task {
            await loadWebhooks()
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateWebhookView { newWebhook in
                webhooks.insert(newWebhook, at: 0)
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadWebhooks() async {
        guard let webhookService else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await webhookService.listWebhooks()
            webhooks = response.data
        } catch {
            logger.error("Failed to load webhooks: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Webhook Row

struct WebhookRow: View {
    let webhook: Webhook

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(webhook.url)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                statusBadge
            }

            HStack(spacing: 8) {
                Label("\(webhook.events.count) event\(webhook.events.count == 1 ? "" : "s")",
                      systemImage: "bell")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastDelivery = webhook.lastDeliveryAtDate {
                    Text("Last delivery \(lastDelivery, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(webhook.status.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(webhook.isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
            )
            .foregroundStyle(webhook.isActive ? .green : .secondary)
    }
}

// MARK: - Webhook Detail View

struct WebhookDetailView: View {
    @Environment(\.webhookService) private var webhookService
    @Environment(\.dismiss) private var dismiss

    let webhook: Webhook
    let onDelete: () -> Void

    @State private var deliveries: [WebhookDelivery] = []
    @State private var isLoadingDeliveries = false
    @State private var isTesting = false
    @State private var isDeleting = false
    @State private var testResult: WebhookTestResult?
    @State private var showTestResult = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var nextCursor: String?
    @State private var hasMore = false

    var body: some View {
        List {
            // Webhook Info Section
            Section("Configuration") {
                LabeledContent("URL", value: webhook.url)
                LabeledContent("Status", value: webhook.status.capitalized)
                LabeledContent("Events") {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(webhook.events, id: \.self) { event in
                            Text(event)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                if let prefix = webhook.secretPrefix {
                    LabeledContent("Secret", value: "\(prefix)...")
                }
                LabeledContent("Created", value: webhook.createdAtDate.formatted(.dateTime.month().day().year()))
            }

            // Actions Section
            Section("Actions") {
                Button {
                    Task { await sendTest() }
                } label: {
                    HStack {
                        Label("Send Test Event", systemImage: "paperplane")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTesting)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Label("Delete Webhook", systemImage: "trash")
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeleting)
            }

            // Delivery Logs Section
            Section("Recent Deliveries") {
                if isLoadingDeliveries && deliveries.isEmpty {
                    ProgressView("Loading deliveries...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if deliveries.isEmpty {
                    Text("No deliveries yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(deliveries) { delivery in
                        NavigationLink {
                            DeliveryDetailView(delivery: delivery)
                        } label: {
                            DeliveryRow(delivery: delivery)
                        }
                    }

                    if hasMore {
                        Button("Load More") {
                            Task { await loadMoreDeliveries() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Webhook")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadDeliveries()
        }
        .alert("Test Result", isPresented: $showTestResult) {
            Button("OK") { testResult = nil }
        } message: {
            if let result = testResult {
                if result.success {
                    Text("✅ Success! Response: \(result.responseStatus ?? 0) in \(result.durationMs)ms")
                } else if let error = result.error {
                    Text("❌ Failed: \(error)")
                } else {
                    Text("❌ Failed with status \(result.responseStatus ?? 0)")
                }
            }
        }
        .confirmationDialog("Delete Webhook?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await deleteWebhook() }
            }
        } message: {
            Text("This will permanently delete this webhook and stop all future deliveries.")
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadDeliveries() async {
        guard let webhookService else { return }
        isLoadingDeliveries = true
        defer { isLoadingDeliveries = false }

        do {
            let response = try await webhookService.listDeliveries(webhookId: webhook.id, limit: 20)
            deliveries = response.data
            nextCursor = response.pagination.nextCursor
            hasMore = response.pagination.hasMore
        } catch {
            logger.error("Failed to load deliveries: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreDeliveries() async {
        guard let webhookService, let cursor = nextCursor else { return }

        do {
            let response = try await webhookService.listDeliveries(webhookId: webhook.id, limit: 20, cursor: cursor)
            deliveries.append(contentsOf: response.data)
            nextCursor = response.pagination.nextCursor
            hasMore = response.pagination.hasMore
        } catch {
            logger.error("Failed to load more deliveries: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func sendTest() async {
        guard let webhookService else { return }
        isTesting = true
        defer { isTesting = false }

        do {
            testResult = try await webhookService.testDelivery(webhookId: webhook.id)
            showTestResult = true
            // Reload deliveries to show the test delivery
            await loadDeliveries()
        } catch {
            logger.error("Test delivery failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func deleteWebhook() async {
        guard let webhookService else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await webhookService.deleteWebhook(id: webhook.id)
            onDelete()
            dismiss()
        } catch {
            logger.error("Failed to delete webhook: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Delivery Row

struct DeliveryRow: View {
    let delivery: WebhookDelivery

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                statusIcon
                Text(delivery.eventType)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(delivery.createdAtDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let status = delivery.lastResponseStatus {
                    Text("HTTP \(status)")
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }

                if delivery.attempts > 1 {
                    Text("\(delivery.attempts) attempts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if delivery.isPending {
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        Group {
            if delivery.isSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if delivery.isPending {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline)
    }

    private var statusColor: Color {
        if delivery.isSuccess { return .green }
        if delivery.isPending { return .orange }
        return .red
    }
}

// MARK: - Delivery Detail View

struct DeliveryDetailView: View {
    let delivery: WebhookDelivery

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Event", value: delivery.eventType)
                LabeledContent("Status", value: delivery.status.capitalized)
                LabeledContent("Attempts", value: "\(delivery.attempts)")
                LabeledContent("Created", value: delivery.createdAtDate.formatted(.dateTime))
                if let completed = delivery.completedAtDate {
                    LabeledContent("Completed", value: completed.formatted(.dateTime))
                }
                if let nextRetry = delivery.nextRetryAtDate {
                    LabeledContent("Next Retry", value: nextRetry.formatted(.dateTime))
                }
                if let lastAttempt = delivery.lastAttemptAtDate {
                    LabeledContent("Last Attempt", value: lastAttempt.formatted(.dateTime))
                }
            }

            if let status = delivery.lastResponseStatus {
                Section("Response") {
                    LabeledContent("HTTP Status", value: "\(status)")

                    if let body = delivery.lastResponseBody, !body.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Response Body")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(body)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if let error = delivery.lastError {
                Section("Error") {
                    Text(error)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("IDs") {
                LabeledContent("Delivery ID") {
                    Text(delivery.id)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Event ID") {
                    Text(delivery.eventId)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Webhook ID") {
                    Text(delivery.webhookId)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Delivery")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Create Webhook View

struct CreateWebhookView: View {
    @Environment(\.webhookService) private var webhookService
    @Environment(\.dismiss) private var dismiss

    let onCreate: (Webhook) -> Void

    @State private var url = ""
    @State private var selectedEvents: Set<String> = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdSecret: String?
    @State private var showSecret = false

    private let availableEvents = [
        "task.created",
        "task.updated",
        "task.completed",
        "task.deleted",
        "stack.created",
        "stack.updated",
        "stack.deleted"
    ]

    var body: some View {
        NavigationStack {
            Form {
                endpointSection
                eventsSection
                secretSection
            }
            .navigationTitle("New Webhook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    confirmButton
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var endpointSection: some View {
        Section("Endpoint") {
            TextField("https://example.com/webhook", text: $url)
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        }
    }

    private var eventsSection: some View {
        Section("Events") {
            ForEach(Array(availableEvents), id: \.self) { (event: String) in
                eventRow(event)
            }
            toggleAllButton
        }
    }

    private func eventRow(_ event: String) -> some View {
        Button {
            if selectedEvents.contains(event) {
                selectedEvents.remove(event)
            } else {
                selectedEvents.insert(event)
            }
        } label: {
            HStack {
                Text(event)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedEvents.contains(event) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var toggleAllButton: some View {
        Button(selectedEvents.count == availableEvents.count ? "Deselect All" : "Select All") {
            if selectedEvents.count == availableEvents.count {
                selectedEvents.removeAll()
            } else {
                selectedEvents = Set(availableEvents)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var secretSection: some View {
        if let secret = createdSecret {
            Section("Signing Secret") {
                secretContent(secret)
            }
        }
    }

    private func secretContent(_ secret: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save this secret now — it won't be shown again.")
                .font(.caption)
                .foregroundStyle(.orange)

            HStack {
                Group {
                    if showSecret {
                        Text(secret)
                    } else {
                        Text(String(repeating: "•", count: 32))
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

                Spacer()

                Button {
                    showSecret.toggle()
                } label: {
                    Image(systemName: showSecret ? "eye.slash" : "eye")
                }
            }

            Button {
                copyToClipboard(secret)
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    @ViewBuilder
    private var confirmButton: some View {
        if createdSecret != nil {
            Button("Done") { dismiss() }
        } else {
            Button("Create") {
                Task { await createWebhook() }
            }
            .disabled(url.isEmpty || selectedEvents.isEmpty || isCreating)
        }
    }

    private func createWebhook() async {
        guard let webhookService else { return }
        isCreating = true
        defer { isCreating = false }

        do {
            let request = CreateWebhookRequest(
                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                events: Array(selectedEvents).sorted(),
                secret: nil
            )
            let webhook = try await webhookService.createWebhook(request)
            createdSecret = webhook.secret
            onCreate(webhook)
        } catch {
            logger.error("Failed to create webhook: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}
