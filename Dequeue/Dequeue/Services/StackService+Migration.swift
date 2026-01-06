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

    /// Migrates existing data to ensure exactly one stack has isActive = true.
    /// Call this on app startup to handle the schema migration from sortOrder-based
    /// active tracking to explicit isActive field.
    ///
    /// Migration logic:
    /// 1. If no stack has isActive = true, set the stack with sortOrder = 0 as active
    /// 2. If multiple stacks have isActive = true, keep only the one with lowest sortOrder
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
