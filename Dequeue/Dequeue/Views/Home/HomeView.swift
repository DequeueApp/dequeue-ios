//
//  HomeView.swift
//  Dequeue
//
//  Main dashboard showing active stacks
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.syncManager) var syncManager
    @Environment(\.authService) var authService
    @Environment(\.undoCompletionManager) var undoCompletionManager
    @Query var stacks: [Stack]
    @Query var allStacks: [Stack]
    @Query var tasks: [QueueTask]
    @Query private var reminders: [Reminder]
    @Query private var pendingEvents: [Event]
    @Query private var allTags: [Tag]

    @State private var syncStatusViewModel: SyncStatusViewModel?
    @State var cachedDeviceId: String = ""

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

        // Fetch all tags for filter bar
        _allTags = Query(
            filter: #Predicate<Tag> { tag in
                tag.isDeleted == false
            },
            sort: \.name
        )
    }

    @State var selectedStack: Stack?
    @State var selectedTask: QueueTask?
    @State private var showReminders = false
    @State private var offlineBannerDismissed = false
    @State private var syncError: Error?
    @State private var showingSyncError = false
    @State var errorMessage: String?
    @State var showError = false
    @State var stackToComplete: Stack?
    @State var showCompleteConfirmation = false
    @State private var selectedTagIds: Set<String> = []

    /// Network monitor for offline detection
    private let networkMonitor = NetworkMonitor.shared

    /// Stack service for operations - lightweight struct, safe to recreate each call
    var stackService: StackService {
        StackService(
            modelContext: modelContext,
            userId: authService.currentUserId ?? "",
            deviceId: cachedDeviceId,
            syncManager: syncManager
        )
    }

    /// Count of overdue reminders for badge display
    private var overdueCount: Int {
        reminders.filter { $0.status == .active && $0.isPastDue }.count
    }

    /// Stacks filtered by selected tags (OR logic)
    private var filteredStacks: [Stack] {
        if selectedTagIds.isEmpty {
            return stacks
        }
        return stacks.filter { stack in
            stack.tagObjects.contains { tag in
                selectedTagIds.contains(tag.id) && !tag.isDeleted
            }
        }
    }

    /// Whether the filter bar should be shown
    private var shouldShowFilterBar: Bool {
        // Show filter bar if there are any tags with stacks
        allTags.contains { tag in
            stacks.contains { stack in
                stack.tagObjects.contains { $0.id == tag.id && !$0.isDeleted }
            }
        }
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

                // Tag filter bar
                if shouldShowFilterBar {
                    TagFilterBar(
                        tags: allTags,
                        stacks: stacks,
                        selectedTagIds: $selectedTagIds
                    )
                }

                Group {
                    if stacks.isEmpty {
                        emptyState
                    } else if filteredStacks.isEmpty {
                        noFilterResultsState
                    } else {
                        stackList
                    }
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
                // Fetch device ID for service creation
                if cachedDeviceId.isEmpty {
                    cachedDeviceId = await DeviceService.shared.getDeviceId()
                }

                // Initialize sync status view model
                if syncStatusViewModel == nil {
                    syncStatusViewModel = SyncStatusViewModel(modelContext: modelContext)
                    if let syncManager = syncManager {
                        syncStatusViewModel?.setSyncManager(syncManager)
                    }
                }
            }
            .onDisappear {
                // Stop monitoring to prevent background Task from running indefinitely
                syncStatusViewModel?.stopMonitoring()
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
            .confirmationDialog(
                "Complete Stack?",
                isPresented: $showCompleteConfirmation,
                presenting: stackToComplete
            ) { stack in
                Button("Complete Stack & All Tasks") {
                    completeStack(stack)
                }
                Button("Cancel", role: .cancel) { }
            } message: { stack in
                Text("This will mark \"\(stack.title)\" and all its pending tasks as completed.")
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

    private var noFilterResultsState: some View {
        ContentUnavailableView(
            "No Matching Stacks",
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text("No stacks match the selected tags")
        ) {
            Button("Clear Filters") {
                selectedTagIds.removeAll()
            }
        }
    }

    // MARK: - Stack List

    private var stackList: some View {
        List {
            ForEach(filteredStacks) { stack in
                StackRowView(stack: stack)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedStack = stack
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if stack.isActive {
                            Button {
                                deactivateStack(stack)
                            } label: {
                                Label("Deactivate", systemImage: "star.slash")
                            }
                            .tint(.gray)
                        } else {
                            Button {
                                setAsActive(stack)
                            } label: {
                                Label("Set Active", systemImage: "star.fill")
                            }
                            .tint(.orange)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteStack(stack)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            handleCompleteButtonTapped(for: stack)
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                    }
                    .contextMenu {
                        Button {
                            selectedStack = stack
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        if stack.isActive {
                            Button {
                                deactivateStack(stack)
                            } label: {
                                Label("Deactivate", systemImage: "star.slash")
                            }
                        } else {
                            Button {
                                setAsActive(stack)
                            } label: {
                                Label("Set Active", systemImage: "star.fill")
                            }
                        }

                        Button {
                            handleCompleteButtonTapped(for: stack)
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            deleteStack(stack)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            // Disable reordering when filters are active to avoid confusion
            .onMove(perform: selectedTagIds.isEmpty ? moveStacks : nil)
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

}

#Preview {
    HomeView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
