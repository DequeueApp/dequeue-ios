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
struct EventTests {

    @Test("Event initializes with type string")
    func eventInitializesWithTypeString() {
        let payload = try! JSONEncoder().encode(["key": "value"])
        let event = Event(type: "stack.created", payload: payload)

        #expect(event.type == "stack.created")
        #expect(event.eventType == .stackCreated)
        #expect(event.isSynced == false)
    }

    @Test("Event initializes with EventType enum")
    func eventInitializesWithEventType() {
        let payload = try! JSONEncoder().encode(["stackId": "123"])
        let event = Event(eventType: .stackCreated, payload: payload)

        #expect(event.type == "stack.created")
        #expect(event.eventType == .stackCreated)
    }

    @Test("Event decodes payload correctly")
    func eventDecodesPayload() throws {
        struct TestPayload: Codable, Equatable {
            let stackId: String
            let title: String
        }

        let original = TestPayload(stackId: "123", title: "Test")
        let payload = try JSONEncoder().encode(original)
        let event = Event(eventType: .stackCreated, payload: payload)

        let decoded = try event.decodePayload(TestPayload.self)
        #expect(decoded == original)
    }

    @Test("Event can be persisted")
    func eventCanBePersisted() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Event.self, configurations: config)
        let context = ModelContext(container)

        let payload = try JSONEncoder().encode(["test": "data"])
        let event = Event(eventType: .stackCreated, payload: payload)
        context.insert(event)

        try context.save()

        let fetchDescriptor = FetchDescriptor<Event>()
        let events = try context.fetch(fetchDescriptor)

        #expect(events.count == 1)
        #expect(events.first?.eventType == .stackCreated)
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
