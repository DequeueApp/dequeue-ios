//
//  HomeView.swift
//  Dequeue
//
//  Main dashboard showing active stacks with navigation chrome
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.syncManager) var syncManager
    @Environment(\.authService) var authService

    @Query private var reminders: [Reminder]
    @Query private var pendingEvents: [Event]
    @Query private var allStacks: [Stack]
    @Query private var tasks: [QueueTask]

    @State private var syncStatusViewModel: SyncStatusViewModel?
    @State private var cachedDeviceId: String = ""
    @State private var showReminders = false
    @State private var offlineBannerDismissed = false
    @State private var selectedStack: Stack?
    @State private var selectedTask: QueueTask?

    private let networkMonitor = NetworkMonitor.shared

    init() {
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

        // Fetch all stacks for reminder navigation
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

                InProgressStacksListView()
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
                if cachedDeviceId.isEmpty {
                    cachedDeviceId = await DeviceService.shared.getDeviceId()
                }

                if syncStatusViewModel == nil {
                    syncStatusViewModel = SyncStatusViewModel(modelContext: modelContext)
                    if let syncManager = syncManager {
                        syncStatusViewModel?.setSyncManager(syncManager)
                    }
                }
            }
            .onDisappear {
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
            .onChange(of: networkMonitor.isConnected) { _, isConnected in
                if !isConnected {
                    offlineBannerDismissed = false
                }
            }
        }
    }

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
}

#Preview {
    HomeView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self, Tag.self], inMemory: true)
}
