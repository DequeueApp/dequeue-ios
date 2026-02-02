//
//  StackCompletionStatusBanner.swift
//  Dequeue
//
//  Banner showing completion/deletion details for completed stacks (DEQ-133)
//

import SwiftUI
import SwiftData

struct StackCompletionStatusBanner: View {
    let stack: Stack

    @Environment(\.modelContext) private var modelContext
    @State private var completionEvent: Event?
    @State private var isLoading = true

    var body: some View {
        if !isLoading, stack.status != .active {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    statusIcon
                        .font(.title2)
                        .foregroundStyle(statusColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.headline)
                            .foregroundStyle(statusColor)

                        if let event = completionEvent {
                            Text(timestampText(for: event))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text(taskCompletionSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(statusColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .task(id: stack.id) {
                await loadCompletionEvent()
            }
        }
    }

    // MARK: - Computed Properties

    private var statusIcon: Image {
        if stack.isDeleted {
            return Image(systemName: "trash.circle.fill")
        } else if stack.status == .completed {
            return Image(systemName: "checkmark.circle.fill")
        } else if stack.status == .closed {
            return Image(systemName: "xmark.circle.fill")
        } else {
            return Image(systemName: "circle.fill")
        }
    }

    private var statusColor: Color {
        if stack.isDeleted {
            return .red
        } else if stack.status == .completed {
            return .green
        } else if stack.status == .closed {
            return .orange
        } else {
            return .gray
        }
    }

    private var statusTitle: String {
        if stack.isDeleted {
            return "Deleted"
        } else if stack.status == .completed {
            return "Completed"
        } else if stack.status == .closed {
            return "Closed"
        } else {
            return "Unknown Status"
        }
    }

    private var taskCompletionSummary: String {
        let totalTasks = stack.tasks.count
        let completedCount = stack.completedTasks.count

        if totalTasks == 0 {
            return "No tasks"
        } else if completedCount == totalTasks {
            return "All \(totalTasks) task\(totalTasks == 1 ? "" : "s") completed"
        } else {
            return "\(completedCount) of \(totalTasks) task\(totalTasks == 1 ? "" : "s") completed"
        }
    }

    private func timestampText(for event: Event) -> String {
        let timeStyle: Date.FormatStyle = .dateTime
            .hour()
            .minute()

        let dateStyle: Date.FormatStyle = .dateTime
            .month(.wide)
            .day()
            .year()

        let time = event.timestamp.formatted(timeStyle)
        let date = event.timestamp.formatted(dateStyle)

        if stack.isDeleted {
            return "Deleted at \(time) on \(date)"
        } else if stack.status == .completed {
            return "Completed at \(time) on \(date)"
        } else if stack.status == .closed {
            return "Closed at \(time) on \(date)"
        } else {
            return "Updated at \(time) on \(date)"
        }
    }

    // MARK: - Data Loading

    private func loadCompletionEvent() async {
        isLoading = true
        defer { isLoading = false }

        let service = EventService.readOnly(modelContext: modelContext)

        do {
            let events = try service.fetchStackHistoryWithRelated(for: stack)

            // Find the most recent completion/closure/deletion event
            completionEvent = events.first { event in
                event.type == "stack.completed" ||
                event.type == "stack.closed" ||
                event.type == "stack.deleted"
            }
        } catch {
            // Silently fail - banner just won't show timestamp
            completionEvent = nil
        }
    }
}
