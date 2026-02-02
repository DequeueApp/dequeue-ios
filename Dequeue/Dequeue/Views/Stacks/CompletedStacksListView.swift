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
                        VStack(alignment: .leading) {
                            Text(stack.title)
                                .font(.headline)
                            Text("Created \(stack.createdAt, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
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
