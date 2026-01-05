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

        do {
            let stackService = StackService(
                modelContext: modelContext,
                userId: authService.currentUserId ?? "",
                deviceId: cachedDeviceId,
                syncManager: syncManager
            )
            try stackService.revertToHistoricalState(stack, from: event)
            // Refresh history to show the new revert event
            Task {
                await loadHistory()
            }
        } catch {
            revertError = error
            showRevertError = true
        }

        eventToRevert = nil
    }
}

// MARK: - History Row

struct StackHistoryRow: View {
    let event: Event
    let canRevert: Bool
    let onRevert: () -> Void

    private var actionLabel: String {
        switch event.type {
        // Stack events
        case "stack.created": return "Stack Created"
        case "stack.updated": return "Stack Updated"
        case "stack.completed": return "Stack Completed"
        case "stack.activated": return "Stack Activated"
        case "stack.deactivated": return "Stack Deactivated"
        case "stack.closed": return "Stack Closed"
        case "stack.deleted": return "Stack Deleted"
        case "stack.reordered": return "Stack Reordered"
        // Task events
        case "task.created": return "Task Added"
        case "task.updated": return "Task Updated"
        case "task.completed": return "Task Completed"
        case "task.activated": return "Task Activated"
        case "task.deleted": return "Task Deleted"
        case "task.reordered": return "Tasks Reordered"
        // Reminder events
        case "reminder.created": return "Reminder Set"
        case "reminder.updated": return "Reminder Updated"
        case "reminder.deleted": return "Reminder Removed"
        case "reminder.snoozed": return "Reminder Snoozed"
        default: return event.type
        }
    }

    private var actionIcon: String {
        switch event.type {
        // Stack events
        case "stack.created": return "plus.circle.fill"
        case "stack.updated": return "pencil.circle.fill"
        case "stack.completed": return "checkmark.circle.fill"
        case "stack.activated": return "play.circle.fill"
        case "stack.deactivated": return "pause.circle.fill"
        case "stack.closed": return "xmark.circle.fill"
        case "stack.deleted": return "trash.circle.fill"
        case "stack.reordered": return "arrow.up.arrow.down.circle.fill"
        // Task events
        case "task.created": return "checklist"
        case "task.updated": return "pencil"
        case "task.completed": return "checkmark.square.fill"
        case "task.activated": return "star.fill"
        case "task.deleted": return "trash"
        case "task.reordered": return "arrow.up.arrow.down"
        // Reminder events
        case "reminder.created": return "bell.fill"
        case "reminder.updated": return "bell.badge"
        case "reminder.deleted": return "bell.slash"
        case "reminder.snoozed": return "moon.zzz.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var actionColor: Color {
        switch event.type {
        // Stack events
        case "stack.created": return .green
        case "stack.updated": return .blue
        case "stack.completed": return .purple
        case "stack.activated": return .green
        case "stack.deactivated": return .orange
        case "stack.closed": return .gray
        case "stack.deleted": return .red
        case "stack.reordered": return .secondary
        // Task events
        case "task.created": return .teal
        case "task.updated": return .blue
        case "task.completed": return .purple
        case "task.activated": return .cyan
        case "task.deleted": return .red
        case "task.reordered": return .secondary
        // Reminder events
        case "reminder.created": return .yellow
        case "reminder.updated": return .yellow
        case "reminder.deleted": return .red
        case "reminder.snoozed": return .indigo
        default: return .secondary
        }
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
        StackHistoryView(stack: Stack(title: "Test Stack"))
    }
    .modelContainer(for: [Stack.self, Event.self], inMemory: true)
}
