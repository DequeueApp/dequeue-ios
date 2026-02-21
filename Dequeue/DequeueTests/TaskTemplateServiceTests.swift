//
//  TaskTemplateServiceTests.swift
//  DequeueTests
//
//  Tests for task template service — CRUD, persistence, and built-in templates.
//

import XCTest
@testable import Dequeue

@MainActor
final class TaskTemplateServiceTests: XCTestCase {

    private var service: TaskTemplateService!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TaskTemplateTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        service = TaskTemplateService(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        service = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialTemplatesAreBuiltIn() {
        // Should start with built-in templates
        XCTAssertFalse(service.templates.isEmpty)
        XCTAssertTrue(service.templates.allSatisfy(\.isBuiltIn))
    }

    func testBuiltInTemplatesCount() {
        XCTAssertEqual(TaskTemplateService.builtInTemplates.count, 6)
    }

    func testBuiltInTemplateNames() {
        let names = TaskTemplateService.builtInTemplates.map(\.name)
        XCTAssertTrue(names.contains("Daily Standup"))
        XCTAssertTrue(names.contains("Code Review"))
        XCTAssertTrue(names.contains("Bug Report"))
        XCTAssertTrue(names.contains("Weekly Review"))
        XCTAssertTrue(names.contains("Follow Up"))
        XCTAssertTrue(names.contains("Quick Task"))
    }

    // MARK: - Add

    func testAddTemplate() {
        let template = TaskTemplate(
            name: "Custom Template",
            title: "Custom task",
            priority: 2,
            tags: ["custom"]
        )

        let countBefore = service.templates.count
        service.add(template)

        XCTAssertEqual(service.templates.count, countBefore + 1)
        XCTAssertEqual(service.templates.last?.name, "Custom Template")
    }

    func testAddTemplatePersists() {
        let template = TaskTemplate(
            name: "Persistent Template",
            title: "Persist this"
        )
        service.add(template)

        // Create new service with same UserDefaults
        let service2 = TaskTemplateService(userDefaults: userDefaults)
        let found = service2.templates.first { $0.name == "Persistent Template" }
        XCTAssertNotNil(found)
    }

    // MARK: - Update

    func testUpdateTemplate() {
        let template = TaskTemplate(name: "Original", title: "Original title")
        service.add(template)

        var updated = template
        updated.name = "Updated"
        updated.title = "Updated title"
        service.update(updated)

        let found = service.templates.first { $0.id == template.id }
        XCTAssertEqual(found?.name, "Updated")
        XCTAssertEqual(found?.title, "Updated title")
    }

    func testUpdateNonExistentTemplateDoesNothing() {
        let countBefore = service.templates.count
        let template = TaskTemplate(id: "nonexistent", name: "Ghost", title: "Ghost")
        service.update(template)

        XCTAssertEqual(service.templates.count, countBefore)
    }

    // MARK: - Delete

    func testDeleteCustomTemplate() {
        let template = TaskTemplate(name: "Deletable", title: "Delete me")
        service.add(template)

        let countAfterAdd = service.templates.count
        service.delete(template)

        XCTAssertEqual(service.templates.count, countAfterAdd - 1)
        XCTAssertNil(service.templates.first { $0.id == template.id })
    }

    func testCannotDeleteBuiltInTemplate() {
        let builtIn = service.templates.first { $0.isBuiltIn }!
        let countBefore = service.templates.count

        service.delete(builtIn)

        // Built-in template should still be there
        XCTAssertEqual(service.templates.count, countBefore)
    }

    // MARK: - Apply

    func testApplyTemplateWithDueDate() {
        let now = Date()
        let template = TaskTemplate(
            name: "Test",
            title: "Test task",
            priority: 2,
            tags: ["work"],
            dueDateOffset: 86400 // 1 day
        )

        let result = service.apply(template, at: now)

        XCTAssertEqual(result.title, "Test task")
        XCTAssertEqual(result.priority, 2)
        XCTAssertEqual(result.tags, ["work"])
        XCTAssertNotNil(result.dueTime)

        // Should be approximately 1 day in the future
        let interval = result.dueTime!.timeIntervalSince(now)
        XCTAssertEqual(interval, 86400, accuracy: 1)
    }

    func testApplyTemplateWithoutDueDate() {
        let template = TaskTemplate(
            name: "No Date",
            title: "No date task",
            dueDateOffset: nil
        )

        let result = service.apply(template)

        XCTAssertEqual(result.title, "No date task")
        XCTAssertNil(result.dueTime)
        XCTAssertNil(result.startTime)
    }

    func testApplyTemplateWithStartDate() {
        let now = Date()
        let template = TaskTemplate(
            name: "Start Date",
            title: "With start",
            startDateOffset: 172800 // 2 days
        )

        let result = service.apply(template, at: now)

        XCTAssertNotNil(result.startTime)
        let interval = result.startTime!.timeIntervalSince(now)
        XCTAssertEqual(interval, 172800, accuracy: 1)
    }

    func testApplyTemplateWithBothDates() {
        let now = Date()
        let template = TaskTemplate(
            name: "Both Dates",
            title: "Full date task",
            dueDateOffset: 604800, // 1 week
            startDateOffset: 86400 // 1 day
        )

        let result = service.apply(template, at: now)

        XCTAssertNotNil(result.dueTime)
        XCTAssertNotNil(result.startTime)
        XCTAssertTrue(result.startTime! < result.dueTime!)
    }

    // MARK: - Create From Task

    func testCreateFromTask() {
        let template = service.createFromTask(
            name: "From Existing",
            title: "Existing task title",
            description: "Some description",
            priority: 3,
            tags: ["urgent", "bug"],
            icon: "ladybug"
        )

        XCTAssertEqual(template.name, "From Existing")
        XCTAssertEqual(template.title, "Existing task title")
        XCTAssertEqual(template.taskDescription, "Some description")
        XCTAssertEqual(template.priority, 3)
        XCTAssertEqual(template.tags, ["urgent", "bug"])
        XCTAssertEqual(template.icon, "ladybug")
        XCTAssertFalse(template.isBuiltIn)

        // Should be added to templates
        XCTAssertTrue(service.templates.contains { $0.id == template.id })
    }

    // MARK: - Reorder

    func testMoveTemplates() {
        // Add some custom templates
        let a = TaskTemplate(name: "A", title: "A")
        let b = TaskTemplate(name: "B", title: "B")
        service.add(a)
        service.add(b)

        let lastIndex = service.templates.count - 1
        // Move last to second-to-last
        service.move(from: IndexSet(integer: lastIndex), to: lastIndex - 1)

        // B should now be before A
        let bIndex = service.templates.firstIndex { $0.id == b.id }!
        let aIndex = service.templates.firstIndex { $0.id == a.id }!
        XCTAssertTrue(bIndex < aIndex)
    }

    // MARK: - Reset

    func testResetToDefaults() {
        // Add custom templates
        service.add(TaskTemplate(name: "Custom 1", title: "C1"))
        service.add(TaskTemplate(name: "Custom 2", title: "C2"))

        service.resetToDefaults()

        XCTAssertEqual(service.templates.count, TaskTemplateService.builtInTemplates.count)
        XCTAssertTrue(service.templates.allSatisfy(\.isBuiltIn))
    }

    // MARK: - Task Template Model

    func testTaskTemplateEquality() {
        let a = TaskTemplate(id: "same", name: "A", title: "A")
        let b = TaskTemplate(id: "same", name: "A", title: "A")
        XCTAssertEqual(a, b)
    }

    func testTaskTemplateIdentifiable() {
        let template = TaskTemplate(id: "test-id", name: "Test", title: "Test")
        XCTAssertEqual(template.id, "test-id")
    }

    func testTaskTemplateCodable() throws {
        let template = TaskTemplate(
            name: "Codable Test",
            title: "Test",
            priority: 2,
            tags: ["a", "b"],
            dueDateOffset: 3600
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(TaskTemplate.self, from: data)

        XCTAssertEqual(decoded.name, template.name)
        XCTAssertEqual(decoded.title, template.title)
        XCTAssertEqual(decoded.priority, template.priority)
        XCTAssertEqual(decoded.tags, template.tags)
        XCTAssertEqual(decoded.dueDateOffset, template.dueDateOffset)
    }

    // MARK: - Template Application Result

    func testTemplateApplicationResultEquality() {
        let a = TemplateApplicationResult(
            title: "Test", taskDescription: nil, priority: 1,
            tags: ["a"], dueTime: nil, startTime: nil
        )
        let b = TemplateApplicationResult(
            title: "Test", taskDescription: nil, priority: 1,
            tags: ["a"], dueTime: nil, startTime: nil
        )
        XCTAssertEqual(a, b)
    }
}
