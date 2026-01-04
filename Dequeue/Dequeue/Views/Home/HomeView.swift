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
    @Query private var pendingEvents: [Event]

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

        // Fetch pending events for offline banner
        _pendingEvents = Query(
            filter: #Predicate<Event> { event in
                event.isSynced == false
            }
        )
    }

    @State private var selectedStack: Stack?
    @State private var selectedTask: QueueTask?
    @State private var showReminders = false
    @State private var offlineBannerDismissed = false
    @State private var syncError: Error?
    @State private var showingSyncError = false
    @State private var errorMessage: String?
    @State private var showError = false

    /// Network monitor for offline detection
    private let networkMonitor = NetworkMonitor.shared

    /// Stack service for operations - lightweight struct, safe to recreate each call
    private var stackService: StackService {
        StackService(modelContext: modelContext)
    }

    /// Count of overdue reminders for badge display
    private var overdueCount: Int {
        reminders.filter { $0.status == .active && $0.isPastDue }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Offline banner at the top
                if !networkMonitor.isConnected && !offlineBannerDismissed {
                    OfflineBanner(
                        pendingCount: pendingEvents.count,
                        isDismissed: $offlineBannerDismissed
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                Group {
                    if stacks.isEmpty {
                        emptyState
                    } else {
                        stackList
                    }
                }
            }
            .navigationTitle("Dequeue")
            .toolbar {
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
            .alert("Sync Failed", isPresented: $showingSyncError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let syncError = syncError {
                    Text(syncError.localizedDescription)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: networkMonitor.isConnected) { _, isConnected in
                // Reset banner dismissal when network changes
                if !isConnected {
                    offlineBannerDismissed = false
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
        .refreshable {
            await performSync()
        }
    }

    // MARK: - Sync

    /// Performs a manual sync: pushes local changes first, then pulls from server.
    /// Push-first order ensures local changes are sent before potentially receiving
    /// conflicting updates, allowing the server to handle conflict resolution.
    private func performSync() async {
        guard let syncManager = syncManager else {
            ErrorReportingService.addBreadcrumb(
                category: "sync",
                message: "Pull-to-refresh attempted with nil syncManager"
            )
            return
        }

        do {
            // Push local changes first
            try await syncManager.manualPush()
            // Then pull from server
            try await syncManager.manualPull()
        } catch {
            syncError = error
            showingSyncError = true
            ErrorReportingService.capture(
                error: error,
                context: ["source": "pull_to_refresh"]
            )
        }
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
        // Capture original sort orders from the actual Stack model objects (via @Query).
        // updateSortOrders() modifies these objects in-place before saving, so we need
        // the original values to revert if the save fails.
        let originalSortOrders = stacks.map { ($0.id, $0.sortOrder) }

        var reorderedStacks = stacks
        reorderedStacks.move(fromOffsets: source, toOffset: destination)

        do {
            try stackService.updateSortOrders(reorderedStacks)
            // Trigger immediate sync after successful save
            syncManager?.triggerImmediatePush()
        } catch {
            // Revert in-memory state on failure. This works because `stacks` (from @Query)
            // returns the actual SwiftData model objects, and we're restoring their
            // sortOrder property to the original values captured before the failed save.
            for (id, originalOrder) in originalSortOrders {
                if let stack = stacks.first(where: { $0.id == id }) {
                    stack.sortOrder = originalOrder
                }
            }
            ErrorReportingService.capture(error: error, context: ["action": "moveStacks"])
            errorMessage = "Failed to save stack reorder: \(error.localizedDescription)"
            showError = true
        }
    }

    private func deleteStacks(at offsets: IndexSet) {
        for index in offsets {
            do {
                try stackService.deleteStack(stacks[index])
                // Trigger immediate sync after successful delete
                syncManager?.triggerImmediatePush()
            } catch {
                ErrorReportingService.capture(error: error, context: ["action": "deleteStack"])
                errorMessage = "Failed to delete stack: \(error.localizedDescription)"
                showError = true
            }
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

                if stack.isActive {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                        .accessibilityLabel("Active stack")
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
