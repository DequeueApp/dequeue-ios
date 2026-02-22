//
//  EnumsTests.swift
//  DequeueTests
//
//  Tests for shared model enums
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - StackStatus Tests

@Suite("StackStatus Tests")
@MainActor
struct StackStatusTests {
    @Test("StackStatus has correct raw values")
    func stackStatusRawValues() {
        #expect(StackStatus.active.rawValue == "active")
        #expect(StackStatus.completed.rawValue == "completed")
        #expect(StackStatus.closed.rawValue == "closed")
        #expect(StackStatus.archived.rawValue == "archived")
    }

    @Test("StackStatus has exactly 4 cases")
    func stackStatusCaseCount() {
        #expect(StackStatus.allCases.count == 4)
    }

    @Test("StackStatus can be created from valid raw values")
    func stackStatusFromRawValue() {
        #expect(StackStatus(rawValue: "active") == .active)
        #expect(StackStatus(rawValue: "completed") == .completed)
        #expect(StackStatus(rawValue: "closed") == .closed)
        #expect(StackStatus(rawValue: "archived") == .archived)
    }

    @Test("StackStatus returns nil for invalid raw value")
    func stackStatusInvalidRawValue() {
        #expect(StackStatus(rawValue: "invalid") == nil)
        #expect(StackStatus(rawValue: "") == nil)
        #expect(StackStatus(rawValue: "Active") == nil)
    }

    @Test("StackStatus is Codable (round-trip)")
    func stackStatusCodable() throws {
        let original = StackStatus.active
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StackStatus.self, from: data)
        #expect(decoded == original)
    }

    @Test("StackStatus decodes from JSON string")
    func stackStatusDecodesFromJSON() throws {
        let json = Data("\"archived\"".utf8)
        let decoded = try JSONDecoder().decode(StackStatus.self, from: json)
        #expect(decoded == .archived)
    }
}

// MARK: - TaskStatus Tests

@Suite("TaskStatus Tests")
@MainActor
struct TaskStatusTests {
    @Test("TaskStatus has correct raw values")
    func taskStatusRawValues() {
        #expect(TaskStatus.pending.rawValue == "pending")
        #expect(TaskStatus.completed.rawValue == "completed")
        #expect(TaskStatus.blocked.rawValue == "blocked")
        #expect(TaskStatus.closed.rawValue == "closed")
    }

    @Test("TaskStatus has exactly 4 cases")
    func taskStatusCaseCount() {
        #expect(TaskStatus.allCases.count == 4)
    }

    @Test("TaskStatus returns nil for invalid raw value")
    func taskStatusInvalidRawValue() {
        #expect(TaskStatus(rawValue: "done") == nil)
        #expect(TaskStatus(rawValue: "in_progress") == nil)
    }

