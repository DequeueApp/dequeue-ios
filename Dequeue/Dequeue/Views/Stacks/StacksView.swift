//
//  StacksView.swift
//  Dequeue
//
//  Unified stacks view with segmented control for filtering by status
//

import SwiftUI
import SwiftData

struct StacksView: View {
    enum StackFilter: String, CaseIterable {
        case inProgress = "In Progress"
        case drafts = "Drafts"
        case completed = "Completed"
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager

    @Query(filter: #Predicate<Reminder> { reminder in
        reminder.isDeleted == false
    }) private var allReminders: [Reminder]

    @State private var selectedFilter: StackFilter = .inProgress
    @State private var showAddSheet = false
    @State private var showRemindersSheet = false
    @State private var syncStatusViewModel: SyncStatusViewModel?

    /// Count of reminders needing attention (overdue or due today)
    private var urgentReminderCount: Int {
        let calendar = Calendar.current
        return allReminders.filter { reminder in
            guard reminder.status == .active else { return false }
            // Overdue or due today
            return reminder.isPastDue || calendar.isDateInToday(reminder.remindAt)
        }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if let syncStatus = syncStatusViewModel, syncStatus.isInitialSyncInProgress {
                    // Show loading view during initial sync to prevent flickering (DEQ-240)
                    InitialSyncLoadingView(
                        eventsProcessed: syncStatus.initialSyncEventsProcessed,
                        totalEvents: syncStatus.initialSyncTotalEvents > 0 ? syncStatus.initialSyncTotalEvents : nil
                    )
                } else {
                    // Show normal stacks content after initial sync completes
                    stacksContent
                }
            }
            .navigationTitle("Stacks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        // Reminders button with badge
                        Button {
                            showRemindersSheet = true
                        } label: {
                            remindersButtonLabel
                        }
                        .accessibilityLabel("Reminders")
                        .accessibilityHint(urgentReminderCount > 0
                            ? "\(urgentReminderCount) reminders need attention"
                            : "View all reminders")

                        // Add stack button
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add Stack", systemImage: "plus")
                        }
                        #if os(macOS)
                        .keyboardShortcut("n", modifiers: .command)
                        #endif
                        .accessibilityIdentifier("addStackButton")
                        .accessibilityLabel("Add new stack")
                        .accessibilityHint("Creates a new stack")
                    }
                }
            }
            .task {
                // Initialize sync status view model
                if syncStatusViewModel == nil {
                    let viewModel = SyncStatusViewModel(modelContext: modelContext)
                    if let manager = syncManager {
                        viewModel.setSyncManager(manager)
                    }
                    syncStatusViewModel = viewModel
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            StackEditorView(mode: .create)
        }
        .sheet(isPresented: $showRemindersSheet) {
            RemindersListView()
        }
        #if os(macOS)
        .focusedValue(\.newStackAction) {
            // DEQ-50: ⌘N creates new stack
            showAddSheet = true
        }
        #endif
    }

    private var stacksContent: some View {
        VStack(spacing: 0) {
            // Segmented control for filtering
            Picker("Filter", selection: $selectedFilter) {
                ForEach(StackFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityLabel("Stack filter")
            .accessibilityHint("Select to filter stacks by status")

            // Content based on selection
            switch selectedFilter {
            case .inProgress:
                InProgressStacksListView()
            case .drafts:
                DraftsStacksListView()
            case .completed:
                CompletedStacksListView()
            }
        }
    }

    @ViewBuilder
    private var remindersButtonLabel: some View {
        if urgentReminderCount > 0 {
            // Show badge with count
            Image(systemName: "bell.badge.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, .primary)
                .overlay(alignment: .topTrailing) {
                    Text("\(min(urgentReminderCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.red, in: Circle())
                        .offset(x: 6, y: -6)
                }
        } else {
            Image(systemName: "bell")
        }
    }
}

#Preview {
    StacksView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self, Tag.self], inMemory: true)
}
