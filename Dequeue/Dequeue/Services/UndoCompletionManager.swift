//
//  UndoCompletionManager.swift
//  Dequeue
//
//  Manages delayed stack completion with undo capability
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "UndoCompletionManager")

/// Manages a delayed stack completion that can be undone within a grace period.
///
/// When a stack with no pending tasks is completed, instead of immediately marking it
/// as completed, this manager holds the stack and starts a countdown timer. The user
/// can undo the completion within the grace period, or let it proceed automatically.
///
/// ### Supersede semantics
/// If a *different* stack is tapped to complete while a previous stack is still in
/// its grace period, the previous stack is **immediately committed** (not dropped)
/// and the new stack takes over the banner with a fresh timer. This matches the
/// "rapid-fire complete" user flow where a user completes several stacks in a row
/// faster than the grace period elapses — without this behavior, every stack except
/// the last would silently revert and never sync.
@MainActor
@Observable
final class UndoCompletionManager {
    /// The stack pending completion, if any
    private(set) var pendingStack: Stack?

    /// Progress from 0.0 to 1.0 for the countdown animation
    private(set) var progress: Double = 0.0

    /// Whether there's a pending completion that can be undone
    var hasPendingCompletion: Bool {
        pendingStack != nil
    }

    /// Duration of the undo grace period in seconds
    static let gracePeriodDuration: TimeInterval = 5.0

    // MARK: - Private State

    private var completionTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    private var syncManager: SyncManager?
    private var userId: String = ""
    private var deviceId: String = ""

    // MARK: - Configuration

    /// Configure the manager with the required context for completing stacks
    func configure(modelContext: ModelContext, syncManager: SyncManager?, userId: String, deviceId: String) {
        self.modelContext = modelContext
        self.syncManager = syncManager
        self.userId = userId
        self.deviceId = deviceId
    }

    // MARK: - Public Methods

    /// Start a delayed completion for the given stack.
    /// The stack will be marked as completed after the grace period unless undone.
    ///
    /// If a *different* stack is already pending, that prior stack is committed
    /// immediately (not silently dropped) before the new timer starts.
    func startDelayedCompletion(for stack: Stack) {
        // Supersede: if a different stack is pending, commit it now.
        // (If the same stack is re-tapped, just reset the timer.)
        if let existing = pendingStack, existing.id != stack.id {
            logger.info("Superseding pending completion: committing '\(existing.title)' immediately")
            commitCompletion(of: existing)
        }

        // Tear down any existing timers and visible state before starting fresh.
        cancelTimers()

        logger.info("Starting delayed completion for stack: \(stack.title)")

        pendingStack = stack
        progress = 0.0

        // Start progress animation
        startProgressAnimation()

        // Start completion timer
        completionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.gracePeriodDuration))

                // If we weren't cancelled (and the same stack is still pending), commit it.
                guard let self, !Task.isCancelled, self.pendingStack?.id == stack.id else {
                    return
                }
                self.commitPendingCompletion()
            } catch {
                // Task was cancelled - that's expected if user tapped undo
                logger.debug("Completion timer cancelled")
            }
        }
    }

    /// Undo the pending completion and restore the stack to active state.
    /// This drops the pending stack *without* committing it (intentional — the user
    /// is explicitly cancelling).
    func undoCompletion() {
        guard let stack = pendingStack else { return }

        logger.info("Undoing completion for stack: \(stack.title)")

        cancelTimers()
        pendingStack = nil
        progress = 0.0
    }

    // MARK: - Private Methods

    /// Cancel any in-flight timers (progress + completion sleep) without touching
    /// `pendingStack`/`progress` state. Callers decide whether to clear that state.
    private func cancelTimers() {
        completionTask?.cancel()
        completionTask = nil
        progressTask?.cancel()
        progressTask = nil
    }

    private func startProgressAnimation() {
        progressTask = Task { [weak self] in
            let startTime = Date()
            let duration = Self.gracePeriodDuration

            while !Task.isCancelled {
                guard let self else { return }

                let elapsed = Date().timeIntervalSince(startTime)
                self.progress = min(elapsed / duration, 1.0)

                if self.progress >= 1.0 {
                    break
                }

                // Update at ~10fps (100ms) for efficiency - still smooth visually
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Called when the grace-period timer elapses for the currently pending stack.
    /// Clears banner state and triggers the persistence commit.
    private func commitPendingCompletion() {
        guard let stack = pendingStack else { return }

        pendingStack = nil
        progress = 0.0
        completionTask = nil
        progressTask = nil

        commitCompletion(of: stack)
    }

    /// Persist the completion for the given stack and trigger sync.
    /// Used by both the natural grace-period commit path and the supersede path.
    private func commitCompletion(of stack: Stack) {
        guard let modelContext = modelContext else {
            logger.error("Cannot complete stack: missing model context")
            return
        }

        logger.info("Committing completion for stack: \(stack.title)")

        let stackService = StackService(
            modelContext: modelContext,
            userId: userId,
            deviceId: deviceId,
            syncManager: syncManager
        )
        let sync = syncManager

        Task {
            do {
                try await stackService.markAsCompleted(stack, completeAllTasks: true)
                sync?.triggerImmediatePush()
            } catch {
                logger.error("Failed to complete stack: \(error.localizedDescription)")
                ErrorReportingService.capture(
                    error: error,
                    context: ["action": "delayedStackComplete"]
                )
            }
        }
    }
}

// MARK: - Environment Key

private struct UndoCompletionManagerKey: EnvironmentKey {
    static let defaultValue: UndoCompletionManager? = nil
}

extension EnvironmentValues {
    var undoCompletionManager: UndoCompletionManager? {
        get { self[UndoCompletionManagerKey.self] }
        set { self[UndoCompletionManagerKey.self] = newValue }
    }
}
