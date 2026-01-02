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
    @Query private var stacks: [Stack]
    @Query private var reminders: [Reminder]

    init() {
        // Filter for active stacks only (exclude completed, closed, and archived)
        // Note: SwiftData #Predicate doesn't support captured enum values,
        // so we compare against the rawValue string directly
        let activeRawValue = StackStatus.active.rawValue
        _stacks = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false &&
                stack.isDraft == false &&
                stack.statusRawValue == activeRawValue
            },
            sort: \Stack.sortOrder
        )

        // Fetch active reminders for badge count
        _reminders = Query(
            filter: #Predicate<Reminder> { reminder in
                reminder.isDeleted == false
            }
        )
    }

    @State private var selectedStack: Stack?
    @State private var showReminders = false

    /// Count of overdue reminders for badge display
    private var overdueCount: Int {
        reminders.filter { $0.status == .active && $0.isPastDue }.count
    }

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
                        showReminders = true
                    } label: {
                        Image(systemName: overdueCount > 0 ? "bell.badge.fill" : "bell")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(overdueCount > 0 ? .red : .primary, .primary)
                    }
                    .overlay(alignment: .topTrailing) {
                        if overdueCount > 0 {
                            Text("\(overdueCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 8, y: -8)
                        }
                    }
                }
            }
            .sheet(isPresented: $showReminders) {
                RemindersListView()
            }
            .sheet(item: $selectedStack) { stack in
                StackEditorView(mode: .edit(stack))
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
