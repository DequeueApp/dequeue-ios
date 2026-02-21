//
//  AppIntentsTests.swift
//  DequeueTests
//
//  Tests for App Intents (Siri/Shortcuts integration)
//

import Testing
import Foundation
import SwiftData
import AppIntents
@testable import Dequeue

// MARK: - Stack Entity Tests

@Suite("StackEntity")
@MainActor
struct StackEntityTests {
    @Test("Creates entity from stack model")
    func entityFromStack() throws {
        let stack = Stack(title: "Work Tasks", isActive: true)
        let task1 = QueueTask(title: "Task 1", status: .pending, stack: stack)
        let task2 = QueueTask(title: "Task 2", status: .completed, stack: stack)
        stack.tasks = [task1, task2]

        let entity = stack.toEntity()
        #expect(entity.id == stack.id)
        #expect(entity.title == "Work Tasks")
        #expect(entity.taskCount == 2)
        #expect(entity.pendingTaskCount == 1)
        #expect(entity.isActive == true)
        #expect(entity.status == "active")
    }

    @Test("Entity excludes deleted tasks from counts")
    func entityExcludesDeletedTasks() throws {
        let stack = Stack(title: "Test Stack")
        let task1 = QueueTask(title: "Active", status: .pending, stack: stack)
        let task2 = QueueTask(title: "Deleted", status: .pending, isDeleted: true, stack: stack)
        stack.tasks = [task1, task2]

        let entity = stack.toEntity()
        #expect(entity.taskCount == 1)
        #expect(entity.pendingTaskCount == 1)
    }

    @Test("Active stack has display representation")
    func activeStackDisplay() throws {
        let entity = StackEntity(
            id: "test",
            title: "Active Stack",
            taskCount: 5,
            pendingTaskCount: 3,
            isActive: true,
            status: "active"
        )

        // Verify displayRepresentation is accessible (title is LocalizedStringResource)
        let repr = entity.displayRepresentation
        _ = repr  // No crash = success
    }

    @Test("Inactive stack has display representation")
    func inactiveStackDisplay() throws {
        let entity = StackEntity(
            id: "test",
            title: "Inactive Stack",
            taskCount: 5,
            pendingTaskCount: 3,
            isActive: false,
            status: "active"
        )

        let repr = entity.displayRepresentation
        _ = repr  // No crash = success
    }
}

// MARK: - Task Entity Tests

@Suite("TaskEntity")
@MainActor
struct TaskEntityTests {
    @Test("Creates entity from task model")
    func entityFromTask() throws {
        let stack = Stack(title: "Parent Stack")
        let task = QueueTask(
            title: "Important Task",
            dueTime: Date(),
            status: .pending,
            priority: 2,
            stack: stack
        )

        let entity = task.toEntity()
        #expect(entity.id == task.id)
        #expect(entity.title == "Important Task")
        #expect(entity.stackTitle == "Parent Stack")
        #expect(entity.priority == 2)
        #expect(entity.hasDueDate == true)
    }

    @Test("Task entity without stack shows nil stack title")
    func entityWithoutStack() throws {
        let task = QueueTask(title: "Orphan Task")
        let entity = task.toEntity()
        #expect(entity.stackTitle == nil)
    }

    @Test("Task entity has display representation")
    func entityDisplayWithStack() throws {
        let entity = TaskEntity(
            id: "test",
            title: "My Task",
            stackTitle: "Work",
            status: "pending",
            priority: nil,
            hasDueDate: false
        )

        let repr = entity.displayRepresentation
        _ = repr  // No crash = success
    }
}

// MARK: - Intent Priority Tests

@Suite("IntentPriority")
struct IntentPriorityTests {
    @Test("Priority raw values match expected integers")
    func priorityRawValues() {
        #expect(IntentPriority.low.rawIntValue == 0)
        #expect(IntentPriority.medium.rawIntValue == 1)
        #expect(IntentPriority.high.rawIntValue == 2)
        #expect(IntentPriority.urgent.rawIntValue == 3)
    }

    @Test("All priority cases have display representations")
    func priorityDisplayRepresentations() {
        let allCases: [IntentPriority] = [.low, .medium, .high, .urgent]
        for priority in allCases {
            #expect(IntentPriority.caseDisplayRepresentations[priority] != nil)
        }
    }
}

// MARK: - Intent Error Tests

@Suite("IntentError")
struct IntentErrorTests {
    @Test("All error cases have localized descriptions")
    func errorDescriptions() {
        let errors: [IntentError] = [
            .stackNotFound,
            .noActiveStack,
            .taskNotFound,
            .noActiveTask,
            .alreadyCompleted
        ]

        for error in errors {
            // Just verify it doesn't crash when accessed
            _ = error.localizedStringResource
        }
    }
}

