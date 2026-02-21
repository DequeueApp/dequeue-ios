//
//  WidgetModelsTests.swift
//  DequeueTests
//
//  Tests for shared widget models (WidgetModels.swift)
//  DEQ-120, DEQ-121
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - WidgetActiveStackData Tests

@Suite("WidgetActiveStackData Tests")
@MainActor
struct WidgetActiveStackDataTests {
    @Test("Encoding and decoding roundtrip preserves all fields")
    func encodingDecodingRoundtrip() throws {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let original = WidgetActiveStackData(
            stackTitle: "My Active Stack",
            stackId: "stack-abc-123",
            activeTaskTitle: "Do the thing",
            activeTaskId: "task-xyz-789",
            pendingTaskCount: 5,
            totalTaskCount: 12,
            dueDate: dueDate,
            priority: 3,
            tags: ["work", "urgent"]
        )

        let data = try JSONEncoder.widgetEncoder.encode(original)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetActiveStackData.self, from: data)

        #expect(decoded.stackTitle == "My Active Stack")
        #expect(decoded.stackId == "stack-abc-123")
        #expect(decoded.activeTaskTitle == "Do the thing")
        #expect(decoded.activeTaskId == "task-xyz-789")
        #expect(decoded.pendingTaskCount == 5)
        #expect(decoded.totalTaskCount == 12)
        #expect(decoded.dueDate == dueDate)
        #expect(decoded.priority == 3)
        #expect(decoded.tags == ["work", "urgent"])
    }

    @Test("Encoding and decoding with nil optional fields")
    func encodingDecodingWithNils() throws {
        let original = WidgetActiveStackData(
            stackTitle: "Minimal Stack",
            stackId: "stack-min-001",
            activeTaskTitle: nil,
            activeTaskId: nil,
            pendingTaskCount: 0,
            totalTaskCount: 0,
            dueDate: nil,
            priority: nil,
            tags: []
        )

        let data = try JSONEncoder.widgetEncoder.encode(original)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetActiveStackData.self, from: data)

        #expect(decoded.stackTitle == "Minimal Stack")
        #expect(decoded.stackId == "stack-min-001")
        #expect(decoded.activeTaskTitle == nil)
        #expect(decoded.activeTaskId == nil)
        #expect(decoded.pendingTaskCount == 0)
        #expect(decoded.totalTaskCount == 0)
        #expect(decoded.dueDate == nil)
        #expect(decoded.priority == nil)
        #expect(decoded.tags.isEmpty)
    }
}

// MARK: - WidgetUpNextData Tests

@Suite("WidgetUpNextData Tests")
@MainActor
struct WidgetUpNextDataTests {
    @Test("Encoding and decoding roundtrip preserves all fields")
    func encodingDecodingRoundtrip() throws {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let tasks = [
            WidgetTaskItem(
                id: "task-1",
                title: "First Task",
                stackTitle: "Stack A",
                stackId: "stack-a",
                dueDate: dueDate,
                priority: 2,
                isOverdue: false
            ),
            WidgetTaskItem(
                id: "task-2",
                title: "Second Task",
                stackTitle: "Stack B",
                stackId: "stack-b",
                dueDate: nil,
                priority: nil,
                isOverdue: true
            ),
        ]

        let original = WidgetUpNextData(
            upcomingTasks: tasks,
            overdueCount: 1
        )

        let data = try JSONEncoder.widgetEncoder.encode(original)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetUpNextData.self, from: data)

        #expect(decoded.upcomingTasks.count == 2)
        #expect(decoded.overdueCount == 1)
        #expect(decoded.upcomingTasks[0].id == "task-1")
        #expect(decoded.upcomingTasks[0].title == "First Task")
        #expect(decoded.upcomingTasks[0].stackTitle == "Stack A")
        #expect(decoded.upcomingTasks[0].dueDate == dueDate)
        #expect(decoded.upcomingTasks[0].priority == 2)
        #expect(decoded.upcomingTasks[0].isOverdue == false)
        #expect(decoded.upcomingTasks[1].id == "task-2")
        #expect(decoded.upcomingTasks[1].isOverdue == true)
    }

    @Test("Empty task list roundtrip")
    func emptyTasksRoundtrip() throws {
        let original = WidgetUpNextData(
            upcomingTasks: [],
            overdueCount: 0
        )

        let data = try JSONEncoder.widgetEncoder.encode(original)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetUpNextData.self, from: data)

        #expect(decoded.upcomingTasks.isEmpty)
        #expect(decoded.overdueCount == 0)
    }
}

