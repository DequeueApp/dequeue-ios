//
//  StackEditorView+Tasks.swift
//  Dequeue
//
//  Tasks section for StackEditorView (edit mode)
//

import SwiftUI

// MARK: - Tasks Section

extension StackEditorView {
    var pendingTasksSection: some View {
        Section {
            if case .edit(let stack) = mode {
                if stack.pendingTasks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "checkmark.circle")
                    } description: {
                        Text("All tasks completed!")
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("No pending tasks. All tasks completed!")
                } else {
                    taskListContent(for: stack)
                }
            }
        } header: {
            HStack {
                Text("Tasks")
                Spacer()
                if case .edit(let stack) = mode {
                    Text("\(stack.pendingTasks.count) pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !isReadOnly {
                    Button {
                        showAddTask = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("addTaskButton")
                }
            }
        }
    }

    @ViewBuilder
    func taskListContent(for stack: Stack) -> some View {
        let taskList = ForEach(stack.pendingTasks) { task in
            NavigationLink {
                TaskDetailView(task: task)
            } label: {
                TaskRowView(
                    task: task,
                    isActive: task.id == stack.activeTask?.id,
                    onToggleComplete: isReadOnly ? nil : { toggleTaskComplete(task) },
                    onSetActive: isReadOnly ? nil : { setTaskActive(task) }
                )
            }
            .buttonStyle(.plain)
        }

        if isReadOnly {
            taskList
        } else {
            taskList.onMove(perform: moveTask)
        }
    }

    var completedTasksSection: some View {
        Section {
            if case .edit(let stack) = mode {
                DisclosureGroup(isExpanded: $showCompletedTasks) {
                    ForEach(stack.completedTasks) { task in
                        NavigationLink {
                            TaskDetailView(task: task)
                        } label: {
                            CompletedTaskRowView(task: task)
                        }
                        .buttonStyle(.plain)
                    }
                } label: {
                    HStack {
                        Text("Completed")
                        Spacer()
                        Text("\(stack.completedTasks.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
