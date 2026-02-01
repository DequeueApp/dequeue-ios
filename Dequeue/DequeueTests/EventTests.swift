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
}
