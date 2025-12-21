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
    @Query(
        filter: #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == false
        },
        sort: \Stack.updatedAt,
        order: .reverse
    ) private var completedStacks: [Stack]

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
        .modelContainer(for: [Stack.self, Task.self, Reminder.self], inMemory: true)
}
