//
//  ArcHistoryView.swift
//  Dequeue
//
//  Shows change history for an arc with all events (including child elements)
//

import SwiftUI
import SwiftData

struct ArcHistoryView: View {
    let arc: Arc
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService
    @State private var cachedDeviceId: String = ""
    @State private var events: [Event] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var showLoadError = false
    @State private var eventToRevert: Event?
    @State private var showRevertConfirmation = false
    @State private var revertError: Error?
    @State private var showRevertError = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading history...")
            } else if events.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No events recorded for this arc")
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
        // 2. Automatically refresh when the arc is modified elsewhere
        .task(id: arc.updatedAt) {
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
               let payload = try? event.decodePayload(ArcEventPayload.self) {
                let timestamp = event.timestamp.formatted(date: .abbreviated, time: .shortened)
                Text("This will restore the arc to \"\(payload.title)\" as it was on \(timestamp).")
            }
        }
        .alert("Revert Failed", isPresented: $showRevertError) {
            Button("OK", role: .cancel) { /* Dismiss handled by SwiftUI */ }
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
            Button("OK", role: .cancel) { /* Dismiss handled by SwiftUI */ }
        } message: {
            if let error = loadError {
                Text(error.localizedDescription)
            }
        }
    }

    private var historyList: some View {
        List(events) { event in
            ArcHistoryRow(
                event: event,
                canRevert: canRevert(event),
                onRevert: {
                    eventToRevert = event
                    showRevertConfirmation = true
                }
            )
        }
    }

    private func loadHistory() async {
        isLoading = true
        loadError = nil

        let service = EventService.readOnly(modelContext: modelContext)
        do {
            events = try service.fetchArcHistoryWithRelated(for: arc)
        } catch {
            loadError = error
            showLoadError = true
            events = []
        }
        isLoading = false
    }

    /// Only arc events with full payload data (created/updated) can be reverted to
    private func canRevert(_ event: Event) -> Bool {
        guard event.type == "arc.created" || event.type == "arc.updated" else {
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

        Task {
            do {
                let arcService = ArcService(
                    modelContext: modelContext,
                    userId: authService.currentUserId ?? "",
                    deviceId: cachedDeviceId,
                    syncManager: syncManager
                )
                try await arcService.revertToHistoricalState(arc, from: event)
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

// MARK: - History Row

struct ArcHistoryRow: View {
    let event: Event
    let canRevert: Bool
    let onRevert: () -> Void

    private var actionLabel: String {
        switch event.type {
        // Arc events
        case "arc.created": return "Arc Created"
        case "arc.updated": return "Arc Updated"
        case "arc.completed": return "Arc Completed"
        case "arc.activated": return "Arc Activated"
        case "arc.deactivated": return "Arc Deactivated"
        case "arc.paused": return "Arc Paused"
        case "arc.deleted": return "Arc Deleted"
        case "arc.reordered": return "Arc Reordered"
        // Stack association events
        case "stack.assignedToArc": return "Stack Added"
        case "stack.removedFromArc": return "Stack Removed"
        // Stack events (direct children)
        case "stack.created": return "Stack Created"
        case "stack.updated": return "Stack Updated"
        case "stack.completed": return "Stack Completed"
        case "stack.activated": return "Stack Activated"
        case "stack.deactivated": return "Stack Deactivated"
        case "stack.closed": return "Stack Closed"
        case "stack.deleted": return "Stack Deleted"
        // Reminder events
        case "reminder.created": return "Reminder Set"
        case "reminder.updated": return "Reminder Updated"
        case "reminder.deleted": return "Reminder Removed"
        case "reminder.snoozed": return "Reminder Snoozed"
        // Attachment events
        case "attachment.created": return "Attachment Added"
        case "attachment.updated": return "Attachment Updated"
        case "attachment.deleted": return "Attachment Removed"
        default: return event.type
        }
    }

    private var actionIcon: String {
        switch event.type {
        // Arc events
        case "arc.created": return "plus.circle.fill"
        case "arc.updated": return "pencil.circle.fill"
        case "arc.completed": return "checkmark.circle.fill"
        case "arc.activated": return "play.circle.fill"
        case "arc.deactivated": return "pause.circle.fill"
        case "arc.paused": return "pause.circle.fill"
        case "arc.deleted": return "trash.circle.fill"
        case "arc.reordered": return "arrow.up.arrow.down.circle.fill"
        // Stack association events
        case "stack.assignedToArc": return "link.circle.fill"
        case "stack.removedFromArc": return "link.badge.plus"
        // Stack events
        case "stack.created": return "rectangle.stack.fill.badge.plus"
        case "stack.updated": return "rectangle.stack"
        case "stack.completed": return "checkmark.rectangle.stack.fill"
        case "stack.activated": return "play.rectangle.fill"
        case "stack.deactivated": return "pause.rectangle.fill"
        case "stack.closed": return "xmark.rectangle.fill"
        case "stack.deleted": return "trash"
        // Reminder events
        case "reminder.created": return "bell.fill"
        case "reminder.updated": return "bell.badge"
        case "reminder.deleted": return "bell.slash"
        case "reminder.snoozed": return "moon.zzz.fill"
        // Attachment events
        case "attachment.created": return "paperclip.circle.fill"
        case "attachment.updated": return "paperclip"
        case "attachment.deleted": return "paperclip.badge.ellipsis"
        default: return "questionmark.circle.fill"
        }
    }

    private var actionColor: Color {
        switch event.type {
        // Arc events
        case "arc.created": return .green
        case "arc.updated": return .blue
        case "arc.completed": return .purple
        case "arc.activated": return .green
        case "arc.deactivated": return .orange
        case "arc.paused": return .orange
        case "arc.deleted": return .red
        case "arc.reordered": return .secondary
        // Stack association events
        case "stack.assignedToArc": return .teal
        case "stack.removedFromArc": return .orange
        // Stack events
        case "stack.created": return .teal
        case "stack.updated": return .blue
        case "stack.completed": return .purple
        case "stack.activated": return .green
        case "stack.deactivated": return .orange
        case "stack.closed": return .gray
        case "stack.deleted": return .red
        // Reminder events
        case "reminder.created": return .yellow
        case "reminder.updated": return .yellow
        case "reminder.deleted": return .red
        case "reminder.snoozed": return .indigo
        // Attachment events
        case "attachment.created": return .cyan
        case "attachment.updated": return .blue
        case "attachment.deleted": return .red
        default: return .secondary
        }
    }

    /// Extracts display details from the event payload based on event type
    private var eventDetails: (title: String?, subtitle: String?)? {
        // Arc events
        if event.type.hasPrefix("arc."),
           let payload = try? event.decodePayload(ArcEventPayload.self) {
            return (payload.title, payload.description)
        }
        // Stack association events
        if event.type == "stack.assignedToArc" || event.type == "stack.removedFromArc",
           let payload = try? event.decodePayload(StackArcAssignmentPayload.self) {
            return ("Stack: \(payload.stackId.prefix(8))...", nil)
        }
        // Stack events
        if event.type.hasPrefix("stack."),
           let payload = try? event.decodePayload(StackEventPayload.self) {
            return (payload.title, payload.description)
        }
        // Reminder events
        if event.type.hasPrefix("reminder."),
           let payload = try? event.decodePayload(ReminderEventPayload.self) {
            let dateStr = payload.remindAt.formatted(date: .abbreviated, time: .shortened)
            return ("Reminder for \(dateStr)", nil)
        }
        // Attachment events
        if event.type.hasPrefix("attachment."),
           let payload = try? event.decodePayload(AttachmentEventPayload.self) {
            return (payload.filename, nil)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: actionIcon)
                .font(.title2)
                .foregroundStyle(actionColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(actionLabel)
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
        ArcHistoryView(arc: Arc(title: "Test Arc"))
    }
    .modelContainer(for: [Arc.self, Event.self], inMemory: true)
}
