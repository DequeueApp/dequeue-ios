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
    @State private var events: [Event] = []
    @State private var isLoading = true
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
        .navigationTitle("History")
        .task {
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
        let service = EventService(modelContext: modelContext)
        events = (try? service.fetchHistoryReversed(for: stack.id)) ?? []
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
            let stackService = StackService(modelContext: modelContext)
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
        case "stack.created": return "Created"
        case "stack.updated": return "Updated"
        case "stack.completed": return "Completed"
        case "stack.activated": return "Activated"
        case "stack.deactivated": return "Deactivated"
        case "stack.closed": return "Closed"
        case "stack.deleted": return "Deleted"
        case "stack.reordered": return "Reordered"
        default: return event.type
        }
    }

    private var actionIcon: String {
        switch event.type {
        case "stack.created": return "plus.circle.fill"
        case "stack.updated": return "pencil.circle.fill"
        case "stack.completed": return "checkmark.circle.fill"
        case "stack.activated": return "play.circle.fill"
        case "stack.deactivated": return "pause.circle.fill"
        case "stack.closed": return "xmark.circle.fill"
        case "stack.deleted": return "trash.circle.fill"
        case "stack.reordered": return "arrow.up.arrow.down.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var actionColor: Color {
        switch event.type {
        case "stack.created": return .green
        case "stack.updated": return .blue
        case "stack.completed": return .purple
        case "stack.activated": return .green
        case "stack.deactivated": return .orange
        case "stack.closed": return .gray
        case "stack.deleted": return .red
        case "stack.reordered": return .secondary
        default: return .secondary
        }
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

                if let payload = try? event.decodePayload(StackEventPayload.self) {
                    Text(payload.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let description = payload.description, !description.isEmpty {
                        Text(description)
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
