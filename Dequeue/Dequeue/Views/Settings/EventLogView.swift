//
//  EventLogView.swift
//  Dequeue
//
//  Shows event log for debugging sync and event sourcing
//

import SwiftUI
import SwiftData

struct EventLogView: View {
    @Query(sort: \Event.timestamp, order: .reverse)
    private var events: [Event]

    @State private var selectedFilter: EventFilter = .all
    @State private var selectedEvent: Event?

    var filteredEvents: [Event] {
        switch selectedFilter {
        case .all:
            return events
        case .stack:
            return events.filter { $0.type.hasPrefix("stack.") }
        case .task:
            return events.filter { $0.type.hasPrefix("task.") }
        case .device:
            return events.filter { $0.type.hasPrefix("device.") }
        case .reminder:
            return events.filter { $0.type.hasPrefix("reminder.") }
        case .pending:
            return events.filter { !$0.isSynced }
        case .synced:
            return events.filter { $0.isSynced }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(EventFilter.allCases, id: \.self) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                if filteredEvents.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "list.bullet.rectangle",
                        description: Text("No events match the current filter.")
                    )
                } else {
                    ForEach(filteredEvents) { event in
                        EventRow(event: event)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEvent = event
                            }
                    }
                }
            } header: {
                Text("\(filteredEvents.count) Events")
            }
        }
        .navigationTitle("Event Log")
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
    }
}

// MARK: - Event Filter

enum EventFilter: String, CaseIterable {
    case all
    case stack
    case task
    case device
    case reminder
    case pending
    case synced

    var label: String {
        switch self {
        case .all: return "All"
        case .stack: return "Stacks"
        case .task: return "Tasks"
        case .device: return "Devices"
        case .reminder: return "Reminders"
        case .pending: return "Pending Sync"
        case .synced: return "Synced"
        }
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: Event

    private var eventIcon: String {
        if event.type.hasPrefix("stack.") { return "square.stack.3d.up" }
        if event.type.hasPrefix("task.") { return "checkmark.circle" }
        if event.type.hasPrefix("device.") { return "iphone" }
        if event.type.hasPrefix("reminder.") { return "bell" }
        return "doc"
    }

    private var eventColor: Color {
        if event.type.contains("created") { return .green }
        if event.type.contains("deleted") { return .red }
        if event.type.contains("updated") { return .blue }
        if event.type.contains("completed") { return .purple }
        return .secondary
    }

    private var timestampText: String {
        event.timestamp.formatted(date: .abbreviated, time: .standard)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: eventIcon)
                .foregroundStyle(eventColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.type)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(timestampText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: event.isSynced ? "checkmark.circle.fill" : "clock")
                    .foregroundStyle(event.isSynced ? .green : .orange)
                    .font(.caption)

                Text(event.isSynced ? "Synced" : "Pending")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Event Detail View

struct EventDetailView: View {
    let event: Event
    @Environment(\.dismiss) private var dismiss

    private var payloadJSON: String {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: event.payload),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return String(data: event.payload, encoding: .utf8) ?? "Unable to decode payload"
        }
        return prettyString
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Event Info") {
                    LabeledContent("ID", value: event.id)
                    LabeledContent("Type", value: event.type)
                    LabeledContent("Timestamp", value: event.timestamp.formatted())
                }

                Section("Sync Status") {
                    LabeledContent("Status", value: event.isSynced ? "Synced" : "Pending")
                    if let syncedAt = event.syncedAt {
                        LabeledContent("Synced At", value: syncedAt.formatted())
                    }
                }

                Section("Payload") {
                    Text(payloadJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Event Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}

#Preview {
    NavigationStack {
        EventLogView()
    }
    .modelContainer(for: [Event.self], inMemory: true)
}
