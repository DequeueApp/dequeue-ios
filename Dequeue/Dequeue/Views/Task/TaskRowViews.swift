//
//  TaskRowViews.swift
//  Dequeue
//
//  Row views for displaying tasks in lists
//

import SwiftUI

// MARK: - Task Row View

struct TaskRowView: View {
    let task: QueueTask
    let isActive: Bool
    let onToggleComplete: () -> Void
    let onSetActive: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggleComplete()
            } label: {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(isActive ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(task.title)
                        .fontWeight(isActive ? .semibold : .regular)

                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                if let description = task.taskDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !isActive {
                Button {
                    onSetActive()
                } label: {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isActive ? Color.blue.opacity(0.08) : nil)
    }
}

// MARK: - Read-Only Task Row View

struct ReadOnlyTaskRowView: View {
    let task: QueueTask
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle")
                .font(.title2)
                .foregroundStyle(isActive ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(task.title)
                        .fontWeight(isActive ? .semibold : .regular)

                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                if let description = task.taskDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(isActive ? Color.blue.opacity(0.08) : nil)
    }
}

// MARK: - Completed Task Row View

struct CompletedTaskRowView: View {
    let task: QueueTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough()
                    .foregroundStyle(.secondary)

                Text(task.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
