//
//  StackHistoryView.swift
//  Dequeue
//
//  Shows change history for a stack with all events and revert capability
//

import SwiftUI
import SwiftData

struct StackHistoryView: View {
    let stack: Stack
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService
    @AppStorage("developerModeEnabled") private var developerModeEnabled = false
    @State private var cachedDeviceId: String = ""
    @State private var events: [Event] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var showLoadError = false
    @State private var eventToRevert: Event?
    @State private var showRevertConfirmation = false
    @State private var revertError: Error?
    @State private var showRevertError = false
    @State private var selectedEventForDetail: Event?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading history...")
            } else if events.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No events recorded for this stack")
                )
            } else {
                historyList
            }
        }
        .navigationTitle("Event History")
        #if os(macOS)
        // macOS sheets and navigation destinations need explicit frame sizing
        // to render correctly within NavigationStack contexts
        .frame(minWidth: 500, minHeight: 400)
        #endif
        // Use .task(id:) with updatedAt to:
        // 1. Load reliably on both iOS and macOS (onAppear is unreliable on macOS in sheets)
        // 2. Automatically refresh when the stack is modified elsewhere
        .task(id: stack.updatedAt) {
            // Fetch device ID for service creation
            if cachedDeviceId.isEmpty {
                cachedDeviceId = await DeviceService.shared.getDeviceId()
            }
            await loadHistory()
        }
        .confirmationDialog(
            "Revert to this version?",
            isPresented: $showRevertConfirmation,
            titleVisibility: .visible
        ) {
            Button("Revert", role: .destructive) {
                performRevert()
            }
            Button("Cancel", role: .cancel) {
                eventToRevert = nil
            }
        } message: {
            if let event = eventToRevert,
               let payload = try? event.decodePayload(StackEventPayload.self) {
                let timestamp = event.timestamp.formatted(date: .abbreviated, time: .shortened)
                Text("This will restore the stack to \"\(payload.title)\" as it was on \(timestamp).")
            }
        }
        .alert("Revert Failed", isPresented: $showRevertError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = revertError {
                Text(error.localizedDescription)
            }
        }
        .alert("Failed to Load History", isPresented: $showLoadError) {
            Button("Retry") {
                Task {
                    await loadHistory()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            if let error = loadError {
                Text(error.localizedDescription)
            }
        }
    }

    private var historyList: some View {
        List(events) { event in
            StackHistoryRow(
                event: event,
                canRevert: canRevert(event),
                onRevert: {
                    eventToRevert = event
                    showRevertConfirmation = true
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard developerModeEnabled else { return }
                selectedEventForDetail = event
            }
        }
        .sheet(item: $selectedEventForDetail) { event in
            EventDetailTableView(event: event)
        }
    }

    private func loadHistory() async {
        isLoading = true
        loadError = nil

        let service = EventService.readOnly(modelContext: modelContext)
        do {
            events = try service.fetchStackHistoryWithRelated(for: stack)
        } catch {
            loadError = error
            showLoadError = true
            events = []
        }
        isLoading = false
    }

    /// Only events with full payload data (created/updated) can be reverted to
    private func canRevert(_ event: Event) -> Bool {
        guard event.type == "stack.created" || event.type == "stack.updated" else {
            return false
        }
        // Don't allow revert to current state (most recent event)
        guard event.id != events.first?.id else {
            return false
        }
        return true
    }

    private func performRevert() {
        guard let event = eventToRevert else { return }

        let stackService = StackService(
            modelContext: modelContext,
            userId: authService.currentUserId ?? "",
            deviceId: cachedDeviceId,
            syncManager: syncManager
        )

        Task {
            do {
                try await stackService.revertToHistoricalState(stack, from: event)
                // Refresh history to show the new revert event
                await loadHistory()
            } catch {
                revertError = error
                showRevertError = true
            }
        }

        eventToRevert = nil
    }
}

// MARK: - Event Display Configuration

/// Consolidated display properties for event types to reduce code duplication
private struct EventDisplayConfig {
    let label: String
    let icon: String
    let color: Color

    /// Static configuration map for all known event types
    private static let configMap: [String: EventDisplayConfig] = [
        // Stack events
        "stack.created": EventDisplayConfig(label: "Stack Created", icon: "plus.circle.fill", color: .green),
        "stack.updated": EventDisplayConfig(label: "Stack Updated", icon: "pencil.circle.fill", color: .blue),
        "stack.completed": EventDisplayConfig(label: "Stack Completed", icon: "checkmark.circle.fill", color: .purple),
        "stack.activated": EventDisplayConfig(label: "Stack Activated", icon: "play.circle.fill", color: .green),
        "stack.deactivated": EventDisplayConfig(label: "Stack Deactivated", icon: "pause.circle.fill", color: .orange),
        "stack.closed": EventDisplayConfig(label: "Stack Closed", icon: "xmark.circle.fill", color: .gray),
        "stack.deleted": EventDisplayConfig(label: "Stack Deleted", icon: "trash.circle.fill", color: .red),
        "stack.reordered": EventDisplayConfig(label: "Stack Reordered", icon: "arrow.up.arrow.down.circle.fill", color: .secondary),
        // Task events
        "task.created": EventDisplayConfig(label: "Task Added", icon: "checklist", color: .teal),
        "task.updated": EventDisplayConfig(label: "Task Updated", icon: "pencil", color: .blue),
        "task.completed": EventDisplayConfig(label: "Task Completed", icon: "checkmark.square.fill", color: .purple),
        "task.activated": EventDisplayConfig(label: "Task Activated", icon: "star.fill", color: .cyan),
        "task.deleted": EventDisplayConfig(label: "Task Deleted", icon: "trash", color: .red),
        "task.reordered": EventDisplayConfig(label: "Tasks Reordered", icon: "arrow.up.arrow.down", color: .secondary),
        // Reminder events
        "reminder.created": EventDisplayConfig(label: "Reminder Set", icon: "bell.fill", color: .yellow),
        "reminder.updated": EventDisplayConfig(label: "Reminder Updated", icon: "bell.badge", color: .yellow),
        "reminder.deleted": EventDisplayConfig(label: "Reminder Removed", icon: "bell.slash", color: .red),
        "reminder.snoozed": EventDisplayConfig(label: "Reminder Snoozed", icon: "moon.zzz.fill", color: .indigo),
        // Tag events
        "tag.created": EventDisplayConfig(label: "Tag Created", icon: "tag.fill", color: .pink),
        "tag.updated": EventDisplayConfig(label: "Tag Updated", icon: "tag", color: .pink),
        "tag.deleted": EventDisplayConfig(label: "Tag Deleted", icon: "tag.slash", color: .red),
        // Attachment events
        "attachment.added": EventDisplayConfig(label: "Attachment Added", icon: "paperclip.circle.fill", color: .mint),
        "attachment.removed": EventDisplayConfig(label: "Attachment Removed", icon: "paperclip.badge.ellipsis", color: .red)
    ]

    /// Maps event types to their display configuration using dictionary lookup
    static func config(for eventType: String) -> EventDisplayConfig {
        configMap[eventType] ?? EventDisplayConfig(
            label: eventType,
            icon: "questionmark.circle.fill",
            color: .secondary
        )
    }
}

// MARK: - History Row

struct StackHistoryRow: View {
    let event: Event
    let canRevert: Bool
    let onRevert: () -> Void

    private var displayConfig: EventDisplayConfig {
        EventDisplayConfig.config(for: event.type)
    }

    /// Extracts display details from the event payload based on event type
    private var eventDetails: (title: String?, subtitle: String?)? {
        // Stack events
        if event.type.hasPrefix("stack."),
           let payload = try? event.decodePayload(StackEventPayload.self) {
            return (payload.title, payload.description)
        }
        // Task events
        if event.type.hasPrefix("task."),
           let payload = try? event.decodePayload(TaskEventPayload.self) {
            return (payload.title, payload.description)
        }
        // Reminder events
        if event.type.hasPrefix("reminder."),
           let payload = try? event.decodePayload(ReminderEventPayload.self) {
            let dateStr = payload.remindAt.formatted(date: .abbreviated, time: .shortened)
            return ("Reminder for \(dateStr)", nil)
        }
        // Tag events
        if event.type.hasPrefix("tag."),
           let payload = try? event.decodePayload(TagEventPayload.self) {
            return (payload.name, payload.colorHex)
        }
        // Attachment events
        if event.type.hasPrefix("attachment."),
           let payload = try? event.decodePayload(AttachmentEventPayload.self) {
            return (payload.filename, payload.mimeType)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: displayConfig.icon)
                .font(.title2)
                .foregroundStyle(displayConfig.color)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayConfig.label)
                        .font(.headline)
                    Spacer()
                    Text(event.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let details = eventDetails {
                    if let title = details.title {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let subtitle = details.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if canRevert {
                Button {
                    onRevert()
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            if canRevert {
                Button {
                    onRevert()
                } label: {
                    Label("Revert to this version", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        StackHistoryView(stack: Stack(title: "Test Stack"))
    }
    .modelContainer(for: [Stack.self, Event.self], inMemory: true)
}
