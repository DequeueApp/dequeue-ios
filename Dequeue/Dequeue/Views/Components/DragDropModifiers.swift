//
//  DragDropModifiers.swift
//  Dequeue
//
//  Cross-app drag and drop support for tasks and stacks
//  Allows dragging tasks between stacks and reordering via drag
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Dequeue UTTypes

extension UTType {
    /// Custom UTType for Dequeue task references (task ID)
    nonisolated static let dequeueTask = UTType(exportedAs: "app.dequeue.task")
    /// Custom UTType for Dequeue stack references (stack ID)
    nonisolated static let dequeueStack = UTType(exportedAs: "app.dequeue.stack")
}

// MARK: - Task Transferable

/// Lightweight transferable representation of a task (just the ID + title)
struct TaskTransferItem: Codable, Transferable {
    let taskId: String
    let title: String
    let stackId: String?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .dequeueTask)
        // Also provide plain text for cross-app dragging
        ProxyRepresentation(exporting: \.title)
    }
}

// MARK: - Stack Transferable

/// Lightweight transferable representation of a stack (just the ID + title)
struct StackTransferItem: Codable, Transferable {
    let stackId: String
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .dequeueStack)
        ProxyRepresentation(exporting: \.title)
    }
}

// MARK: - Drag & Drop Task Row Modifier

/// Makes a task row draggable and handles drop for reordering
struct TaskDragDropModifier: ViewModifier {
    let task: QueueTask
    let onMoveTask: (QueueTask, Int) -> Void

    func body(content: Content) -> some View {
        content
            .draggable(TaskTransferItem(
                taskId: task.id,
                title: task.title,
                stackId: task.stack?.id
            ))
    }
}

// MARK: - Stack Drag Drop Modifier

/// Makes a stack row draggable
struct StackDragDropModifier: ViewModifier {
    let stack: Stack

    func body(content: Content) -> some View {
        content
            .draggable(StackTransferItem(
                stackId: stack.id,
                title: stack.title
            ))
    }
}

// MARK: - Drop Delegate for Task List Reordering

/// Handles reordering tasks within a list via drag and drop
class TaskListDropDelegate: DropDelegate {
    let targetTask: QueueTask
    let tasks: [QueueTask]
    let onReorder: ([QueueTask]) -> Void

    init(targetTask: QueueTask, tasks: [QueueTask], onReorder: @escaping ([QueueTask]) -> Void) {
        self.targetTask = targetTask
        self.tasks = tasks
        self.onReorder = onReorder
    }

    func performDrop(info: DropInfo) -> Bool {
        true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        // TaskListDropDelegate is a basic implementation — actual reordering
        // is handled by TaskReorderDropDelegate below
    }
}

// MARK: - View Extensions

extension View {
    /// Makes a task row draggable
    func taskDraggable(_ task: QueueTask) -> some View {
        modifier(TaskDragDropModifier(
            task: task,
            onMoveTask: { _, _ in }
        ))
    }

    /// Makes a stack row draggable
    func stackDraggable(_ stack: Stack) -> some View {
        modifier(StackDragDropModifier(stack: stack))
    }

    /// Adds a drop target for receiving tasks (e.g., on a stack to move tasks between stacks)
    func taskDropTarget(
        onTaskDropped: @escaping (String) -> Void
    ) -> some View {
        self.dropDestination(for: TaskTransferItem.self) { items, _ in
            guard let item = items.first else { return false }
            onTaskDropped(item.taskId)
            return true
        }
    }
}

// MARK: - Reorderable Task List

/// A list of tasks that supports drag-to-reorder
struct ReorderableTaskList<Content: View>: View {
    let tasks: [QueueTask]
    let onReorder: ([QueueTask]) -> Void
    @ViewBuilder let rowContent: (QueueTask) -> Content

    @State private var draggedTask: QueueTask?

    var body: some View {
        ForEach(tasks) { task in
            rowContent(task)
                .taskDraggable(task)
                .onDrag {
                    draggedTask = task
                    return NSItemProvider(
                        object: (task.title as NSString)
                    )
                }
                .onDrop(of: [.dequeueTask, .text], delegate: TaskReorderDropDelegate(
                    targetTask: task,
                    tasks: tasks,
                    draggedTask: $draggedTask,
                    onReorder: onReorder
                ))
        }
    }
}

// MARK: - Task Reorder Drop Delegate

/// Drop delegate that handles the actual reordering logic
struct TaskReorderDropDelegate: DropDelegate {
    let targetTask: QueueTask
    let tasks: [QueueTask]
    @Binding var draggedTask: QueueTask?
    let onReorder: ([QueueTask]) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedTask = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedTask,
              dragged.id != targetTask.id,
              let sourceIndex = tasks.firstIndex(where: { $0.id == dragged.id }),
              let targetIndex = tasks.firstIndex(where: { $0.id == targetTask.id }) else {
            return
        }

        var reordered = tasks
        let moved = reordered.remove(at: sourceIndex)
        reordered.insert(moved, at: targetIndex)
        onReorder(reordered)
    }
}

// MARK: - Stack Drop Target (for moving tasks between stacks)

/// Drop target for a stack that accepts tasks from other stacks
struct StackDropTargetModifier: ViewModifier {
    let stack: Stack
    let onTaskReceived: (String, Stack) -> Void

    func body(content: Content) -> some View {
        content
            .dropDestination(for: TaskTransferItem.self) { items, _ in
                guard let item = items.first else { return false }
                // Only accept tasks from different stacks
                if item.stackId != stack.id {
                    onTaskReceived(item.taskId, stack)
                    return true
                }
                return false
            } isTargeted: { _ in
                // Could add visual feedback here
            }
    }
}

extension View {
    /// Makes a stack a drop target for tasks from other stacks
    func stackDropTarget(
        _ stack: Stack,
        onTaskReceived: @escaping (String, Stack) -> Void
    ) -> some View {
        modifier(StackDropTargetModifier(stack: stack, onTaskReceived: onTaskReceived))
    }
}
