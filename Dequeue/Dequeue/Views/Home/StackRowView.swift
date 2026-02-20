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

    @Environment(\.sizeCategory) private var sizeCategory

    /// Non-deleted tags to display
    private var visibleTags: [Tag] {
        stack.tagObjects.filter { !$0.isDeleted }
    }

    /// Is this an accessibility size category?
    private var isAccessibilitySize: Bool {
        sizeCategory.isAccessibilityCategory
    }

    /// Returns the color for an arc, falling back to indigo
    private func arcColor(for arc: Arc) -> Color {
        if let hex = arc.colorHex {
            return Color(hex: hex) ?? .indigo
        }
        return .indigo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                // Arc indicator
                if let arc = stack.arc {
                    Circle()
                        .fill(arcColor(for: arc))
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Arc: \(arc.title)")
                }

                Text(stack.title)
                    .font(.headline)
                    .lineLimit(isAccessibilitySize ? 2 : 1)

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
                        .monospacedDigit()
                }
                .foregroundStyle(.orange)
                .frame(minHeight: 22) // Ensure minimum touch target
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

#Preview("Stack with Arc") {
    let arc = Arc(title: "OEM Strategy", colorHex: "FF6B6B")
    let stack = Stack(title: "Stack in Arc", stackDescription: nil, status: .active, sortOrder: 0)
    stack.arc = arc
    stack.arcId = arc.id
    return StackRowView(stack: stack)
        .padding()
}
