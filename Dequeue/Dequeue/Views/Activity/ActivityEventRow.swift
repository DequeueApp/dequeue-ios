//
//  ActivityEventRow.swift
//  Dequeue
//
//  A single row in the activity timeline showing an event
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.dequeue", category: "ActivityEventRow")

struct ActivityEventRow: View {
    let event: Event
    let onStackSelected: (String) -> Void

    /// Extracts entity name from the event payload
    private var entityName: String {
        extractEntityName() ?? "Unknown"
    }

    /// Returns the stack ID if this event is stack-related
    private var relatedStackId: String? {
        extractRelatedStackId()
    }

    var body: some View {
        Button {
            if let stackId = relatedStackId {
                onStackSelected(stackId)
            }
        } label: {
            HStack(spacing: 12) {
                // Icon based on event type
                eventIcon
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    // Event description
                    Text(eventDescription)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    // Entity name
                    Text(entityName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Timestamp
                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(formattedTime), \(eventDescription), \(entityName)")
        .accessibilityHint(relatedStackId != nil ? "Double tap to view details" : "")
    }

    // MARK: - Event Display

    private var eventIcon: some View {
        Group {
            switch event.eventType {
            case .stackCompleted, .taskCompleted, .arcCompleted:
                Image(systemName: "checkmark.circle.fill")
            case .stackActivated, .taskActivated, .arcActivated:
                Image(systemName: "play.circle.fill")
            case .stackCreated:
                Image(systemName: "plus.circle.fill")
            default:
                Image(systemName: "circle.fill")
            }
        }
    }

    private var iconColor: Color {
        switch event.eventType {
        case .stackCompleted, .taskCompleted, .arcCompleted:
            return .green
        case .stackActivated, .taskActivated, .arcActivated:
            return .blue
        case .stackCreated:
            return .orange
        default:
            return .gray
        }
    }

    private var eventDescription: String {
        switch event.eventType {
        case .stackCompleted:
            return "Completed stack"
        case .stackActivated:
            return "Started stack"
        case .stackCreated:
            return "Created stack"
        case .taskCompleted:
            return "Completed task"
        case .taskActivated:
            return "Started task"
        case .arcCompleted:
            return "Completed arc"
        case .arcActivated:
            return "Started arc"
        default:
            return "Activity"
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.timestamp)
    }

    // MARK: - Payload Extraction

    private func extractEntityName() -> String? {
        // Try stack payload first
        if let payload = try? event.decodePayload(StackEventPayload.self) {
            return payload.title
        }

        // Try task payload
        if let payload = try? event.decodePayload(TaskEventPayload.self) {
            return payload.title
        }

        // Try arc payload
        if let payload = try? event.decodePayload(ArcEventPayload.self) {
            return payload.title
        }

        // Try status payload (for activated/completed events)
        if let payload = try? event.decodePayload(StackStatusPayload.self) {
            return payload.fullState.title
        }

        if let payload = try? event.decodePayload(TaskStatusPayload.self) {
            return payload.fullState.title
        }

        if let payload = try? event.decodePayload(ArcStatusPayload.self) {
            return payload.fullState.title
        }

        logger.warning("Could not extract entity name from event \(event.id) of type \(event.type)")
        return nil
    }

    private func extractRelatedStackId() -> String? {
        switch event.eventType {
        case .stackCompleted, .stackActivated, .stackCreated:
            // Direct stack event
            if let payload = try? event.decodePayload(StackEventPayload.self) {
                return payload.id
            }
            if let payload = try? event.decodePayload(StackStatusPayload.self) {
                return payload.stackId
            }
            if let payload = try? event.decodePayload(StackCreatedPayload.self) {
                return payload.stackId
            }
            return event.entityId

        case .taskCompleted, .taskActivated:
            // Task event - get parent stack ID
            if let payload = try? event.decodePayload(TaskEventPayload.self) {
                return payload.stackId
            }
            if let payload = try? event.decodePayload(TaskStatusPayload.self) {
                return payload.stackId
            }
            return nil

        default:
            return nil
        }
    }
}

#Preview {
    List {
        ActivityEventRow(
            event: Event(
                type: "stack.completed",
                payload: Data(),
                userId: "test",
                deviceId: "test",
                appId: "test"
            ),
            onStackSelected: { _ in }
        )
    }
    .listStyle(.plain)
}
