//
//  AddTaskIntent.swift
//  Dequeue
//
//  Siri/Shortcuts intent for adding tasks to stacks
//

import AppIntents
import SwiftData
import os.log

/// Add a new task to a stack via Siri or Shortcuts
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description: IntentDescription = IntentDescription(
        "Add a new task to a stack in Dequeue",
        categoryName: "Tasks"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Task Title")
    var taskTitle: String

    @Parameter(title: "Stack", description: "The stack to add the task to. Uses the active stack if not specified.")
    var stack: StackEntity?

    @Parameter(title: "Priority", default: nil)
    var priority: IntentPriority?

    @Parameter(title: "Due Date", default: nil)
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to \(\.$stack)") {
            \.$priority
            \.$dueDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TaskEntity> & ProvidesDialog {
        let container = try IntentsModelContainer.shared
        let context = ModelContext(container)

        // Resolve target stack
        let targetStack: Stack
        if let stackEntity = stack {
            let stackId = stackEntity.id
            let predicate = #Predicate<Stack> { $0.id == stackId && !$0.isDeleted }
            let descriptor = FetchDescriptor<Stack>(predicate: predicate)
            guard let found = try context.fetch(descriptor).first else {
                throw IntentError.stackNotFound
            }
            targetStack = found
        } else {
            // Use active stack
            let predicate = #Predicate<Stack> { $0.isActive && !$0.isDeleted }
            let descriptor = FetchDescriptor<Stack>(predicate: predicate)
            guard let found = try context.fetch(descriptor).first else {
                throw IntentError.noActiveStack
            }
            targetStack = found
        }

        // Determine sort order (add to end)
        let existingTasks = targetStack.tasks.filter { !$0.isDeleted }
        let maxSortOrder = existingTasks.map(\.sortOrder).max() ?? -1

        // Get stored user context for event creation
        let userCtx = AppGroupConfig.storedUserContext()

        // Create the task
        let newTask = QueueTask(
            title: taskTitle,
            dueTime: dueDate,
            status: .pending,
            priority: priority?.rawIntValue,
            sortOrder: maxSortOrder + 1,
            userId: userCtx?.userId,
            deviceId: userCtx?.deviceId,
            stack: targetStack
        )

        context.insert(newTask)

        // Create sync event
        IntentEventHelper.recordTaskCreated(newTask, context: context)

        try context.save()

        os_log("[AppIntents] Added task '\(taskTitle)' to stack '\(targetStack.title)'")

        let entity = newTask.toEntity()
        return .result(
            value: entity,
            dialog: "Added \"\(taskTitle)\" to \(targetStack.title)"
        )
    }
}

// MARK: - Priority Enum for Intents

enum IntentPriority: Int, AppEnum {
    case low = 0
    case medium = 1
    case high = 2
    case urgent = 3

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Priority"

    static let caseDisplayRepresentations: [IntentPriority: DisplayRepresentation] = [
        .low: "Low",
        .medium: "Medium",
        .high: "High",
        .urgent: "Urgent"
    ]

    var rawIntValue: Int {
        rawValue
    }
}

// MARK: - Intent Errors

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case stackNotFound
    case noActiveStack
    case taskNotFound
    case noActiveTask
    case alreadyCompleted

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .stackNotFound:
            return "The specified stack could not be found."
        case .noActiveStack:
            return "No active stack. Please activate a stack in Dequeue first."
        case .taskNotFound:
            return "The specified task could not be found."
        case .noActiveTask:
            return "No active task in the current stack."
        case .alreadyCompleted:
            return "This task is already completed."
        }
    }
}
