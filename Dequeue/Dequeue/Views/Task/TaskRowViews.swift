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
    var onToggleComplete: (() -> Void)?
    var onSetActive: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon
            taskInfo
            Spacer()
            trailingButton
        }
        .padding(.vertical, 4)
        .listRowBackground(isActive ? Color.blue.opacity(0.08) : nil)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let onToggleComplete {
            Button {
                onToggleComplete()
            } label: {
                circleIcon
            }
            .buttonStyle(.plain)
        } else {
            circleIcon
        }
    }

    private var circleIcon: some View {
        Image(systemName: "circle")
            .font(.title2)
            .foregroundStyle(isActive ? .blue : .secondary)
    }

    private var taskInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(task.title)
                    .fontWeight(isActive ? .semibold : .regular)

                if isActive {
                    ActiveBadge()
                }
                
                if task.aiDelegatedAt != nil {
                    AIDelegationBadge()
                }
            }

            if let description = task.taskDescription, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if !isActive, let onSetActive {
            Button {
                onSetActive()
            } label: {
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Active Badge

private struct ActiveBadge: View {
    var body: some View {
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

// MARK: - AI Delegation Badge

private struct AIDelegationBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.caption2)
            Text("AI")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.purple.opacity(0.15))
        .foregroundStyle(.purple)
        .clipShape(Capsule())
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
