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

/// Status of an Arc - higher-level organizational container
enum ArcStatus: String, Codable, CaseIterable {
    /// Currently being worked on
    case active
    /// All work finished successfully
    case completed
    /// Temporarily on hold
    case paused
    /// Historical, no longer relevant
    case archived
}

enum ParentType: String, Codable, CaseIterable {
    case stack
    case task
    case arc
}

/// Distinguishes whether an event was created by a human user or an AI agent (DEQ-55)
enum ActorType: String, Codable, CaseIterable, Sendable {
    /// Event created by a human user
    case human
    /// Event created by an AI agent
    case ai
}

/// Metadata attached to events to track who/what created them (DEQ-55)
/// Includes actor type (human vs AI) and optional AI agent identification.
struct EventMetadata: Codable, Sendable {
    /// Type of actor that created this event (human or AI)
    var actorType: ActorType

    /// AI agent identifier (required when actorType is .ai, nil otherwise)
    var actorId: String?

    nonisolated init(actorType: ActorType = .human, actorId: String? = nil) {
        self.actorType = actorType
        self.actorId = actorId
    }

    /// Create metadata for a human actor
    static func human() -> EventMetadata {
        EventMetadata(actorType: .human, actorId: nil)
    }

    /// Create metadata for an AI actor
    static func ai(agentId: String) -> EventMetadata {
        EventMetadata(actorType: .ai, actorId: agentId)
    }
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
    case taskDelegatedToAI = "task.delegatedToAI"  // DEQ-56

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

    // Attachment events
    case attachmentAdded = "attachment.added"
    case attachmentRemoved = "attachment.removed"

    // Arc events
    case arcCreated = "arc.created"
    case arcUpdated = "arc.updated"
    case arcDeleted = "arc.deleted"
    case arcActivated = "arc.activated"
    case arcDeactivated = "arc.deactivated"
    case arcCompleted = "arc.completed"
    case arcPaused = "arc.paused"
    case arcReordered = "arc.reordered"
    case stackAssignedToArc = "stack.assignedToArc"
    case stackRemovedFromArc = "stack.removedFromArc"
}
