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
    @Environment(\.syncManager) private var syncManager
    @Query private var stacks: [Stack]
    @Query private var allStacks: [Stack]
    @Query private var tasks: [QueueTask]
    @Query private var reminders: [Reminder]

    @State private var syncStatusViewModel: SyncStatusViewModel?

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

        // Fetch all stacks for reminder navigation (includes completed, closed, etc.)
        _allStacks = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false
            }
        )

        // Fetch all tasks for reminder navigation
        _tasks = Query(
            filter: #Predicate<QueueTask> { task in
                task.isDeleted == false
            }
        )

        // Fetch active reminders for badge count
        _reminders = Query(
            filter: #Predicate<Reminder> { reminder in
                reminder.isDeleted == false
            }
        )
    }

    @State private var selectedStack: Stack?
    @State private var selectedTask: QueueTask?
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
                    if let viewModel = syncStatusViewModel {
                        SyncStatusIndicator(viewModel: viewModel)
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        showReminders = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: overdueCount > 0 ? "bell.badge.fill" : "bell")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(overdueCount > 0 ? .red : .primary, .primary)
                                .font(.body)

                            if overdueCount > 0 {
                                Text("\(overdueCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .frame(minWidth: 14, minHeight: 14)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                                    .offset(x: 6, y: -6)
                            }
                        }
                        .frame(width: 32, height: 32)
                    }
                }
            }
            .task {
                // Initialize sync status view model
                if syncStatusViewModel == nil {
                    syncStatusViewModel = SyncStatusViewModel(modelContext: modelContext)
                    if let syncManager = syncManager {
                        syncStatusViewModel?.setSyncManager(syncManager)
                    }
                }
            }
            .sheet(isPresented: $showReminders) {
                RemindersListView(onGoToItem: handleGoToItem)
            }
            .sheet(item: $selectedStack) { stack in
                StackEditorView(mode: .edit(stack))
            }
            .sheet(item: $selectedTask) { task in
                NavigationStack {
                    TaskDetailView(task: task)
                }
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

    /// Handle navigation to a Stack or Task from the Reminders list
    private func handleGoToItem(parentId: String, parentType: ParentType) {
        switch parentType {
        case .stack:
            if let stack = allStacks.first(where: { $0.id == parentId }) {
                selectedStack = stack
            }
        case .task:
            if let task = tasks.first(where: { $0.id == parentId }) {
                selectedTask = task
            }
        }
    }

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