// MARK: - WidgetStatsData Tests

@Suite("WidgetStatsData Tests")
@MainActor
struct WidgetStatsDataTests {
    @Test("Encoding and decoding roundtrip preserves all fields")
    func encodingDecodingRoundtrip() throws {
        let original = WidgetStatsData(
            completedToday: 7,
            pendingTotal: 23,
            activeStackCount: 3,
            overdueCount: 2,
            completionRate: 0.65
        )

        let data = try JSONEncoder.widgetEncoder.encode(original)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetStatsData.self, from: data)

        #expect(decoded.completedToday == 7)
        #expect(decoded.pendingTotal == 23)
        #expect(decoded.activeStackCount == 3)
        #expect(decoded.overdueCount == 2)
        #expect(abs(decoded.completionRate - 0.65) < 0.001)
    }

    @Test("Zero stats roundtrip")
    func zeroStatsRoundtrip() throws {
        let original = WidgetStatsData(
            completedToday: 0,
            pendingTotal: 0,
            activeStackCount: 0,
            overdueCount: 0,
            completionRate: 0.0
        )

        let data = try JSONEncoder.widgetEncoder.encode(original)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetStatsData.self, from: data)

        #expect(decoded.completedToday == 0)
        #expect(decoded.pendingTotal == 0)
        #expect(decoded.activeStackCount == 0)
        #expect(decoded.overdueCount == 0)
        #expect(decoded.completionRate == 0.0)
    }

    @Test("Full completion rate roundtrip")
    func fullCompletionRateRoundtrip() throws {
        let original = WidgetStatsData(
            completedToday: 10,
            pendingTotal: 0,
            activeStackCount: 1,
            overdueCount: 0,
            completionRate: 1.0
        )

        let data = try JSONEncoder.widgetEncoder.encode(original)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetStatsData.self, from: data)

        #expect(decoded.completionRate == 1.0)
    }
}

// MARK: - WidgetTaskItem Tests

@Suite("WidgetTaskItem Tests")
@MainActor
struct WidgetTaskItemTests {
    @Test("Encoding and decoding with all fields populated")
    func encodingDecodingAllFields() throws {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let item = WidgetTaskItem(
            id: "task-abc",
            title: "Buy groceries",
            stackTitle: "Errands",
            stackId: "stack-errands",
            dueDate: dueDate,
            priority: 1,
            isOverdue: false
        )

        let data = try JSONEncoder.widgetEncoder.encode(item)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetTaskItem.self, from: data)

        #expect(decoded.id == "task-abc")
        #expect(decoded.title == "Buy groceries")
        #expect(decoded.stackTitle == "Errands")
        #expect(decoded.stackId == "stack-errands")
        #expect(decoded.dueDate == dueDate)
        #expect(decoded.priority == 1)
        #expect(decoded.isOverdue == false)
    }

    @Test("Encoding and decoding with nil optional fields")
    func encodingDecodingWithNils() throws {
        let item = WidgetTaskItem(
            id: "task-nil",
            title: "No extras",
            stackTitle: "Stack",
            stackId: "stack-id",
            dueDate: nil,
            priority: nil,
            isOverdue: false
        )

        let data = try JSONEncoder.widgetEncoder.encode(item)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetTaskItem.self, from: data)

        #expect(decoded.dueDate == nil)
        #expect(decoded.priority == nil)
    }

    @Test("Identifiable conformance uses id property")
    func identifiableConformance() {
        let item = WidgetTaskItem(
            id: "unique-id-123",
            title: "Test",
            stackTitle: "Stack",
            stackId: "stack-id",
            dueDate: nil,
            priority: nil,
            isOverdue: false
        )

        #expect(item.id == "unique-id-123")
    }
}

// MARK: - AppGroupConfig Tests

@Suite("AppGroupConfig Tests")
@MainActor
struct AppGroupConfigTests {
    @Test("Suite name is non-empty")
    func suiteNameNonEmpty() {
        #expect(!AppGroupConfig.suiteName.isEmpty)
        #expect(AppGroupConfig.suiteName.contains("Dequeue"))
    }

