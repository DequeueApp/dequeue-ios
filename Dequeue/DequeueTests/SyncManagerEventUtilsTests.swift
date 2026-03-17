//
//  SyncManagerEventUtilsTests.swift
//  DequeueTests
//
//  Tests for SyncManager static event utilities:
//    - extractEntityId(from:eventType:)  — payload ID extraction for history queries
//    - addActorMetadata(from:to:)         — actor metadata injection into event dicts
//    - generateSyncId()                  — short UUID-based ID for log correlation
//
//  These helpers live in SyncManager+DateParsing.swift and had zero coverage
//  before this file was added (2026-03-17).
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - extractEntityId Tests

@Suite("SyncManager extractEntityId Tests")
struct SyncManagerExtractEntityIdTests {

    // MARK: - stack.* events

    @Test("stack.* event returns stackId from payload")
    func stackEventReturnsStackId() {
        let payload: [String: Any] = ["stackId": "stack-123", "other": "value"]
        let result = SyncManager.extractEntityId(from: payload, eventType: "stack.created")
        #expect(result == "stack-123")
    }

    @Test("stack.updated event returns stackId")
    func stackUpdatedReturnsStackId() {
        let payload: [String: Any] = ["stackId": "stack-abc"]
        let result = SyncManager.extractEntityId(from: payload, eventType: "stack.updated")
        #expect(result == "stack-abc")
    }

    @Test("stack.* event without stackId falls through to state.id")
    func stackEventFallsToStateId() {
        let payload: [String: Any] = ["state": ["id": "state-id-xyz"]]
        let result = SyncManager.extractEntityId(from: payload, eventType: "stack.deleted")
        #expect(result == "state-id-xyz")
    }

    // MARK: - task.* events

    @Test("task.* event returns taskId from payload")
    func taskEventReturnsTaskId() {
        let payload: [String: Any] = ["taskId": "task-456", "stackId": "stack-999"]
        let result = SyncManager.extractEntityId(from: payload, eventType: "task.created")
        #expect(result == "task-456")
    }

    @Test("task.completed returns taskId")
    func taskCompletedReturnsTaskId() {
        let payload: [String: Any] = ["taskId": "task-completed-001"]
        let result = SyncManager.extractEntityId(from: payload, eventType: "task.completed")
        #expect(result == "task-completed-001")
    }

    @Test("task.* event without taskId falls through to state.id")
    func taskEventFallsToStateId() {
        let payload: [String: Any] = ["state": ["id": "task-state-id"]]
        let result = SyncManager.extractEntityId(from: payload, eventType: "task.updated")
        #expect(result == "task-state-id")
    }

    // MARK: - reminder.* events

    @Test("reminder.* event returns reminderId from payload")
    func reminderEventReturnsReminderId() {
        let payload: [String: Any] = ["reminderId": "reminder-789"]
        let result = SyncManager.extractEntityId(from: payload, eventType: "reminder.created")
        #expect(result == "reminder-789")
    }

    @Test("reminder.snoozed returns reminderId")
    func reminderSnoozedReturnsReminderId() {
        let payload: [String: Any] = ["reminderId": "reminder-snoozed-42", "snoozeUntil": "2026-01-01T00:00:00Z"]
        let result = SyncManager.extractEntityId(from: payload, eventType: "reminder.snoozed")
        #expect(result == "reminder-snoozed-42")
    }

    @Test("reminder.* event without reminderId falls through to state.id")
    func reminderEventFallsToStateId() {
        let payload: [String: Any] = ["state": ["id": "reminder-state-id"]]
        let result = SyncManager.extractEntityId(from: payload, eventType: "reminder.deleted")
        #expect(result == "reminder-state-id")
    }

    // MARK: - device.* events

    @Test("device.* event extracts id from state dict, not deviceId")
    func deviceEventUsesStateId() {
        // Device events use state.id (the record PK), NOT deviceId (the hardware identifier).
        let payload: [String: Any] = [
            "deviceId": "hardware-identifier-abc",
            "state": ["id": "device-record-uuid"]
        ]
        let result = SyncManager.extractEntityId(from: payload, eventType: "device.discovered")
        #expect(result == "device-record-uuid")
    }

    @Test("device.* event without state.id returns nil")
    func deviceEventWithoutStateIdReturnsNil() {
        let payload: [String: Any] = ["deviceId": "hardware-only"]
        let result = SyncManager.extractEntityId(from: payload, eventType: "device.discovered")
        #expect(result == nil)
    }

    // MARK: - Fallback paths for unrecognized prefixes

    @Test("Unknown event type falls back to state.id")
    func unknownEventTypeUsesStateId() {
        let payload: [String: Any] = ["state": ["id": "fallback-id-001"]]
        let result = SyncManager.extractEntityId(from: payload, eventType: "attachment.added")
        #expect(result == "fallback-id-001")
    }

    @Test("Unknown event type falls back to fullState.id when state is absent")
    func unknownEventTypeUsesFullStateId() {
        let payload: [String: Any] = ["fullState": ["id": "full-state-id-002"]]
        let result = SyncManager.extractEntityId(from: payload, eventType: "tag.updated")
        #expect(result == "full-state-id-002")
    }

    @Test("state.id takes priority over fullState.id")
    func stateIdTakesPriorityOverFullStateId() {
        let payload: [String: Any] = [
            "state": ["id": "state-wins"],
            "fullState": ["id": "full-state-loses"]
        ]
        let result = SyncManager.extractEntityId(from: payload, eventType: "arc.updated")
        #expect(result == "state-wins")
    }

