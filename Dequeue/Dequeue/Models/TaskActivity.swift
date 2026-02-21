//
//  TaskActivity.swift
//  Dequeue
//
//  Represents a historical change to a task for the activity log.
//  Activities are derived from sync events.
//

import Foundation

// MARK: - Activity Type

enum TaskActivityType: String, Codable, Sendable {
    case created = "created"
    case statusChanged = "status_changed"
    case titleChanged = "title_changed"
    case descriptionChanged = "description_changed"
    case priorityChanged = "priority_changed"
    case dueDateChanged = "due_date_changed"
    case dueDateRemoved = "due_date_removed"
    case movedToStack = "moved_to_stack"
    case tagAdded = "tag_added"
    case tagRemoved = "tag_removed"
    case reminderAdded = "reminder_added"
    case dependencyAdded = "dependency_added"
    case dependencyRemoved = "dependency_removed"
    case completed = "completed"
    case reopened = "reopened"
    case blocked = "blocked"
    case unblocked = "unblocked"

    var icon: String {
        switch self {
        case .created: return "plus.circle.fill"
        case .statusChanged: return "arrow.triangle.2.circlepath"
        case .titleChanged: return "pencil"
        case .descriptionChanged: return "text.alignleft"
        case .priorityChanged: return "flag.fill"
        case .dueDateChanged: return "calendar.badge.clock"
        case .dueDateRemoved: return "calendar.badge.minus"
        case .movedToStack: return "tray.and.arrow.down"
        case .tagAdded: return "tag.fill"
        case .tagRemoved: return "tag.slash"
        case .reminderAdded: return "bell.fill"
        case .dependencyAdded: return "link"
        case .dependencyRemoved: return "link.badge.plus"
        case .completed: return "checkmark.circle.fill"
        case .reopened: return "arrow.uturn.backward.circle"
        case .blocked: return "hand.raised.fill"
        case .unblocked: return "hand.thumbsup.fill"
        }
    }

    var color: String {
        switch self {
        case .created: return "green"
        case .completed: return "green"
        case .blocked: return "red"
        case .priorityChanged: return "orange"
        case .dueDateChanged, .dueDateRemoved: return "blue"
        case .reopened, .unblocked: return "teal"
        default: return "gray"
        }
    }

    var displayName: String {
        switch self {
        case .created: return "Created"
        case .statusChanged: return "Status changed"
        case .titleChanged: return "Title updated"
        case .descriptionChanged: return "Notes updated"
        case .priorityChanged: return "Priority changed"
        case .dueDateChanged: return "Due date set"
        case .dueDateRemoved: return "Due date removed"
        case .movedToStack: return "Moved to stack"
        case .tagAdded: return "Tag added"
        case .tagRemoved: return "Tag removed"
        case .reminderAdded: return "Reminder set"
        case .dependencyAdded: return "Dependency added"
        case .dependencyRemoved: return "Dependency removed"
        case .completed: return "Completed"
        case .reopened: return "Reopened"
        case .blocked: return "Blocked"
        case .unblocked: return "Unblocked"
        }
    }
}

// MARK: - Task Activity

struct TaskActivity: Identifiable, Codable, Sendable {
    let id: String
    let taskId: String
    let type: TaskActivityType
    let timestamp: Date
    let detail: String?
    let previousValue: String?
    let newValue: String?

    init(
        id: String = UUID().uuidString,
        taskId: String,
        type: TaskActivityType,
        timestamp: Date = Date(),
        detail: String? = nil,
        previousValue: String? = nil,
        newValue: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.type = type
        self.timestamp = timestamp
        self.detail = detail
        self.previousValue = previousValue
        self.newValue = newValue
    }

