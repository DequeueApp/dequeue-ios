//
//  HomeView.swift
//  Dequeue
//
//  Main dashboard showing active stacks
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == false
        },
        sort: \Stack.sortOrder
    ) private var stacks: [Stack]

    @State private var selectedStack: Stack?

    var body: some View {
        NavigationStack {
            Group {
                if stacks.isEmpty {
                    emptyState
                } else {
                    stackList
                }
            }
            .navigationTitle("Dequeue")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        // TODO: Show notifications
                    } label: {
                        Image(systemName: "bell")
                    }
                }
            }
            .sheet(item: $selectedStack) { stack in
                Text("Stack: \(stack.title)")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Stacks",
            systemImage: "tray",
            description: Text("Add a stack to get started")
        )
    }

    // MARK: - Stack List

    private var stackList: some View {
        List {
            ForEach(stacks) { stack in
                StackRowView(stack: stack)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedStack = stack
                    }
            }
            .onMove(perform: moveStacks)
            .onDelete(perform: deleteStacks)
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func moveStacks(from source: IndexSet, to destination: Int) {
        var reorderedStacks = stacks
        reorderedStacks.move(fromOffsets: source, toOffset: destination)

        for (index, stack) in reorderedStacks.enumerated() {
            stack.sortOrder = index
            stack.updatedAt = Date()
            stack.syncState = .pending
        }
    }

    private func deleteStacks(at offsets: IndexSet) {
        for index in offsets {
            stacks[index].isDeleted = true
            stacks[index].updatedAt = Date()
            stacks[index].syncState = .pending
        }
    }
}

// MARK: - Stack Row

struct StackRowView: View {
    let stack: Stack

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stack.title)
                    .font(.headline)

                Spacer()

                if stack.sortOrder == 0 {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
            }

            if let activeTask = stack.activeTask {
                Text(activeTask.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !stack.activeReminders.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                    Text("\(stack.activeReminders.count)")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
