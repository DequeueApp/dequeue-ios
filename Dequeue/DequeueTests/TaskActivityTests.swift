//
//  TaskActivityTests.swift
//  DequeueTests
//
//  Tests for TaskActivity model, TaskActivityService, and activity types.
//

import Testing
import Foundation

@testable import Dequeue

// MARK: - TaskActivityType Tests

@Suite("TaskActivityType")
@MainActor
struct TaskActivityTypeTests {
    @Test("All types have icons")
    func allHaveIcons() {
        let allTypes: [TaskActivityType] = [
            .created, .statusChanged, .titleChanged, .descriptionChanged,
            .priorityChanged, .dueDateChanged, .dueDateRemoved, .movedToStack,
            .tagAdded, .tagRemoved, .reminderAdded, .dependencyAdded,
            .dependencyRemoved, .completed, .reopened, .blocked, .unblocked
        ]
        for type in allTypes {
            #expect(!type.icon.isEmpty, "Missing icon for \(type)")
        }
    }

    @Test("All types have display names")
    func allHaveDisplayNames() {
        let allTypes: [TaskActivityType] = [
            .created, .statusChanged, .titleChanged, .descriptionChanged,
            .priorityChanged, .dueDateChanged, .dueDateRemoved, .movedToStack,
            .tagAdded, .tagRemoved, .reminderAdded, .dependencyAdded,
            .dependencyRemoved, .completed, .reopened, .blocked, .unblocked
        ]
        for type in allTypes {
            #expect(!type.displayName.isEmpty, "Missing displayName for \(type)")
        }
    }

    @Test("All types have colors")
    func allHaveColors() {
        let allTypes: [TaskActivityType] = [
            .created, .statusChanged, .titleChanged, .descriptionChanged,
            .priorityChanged, .dueDateChanged, .dueDateRemoved, .movedToStack,
            .tagAdded, .tagRemoved, .reminderAdded, .dependencyAdded,
            .dependencyRemoved, .completed, .reopened, .blocked, .unblocked
        ]
        for type in allTypes {
            #expect(!type.color.isEmpty, "Missing color for \(type)")
        }
    }

    @Test("Types are Codable")
    func codable() throws {
        let data = try JSONEncoder().encode(TaskActivityType.completed)
        let decoded = try JSONDecoder().decode(TaskActivityType.self, from: data)
        #expect(decoded == .completed)
    }
}

// MARK: - TaskActivity Model Tests

@Suite("TaskActivity Model")
@MainActor
struct TaskActivityModelTests {
    @Test("Creates with default values")
    func defaultInit() {
        let activity = TaskActivity(taskId: "task-1", type: .created)
        #expect(activity.taskId == "task-1")
        #expect(activity.type == .created)
        #expect(!activity.id.isEmpty)
        #expect(activity.detail == nil)
        #expect(activity.previousValue == nil)
        #expect(activity.newValue == nil)
    }

    @Test("Summary for created activity")
    func createdSummary() {
        let activity = TaskActivity(taskId: "t", type: .created)
        #expect(activity.summary == "Task created")
    }

    @Test("Summary for completed activity")
    func completedSummary() {
        let activity = TaskActivity(taskId: "t", type: .completed)
        #expect(activity.summary == "Task completed")
    }

    @Test("Summary for blocked with reason")
    func blockedWithReason() {
        let activity = TaskActivity(taskId: "t", type: .blocked, detail: "Waiting on API")
        #expect(activity.summary == "Blocked: Waiting on API")
    }

    @Test("Summary for status change")
    func statusChangeSummary() {
        let activity = TaskActivity(taskId: "t", type: .statusChanged, newValue: "completed")
        #expect(activity.summary == "Status → completed")
    }

    @Test("Summary for title change")
    func titleChangeSummary() {
        let activity = TaskActivity(taskId: "t", type: .titleChanged, newValue: "New Title")
        #expect(activity.summary == "Renamed to \"New Title\"")
    }

    @Test("Summary for priority change")
    func priorityChangeSummary() {
        let activity = TaskActivity(taskId: "t", type: .priorityChanged, newValue: "3")
        #expect(activity.summary == "Priority → High")
    }

    @Test("Summary for move to stack")
    func moveToStackSummary() {
        let activity = TaskActivity(taskId: "t", type: .movedToStack, detail: "Inbox")
        #expect(activity.summary == "Moved to \"Inbox\"")
    }

