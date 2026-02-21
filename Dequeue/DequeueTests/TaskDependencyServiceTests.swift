//
//  TaskDependencyServiceTests.swift
//  DequeueTests
//
//  Tests for TaskDependencyService
//

import XCTest
import SwiftData
@testable import Dequeue

@MainActor
final class TaskDependencyServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var service: TaskDependencyService!
    var stack: Stack!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Stack.self, QueueTask.self, Reminder.self, Event.self, Tag.self, Arc.self, Device.self,
            configurations: config
        )
        context = container.mainContext
        service = TaskDependencyService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
        context.insert(stack)
        try context.save()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        service = nil
        stack = nil
    }

    // MARK: - Basic Dependency Tests

    func testAddDependency() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")

        let result = try await service.addDependency(task: taskB, blockedBy: taskA)

        XCTAssertTrue(result)
        XCTAssertTrue(taskB.dependencyIds.contains(taskA.id))
        XCTAssertEqual(taskB.dependencyCount, 1)
    }

    func testAddDependencyBlocksTask() async throws {
        let taskA = createTask("Task A", status: .pending)
        let taskB = createTask("Task B", status: .pending)

        _ = try await service.addDependency(task: taskB, blockedBy: taskA)

        XCTAssertEqual(taskB.status, .blocked)
        XCTAssertNotNil(taskB.blockedReason)
        XCTAssertTrue(taskB.blockedReason!.contains("Task A"))
    }

    func testAddDependencyDoesNotBlockIfBlockerCompleted() async throws {
        let taskA = createTask("Task A", status: .completed)
        let taskB = createTask("Task B", status: .pending)

        _ = try await service.addDependency(task: taskB, blockedBy: taskA)

        XCTAssertEqual(taskB.status, .pending) // Stays pending since blocker is done
    }

    func testRemoveDependency() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")
        _ = try await service.addDependency(task: taskB, blockedBy: taskA)

        try await service.removeDependency(task: taskB, blockerTaskId: taskA.id)

        XCTAssertFalse(taskB.dependencyIds.contains(taskA.id))
        XCTAssertEqual(taskB.dependencyCount, 0)
    }

    func testRemoveDependencyUnblocks() async throws {
        let taskA = createTask("Task A", status: .pending)
        let taskB = createTask("Task B", status: .pending)
        _ = try await service.addDependency(task: taskB, blockedBy: taskA)
        XCTAssertEqual(taskB.status, .blocked)

        // Complete taskA first so dependency is satisfied
        taskA.status = .completed
        try context.save()

        try await service.removeDependency(task: taskB, blockerTaskId: taskA.id)
        XCTAssertEqual(taskB.status, .pending)
    }

    // MARK: - Self-Dependency Prevention

    func testPreventSelfDependency() async throws {
        let taskA = createTask("Task A")

        let result = try await service.addDependency(task: taskA, blockedBy: taskA)

        XCTAssertFalse(result)
        XCTAssertEqual(taskA.dependencyCount, 0)
    }

    // MARK: - Circular Dependency Detection

    func testPreventCircularDependency() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")

        _ = try await service.addDependency(task: taskB, blockedBy: taskA) // B depends on A

        // Now try to make A depend on B — should fail
        let result = try await service.addDependency(task: taskA, blockedBy: taskB)
        XCTAssertFalse(result)
    }

    func testPreventTransitiveCircularDependency() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")
        let taskC = createTask("Task C")

        _ = try await service.addDependency(task: taskB, blockedBy: taskA) // B depends on A
        _ = try await service.addDependency(task: taskC, blockedBy: taskB) // C depends on B

        // Now try to make A depend on C — would create A->C->B->A cycle
        let result = try await service.addDependency(task: taskA, blockedBy: taskC)
        XCTAssertFalse(result)
    }

    // MARK: - Multiple Dependencies

    func testMultipleDependencies() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")
        let taskC = createTask("Task C")

        _ = try await service.addDependency(task: taskC, blockedBy: taskA)
        _ = try await service.addDependency(task: taskC, blockedBy: taskB)

        XCTAssertEqual(taskC.dependencyCount, 2)
        XCTAssertTrue(taskC.dependencyIds.contains(taskA.id))
        XCTAssertTrue(taskC.dependencyIds.contains(taskB.id))
    }

    func testDuplicateDependencyIgnored() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")

        _ = try await service.addDependency(task: taskB, blockedBy: taskA)
        _ = try await service.addDependency(task: taskB, blockedBy: taskA) // Duplicate

        XCTAssertEqual(taskB.dependencyCount, 1) // Still just 1
    }

    // MARK: - Dependency Satisfaction Tests

    func testDependenciesSatisfiedWhenAllCompleted() async throws {
        let taskA = createTask("Task A", status: .completed)
        let taskB = createTask("Task B", status: .completed)
        let taskC = createTask("Task C")
        _ = try await service.addDependency(task: taskC, blockedBy: taskA)
        _ = try await service.addDependency(task: taskC, blockedBy: taskB)

        let satisfied = try service.areDependenciesSatisfied(for: taskC)
        XCTAssertTrue(satisfied)
    }

    func testDependenciesNotSatisfiedWhenPending() async throws {
        let taskA = createTask("Task A", status: .pending)
        let taskB = createTask("Task B", status: .completed)
        let taskC = createTask("Task C")
        _ = try await service.addDependency(task: taskC, blockedBy: taskA)
        _ = try await service.addDependency(task: taskC, blockedBy: taskB)

        let satisfied = try service.areDependenciesSatisfied(for: taskC)
        XCTAssertFalse(satisfied)
    }

    func testNoDependenciesAlwaysSatisfied() throws {
        let task = createTask("Solo Task")

        let satisfied = try service.areDependenciesSatisfied(for: task)
        XCTAssertTrue(satisfied)
    }

    // MARK: - Auto-Unblock Tests

    func testAutoUnblockOnCompletion() async throws {
        let taskA = createTask("Task A", status: .pending)
        let taskB = createTask("Task B", status: .pending)
        _ = try await service.addDependency(task: taskB, blockedBy: taskA)
        XCTAssertEqual(taskB.status, .blocked)

        // Complete taskA
        taskA.status = .completed
        try context.save()

        try await service.onTaskCompleted(taskA)

        XCTAssertEqual(taskB.status, .pending)
        XCTAssertNil(taskB.blockedReason)
    }

    func testNoUnblockWhenOtherDependenciesPending() async throws {
        let taskA = createTask("Task A", status: .pending)
        let taskB = createTask("Task B", status: .pending)
        let taskC = createTask("Task C", status: .pending)
        _ = try await service.addDependency(task: taskC, blockedBy: taskA)
        _ = try await service.addDependency(task: taskC, blockedBy: taskB)

        // Complete only taskA — taskB still pending
        taskA.status = .completed
        try context.save()

        try await service.onTaskCompleted(taskA)

        XCTAssertEqual(taskC.status, .blocked) // Still blocked by taskB
    }

    // MARK: - Query Tests

    func testGetDependencyTasks() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")
        let taskC = createTask("Task C")
        _ = try await service.addDependency(task: taskC, blockedBy: taskA)
        _ = try await service.addDependency(task: taskC, blockedBy: taskB)

        let deps = try service.getDependencyTasks(for: taskC)
        XCTAssertEqual(deps.count, 2)
    }

    func testGetDependentTasks() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")
        let taskC = createTask("Task C")
        _ = try await service.addDependency(task: taskB, blockedBy: taskA)
        _ = try await service.addDependency(task: taskC, blockedBy: taskA)

        let dependents = try service.getDependentTasks(for: taskA)
        XCTAssertEqual(dependents.count, 2)
    }

    // MARK: - QueueTask Extension Tests

    func testHasDependencies() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")

        XCTAssertFalse(taskB.hasDependencies)

        _ = try await service.addDependency(task: taskB, blockedBy: taskA)

        XCTAssertTrue(taskB.hasDependencies)
    }

    func testDependencyCount() async throws {
        let taskA = createTask("Task A")
        let taskB = createTask("Task B")
        let taskC = createTask("Task C")

        XCTAssertEqual(taskC.dependencyCount, 0)

        _ = try await service.addDependency(task: taskC, blockedBy: taskA)
        XCTAssertEqual(taskC.dependencyCount, 1)

        _ = try await service.addDependency(task: taskC, blockedBy: taskB)
        XCTAssertEqual(taskC.dependencyCount, 2)
    }

    // MARK: - Helpers

    private func createTask(_ title: String, status: TaskStatus = .pending) -> QueueTask {
        let task = QueueTask(title: title, status: status, sortOrder: 0, stack: stack)
        context.insert(task)
        try? context.save()
        return task
    }
}
