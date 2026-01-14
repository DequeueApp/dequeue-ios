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
        // Include both completed and closed stacks (closed stacks are ones that
        // were dismissed without completing - the UI says "find it in completed stacks later")
        let completedRaw = StackStatus.completed.rawValue
        let closedRaw = StackStatus.closed.rawValue
        _completedStacks = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false &&
                (stack.statusRawValue == completedRaw || stack.statusRawValue == closedRaw)
            },
            sort: \Stack.createdAt,
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
            "No Completed Stacks",
            systemImage: "checkmark.circle",
            description: Text("Completed stacks will appear here")
        )
    }

    // MARK: - Completed List

    private var completedList: some View {
        List {
            ForEach(completedStacks) { stack in
                NavigationLink {
                    StackEditorView(mode: .edit(stack), isReadOnly: true)
                } label: {
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
        .listStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        CompletedStacksListView()
    }
    .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