    @Test("TaskStatus is Codable (round-trip)")
    func taskStatusCodable() throws {
        for status in TaskStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(TaskStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

// MARK: - ReminderStatus Tests

@Suite("ReminderStatus Tests")
@MainActor
struct ReminderStatusTests {
    @Test("ReminderStatus has correct raw values")
    func reminderStatusRawValues() {
        #expect(ReminderStatus.active.rawValue == "active")
        #expect(ReminderStatus.snoozed.rawValue == "snoozed")
        #expect(ReminderStatus.fired.rawValue == "fired")
    }

    @Test("ReminderStatus has exactly 3 cases")
    func reminderStatusCaseCount() {
        #expect(ReminderStatus.allCases.count == 3)
    }

    @Test("ReminderStatus is Codable (round-trip)")
    func reminderStatusCodable() throws {
        for status in ReminderStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ReminderStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

// MARK: - ArcStatus Tests

@Suite("ArcStatus Tests")
@MainActor
struct ArcStatusTests {
    @Test("ArcStatus has correct raw values")
    func arcStatusRawValues() {
        #expect(ArcStatus.active.rawValue == "active")
        #expect(ArcStatus.completed.rawValue == "completed")
        #expect(ArcStatus.paused.rawValue == "paused")
        #expect(ArcStatus.archived.rawValue == "archived")
    }

    @Test("ArcStatus has exactly 4 cases")
    func arcStatusCaseCount() {
        #expect(ArcStatus.allCases.count == 4)
    }

    @Test("ArcStatus is Codable (round-trip)")
    func arcStatusCodable() throws {
        for status in ArcStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ArcStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

// MARK: - ParentType Tests

@Suite("ParentType Tests")
@MainActor
struct ParentTypeTests {
    @Test("ParentType has correct raw values")
    func parentTypeRawValues() {
        #expect(ParentType.stack.rawValue == "stack")
        #expect(ParentType.task.rawValue == "task")
        #expect(ParentType.arc.rawValue == "arc")
    }

    @Test("ParentType has exactly 3 cases")
    func parentTypeCaseCount() {
        #expect(ParentType.allCases.count == 3)
    }

    @Test("ParentType is Codable (round-trip)")
    func parentTypeCodable() throws {
        for parentType in ParentType.allCases {
            let data = try JSONEncoder().encode(parentType)
            let decoded = try JSONDecoder().decode(ParentType.self, from: data)
            #expect(decoded == parentType)
        }
    }
}

// MARK: - ActorType Tests

@Suite("ActorType Tests")
@MainActor
struct ActorTypeTests {
    @Test("ActorType has correct raw values")
    func actorTypeRawValues() {
        #expect(ActorType.human.rawValue == "human")
        #expect(ActorType.ai.rawValue == "ai")
    }

    @Test("ActorType has exactly 2 cases")
    func actorTypeCaseCount() {
        #expect(ActorType.allCases.count == 2)
    }

    @Test("ActorType is Codable (round-trip)")
    func actorTypeCodable() throws {
        for actorType in ActorType.allCases {
            let data = try JSONEncoder().encode(actorType)
            let decoded = try JSONDecoder().decode(ActorType.self, from: data)
            #expect(decoded == actorType)
        }
    }

    @Test("ActorType conforms to Sendable")
    func actorTypeIsSendable() {
        let actorType: any Sendable = ActorType.human
        #expect(actorType is ActorType)
    }
}

// MARK: - EventMetadata Tests

@Suite("EventMetadata Tests")
@MainActor
struct EventMetadataTests {
    @Test("EventMetadata defaults to human actor")
    func eventMetadataDefaultsToHuman() {
        let metadata = EventMetadata()
        #expect(metadata.actorType == .human)
        #expect(metadata.actorId == nil)
    }

    @Test("EventMetadata human factory creates human metadata")
    func eventMetadataHumanFactory() {
        let metadata = EventMetadata.human()
        #expect(metadata.actorType == .human)
        #expect(metadata.actorId == nil)
    }

    @Test("EventMetadata AI factory creates AI metadata with agent ID")
    func eventMetadataAIFactory() {
        let metadata = EventMetadata.ai(agentId: "ada-agent")
        #expect(metadata.actorType == .ai)
        #expect(metadata.actorId == "ada-agent")
    }

    @Test("EventMetadata is Codable (round-trip)")
    func eventMetadataCodable() throws {
        let original = EventMetadata.ai(agentId: "test-agent-123")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventMetadata.self, from: data)
        #expect(decoded.actorType == original.actorType)
        #expect(decoded.actorId == original.actorId)
    }

    @Test("EventMetadata human round-trips with nil actorId")
    func eventMetadataHumanCodable() throws {
        let original = EventMetadata.human()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventMetadata.self, from: data)
        #expect(decoded.actorType == .human)
        #expect(decoded.actorId == nil)
    }

    @Test("EventMetadata custom init sets values correctly")
    func eventMetadataCustomInit() {
        let metadata = EventMetadata(actorType: .ai, actorId: "custom-id")
        #expect(metadata.actorType == .ai)
        #expect(metadata.actorId == "custom-id")
    }

    @Test("EventMetadata conforms to Sendable")
    func eventMetadataIsSendable() {
        let metadata: any Sendable = EventMetadata.human()
        #expect(metadata is EventMetadata)
    }
}

// MARK: - SyncState Tests

@Suite("SyncState Tests")
@MainActor
struct SyncStateTests {
    @Test("SyncState has correct raw values")
    func syncStateRawValues() {
        #expect(SyncState.pending.rawValue == "pending")
        #expect(SyncState.synced.rawValue == "synced")
        #expect(SyncState.failed.rawValue == "failed")
    }

    @Test("SyncState has exactly 3 cases")
    func syncStateCaseCount() {
        #expect(SyncState.allCases.count == 3)
    }

    @Test("SyncState is Codable (round-trip)")
    func syncStateCodable() throws {
        for state in SyncState.allCases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(SyncState.self, from: data)
            #expect(decoded == state)
        }
    }
}

// MARK: - UploadState Tests

@Suite("UploadState Tests")
@MainActor
struct UploadStateTests {
    @Test("UploadState has correct raw values")
    func uploadStateRawValues() {
        #expect(UploadState.pending.rawValue == "pending")
        #expect(UploadState.uploading.rawValue == "uploading")
        #expect(UploadState.completed.rawValue == "completed")
        #expect(UploadState.failed.rawValue == "failed")
    }

    @Test("UploadState has exactly 4 cases")
    func uploadStateCaseCount() {
        #expect(UploadState.allCases.count == 4)
    }

    @Test("UploadState is Codable (round-trip)")
    func uploadStateCodable() throws {
        for state in UploadState.allCases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(UploadState.self, from: data)
            #expect(decoded == state)
        }
    }
}

// MARK: - EventType Tests

@Suite("EventType Tests")
@MainActor
struct EventTypeTests {
    @Test("EventType stack events have correct raw values")
    func eventTypeStackRawValues() {
        #expect(EventType.stackCreated.rawValue == "stack.created")
        #expect(EventType.stackUpdated.rawValue == "stack.updated")
        #expect(EventType.stackDeleted.rawValue == "stack.deleted")
        #expect(EventType.stackDiscarded.rawValue == "stack.discarded")
        #expect(EventType.stackActivated.rawValue == "stack.activated")
        #expect(EventType.stackDeactivated.rawValue == "stack.deactivated")
        #expect(EventType.stackCompleted.rawValue == "stack.completed")
        #expect(EventType.stackClosed.rawValue == "stack.closed")
        #expect(EventType.stackReordered.rawValue == "stack.reordered")
    }

    @Test("EventType task events have correct raw values")
    func eventTypeTaskRawValues() {
        #expect(EventType.taskCreated.rawValue == "task.created")
        #expect(EventType.taskUpdated.rawValue == "task.updated")
        #expect(EventType.taskDeleted.rawValue == "task.deleted")
        #expect(EventType.taskActivated.rawValue == "task.activated")
        #expect(EventType.taskCompleted.rawValue == "task.completed")
        #expect(EventType.taskClosed.rawValue == "task.closed")
        #expect(EventType.taskReordered.rawValue == "task.reordered")
        #expect(EventType.taskDelegatedToAI.rawValue == "task.delegatedToAI")
        #expect(EventType.taskAICompleted.rawValue == "task.aiCompleted")
    }

    @Test("EventType reminder events have correct raw values")
    func eventTypeReminderRawValues() {
        #expect(EventType.reminderCreated.rawValue == "reminder.created")
        #expect(EventType.reminderUpdated.rawValue == "reminder.updated")
        #expect(EventType.reminderDeleted.rawValue == "reminder.deleted")
        #expect(EventType.reminderSnoozed.rawValue == "reminder.snoozed")
    }

    @Test("EventType tag events have correct raw values")
    func eventTypeTagRawValues() {
        #expect(EventType.tagCreated.rawValue == "tag.created")
        #expect(EventType.tagUpdated.rawValue == "tag.updated")
        #expect(EventType.tagDeleted.rawValue == "tag.deleted")
    }

    @Test("EventType arc events have correct raw values")
    func eventTypeArcRawValues() {
        #expect(EventType.arcCreated.rawValue == "arc.created")
        #expect(EventType.arcUpdated.rawValue == "arc.updated")
        #expect(EventType.arcDeleted.rawValue == "arc.deleted")
        #expect(EventType.arcActivated.rawValue == "arc.activated")
        #expect(EventType.arcDeactivated.rawValue == "arc.deactivated")
        #expect(EventType.arcCompleted.rawValue == "arc.completed")
        #expect(EventType.arcPaused.rawValue == "arc.paused")
        #expect(EventType.arcReordered.rawValue == "arc.reordered")
        #expect(EventType.stackAssignedToArc.rawValue == "stack.assignedToArc")
        #expect(EventType.stackRemovedFromArc.rawValue == "stack.removedFromArc")
    }

    @Test("EventType attachment events have correct raw values")
    func eventTypeAttachmentRawValues() {
        #expect(EventType.attachmentAdded.rawValue == "attachment.added")
        #expect(EventType.attachmentRemoved.rawValue == "attachment.removed")
    }

    @Test("EventType device events have correct raw values")
    func eventTypeDeviceRawValues() {
        #expect(EventType.deviceDiscovered.rawValue == "device.discovered")
    }

    @Test("EventType is Codable (round-trip for all cases)")
    func eventTypeCodableAllCases() throws {
        for eventType in EventType.allCases {
            let data = try JSONEncoder().encode(eventType)
            let decoded = try JSONDecoder().decode(EventType.self, from: data)
            #expect(decoded == eventType, "Failed round-trip for \(eventType.rawValue)")
        }
    }

    @Test("EventType decodes from JSON raw value string")
    func eventTypeDecodesFromJSON() throws {
        let json = Data("\"task.completed\"".utf8)
        let decoded = try JSONDecoder().decode(EventType.self, from: json)
        #expect(decoded == .taskCompleted)
    }

    @Test("EventType has expected total case count")
    func eventTypeTotalCaseCount() {
        // 9 stack + 9 task + 4 reminder + 3 tag + 1 device + 2 attachment + 10 arc = 38
        #expect(EventType.allCases.count == 38)
    }

    @Test("EventType returns nil for invalid raw value")
    func eventTypeInvalidRawValue() {
        #expect(EventType(rawValue: "invalid.event") == nil)
        #expect(EventType(rawValue: "") == nil)
        #expect(EventType(rawValue: "stack") == nil)
    }
}
