//
//  EventTests.swift
//  DequeueTests
//
//  Tests for Event model
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Event Model Tests")
@MainActor
struct EventTests {
    @Test("Event initializes with type string")
    func eventInitializesWithTypeString() throws {
        let payload = try JSONEncoder().encode(["key": "value"])
        let event = Event(
            type: "stack.created",
            payload: payload,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )

        #expect(event.type == "stack.created")
        #expect(event.eventType == .stackCreated)
        #expect(event.isSynced == false)
        #expect(event.userId == "test-user")
        #expect(event.deviceId == "test-device")
        #expect(event.appId == "test-app")
        #expect(event.payloadVersion == Event.currentPayloadVersion)
    }

    @Test("Event initializes with EventType enum")
    func eventInitializesWithEventType() throws {
        let payload = try JSONEncoder().encode(["stackId": "123"])
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )

        #expect(event.type == "stack.created")
        #expect(event.eventType == .stackCreated)
        #expect(event.userId == "test-user")
        #expect(event.deviceId == "test-device")
        #expect(event.appId == "test-app")
    }

    @Test("Event decodes payload correctly")
    func eventDecodesPayload() throws {
        struct TestPayload: Codable, Equatable {
            let stackId: String
            let title: String
        }

        let original = TestPayload(stackId: "123", title: "Test")
        let payload = try JSONEncoder().encode(original)
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )

        let decoded = try event.decodePayload(TestPayload.self)
        #expect(decoded == original)
    }

    @Test("Event can be persisted")
    func eventCanBePersisted() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Event.self, configurations: config)
        let context = ModelContext(container)

        let payload = try JSONEncoder().encode(["test": "data"])
        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )
        context.insert(event)

        try context.save()

        let fetchDescriptor = FetchDescriptor<Event>()
        let events = try context.fetch(fetchDescriptor)

        #expect(events.count == 1)
        #expect(events.first?.eventType == .stackCreated)
        #expect(events.first?.userId == "test-user")
        #expect(events.first?.deviceId == "test-device")
        #expect(events.first?.appId == "test-app")
    }

    @Test("encodePayload helper works")
    func encodePayloadHelperWorks() throws {
        struct TestData: Codable {
            let id: String
        }

        let data = TestData(id: "test-id")
        let encoded = try Event.encodePayload(data)

        #expect(!encoded.isEmpty)

        let decoded = try JSONDecoder().decode(TestData.self, from: encoded)
        #expect(decoded.id == "test-id")
    }

    // MARK: - ActorType Metadata Tests (DEQ-55)

    @Test("EventMetadata human factory creates human actor")
    func eventMetadataHumanFactory() throws {
        let metadata = EventMetadata.human()

        #expect(metadata.actorType == .human)
        #expect(metadata.actorId == nil)
    }

    @Test("EventMetadata ai factory creates AI actor with agent ID")
    func eventMetadataAIFactory() throws {
        let metadata = EventMetadata.ai(agentId: "agent-123")

        #expect(metadata.actorType == .ai)
        #expect(metadata.actorId == "agent-123")
    }

    @Test("Event with human actor metadata")
    func eventWithHumanActorMetadata() throws {
        let payload = try JSONEncoder().encode(["test": "data"])
        let metadata = try JSONEncoder().encode(EventMetadata.human())

        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            metadata: metadata,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )

        let decoded = try event.actorMetadata()
        #expect(decoded?.actorType == .human)
        #expect(decoded?.actorId == nil)
        #expect(event.isFromHuman == true)
        #expect(event.isFromAI == false)
    }

    @Test("Event with AI actor metadata")
    func eventWithAIActorMetadata() throws {
        let payload = try JSONEncoder().encode(["test": "data"])
        let metadata = try JSONEncoder().encode(EventMetadata.ai(agentId: "ai-agent-007"))

        let event = Event(
            eventType: .taskCompleted,
            payload: payload,
            metadata: metadata,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )

        let decoded = try event.actorMetadata()
        #expect(decoded?.actorType == .ai)
        #expect(decoded?.actorId == "ai-agent-007")
        #expect(event.isFromHuman == false)
        #expect(event.isFromAI == true)
    }

    @Test("Event with no metadata defaults to human")
    func eventWithNoMetadataDefaultsToHuman() throws {
        let payload = try JSONEncoder().encode(["test": "data"])

        let event = Event(
            eventType: .stackCreated,
            payload: payload,
            metadata: nil,
            userId: "test-user",
            deviceId: "test-device",
            appId: "test-app"
        )

        let decoded = try event.actorMetadata()
        #expect(decoded == nil)
        // Without metadata, isFromAI returns false (safe default)
        #expect(event.isFromAI == false)
    }
}
