//
//  CompleteTaskIntent.swift
//  Dequeue
//
//  Siri/Shortcuts intent for completing the current task
//

import AppIntents
import SwiftData
import WidgetKit
import os.log

/// Complete the active task in the current stack via Siri or Shortcuts
struct CompleteCurrentTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Current Task"
    static let description: IntentDescription = IntentDescription(
        "Complete the active task in your current stack",
        categoryName: "Tasks"
    )
    static let openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Complete the current task")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try IntentsModelContainer.shared
        let context = ModelContext(container)

        // Find active stack
        let stackPredicate = #Predicate<Stack> { $0.isActive && !$0.isDeleted }
        let stackDescriptor = FetchDescriptor<Stack>(predicate: stackPredicate)
        guard let activeStack = try context.fetch(stackDescriptor).first else {
            throw IntentError.noActiveStack
        }

        // Find active task
        guard let activeTask = activeStack.activeTask else {
            throw IntentError.noActiveTask
        }

        guard activeTask.status == .pending else {
            throw IntentError.alreadyCompleted
        }

        let taskTitle = activeTask.title
        let stackTitle = activeStack.title

        // Complete the task
        activeTask.status = .completed
        activeTask.updatedAt = Date()

        // Create sync event
        IntentEventHelper.recordTaskCompleted(activeTask, context: context)

        // Check if all tasks are now completed
        let remainingPending = activeStack.tasks.filter { !$0.isDeleted && $0.status == .pending }
        // Exclude the task we just completed (status change may not reflect in the relationship yet)
        let actuallyPending = remainingPending.filter { $0.id != activeTask.id }
        let allDone = actuallyPending.isEmpty

        if allDone {
            activeStack.status = .completed
            activeStack.isActive = false
            activeStack.updatedAt = Date()
            IntentEventHelper.recordStackCompleted(activeStack, context: context)
        }

        try context.save()

        // Refresh widgets
        WidgetCenter.shared.reloadAllTimelines()

        os_log("[AppIntents] Completed task '\(taskTitle)' in stack '\(stackTitle)'")

        if allDone {
            return .result(dialog: "Completed \"\(taskTitle)\" — all tasks in \"\(stackTitle)\" are done! 🎉")
        } else {
            let nextTask = actuallyPending.sorted(by: { $0.sortOrder < $1.sortOrder }).first
            let nextInfo = nextTask.map { "Next up: \($0.title)" } ?? ""
            return .result(dialog: "Completed \"\(taskTitle)\". \(nextInfo)")
        }
    }
}

/// Complete a specific task by name or entity
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description: IntentDescription = IntentDescription(
        "Complete a specific task in Dequeue",
        categoryName: "Tasks"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Task")
    var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try IntentsModelContainer.shared
        let context = ModelContext(container)

        let taskId = task.id
        let predicate = #Predicate<QueueTask> { $0.id == taskId && !$0.isDeleted }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
        guard let foundTask = try context.fetch(descriptor).first else {
            throw IntentError.taskNotFound
        }

        guard foundTask.status == .pending else {
            throw IntentError.alreadyCompleted
        }

        let taskTitle = foundTask.title

        foundTask.status = .completed
        foundTask.updatedAt = Date()

        IntentEventHelper.recordTaskCompleted(foundTask, context: context)

        try context.save()

        WidgetCenter.shared.reloadAllTimelines()

        os_log("[AppIntents] Completed task '\(taskTitle)' via specific intent")

        return .result(dialog: "Completed \"\(taskTitle)\"")
    }
}
