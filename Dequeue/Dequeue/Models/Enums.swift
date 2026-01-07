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

/// Tracks the upload state of file attachments to remote storage.
///
/// State transitions:
/// - `pending` → `uploading`: When upload begins
/// - `uploading` → `completed`: When upload succeeds
/// - `uploading` → `failed`: When upload fails (can retry: `failed` → `uploading`)
/// - `pending` → `completed`: When file already exists on server (skip upload)
enum UploadState: String, Codable, CaseIterable {
    /// File has not been uploaded yet and is waiting to be processed
    case pending
    /// File is currently being uploaded to remote storage
    case uploading
    /// File has been successfully uploaded and remoteUrl is available
    case completed
    /// Upload failed; can be retried by transitioning back to uploading
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

    // Tag events
    case tagCreated = "tag.created"
    case tagUpdated = "tag.updated"
    case tagDeleted = "tag.deleted"

    // Device events
    case deviceDiscovered = "device.discovered"
}
