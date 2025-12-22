//
//  StackService.swift
//  Dequeue
//
//  Business logic for Stack operations
//

import Foundation
import SwiftData

@MainActor
final class StackService {
    private let modelContext: ModelContext
    private let eventService: EventService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext)
    }

    // MARK: - Create

    func createStack(
        title: String,
        description: String? = nil,
        isDraft: Bool = false
    ) throws -> Stack {
        let stack = Stack(
            title: title,
            stackDescription: description,
            status: .active,
            sortOrder: 0,
            isDraft: isDraft,
            syncState: .pending
        )

        modelContext.insert(stack)

        if !isDraft {
            try eventService.recordStackCreated(stack)
        }

        try modelContext.save()
        return stack
    }

    // MARK: - Read

    func getActiveStacks() throws -> [Stack] {
        let active = StackStatus.active
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == false && stack.status == active
        }
        let descriptor = FetchDescriptor<Stack>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func getCompletedStacks() throws -> [Stack] {
        let completed = StackStatus.completed
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.status == completed
        }
        let descriptor = FetchDescriptor<Stack>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func getDrafts() throws -> [Stack] {
        let predicate = #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == true
        }
        let descriptor = FetchDescriptor<Stack>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Update

    func updateStack(_ stack: Stack, title: String, description: String?) throws {
        stack.title = title
        stack.stackDescription = description
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackUpdated(stack)
        try modelContext.save()
    }

    func publishDraft(_ stack: Stack) throws {
        guard stack.isDraft else { return }

        stack.isDraft = false
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackCreated(stack)
        try modelContext.save()
    }

    // MARK: - Status Changes

    func markAsCompleted(_ stack: Stack, completeAllTasks: Bool = true) throws {
        stack.status = .completed
        stack.updatedAt = Date()
        stack.syncState = .pending

        if completeAllTasks {
            let taskService = TaskService(modelContext: modelContext)
            for task in stack.tasks where task.status == .pending && !task.isDeleted {
                try taskService.markAsCompleted(task)
            }
        }

        try eventService.recordStackCompleted(stack)
        try modelContext.save()
    }

    func setAsActive(_ stack: Stack) throws {
        let activeStacks = try getActiveStacks()

        for (index, s) in activeStacks.enumerated() {
            if s.id == stack.id {
                s.sortOrder = 0
            } else if s.sortOrder <= stack.sortOrder {
                s.sortOrder = index + 1
            }
            s.syncState = .pending
        }

        try eventService.recordStackActivated(stack)
        try eventService.recordStackReordered(activeStacks)
        try modelContext.save()
    }

    func closeStack(_ stack: Stack, reason: String? = nil) throws {
        stack.status = .closed
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackUpdated(stack)
        try modelContext.save()
    }

    // MARK: - Delete

    func deleteStack(_ stack: Stack) throws {
        stack.isDeleted = true
        stack.updatedAt = Date()
        stack.syncState = .pending

        try eventService.recordStackDeleted(stack)
        try modelContext.save()
    }

    // MARK: - Reorder

    func updateSortOrders(_ stacks: [Stack]) throws {
        for (index, stack) in stacks.enumerated() {
            stack.sortOrder = index
            stack.updatedAt = Date()
            stack.syncState = .pending
        }

        try eventService.recordStackReordered(stacks)
        try modelContext.save()
    }
}
