//
//  EventServiceTests.swift
//  DequeueTests
//
//  Tests for EventService - event storage and retrieval
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container for EventService tests
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Event.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )
}

@Suite("EventService Tests", .serialized)
struct EventServiceTests {

    @Test("fetchEventsByIds returns events matching provided IDs")
    @MainActor
    func fetchEventsByIdsReturnsMatchingEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create test events with specific IDs
        let event1 = Event(
            id: "event-1",
            type: "stack.created",
            payload: try JSONEncoder().encode(["stackId": "123"]),
            timestamp: Date()
        )
        let event2 = Event(
            id: "event-2",
            type: "task.created",
            payload: try JSONEncoder().encode(["taskId": "456"]),
            timestamp: Date()
        )
        let event3 = Event(
            id: "event-3",
            type: "stack.updated",
            payload: try JSONEncoder().encode(["stackId": "123"]),
            timestamp: Date()
        )

        context.insert(event1)
        context.insert(event2)
        context.insert(event3)
        try context.save()

        let eventService = EventService(modelContext: context)

        // Fetch events by specific IDs
        let requestedIds = ["event-1", "event-3"]
        let fetchedEvents = try eventService.fetchEventsByIds(requestedIds)

        #expect(fetchedEvents.count == 2)
        let fetchedIds = Set(fetchedEvents.map { $0.id })
        #expect(fetchedIds.contains("event-1"))
        #expect(fetchedIds.contains("event-3"))
        #expect(!fetchedIds.contains("event-2"))
    }

    @Test("fetchEventsByIds returns empty array when no matching events")
    @MainActor
    func fetchEventsByIdsReturnsEmptyArrayWhenNoMatches() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create test event
        let event = Event(
            id: "event-1",
            type: "stack.created",
            payload: try JSONEncoder().encode(["stackId": "123"]),
            timestamp: Date()
        )
        context.insert(event)
        try context.save()

        let eventService = EventService(modelContext: context)

        // Try to fetch non-existent events
        let fetchedEvents = try eventService.fetchEventsByIds(["non-existent-1", "non-existent-2"])

        #expect(fetchedEvents.isEmpty)
    }

    @Test("fetchEventsByIds returns all matching events from large set")
    @MainActor
    func fetchEventsByIdsHandlesLargeSet() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create 100 test events
        for index in 1...100 {
            let event = Event(
                id: "event-\(index)",
                type: "stack.created",
                payload: try JSONEncoder().encode(["index": index]),
                timestamp: Date()
            )
            context.insert(event)
        }
        try context.save()

        let eventService = EventService(modelContext: context)

        // Fetch specific subset
        let requestedIds = (1...10).map { "event-\($0)" }
        let fetchedEvents = try eventService.fetchEventsByIds(requestedIds)

        #expect(fetchedEvents.count == 10)

        let fetchedIds = Set(fetchedEvents.map { $0.id })
        for id in requestedIds {
            #expect(fetchedIds.contains(id))
        }
    }
}
