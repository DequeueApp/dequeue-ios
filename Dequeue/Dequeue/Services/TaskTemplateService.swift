//
//  TaskTemplateService.swift
//  Dequeue
//
//  Save and reuse task templates for common recurring task patterns.
//  Templates store title, description, priority, tags, and relative dates.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.dequeue", category: "TaskTemplates")

// MARK: - Task Template

/// A reusable task template that can be applied to quickly create tasks
/// with predefined fields.
struct TaskTemplate: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var icon: String
    var title: String
    var taskDescription: String?
    var priority: Int?
    var tags: [String]

    /// Relative due date offset in seconds from creation time.
    /// e.g., 86400 = 1 day from now, 604800 = 1 week from now
    var dueDateOffset: TimeInterval?

    /// Relative start date offset in seconds from creation time.
    var startDateOffset: TimeInterval?

    var createdAt: Date
    var updatedAt: Date

    /// Whether this is a built-in template (cannot be deleted)
    var isBuiltIn: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "doc.text",
        title: String,
        taskDescription: String? = nil,
        priority: Int? = nil,
        tags: [String] = [],
        dueDateOffset: TimeInterval? = nil,
        startDateOffset: TimeInterval? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.title = title
        self.taskDescription = taskDescription
        self.priority = priority
        self.tags = tags
        self.dueDateOffset = dueDateOffset
        self.startDateOffset = startDateOffset
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Template Application Result

/// The result of applying a template, ready to create a task.
struct TemplateApplicationResult: Equatable, Sendable {
    let title: String
    let taskDescription: String?
    let priority: Int?
    let tags: [String]
    let dueTime: Date?
    let startTime: Date?
}

// MARK: - Task Template Service

/// Manages task templates: CRUD operations, built-in templates, and persistence.
@MainActor
final class TaskTemplateService: ObservableObject {

    @Published private(set) var templates: [TaskTemplate] = []

    private let userDefaults: UserDefaults
    private let storageKey = "taskTemplates"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadTemplates()
    }

    // MARK: - Public API

    /// Apply a template to generate task fields with resolved dates.
    func apply(_ template: TaskTemplate, at referenceDate: Date = Date()) -> TemplateApplicationResult {
        let dueTime = template.dueDateOffset.map { referenceDate.addingTimeInterval($0) }
        let startTime = template.startDateOffset.map { referenceDate.addingTimeInterval($0) }

        return TemplateApplicationResult(
            title: template.title,
            taskDescription: template.taskDescription,
            priority: template.priority,
            tags: template.tags,
            dueTime: dueTime,
            startTime: startTime
        )
    }

    /// Add a new custom template.
    func add(_ template: TaskTemplate) {
        templates.append(template)
        saveTemplates()
        logger.info("Template added: \(template.name)")
    }

    /// Update an existing template.
    func update(_ template: TaskTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else {
            logger.warning("Template not found for update: \(template.id)")
            return
        }
        var updated = template
        updated.updatedAt = Date()
        templates[index] = updated
        saveTemplates()
        logger.info("Template updated: \(template.name)")
    }

    /// Delete a template (built-in templates cannot be deleted).
    func delete(_ template: TaskTemplate) {
        guard !template.isBuiltIn else {
            logger.warning("Cannot delete built-in template: \(template.name)")
            return
        }
        templates.removeAll { $0.id == template.id }
        saveTemplates()
        logger.info("Template deleted: \(template.name)")
    }

    /// Delete template at index.
    func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { templates[$0] }.filter { !$0.isBuiltIn }
        for template in toDelete {
            templates.removeAll { $0.id == template.id }
        }
        saveTemplates()
    }

    /// Move templates for reordering.
    func move(from source: IndexSet, to destination: Int) {
        // Manual reorder without SwiftUI's Array.move extension
        let items = source.map { templates[$0] }
        var newTemplates = templates
        // Remove from old positions (reverse to keep indices valid)
        for index in source.sorted().reversed() {
            newTemplates.remove(at: index)
        }
        // Calculate adjusted destination
        let adjustedDest = min(destination, newTemplates.count)
        for (offset, item) in items.enumerated() {
            newTemplates.insert(item, at: adjustedDest + offset)
        }
        templates = newTemplates
        saveTemplates()
    }

    /// Reset to built-in templates only.
    func resetToDefaults() {
        templates = Self.builtInTemplates
        saveTemplates()
    }

    /// Create a template from an existing task's fields.
    func createFromTask(
        name: String,
        title: String,
        description: String?,
        priority: Int?,
        tags: [String],
        dueDateOffset: TimeInterval? = nil,
        startDateOffset: TimeInterval? = nil,
        icon: String = "doc.text"
    ) -> TaskTemplate {
        let template = TaskTemplate(
            name: name,
            icon: icon,
            title: title,
            taskDescription: description,
            priority: priority,
            tags: tags,
            dueDateOffset: dueDateOffset,
            startDateOffset: startDateOffset
        )
        add(template)
        return template
    }

    // MARK: - Built-in Templates

    static let builtInTemplates: [TaskTemplate] = [
        TaskTemplate(
            id: "builtin-daily-standup",
            name: "Daily Standup",
            icon: "person.3",
            title: "Daily standup",
            taskDescription: "What I did yesterday, what I'm doing today, blockers",
            priority: 1,
            tags: ["meetings"],
            dueDateOffset: 3600, // 1 hour from now
            isBuiltIn: true
        ),
        TaskTemplate(
            id: "builtin-code-review",
            name: "Code Review",
            icon: "eye",
            title: "Review PR: ",
            taskDescription: "Check: correctness, tests, style, performance",
            priority: 2,
            tags: ["code-review"],
            dueDateOffset: 86400, // 1 day
            isBuiltIn: true
        ),
        TaskTemplate(
            id: "builtin-bug-report",
            name: "Bug Report",
            icon: "ladybug",
            title: "Fix: ",
            taskDescription: """
            Steps to reproduce:
            1.
            2.
            3.

            Expected behavior:

            Actual behavior:
            """,
            priority: 2,
            tags: ["bug"],
            isBuiltIn: true
        ),
        TaskTemplate(
            id: "builtin-weekly-review",
            name: "Weekly Review",
            icon: "calendar.badge.checkmark",
            title: "Weekly review",
            taskDescription: """
            - Review completed tasks
            - Review upcoming deadlines
            - Clear inbox
            - Plan next week's priorities
            """,
            priority: 1,
            tags: ["review"],
            dueDateOffset: 604800, // 1 week
            isBuiltIn: true
        ),
        TaskTemplate(
            id: "builtin-follow-up",
            name: "Follow Up",
            icon: "arrow.uturn.right",
            title: "Follow up: ",
            priority: 1,
            tags: ["follow-up"],
            dueDateOffset: 259200, // 3 days
            isBuiltIn: true
        ),
        TaskTemplate(
            id: "builtin-quick-task",
            name: "Quick Task",
            icon: "bolt",
            title: "",
            priority: nil,
            tags: [],
            dueDateOffset: nil,
            isBuiltIn: true
        )
    ]

    // MARK: - Persistence

    private func loadTemplates() {
        if let data = userDefaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([TaskTemplate].self, from: data) {
            templates = saved
        } else {
            // First launch — use built-in templates
            templates = Self.builtInTemplates
            saveTemplates()
        }
    }

    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(templates) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}
