//
//  StackService+Migration.swift
//  Dequeue
//
//  Migration methods for StackService - called on app startup
//

import Foundation
import SwiftData

extension StackService {
    // MARK: - Migration

    /// Migrates legacy data from before the explicit `isActive` field was added.
    /// Call this on app startup to handle the schema migration from sortOrder-based
    /// active tracking to explicit isActive field.
    ///
    /// **Important:** As of DEQ-148, the app supports zero active stacks. This migration
    /// is for users upgrading from older versions that used sortOrder=0 to indicate
    /// the active stack. New installs and users who have already migrated don't need this.
    ///
    /// Migration logic:
    /// 1. If no stacks exist with status == .active, no migration is needed
    /// 2. If no stack has isActive = true but stacks exist, activate the one with sortOrder = 0
    ///    (this matches the legacy behavior before explicit isActive field)
    /// 3. If multiple stacks have isActive = true (data corruption), keep only lowest sortOrder
    func migrateActiveStackState() throws {
        let activeStacks = try getActiveStacks()
        guard !activeStacks.isEmpty else { return }

        // Find ALL stacks that have isActive = true (regardless of status)
        let allWithIsActiveTrue = try getAllStacksWithIsActiveTrue()

        if allWithIsActiveTrue.isEmpty {
            // No stack is marked active - activate the one with lowest sortOrder
            if let firstStack = activeStacks.min(by: { $0.sortOrder < $1.sortOrder }) {
                firstStack.isActive = true
                firstStack.syncState = .pending
                try modelContext.save()
            }
        } else if allWithIsActiveTrue.count > 1 {
            // Multiple stacks marked active - keep only the one with lowest sortOrder
            // Prefer stacks with status == .active
            let activeStatusStacks = allWithIsActiveTrue.filter { $0.status == .active }
            let stackToKeepActive: Stack?

            if !activeStatusStacks.isEmpty {
                stackToKeepActive = activeStatusStacks.min(by: { $0.sortOrder < $1.sortOrder })
            } else {
                stackToKeepActive = allWithIsActiveTrue.min(by: { $0.sortOrder < $1.sortOrder })
            }

            for stack in allWithIsActiveTrue {
                if stack.id == stackToKeepActive?.id {
                    stack.isActive = true
                } else {
                    stack.isActive = false
                }
                stack.syncState = .pending
            }
            try modelContext.save()
        }
        // If exactly one is active, no migration needed
    }

    /// Migrates existing data to populate activeTaskId from computed value.
    /// Call this on app startup after migrateActiveStackState().
    ///
    /// Migration logic:
    /// For each stack without activeTaskId, set it to the first pending task (if any)
    func migrateActiveTaskId() throws {
        let activeStacks = try getActiveStacks()

        var needsSave = false
        for stack in activeStacks {
            // Skip if already has activeTaskId set
            guard stack.activeTaskId == nil else { continue }

            // Set activeTaskId to first pending task (matches previous computed behavior)
            if let firstPendingTask = stack.pendingTasks.first {
                stack.activeTaskId = firstPendingTask.id
                stack.syncState = .pending
                needsSave = true
            }
        }

        if needsSave {
            try modelContext.save()
        }
    }
}