    /// Human-readable description of the activity
    var summary: String {
        switch type {
        case .created:
            return "Task created"
        case .completed:
            return "Task completed"
        case .reopened:
            return "Task reopened"
        case .blocked:
            if let reason = detail {
                return "Blocked: \(reason)"
            }
            return "Task blocked"
        case .unblocked:
            return "Task unblocked"
        case .statusChanged:
            if let newVal = newValue {
                return "Status → \(newVal)"
            }
            return "Status changed"
        case .titleChanged:
            if let newVal = newValue {
                return "Renamed to \"\(newVal)\""
            }
            return "Title changed"
        case .descriptionChanged:
            return "Notes updated"
        case .priorityChanged:
            if let newVal = newValue {
                return "Priority → \(priorityName(newVal))"
            }
            return "Priority changed"
        case .dueDateChanged:
            if let newVal = newValue, let date = ISO8601DateFormatter().date(from: newVal) {
                return "Due date → \(date.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Due date set"
        case .dueDateRemoved:
            return "Due date removed"
        case .movedToStack:
            if let stackName = detail {
                return "Moved to \"\(stackName)\""
            }
            return "Moved to another stack"
        case .tagAdded:
            if let tag = detail {
                return "Tagged with \"\(tag)\""
            }
            return "Tag added"
        case .tagRemoved:
            if let tag = detail {
                return "Removed tag \"\(tag)\""
            }
            return "Tag removed"
        case .reminderAdded:
            return "Reminder set"
        case .dependencyAdded:
            if let dep = detail {
                return "Blocked by \"\(dep)\""
            }
            return "Dependency added"
        case .dependencyRemoved:
            if let dep = detail {
                return "Unblocked from \"\(dep)\""
            }
            return "Dependency removed"
        }
    }

    private func priorityName(_ value: String) -> String {
        switch value {
        case "3": return "High"
        case "2": return "Medium"
        case "1": return "Low"
        case "0": return "None"
        default: return value
        }
    }
}

// MARK: - Activity Log Service

@MainActor
final class TaskActivityService {
    private let userDefaults: UserDefaults
    private static let storagePrefix = "taskActivity_"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Records a new activity for a task
    func record(
        taskId: String,
        type: TaskActivityType,
        detail: String? = nil,
        previousValue: String? = nil,
        newValue: String? = nil
    ) {
        let activity = TaskActivity(
            taskId: taskId,
            type: type,
            detail: detail,
            previousValue: previousValue,
            newValue: newValue
        )

        var activities = getActivities(for: taskId)
        activities.append(activity)

        // Keep only last 100 activities per task
        if activities.count > 100 {
            activities = Array(activities.suffix(100))
        }

        saveActivities(activities, for: taskId)
    }

    /// Gets all activities for a task, sorted by timestamp (newest first)
    func getActivities(for taskId: String) -> [TaskActivity] {
        let key = Self.storagePrefix + taskId
        guard let data = userDefaults.data(forKey: key),
              let activities = try? JSONDecoder().decode([TaskActivity].self, from: data) else {
            return []
        }
        return activities.sorted { $0.timestamp > $1.timestamp }
    }

    /// Gets activities grouped by date
    func getGroupedActivities(for taskId: String) -> [(date: String, activities: [TaskActivity])] {
        let activities = getActivities(for: taskId)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: activities) { activity in
            formatter.string(from: activity.timestamp)
        }

        return grouped.map { (date: $0.key, activities: $0.value) }
            .sorted { pair1, pair2 in
                guard let first = pair1.activities.first?.timestamp,
                      let second = pair2.activities.first?.timestamp else { return false }
                return first > second
            }
    }

    /// Clears all activities for a task
    func clearActivities(for taskId: String) {
        let key = Self.storagePrefix + taskId
        userDefaults.removeObject(forKey: key)
    }

    // MARK: - Private

    private func saveActivities(_ activities: [TaskActivity], for taskId: String) {
        let key = Self.storagePrefix + taskId
        if let data = try? JSONEncoder().encode(activities) {
            userDefaults.set(data, forKey: key)
        }
    }
}
