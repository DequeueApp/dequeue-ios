//
//  ViewStackIntent.swift
//  Dequeue
//
//  Siri/Shortcuts intents for viewing and managing stacks
//

import AppIntents
import SwiftData
import WidgetKit
import os.log

/// View the active stack and its tasks via Siri
struct ViewCurrentStackIntent: AppIntent {
    static let title: LocalizedStringResource = "View Current Stack"
    // swiftlint:disable:next redundant_type_annotation
    static let description: IntentDescription = IntentDescription(
        "See your active stack and current task in Dequeue",
        categoryName: "Stacks"
    )
    static let openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("View current stack")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<StackEntity> & ProvidesDialog {
        let container = try IntentsModelContainer.shared
        let context = ModelContext(container)

        let predicate = #Predicate<Stack> { $0.isActive && !$0.isDeleted }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        guard let activeStack = try context.fetch(descriptor).first else {
            throw IntentError.noActiveStack
        }

        let allTasks = activeStack.tasks.filter { !$0.isDeleted }
        let pending = allTasks.filter { $0.status == .pending }
        let completed = allTasks.filter { $0.status == .completed }

        var dialog = "\(activeStack.title): \(completed.count) of \(allTasks.count) tasks done"

        if let currentTask = activeStack.activeTask {
            dialog += ". Current task: \(currentTask.title)"

            if let dueDate = currentTask.dueTime {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relative = formatter.localizedString(for: dueDate, relativeTo: Date())
                dialog += " (due \(relative))"
            }
        }

        if pending.count <= 3 && !pending.isEmpty {
            let names = pending.map(\.title).joined(separator: ", ")
            dialog += ". Remaining: \(names)"
        }

        os_log("[AppIntents] Viewed current stack '\(activeStack.title)'")

        return .result(
            value: activeStack.toEntity(),
            dialog: "\(dialog)"
        )
    }
}

/// Open a specific stack in the app
struct OpenStackIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Stack"
    // swiftlint:disable:next redundant_type_annotation
    static let description: IntentDescription = IntentDescription(
        "Open a specific stack in Dequeue",
        categoryName: "Stacks"
    )
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Stack")
    var stack: StackEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$stack)")
    }

    func perform() async throws -> some IntentResult {
        os_log("[AppIntents] Opening stack '\(stack.title)' (id: \(stack.id))")
        return .result()
    }
}

/// Activate a stack (make it the focused stack)
struct ActivateStackIntent: AppIntent {
    static let title: LocalizedStringResource = "Activate Stack"
    // swiftlint:disable:next redundant_type_annotation
    static let description: IntentDescription = IntentDescription(
        "Set a stack as your active/focused stack in Dequeue",
        categoryName: "Stacks"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Stack")
    var stack: StackEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Activate \(\.$stack)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try IntentsModelContainer.shared
        let context = ModelContext(container)

        let stackId = stack.id
        let predicate = #Predicate<Stack> { $0.id == stackId && !$0.isDeleted }
        let descriptor = FetchDescriptor<Stack>(predicate: predicate)
        guard let targetStack = try context.fetch(descriptor).first else {
            throw IntentError.stackNotFound
        }

        // Deactivate currently active stack (only one active at a time)
        let activePredicate = #Predicate<Stack> { $0.isActive && !$0.isDeleted }
        let activeDescriptor = FetchDescriptor<Stack>(predicate: activePredicate)
        let activeStacks = try context.fetch(activeDescriptor)
        for activeStack in activeStacks where activeStack.id != stackId {
            activeStack.isActive = false
            activeStack.updatedAt = Date()
            IntentEventHelper.recordStackDeactivated(activeStack, context: context)
        }

        // Activate the target stack
        targetStack.isActive = true
        targetStack.updatedAt = Date()
        IntentEventHelper.recordStackActivated(targetStack, context: context)

        try context.save()

        WidgetCenter.shared.reloadAllTimelines()

        os_log("[AppIntents] Activated stack '\(targetStack.title)'")

        let taskInfo: String
        if let activeTask = targetStack.activeTask {
            taskInfo = " Current task: \(activeTask.title)"
        } else {
            taskInfo = " No pending tasks."
        }

        return .result(dialog: "Activated \"\(targetStack.title)\".\(taskInfo)")
    }
}