    @Test("Active stack key is non-empty")
    func activeStackKeyNonEmpty() {
        #expect(!AppGroupConfig.activeStackKey.isEmpty)
    }

    @Test("Up next key is non-empty")
    func upNextKeyNonEmpty() {
        #expect(!AppGroupConfig.upNextKey.isEmpty)
    }

    @Test("Stats key is non-empty")
    func statsKeyNonEmpty() {
        #expect(!AppGroupConfig.statsKey.isEmpty)
    }

    @Test("Last update key is non-empty")
    func lastUpdateKeyNonEmpty() {
        #expect(!AppGroupConfig.lastUpdateKey.isEmpty)
    }

    @Test("All keys are distinct")
    func allKeysDistinct() {
        let keys = [
            AppGroupConfig.activeStackKey,
            AppGroupConfig.upNextKey,
            AppGroupConfig.statsKey,
            AppGroupConfig.lastUpdateKey,
        ]
        #expect(Set(keys).count == keys.count)
    }
}

// MARK: - WidgetDataReader Tests

@Suite("WidgetDataReader Tests")
@MainActor
struct WidgetDataReaderTests {
    @Test("readActiveStack returns nil when no data stored")
    func readActiveStackReturnsNilWhenEmpty() {
        // Clear any existing data
        let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName)
        defaults?.removeObject(forKey: AppGroupConfig.activeStackKey)

        let result = WidgetDataReader.readActiveStack()
        // May be nil because either no data or App Group not available in test environment
        // The key behavior is that it doesn't crash and returns nil gracefully
        #expect(result == nil)
    }

    @Test("readUpNext returns nil when no data stored")
    func readUpNextReturnsNilWhenEmpty() {
        let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName)
        defaults?.removeObject(forKey: AppGroupConfig.upNextKey)

        let result = WidgetDataReader.readUpNext()
        #expect(result == nil)
    }

    @Test("readStats returns nil when no data stored")
    func readStatsReturnsNilWhenEmpty() {
        let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName)
        defaults?.removeObject(forKey: AppGroupConfig.statsKey)

        let result = WidgetDataReader.readStats()
        #expect(result == nil)
    }

    @Test("lastUpdateDate returns nil when no data stored")
    func lastUpdateDateReturnsNilWhenEmpty() {
        let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName)
        defaults?.removeObject(forKey: AppGroupConfig.lastUpdateKey)

        let result = WidgetDataReader.lastUpdateDate()
        #expect(result == nil)
    }

    @Test("readActiveStack returns correct data when stored in UserDefaults")
    func readActiveStackReturnsStoredData() throws {
        guard let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName) else {
            // App Group may not be available in test environment — skip gracefully
            return
        }

        let original = WidgetActiveStackData(
            stackTitle: "Test Stack",
            stackId: "stack-test",
            activeTaskTitle: "Test Task",
            activeTaskId: "task-test",
            pendingTaskCount: 3,
            totalTaskCount: 5,
            dueDate: nil,
            priority: 2,
            tags: ["test"]
        )

        let encoded = try JSONEncoder.widgetEncoder.encode(original)
        defaults.set(encoded, forKey: AppGroupConfig.activeStackKey)

        let result = WidgetDataReader.readActiveStack()
        #expect(result?.stackTitle == "Test Stack")
        #expect(result?.stackId == "stack-test")
        #expect(result?.activeTaskTitle == "Test Task")
        #expect(result?.pendingTaskCount == 3)

        // Clean up
        defaults.removeObject(forKey: AppGroupConfig.activeStackKey)
    }

    @Test("readUpNext returns correct data when stored in UserDefaults")
    func readUpNextReturnsStoredData() throws {
        guard let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName) else {
            return
        }

        let original = WidgetUpNextData(
            upcomingTasks: [
                WidgetTaskItem(
                    id: "task-1",
                    title: "Task 1",
                    stackTitle: "Stack",
                    stackId: "stack-1",
                    dueDate: Date(timeIntervalSince1970: 1_800_000_000),
                    priority: 1,
                    isOverdue: false
                ),
            ],
            overdueCount: 0
        )

        let encoded = try JSONEncoder.widgetEncoder.encode(original)
        defaults.set(encoded, forKey: AppGroupConfig.upNextKey)

        let result = WidgetDataReader.readUpNext()
        #expect(result?.upcomingTasks.count == 1)
        #expect(result?.upcomingTasks.first?.title == "Task 1")
        #expect(result?.overdueCount == 0)

        defaults.removeObject(forKey: AppGroupConfig.upNextKey)
    }

    @Test("readStats returns correct data when stored in UserDefaults")
    func readStatsReturnsStoredData() throws {
        guard let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName) else {
            return
        }

        let original = WidgetStatsData(
            completedToday: 5,
            pendingTotal: 10,
            activeStackCount: 2,
            overdueCount: 1,
            completionRate: 0.33
        )

        let encoded = try JSONEncoder.widgetEncoder.encode(original)
        defaults.set(encoded, forKey: AppGroupConfig.statsKey)

        let result = WidgetDataReader.readStats()
        #expect(result?.completedToday == 5)
        #expect(result?.pendingTotal == 10)
        #expect(result?.activeStackCount == 2)
        #expect(result?.overdueCount == 1)
        #expect(result?.completionRate != nil)
        if let rate = result?.completionRate {
            #expect(abs(rate - 0.33) < 0.001)
        }

        defaults.removeObject(forKey: AppGroupConfig.statsKey)
    }

    @Test("readActiveStack returns nil for invalid/corrupt data")
    func readActiveStackReturnsNilForCorruptData() {
        guard let defaults = UserDefaults(suiteName: AppGroupConfig.suiteName) else {
            return
        }

        // Store invalid JSON data
        defaults.set(Data("not valid json".utf8), forKey: AppGroupConfig.activeStackKey)

        let result = WidgetDataReader.readActiveStack()
        #expect(result == nil)

        defaults.removeObject(forKey: AppGroupConfig.activeStackKey)
    }
}

