//
//  SpotlightIndexer.swift
//  Dequeue
//
//  CoreSpotlight indexing for system-wide search of stacks and tasks
//

import CoreSpotlight
import SwiftData
import os.log

/// Indexes Dequeue stacks and tasks for system-wide Spotlight search.
///
/// Integration points:
/// - Called after sync completes (SyncManager)
/// - Called when app enters background (to index latest changes)
/// - Called on initial launch to build the index
///
/// Uses CSSearchableIndex for persistent, on-device search indexing.
/// Items indexed here appear in Spotlight search results and can deep link
/// back into the app via `dequeue://` URLs.
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    private static let domainStack = "com.ardonos.dequeue.stack"
    private static let domainTask = "com.ardonos.dequeue.task"

    private let logger = Logger(subsystem: "com.ardonos.Dequeue", category: "SpotlightIndexer")

    private init() {}

    // MARK: - Full Re-index

    /// Indexes all non-deleted stacks and their tasks.
    /// Call on first launch and after major sync operations.
    func indexAll(context: ModelContext) {
        let items = buildSearchableItems(context: context)
        guard !items.isEmpty else {
            logger.info("[Spotlight] No items to index")
            return
        }

        CSSearchableIndex.default().indexSearchableItems(items) { [self] error in
            if let error {
                logger.error("[Spotlight] Indexing failed: \(error.localizedDescription)")
            } else {
                logger.info("[Spotlight] Indexed \(items.count) items")
            }
        }
    }

    // MARK: - Incremental Updates

    /// Indexes a single stack and its tasks (call after stack changes)
    func indexStack(_ stack: Stack) {
        var items: [CSSearchableItem] = []
        items.append(makeStackItem(stack))

        for task in stack.tasks where !task.isDeleted {
            items.append(makeTaskItem(task, stackTitle: stack.title))
        }

        CSSearchableIndex.default().indexSearchableItems(items) { [self] error in
            if let error {
                logger.error("[Spotlight] Failed to index stack '\(stack.title)': \(error.localizedDescription)")
            }
        }
    }

    /// Indexes a single task (call after task changes)
    func indexTask(_ task: QueueTask) {
        let item = makeTaskItem(task, stackTitle: task.stack?.title)
        CSSearchableIndex.default().indexSearchableItems([item]) { [self] error in
            if let error {
                logger.error("[Spotlight] Failed to index task '\(task.title)': \(error.localizedDescription)")
            }
        }
    }

    /// Removes a stack and its tasks from the index
    func removeStack(id: String) {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: ["\(Self.domainStack).\(id)"]
        ) { [self] error in
            if let error {
                logger.error("[Spotlight] Failed to remove stack '\(id)': \(error.localizedDescription)")
            }
        }
        // Also remove associated task identifiers
        // Tasks are indexed with their own domain, so we remove by ID pattern
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [stackIdentifier(id)]
        ) { _ in }
    }

    /// Removes a task from the index
    func removeTask(id: String) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [taskIdentifier(id)]
        ) { [self] error in
            if let error {
                logger.error("[Spotlight] Failed to remove task '\(id)': \(error.localizedDescription)")
            }
        }
    }

    /// Removes all Dequeue items from the Spotlight index
    func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [Self.domainStack, Self.domainTask]
        ) { [self] error in
            if let error {
                logger.error("[Spotlight] Failed to remove all items: \(error.localizedDescription)")
            } else {
                logger.info("[Spotlight] Cleared all indexed items")
            }
        }
    }

    // MARK: - Build Searchable Items

    private func buildSearchableItems(context: ModelContext) -> [CSSearchableItem] {
        var items: [CSSearchableItem] = []

        // Fetch all active stacks
        let stackPredicate = #Predicate<Stack> { !$0.isDeleted && !$0.isDraft }
        var stackDescriptor = FetchDescriptor<Stack>(predicate: stackPredicate)
        stackDescriptor.sortBy = [SortDescriptor(\.sortOrder)]

        guard let stacks = try? context.fetch(stackDescriptor) else {
            logger.error("[Spotlight] Failed to fetch stacks for indexing")
            return items
        }

        for stack in stacks {
            items.append(makeStackItem(stack))

            for task in stack.tasks where !task.isDeleted {
                items.append(makeTaskItem(task, stackTitle: stack.title))
            }
        }

        return items
    }

    // MARK: - Item Builders

    private func makeStackItem(_ stack: Stack) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = stack.title
        attributes.contentDescription = buildStackDescription(stack)
        attributes.identifier = stack.id

        // Metadata for richer results
        if let dueDate = stack.dueTime {
            attributes.dueDate = dueDate
        }
        if let startDate = stack.startTime {
            attributes.startDate = startDate
        }

        // Keywords for broader matching
        var keywords = [stack.title, "stack", "dequeue"]
        keywords.append(contentsOf: stack.tags)
        keywords.append(contentsOf: stack.tagNames)
        if stack.isActive { keywords.append("active") }
        attributes.keywords = keywords

        // Thumbnail hint — use app icon tint
        attributes.domainIdentifier = Self.domainStack

        return CSSearchableItem(
            uniqueIdentifier: stackIdentifier(stack.id),
            domainIdentifier: Self.domainStack,
            attributeSet: attributes
        )
    }

    private func makeTaskItem(_ task: QueueTask, stackTitle: String?) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = task.title
        attributes.contentDescription = buildTaskDescription(task, stackTitle: stackTitle)
        attributes.identifier = task.id

        if let dueDate = task.dueTime {
            attributes.dueDate = dueDate
        }

        var keywords = [task.title, "task", "dequeue"]
        keywords.append(contentsOf: task.tags)
        if let stackTitle { keywords.append(stackTitle) }
        if task.status == .pending { keywords.append("pending") }
        if task.status == .completed { keywords.append("completed") }
        if task.priority != nil { keywords.append("priority") }
        attributes.keywords = keywords

        attributes.domainIdentifier = Self.domainTask

        return CSSearchableItem(
            uniqueIdentifier: taskIdentifier(task.id),
            domainIdentifier: Self.domainTask,
            attributeSet: attributes
        )
    }

    // MARK: - Description Builders

    private func buildStackDescription(_ stack: Stack) -> String {
        var parts: [String] = []

        let allTasks = stack.tasks.filter { !$0.isDeleted }
        let pending = allTasks.filter { $0.status == .pending }
        let completed = allTasks.filter { $0.status == .completed }

        if allTasks.isEmpty {
            parts.append("Empty stack")
        } else {
            parts.append("\(completed.count)/\(allTasks.count) tasks completed")
        }

        if stack.isActive {
            parts.append("Active")
            if let activeTask = stack.activeTask {
                parts.append("Current: \(activeTask.title)")
            }
        }

        if let dueDate = stack.dueTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            parts.append("Due: \(formatter.string(from: dueDate))")
        }

        if !stack.tagNames.isEmpty {
            parts.append("Tags: \(stack.tagNames.joined(separator: ", "))")
        }

        return parts.joined(separator: " • ")
    }

    private func buildTaskDescription(_ task: QueueTask, stackTitle: String?) -> String {
        var parts: [String] = []

        if let stackTitle {
            parts.append("In: \(stackTitle)")
        }

        parts.append("Status: \(task.status.rawValue.capitalized)")

        if let priority = task.priority {
            let priorityLabel: String
            switch priority {
            case 3: priorityLabel = "Urgent"
            case 2: priorityLabel = "High"
            case 1: priorityLabel = "Medium"
            default: priorityLabel = "Low"
            }
            parts.append("Priority: \(priorityLabel)")
        }

        if let dueDate = task.dueTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            parts.append("Due: \(formatter.string(from: dueDate))")
        }

        if let description = task.taskDescription, !description.isEmpty {
            let truncated = description.prefix(100)
            parts.append(String(truncated))
        }

        return parts.joined(separator: " • ")
    }

    // MARK: - Identifier Helpers

    private func stackIdentifier(_ id: String) -> String {
        "dequeue://stack/\(id)"
    }

    private func taskIdentifier(_ id: String) -> String {
        "dequeue://task/\(id)"
    }

    // MARK: - Handle Spotlight Continuation

    /// Resolves a Spotlight search result identifier to a deep link URL.
    /// Called when user taps a Dequeue result in Spotlight.
    /// This is a pure function — no mutable state access, safe from any context.
    nonisolated static func handleSpotlightActivity(_ userActivity: NSUserActivity) -> URL? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }
        // Identifiers are already dequeue:// URLs
        return URL(string: identifier)
    }
}
