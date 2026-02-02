//
//  InProgressStacksListView.swift
//  Dequeue
//
//  Displays list of active (in-progress) stacks with tag filtering
//

import SwiftUI
import SwiftData

struct InProgressStacksListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService
    @Environment(\.undoCompletionManager) private var undoCompletionManager

    @Query private var stacks: [Stack]
    @Query private var allTags: [Tag]

    @State private var stackService: StackService?
    @State private var selectedStack: Stack?
    @State private var syncError: Error?
    @State private var showingSyncError = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var stackToComplete: Stack?
    @State private var showCompleteConfirmation = false
    @State private var selectedTagIds: Set<String> = []

    init() {
        let activeRawValue = StackStatus.active.rawValue
        _stacks = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false &&
                stack.isDraft == false &&
                stack.statusRawValue == activeRawValue
            },
            sort: \Stack.updatedAt,
            order: .reverse
        )

        _allTags = Query(
            filter: #Predicate<Tag> { tag in
                tag.isDeleted == false
            },
            sort: \.name
        )
    }

    /// Stacks filtered by selected tags (OR logic) and excluding pending completion
    private var filteredStacks: [Stack] {
        // First, filter out any stack that's pending completion (in undo window)
        let pendingCompletionId = undoCompletionManager?.pendingStack?.id
        let visibleStacks = stacks.filter { $0.id != pendingCompletionId }

        if selectedTagIds.isEmpty {
            return visibleStacks
        }
        return visibleStacks.filter { stack in
            stack.tagObjects.contains { tag in
                selectedTagIds.contains(tag.id) && !tag.isDeleted
            }
        }
    }

    /// Whether the filter bar should be shown
    private var shouldShowFilterBar: Bool {
        allTags.contains { tag in
            stacks.contains { stack in
                stack.tagObjects.contains { $0.id == tag.id && !$0.isDeleted }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
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
        .task {
            guard stackService == nil else { return }
            let deviceId = await DeviceService.shared.getDeviceId()
            stackService = StackService(
                modelContext: modelContext,
                userId: authService.currentUserId ?? "",
                deviceId: deviceId,
                syncManager: syncManager
            )
        }
        .sheet(item: $selectedStack) { stack in
            StackEditorView(mode: .edit(stack))
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
    }

    // MARK: - Empty States

    private var emptyState: some View {
        ContentUnavailableView(
            "No Stacks",
            systemImage: "tray",
            description: Text("Add a stack to get started")
        )
    }

    private var noFilterResultsState: some View {
        ContentUnavailableView {
            Label("No Matching Stacks", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No stacks match the selected tags")
        } actions: {
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
                        leadingSwipeActions(for: stack)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        trailingSwipeActions(for: stack)
                    }
                    .contextMenu {
                        contextMenuContent(for: stack)
                    }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await performSync()
        }
    }

    // MARK: - Swipe Actions

    @ViewBuilder
    private func leadingSwipeActions(for stack: Stack) -> some View {
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

    @ViewBuilder
    private func trailingSwipeActions(for stack: Stack) -> some View {
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

    @ViewBuilder
    private func contextMenuContent(for stack: Stack) -> some View {
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

// MARK: - Actions

extension InProgressStacksListView {
    func performSync() async {
        guard let syncManager = syncManager else {
            ErrorReportingService.addBreadcrumb(
                category: "sync",
                message: "Pull-to-refresh attempted with nil syncManager"
            )
            return
        }

        do {
            try await syncManager.manualPush()
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

    func setAsActive(_ stack: Stack) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.setAsActive(stack)
            } catch {
                ErrorReportingService.capture(error: error, context: ["action": "setAsActive"])
                errorMessage = "Failed to set stack as active: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    func deactivateStack(_ stack: Stack) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.deactivateStack(stack)
            } catch {
                ErrorReportingService.capture(error: error, context: ["action": "deactivateStack"])
                errorMessage = "Failed to deactivate stack: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    func handleCompleteButtonTapped(for stack: Stack) {
        if stack.pendingTasks.isEmpty {
            if let manager = undoCompletionManager {
                manager.startDelayedCompletion(for: stack)
            } else {
                completeStack(stack)
            }
        } else {
            stackToComplete = stack
            showCompleteConfirmation = true
        }
    }

    func completeStack(_ stack: Stack) {
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.markAsCompleted(stack, completeAllTasks: true)
            } catch {
                ErrorReportingService.capture(error: error, context: ["action": "completeStack"])
                errorMessage = "Failed to complete stack: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    func deleteStack(_ stack: Stack) {
        HapticManager.shared.warning()
        guard let service = stackService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.deleteStack(stack)
            } catch {
                ErrorReportingService.capture(error: error, context: ["action": "deleteStack"])
                errorMessage = "Failed to delete stack: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

#Preview {
    InProgressStacksListView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self, Tag.self], inMemory: true)
}