// MARK: - JSON Coding Helpers Tests

@Suite("Widget JSON Coding Tests")
@MainActor
struct WidgetJSONCodingTests {
    @Test("widgetEncoder uses ISO 8601 date format")
    func encoderUsesISO8601() throws {
        let date = Date(timeIntervalSince1970: 0) // 1970-01-01T00:00:00Z
        let item = WidgetTaskItem(
            id: "test",
            title: "Test",
            stackTitle: "Stack",
            stackId: "stack",
            dueDate: date,
            priority: nil,
            isOverdue: false
        )

        let data = try JSONEncoder.widgetEncoder.encode(item)
        let jsonString = String(data: data, encoding: .utf8)!

        // ISO 8601 format should contain "1970-01-01T00:00:00Z" or similar
        #expect(jsonString.contains("1970"))
        #expect(jsonString.contains("T"))
    }

    @Test("widgetDecoder correctly parses ISO 8601 dates")
    func decoderParsesISO8601() throws {
        // Encode a known date, then decode and verify
        let knownDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = WidgetTaskItem(
            id: "date-test",
            title: "Date Test",
            stackTitle: "Stack",
            stackId: "stack",
            dueDate: knownDate,
            priority: nil,
            isOverdue: false
        )

        let data = try JSONEncoder.widgetEncoder.encode(original)
        let decoded = try JSONDecoder.widgetDecoder.decode(WidgetTaskItem.self, from: data)

        // Dates should be equal (ISO 8601 preserves second-level precision)
        #expect(decoded.dueDate != nil)
        let timeDiff = abs(decoded.dueDate!.timeIntervalSince(knownDate))
        #expect(timeDiff < 1.0)
    }

    @Test("Encoder and decoder are consistent roundtrip for dates")
    func encoderDecoderDateConsistency() throws {
        let dates: [Date] = [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1_000_000_000),
            Date(timeIntervalSince1970: 1_800_000_000),
            Date(), // current date
        ]

        for originalDate in dates {
            let item = WidgetActiveStackData(
                stackTitle: "Test",
                stackId: "test",
                activeTaskTitle: nil,
                activeTaskId: nil,
                pendingTaskCount: 0,
                totalTaskCount: 0,
                dueDate: originalDate,
                priority: nil,
                tags: []
            )

            let data = try JSONEncoder.widgetEncoder.encode(item)
            let decoded = try JSONDecoder.widgetDecoder.decode(WidgetActiveStackData.self, from: data)

            #expect(decoded.dueDate != nil)
            let timeDiff = abs(decoded.dueDate!.timeIntervalSince(originalDate))
            #expect(timeDiff < 1.0, "Date roundtrip failed for \(originalDate)")
        }
    }
}