    @Test("Empty payload returns nil")
    func emptyPayloadReturnsNil() {
        let payload: [String: Any] = [:]
        let result = SyncManager.extractEntityId(from: payload, eventType: "stack.created")
        #expect(result == nil)
    }

    @Test("Payload with only unrelated keys returns nil")
    func unrelatedKeysReturnsNil() {
        let payload: [String: Any] = ["foo": "bar", "count": 42]
        let result = SyncManager.extractEntityId(from: payload, eventType: "task.created")
        #expect(result == nil)
    }

    @Test("state dict without id key returns nil")
    func stateDictWithoutIdReturnsNil() {
        let payload: [String: Any] = ["state": ["name": "some-name", "status": "active"]]
        let result = SyncManager.extractEntityId(from: payload, eventType: "stack.updated")
        #expect(result == nil)
    }

    @Test("Non-dict state value returns nil")
    func nonDictStateReturnsNil() {
        let payload: [String: Any] = ["state": "not-a-dict"]
        let result = SyncManager.extractEntityId(from: payload, eventType: "task.updated")
        #expect(result == nil)
    }
}

// MARK: - addActorMetadata Tests

@Suite("SyncManager addActorMetadata Tests")
struct SyncManagerAddActorMetadataTests {

    private func makeMetadataData(actorType: String, actorId: String? = nil) -> Data {
        var dict: [String: Any] = ["actorType": actorType]
        if let actorId { dict["actorId"] = actorId }
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    @Test("nil metadata leaves dict unchanged")
    func nilMetadataLeavesDict() {
        var dict: [String: Any] = ["eventType": "task.created"]
        SyncManager.addActorMetadata(from: nil, to: &dict)
        #expect(dict.count == 1)
        #expect(dict["actor_type"] == nil)
        #expect(dict["actor_id"] == nil)
    }

    @Test("invalid JSON metadata leaves dict unchanged")
    func invalidJsonMetadataLeavesDict() {
        let badData = Data("not valid json".utf8)
        var dict: [String: Any] = ["eventType": "task.created"]
        SyncManager.addActorMetadata(from: badData, to: &dict)
        #expect(dict.count == 1)
        #expect(dict["actor_type"] == nil)
    }

    @Test("metadata without actorType leaves dict unchanged")
    func metadataWithoutActorTypeLeavesDict() {
        // JSON has actorId but NOT actorType — should be a no-op
        let data = try! JSONSerialization.data(withJSONObject: ["actorId": "agent-007"])
        var dict: [String: Any] = ["eventType": "task.created"]
        SyncManager.addActorMetadata(from: data, to: &dict)
        #expect(dict["actor_type"] == nil)
        #expect(dict["actor_id"] == nil)
    }

    @Test("human actorType adds actor_type=human, no actor_id")
    func humanActorTypeAddsActorType() {
        let data = makeMetadataData(actorType: "human")
        var dict: [String: Any] = [:]
        SyncManager.addActorMetadata(from: data, to: &dict)
        #expect(dict["actor_type"] as? String == "human")
        #expect(dict["actor_id"] == nil)
    }

    @Test("ai actorType with actorId adds both actor_type and actor_id")
    func aiActorTypeWithIdAddsBoth() {
        let data = makeMetadataData(actorType: "ai", actorId: "agent-456")
        var dict: [String: Any] = [:]
        SyncManager.addActorMetadata(from: data, to: &dict)
        #expect(dict["actor_type"] as? String == "ai")
        #expect(dict["actor_id"] as? String == "agent-456")
    }

    @Test("ai actorType without actorId adds actor_type but not actor_id")
    func aiActorTypeWithoutIdSkipsActorId() {
        let data = makeMetadataData(actorType: "ai")
        var dict: [String: Any] = [:]
        SyncManager.addActorMetadata(from: data, to: &dict)
        #expect(dict["actor_type"] as? String == "ai")
        #expect(dict["actor_id"] == nil)
    }

    @Test("addActorMetadata does not overwrite unrelated keys")
    func doesNotOverwriteOtherKeys() {
        let data = makeMetadataData(actorType: "human")
        var dict: [String: Any] = ["taskId": "task-999", "payload": ["key": "val"]]
        SyncManager.addActorMetadata(from: data, to: &dict)
        #expect(dict["taskId"] as? String == "task-999")
        #expect(dict["actor_type"] as? String == "human")
    }

    @Test("empty JSON object metadata leaves dict unchanged")
    func emptyJsonObjectLeavesDict() {
        let data = try! JSONSerialization.data(withJSONObject: [String: Any]())
        var dict: [String: Any] = ["x": 1]
        SyncManager.addActorMetadata(from: data, to: &dict)
        #expect(dict["actor_type"] == nil)
        #expect(dict.count == 1)
    }
}

// MARK: - generateSyncId Tests

@Suite("SyncManager generateSyncId Tests")
struct SyncManagerGenerateSyncIdTests {

    @Test("generateSyncId returns exactly 8 characters")
    func generateSyncIdHasLength8() {
        let id = SyncManager.generateSyncId()
        #expect(id.count == 8)
    }

    @Test("generateSyncId returns only alphanumeric and dash characters (UUID prefix)")
    func generateSyncIdIsValidUUIDPrefix() {
        let id = SyncManager.generateSyncId()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        #expect(id.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    @Test("generateSyncId returns unique values on successive calls")
    func generateSyncIdIsUnique() {
        // While not strictly guaranteed (8-char UUID prefix can collide),
        // the probability is ~1 in 10^12 — treat collision as test failure.
        let ids = Set((0..<50).map { _ in SyncManager.generateSyncId() })
        #expect(ids.count == 50)
    }
}
