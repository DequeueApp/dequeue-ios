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

    // MARK: - Configuration

    /// Configure the manager with the required context for completing stacks
    func configure(modelContext: ModelContext, syncManager: SyncManager?) {
        self.modelContext = modelContext
        self.syncManager = syncManager
    }

    // MARK: - Public Methods

    /// Start a delayed completion for the given stack.
    /// The stack will be marked as completed after the grace period unless undone.
    func startDelayedCompletion(for stack: Stack) {
        // Cancel any existing pending completion
        cancelPendingCompletion()

        logger.info("Starting delayed completion for stack: \(stack.title)")

        pendingStack = stack
        progress = 0.0

        // Start progress animation
        startProgressAnimation()

        // Start completion timer
        completionTask = Task {
            do {
                try await Task.sleep(for: .seconds(Self.gracePeriodDuration))

                // If we weren't cancelled, complete the stack
                if !Task.isCancelled && self.pendingStack?.id == stack.id {
                    self.completeStack()
                }
            } catch {
                // Task was cancelled - that's expected if user tapped undo
                logger.debug("Completion timer cancelled")
            }
        }
    }

    /// Undo the pending completion and restore the stack to active state
    func undoCompletion() {
        guard let stack = pendingStack else { return }

        logger.info("Undoing completion for stack: \(stack.title)")

        cancelPendingCompletion()
    }

    // MARK: - Private Methods

    private func cancelPendingCompletion() {
        completionTask?.cancel()
        completionTask = nil
        progressTask?.cancel()
        progressTask = nil
        pendingStack = nil
        progress = 0.0
    }

    private func startProgressAnimation() {
        progressTask = Task {
            let startTime = Date()
            let duration = Self.gracePeriodDuration

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                self.progress = min(elapsed / duration, 1.0)

                if self.progress >= 1.0 {
                    break
                }

                // Update at ~60fps
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func completeStack() {
        guard let stack = pendingStack,
              let modelContext = modelContext else {
            logger.error("Cannot complete stack: missing stack or context")
            return
        }

        logger.info("Completing stack after grace period: \(stack.title)")

        do {
            let stackService = StackService(modelContext: modelContext, syncManager: syncManager)
            try stackService.markAsCompleted(stack, completeAllTasks: true)
            syncManager?.triggerImmediatePush()
        } catch {
            logger.error("Failed to complete stack: \(error.localizedDescription)")
            ErrorReportingService.capture(error: error, context: ["action": "delayedStackComplete"])
        }

        // Clear the pending state
        pendingStack = nil
        progress = 0.0
        completionTask = nil
        progressTask = nil
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