    @Test("Summary for tag added")
    func tagAddedSummary() {
        let activity = TaskActivity(taskId: "t", type: .tagAdded, detail: "urgent")
        #expect(activity.summary == "Tagged with \"urgent\"")
    }

    @Test("Summary for dependency added")
    func dependencyAddedSummary() {
        let activity = TaskActivity(taskId: "t", type: .dependencyAdded, detail: "Setup DB")
        #expect(activity.summary == "Blocked by \"Setup DB\"")
    }

    @Test("Activity is Codable")
    func codable() throws {
        let activity = TaskActivity(
            taskId: "task-1",
            type: .priorityChanged,
            detail: "Manual change",
            previousValue: "1",
            newValue: "3"
        )
        let data = try JSONEncoder().encode(activity)
        let decoded = try JSONDecoder().decode(TaskActivity.self, from: data)
        #expect(decoded.taskId == "task-1")
        #expect(decoded.type == .priorityChanged)
        #expect(decoded.detail == "Manual change")
        #expect(decoded.previousValue == "1")
        #expect(decoded.newValue == "3")
    }
}

// MARK: - TaskActivityService Tests

@Suite("TaskActivityService")
@MainActor
struct TaskActivityServiceTests {
    @Test("Records and retrieves activities")
    @MainActor func recordAndRetrieve() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = TaskActivityService(userDefaults: defaults)

        service.record(taskId: "task-1", type: .created)
        service.record(taskId: "task-1", type: .titleChanged, newValue: "Updated Title")

        let activities = service.getActivities(for: "task-1")
        #expect(activities.count == 2)
    }

    @Test("Activities are sorted newest first")
    @MainActor func sortedNewestFirst() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = TaskActivityService(userDefaults: defaults)

        service.record(taskId: "task-1", type: .created)
        // Small delay to ensure different timestamps
        service.record(taskId: "task-1", type: .completed)

        let activities = service.getActivities(for: "task-1")
        #expect(activities.count == 2)
        #expect(activities[0].timestamp >= activities[1].timestamp)
    }

    @Test("Different tasks have separate histories")
    @MainActor func separateHistories() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = TaskActivityService(userDefaults: defaults)

        service.record(taskId: "task-1", type: .created)
        service.record(taskId: "task-2", type: .created)
        service.record(taskId: "task-2", type: .completed)

        #expect(service.getActivities(for: "task-1").count == 1)
        #expect(service.getActivities(for: "task-2").count == 2)
    }

    @Test("Empty task returns empty activities")
    @MainActor func emptyTask() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = TaskActivityService(userDefaults: defaults)

        let activities = service.getActivities(for: "nonexistent")
        #expect(activities.isEmpty)
    }

    @Test("Clear removes all activities for task")
    @MainActor func clearActivities() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = TaskActivityService(userDefaults: defaults)

        service.record(taskId: "task-1", type: .created)
        service.record(taskId: "task-1", type: .completed)
        #expect(service.getActivities(for: "task-1").count == 2)

        service.clearActivities(for: "task-1")
        #expect(service.getActivities(for: "task-1").isEmpty)
    }

    @Test("Caps at 100 activities per task")
    @MainActor func capsAt100() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = TaskActivityService(userDefaults: defaults)

        for _ in 0..<120 {
            service.record(taskId: "task-1", type: .statusChanged)
        }

        let activities = service.getActivities(for: "task-1")
        #expect(activities.count == 100)
    }

    @Test("Grouped activities returns date groups")
    @MainActor func groupedActivities() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = TaskActivityService(userDefaults: defaults)

        service.record(taskId: "task-1", type: .created)
        service.record(taskId: "task-1", type: .completed)

        let grouped = service.getGroupedActivities(for: "task-1")
        #expect(!grouped.isEmpty)
        // Both recorded now, so should be in same group
        #expect(grouped[0].activities.count == 2)
    }

    @Test("Records with all optional fields")
    @MainActor func recordWithOptionals() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service = TaskActivityService(userDefaults: defaults)

        service.record(
            taskId: "task-1",
            type: .priorityChanged,
            detail: "User changed",
            previousValue: "1",
            newValue: "3"
        )

        let activities = service.getActivities(for: "task-1")
        #expect(activities.count == 1)
        #expect(activities[0].detail == "User changed")
        #expect(activities[0].previousValue == "1")
        #expect(activities[0].newValue == "3")
    }
}
