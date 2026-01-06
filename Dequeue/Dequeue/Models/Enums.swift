//
//  Enums.swift
//  Dequeue
//
//  Shared enums for models
//

import Foundation

enum StackStatus: String, Codable, CaseIterable {
    case active
    case completed
    case closed
    case archived
}

enum TaskStatus: String, Codable, CaseIterable {
    case pending
    case completed
    case blocked
    case closed
}

enum ReminderStatus: String, Codable, CaseIterable {
    case active
    case snoozed
    case fired
}

enum ParentType: String, Codable, CaseIterable {
    case stack
    case task
}

enum SyncState: String, Codable, CaseIterable {
    case pending
    case synced
    case failed
}

enum UploadState: String, Codable, CaseIterable {
    case pending
    case uploading
    case completed
    case failed
}

enum EventType: String, Codable, CaseIterable {
    // Stack events
    case stackCreated = "stack.created"
    case stackUpdated = "stack.updated"
    case stackDeleted = "stack.deleted"
    case stackDiscarded = "stack.discarded"
    case stackActivated = "stack.activated"
    case stackDeactivated = "stack.deactivated"
    case stackCompleted = "stack.completed"
    case stackClosed = "stack.closed"
    case stackReordered = "stack.reordered"

    // Task events
    case taskCreated = "task.created"
    case taskUpdated = "task.updated"
    case taskDeleted = "task.deleted"
    case taskActivated = "task.activated"
    case taskCompleted = "task.completed"
    case taskClosed = "task.closed"
    case taskReordered = "task.reordered"

    // Reminder events
    case reminderCreated = "reminder.created"
    case reminderUpdated = "reminder.updated"
    case reminderDeleted = "reminder.deleted"
    case reminderSnoozed = "reminder.snoozed"

    // Device events
    case deviceDiscovered = "device.discovered"
}
