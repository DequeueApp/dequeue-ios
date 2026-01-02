//
//  CompletedStacksView.swift
//  Dequeue
//
//  Shows completed stacks archive
//

import SwiftUI
import SwiftData

struct CompletedStacksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var completedStacks: [Stack]

    init() {
        // Include both completed and closed stacks (closed stacks are ones that
        // were dismissed without completing - the UI says "find it in completed stacks later")
        // Note: SwiftData #Predicate doesn't support captured enum values,
        // so we compare against the rawValue string directly
        let completedRaw = StackStatus.completed.rawValue
        let closedRaw = StackStatus.closed.rawValue
        _completedStacks = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false &&
                (stack.statusRawValue == completedRaw || stack.statusRawValue == closedRaw)
            },
            sort: \Stack.updatedAt,
            order: .reverse
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if completedStacks.isEmpty {
                    emptyState
                } else {
                    completedList
                }
            }
            .navigationTitle("Completed")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Completed Stacks",
            systemImage: "checkmark.circle",
            description: Text("Completed stacks will appear here")
        )
    }

    private var completedList: some View {
        List {
            ForEach(completedStacks) { stack in
                NavigationLink {
                    StackEditorView(mode: .edit(stack), isReadOnly: true)
                } label: {
                    VStack(alignment: .leading) {
                        Text(stack.title)
                            .font(.headline)
                        Text("Completed \(stack.updatedAt, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    CompletedStacksView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
