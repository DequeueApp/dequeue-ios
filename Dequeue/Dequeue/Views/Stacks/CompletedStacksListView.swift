//
//  CompletedStacksListView.swift
//  Dequeue
//
//  Displays list of completed stacks (read-only)
//

import SwiftUI
import SwiftData

struct CompletedStacksListView: View {
    @Query private var completedStacks: [Stack]

    init() {
        // Include completed, closed, and deleted stacks
        // - completed: successfully finished
        // - closed: dismissed without completing
        // - isDeleted=true: explicitly deleted
        let completedRaw = StackStatus.completed.rawValue
        let closedRaw = StackStatus.closed.rawValue
        _completedStacks = Query(
            filter: #Predicate<Stack> { stack in
                // Show deleted stacks, or stacks with completed/closed status
                stack.isDeleted == true ||
                (stack.isDeleted == false &&
                 (stack.statusRawValue == completedRaw || stack.statusRawValue == closedRaw))
            },
            sort: \Stack.updatedAt,
            order: .reverse
        )
    }

    var body: some View {
        Group {
            if completedStacks.isEmpty {
                emptyState
            } else {
                completedList
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Completed or Deleted Stacks",
            systemImage: "checkmark.circle",
            description: Text("Completed, closed, and deleted stacks will appear here")
        )
    }

    // MARK: - Completed List

    private var completedList: some View {
        List {
            ForEach(completedStacks) { stack in
                NavigationLink {
                    StackEditorView(mode: .edit(stack), isReadOnly: true)
                } label: {
                    HStack(spacing: 12) {
                        statusIndicator(for: stack)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stack.title)
                                .font(.headline)
                            completionDetails(for: stack)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Completion Details

    @ViewBuilder
    private func completionDetails(for stack: Stack) -> some View {
        if stack.isDeleted {
            Text("Deleted \(stack.updatedAt, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // Show completion/close date (updatedAt is set when status changes)
            let statusLabel = stack.status == .completed ? "Completed" : "Closed"
            Text("\(statusLabel) \(stack.updatedAt, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Show duration from creation to completion
            let duration = stack.updatedAt.timeIntervalSince(stack.createdAt)
            if duration > 0 {
                Text(durationText(duration))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Formats a time interval into a human-readable duration string
    private func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 {
            let remainingHours = hours % 24
            if remainingHours > 0 {
                return "\(days)d \(remainingHours)h to complete"
            }
            return "\(days)d to complete"
        } else if hours > 0 {
            let remainingMinutes = minutes % 60
            if remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m to complete"
            }
            return "\(hours)h to complete"
        } else if minutes > 0 {
            return "\(minutes)m to complete"
        } else {
            return "< 1m to complete"
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private func statusIndicator(for stack: Stack) -> some View {
        if stack.isDeleted {
            // Deleted stacks get red trash icon
            Image(systemName: "trash.circle.fill")
                .foregroundStyle(.red)
                .imageScale(.medium)
                .accessibilityLabel("Deleted")
        } else {
            switch stack.status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.medium)
                    .accessibilityLabel("Completed successfully")
            case .closed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.medium)
                    .accessibilityLabel("Closed without completing")
            default:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CompletedStacksListView()
    }
    .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
