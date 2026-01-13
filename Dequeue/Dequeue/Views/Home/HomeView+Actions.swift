//
//  HomeView+Actions.swift
//  Dequeue
//
//  HomeView actions extension - stack operations and navigation handlers
//

import SwiftUI

// MARK: - Sync

extension HomeView {
    /// Performs a manual sync: pushes local changes first, then pulls from server.
    /// Push-first order ensures local changes are sent before potentially receiving
    /// conflicting updates, allowing the server to handle conflict resolution.
    func performSync() async {
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

// MARK: - Actions

extension HomeView {
    /// Handle navigation to a Stack or Task from the Reminders list
    func handleGoToItem(parentId: String, parentType: ParentType) {
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

    func moveStacks(from source: IndexSet, to destination: Int) {
        // Capture original sort orders from the actual Stack model objects (via @Query).
        // updateSortOrders() modifies these objects in-place before saving, so we need
        // the original values to revert if the save fails.
        let originalSortOrders = stacks.map { ($0.id, $0.sortOrder) }

        var reorderedStacks = stacks
        reorderedStacks.move(fromOffsets: source, toOffset: destination)

        do {
            try stackService.updateSortOrders(reorderedStacks)
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

    func setAsActive(_ stack: Stack) {
        do {
            try stackService.setAsActive(stack)
        } catch {
            ErrorReportingService.capture(error: error, context: ["action": "setAsActive"])
            errorMessage = "Failed to set stack as active: \(error.localizedDescription)"
            showError = true
        }
    }

    func deactivateStack(_ stack: Stack) {
        do {
            try stackService.deactivateStack(stack)
        } catch {
            ErrorReportingService.capture(error: error, context: ["action": "deactivateStack"])
            errorMessage = "Failed to deactivate stack: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Handles the Complete button tap with conditional behavior based on pending tasks.
    /// - If stack has pending tasks: show confirmation dialog
    /// - If stack has no pending tasks: use delayed completion with undo
    func handleCompleteButtonTapped(for stack: Stack) {
        if stack.pendingTasks.isEmpty {
            // No pending tasks - use delayed completion with undo banner
            if let manager = undoCompletionManager {
                manager.startDelayedCompletion(for: stack)
            } else {
                // Fallback: complete immediately if manager not available
                completeStack(stack)
            }
        } else {
            // Has pending tasks - show confirmation dialog
            stackToComplete = stack
            showCompleteConfirmation = true
        }
    }

    func completeStack(_ stack: Stack) {
        do {
            try stackService.markAsCompleted(stack, completeAllTasks: true)
        } catch {
            ErrorReportingService.capture(error: error, context: ["action": "completeStack"])
            errorMessage = "Failed to complete stack: \(error.localizedDescription)"
            showError = true
        }
    }

    func deleteStack(_ stack: Stack) {
        do {
            try stackService.deleteStack(stack)
        } catch {
            ErrorReportingService.capture(error: error, context: ["action": "deleteStack"])
            errorMessage = "Failed to delete stack: \(error.localizedDescription)"
            showError = true
        }
    }
}
