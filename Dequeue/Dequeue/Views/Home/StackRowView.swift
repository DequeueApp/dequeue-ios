//
//  StackRowView.swift
//  Dequeue
//
//  Stack row component for Home view list
//

import SwiftUI

/// Row view displaying a stack with title, active task, reminders, and tags.
struct StackRowView: View {
    let stack: Stack

    /// Non-deleted tags to display
    private var visibleTags: [Tag] {
        stack.tagObjects.filter { !$0.isDeleted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stack.title)
                    .font(.headline)

                Spacer()

                if stack.isActive {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                        .accessibilityLabel("Active stack")
                }
            }

            if let activeTask = stack.activeTask {
                Text(activeTask.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !stack.activeReminders.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                    Text("\(stack.activeReminders.count)")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }

            // Tags row - show up to 3 tags with "+N more" indicator
            if !visibleTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(visibleTags.prefix(3))) { tag in
                        TagChip(tag: tag)
                    }

                    if visibleTags.count > 3 {
                        Text("+\(visibleTags.count - 3) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("Simple Stack") {
    let stack = Stack(title: "Test Stack", stackDescription: nil, status: .active, sortOrder: 0)
    return StackRowView(stack: stack)
        .padding()
}

#Preview("Active Stack") {
    let stack = Stack(title: "Active Stack", stackDescription: nil, status: .active, sortOrder: 0)
    stack.isActive = true
    return StackRowView(stack: stack)
        .padding()
}