// MARK: - Deep Link Destination Tests

@Suite("DeepLinkDestination")
@MainActor
struct DeepLinkDestinationTests {
    @Test("Parses stack deep link URL")
    func parseStackURL() throws {
        let url = URL(string: "dequeue://stack/abc123")!
        let destination = DeepLinkDestination(url: url)
        #expect(destination != nil)
        #expect(destination?.parentId == "abc123")
        #expect(destination?.parentType == .stack)
    }

    @Test("Parses task deep link URL")
    func parseTaskURL() throws {
        let url = URL(string: "dequeue://task/xyz789")!
        let destination = DeepLinkDestination(url: url)
        #expect(destination != nil)
        #expect(destination?.parentId == "xyz789")
        #expect(destination?.parentType == .task)
    }

    @Test("Parses arc deep link URL")
    func parseArcURL() throws {
        let url = URL(string: "dequeue://arc/arc456")!
        let destination = DeepLinkDestination(url: url)
        #expect(destination != nil)
        #expect(destination?.parentId == "arc456")
        #expect(destination?.parentType == .arc)
    }

    @Test("Returns nil for non-dequeue scheme")
    func rejectsNonDequeueScheme() throws {
        let url = URL(string: "https://example.com/stack/abc")!
        let destination = DeepLinkDestination(url: url)
        #expect(destination == nil)
    }

    @Test("Returns nil for generic routes without ID")
    func returnsNilForGenericRoutes() throws {
        let homeURL = URL(string: "dequeue://home")!
        let statsURL = URL(string: "dequeue://stats")!
        #expect(DeepLinkDestination(url: homeURL) == nil)
        #expect(DeepLinkDestination(url: statsURL) == nil)
    }

    @Test("Creates from notification userInfo")
    func createFromNotificationUserInfo() throws {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "test-id",
            NotificationConstants.UserInfoKey.parentType: "stack"
        ]
        let destination = DeepLinkDestination(userInfo: userInfo)
        #expect(destination != nil)
        #expect(destination?.parentId == "test-id")
        #expect(destination?.parentType == .stack)
    }

    @Test("Returns nil for invalid notification userInfo")
    func returnsNilForInvalidUserInfo() throws {
        let emptyInfo: [AnyHashable: Any] = [:]
        #expect(DeepLinkDestination(userInfo: emptyInfo) == nil)

        let missingType: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "test-id"
        ]
        #expect(DeepLinkDestination(userInfo: missingType) == nil)
    }

    @Test("DeepLinkDestination equality")
    func destinationEquality() throws {
        let url1 = URL(string: "dequeue://stack/abc")!
        let url2 = URL(string: "dequeue://stack/abc")!
        let url3 = URL(string: "dequeue://stack/xyz")!

        let dest1 = DeepLinkDestination(url: url1)
        let dest2 = DeepLinkDestination(url: url2)
        let dest3 = DeepLinkDestination(url: url3)

        #expect(dest1 == dest2)
        #expect(dest1 != dest3)
    }
}

// MARK: - AppGroupConfig Context Storage Tests

@Suite("AppGroupConfig User Context")
@MainActor
struct AppGroupConfigContextTests {
    @Test("Keys are distinct and non-overlapping")
    func keysAreDistinct() {
        #expect(AppGroupConfig.userIdKey != AppGroupConfig.deviceIdKey)
        #expect(AppGroupConfig.userIdKey != AppGroupConfig.activeStackKey)
        #expect(AppGroupConfig.userIdKey != AppGroupConfig.upNextKey)
        #expect(AppGroupConfig.userIdKey != AppGroupConfig.statsKey)
        #expect(AppGroupConfig.deviceIdKey != AppGroupConfig.activeStackKey)
    }

    @Test("Stores and retrieves user context via test defaults")
    func storeAndRetrieve() throws {
        let testDefaults = UserDefaults(suiteName: "test.appgroup.context.\(UUID().uuidString)")!
        testDefaults.set("user-123", forKey: AppGroupConfig.userIdKey)
        testDefaults.set("device-456", forKey: AppGroupConfig.deviceIdKey)

        let userId = testDefaults.string(forKey: AppGroupConfig.userIdKey)
        let deviceId = testDefaults.string(forKey: AppGroupConfig.deviceIdKey)

        #expect(userId == "user-123")
        #expect(deviceId == "device-456")
    }
}

// MARK: - IntentEventHelper Tests

@Suite("IntentEventHelper")
@MainActor
struct IntentEventHelperTests {
    @Test("userContext returns value or nil gracefully")
    func userContextDoesNotCrash() {
        // This tests that the method doesn't crash regardless of app group state
        let result = IntentEventHelper.userContext()
        _ = result  // May be nil if no user is stored
    }
}
