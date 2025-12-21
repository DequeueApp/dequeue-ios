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
        let completed = StackStatus.completed
        _completedStacks = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false && stack.status == completed
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

#Preview {
    CompletedStacksView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
