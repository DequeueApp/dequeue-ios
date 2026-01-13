//
//  TagFilterBar.swift
//  Dequeue
//
//  Horizontal filter bar for filtering stacks by tags
//

import SwiftUI

/// Horizontal scrolling filter bar for filtering stacks by tags.
///
/// Features:
/// - "All" chip to clear filters
/// - Tag chips with stack count badges
/// - Multiple tag selection (OR logic)
/// - Visual highlight for selected tags
struct TagFilterBar: View {
    /// All available tags to display
    let tags: [Tag]

    /// All stacks to count tags from
    let stacks: [Stack]

    /// Currently selected tag IDs for filtering
    @Binding var selectedTagIds: Set<String>

    /// Count of stacks that have a given tag
    private func stackCount(for tag: Tag) -> Int {
        stacks.filter { stack in
            stack.tagObjects.contains { $0.id == tag.id && !$0.isDeleted }
        }.count
    }

    /// Tags that have at least one stack
    private var tagsWithStacks: [Tag] {
        tags.filter { tag in
            stackCount(for: tag) > 0
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                allChip

                // Tag chips with counts
                ForEach(tagsWithStacks) { tag in
                    tagChip(for: tag)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Subviews

    private var allChip: some View {
        Button {
            withAnimation(filterAnimation) {
                selectedTagIds.removeAll()
            }
        } label: {
            Text("All")
                .font(.subheadline.weight(selectedTagIds.isEmpty ? .semibold : .regular))
                .foregroundStyle(selectedTagIds.isEmpty ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selectedTagIds.isEmpty
                        ? Color.accentColor
                        : Color.secondary.opacity(0.15)
                )
                .clipShape(Capsule())
                .animation(filterAnimation, value: selectedTagIds.isEmpty)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All stacks")
        .accessibilityHint(selectedTagIds.isEmpty ? "Currently selected" : "Double tap to show all stacks")
    }

    /// Animation for filter state changes
    private var filterAnimation: Animation {
        .easeInOut(duration: 0.2)
    }

    private func tagChip(for tag: Tag) -> some View {
        let isSelected = selectedTagIds.contains(tag.id)
        let count = stackCount(for: tag)

        return Button {
            withAnimation(filterAnimation) {
                if isSelected {
                    selectedTagIds.remove(tag.id)
                } else {
                    selectedTagIds.insert(tag.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                // Color indicator dot
                if let colorHex = tag.colorHex, let color = Color(hex: colorHex) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }

                Text(tag.name)
                    .lineLimit(1)

                Text("(\(count))")
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color.secondary.opacity(0.15)
            )
            .clipShape(Capsule())
            .animation(filterAnimation, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tag.name), \(count) stacks")
        .accessibilityHint(isSelected ? "Selected, double tap to deselect" : "Double tap to filter by this tag")
    }
}

// MARK: - Previews

#Preview("Empty Selection") {
    struct PreviewWrapper: View {
        @State private var selectedTagIds: Set<String> = []

        var body: some View {
            let tags = [
                Tag(name: "Work", colorHex: "#007AFF"),
                Tag(name: "Personal", colorHex: "#FF9500"),
                Tag(name: "Urgent", colorHex: "#FF3B30")
            ]
            let stacks = [
                Stack(title: "Stack 1", stackDescription: nil, status: .active, sortOrder: 0),
                Stack(title: "Stack 2", stackDescription: nil, status: .active, sortOrder: 1)
            ]

            VStack {
                TagFilterBar(tags: tags, stacks: stacks, selectedTagIds: $selectedTagIds)
                Text("Selected: \(selectedTagIds.count)")
            }
        }
    }

    return PreviewWrapper()
}

#Preview("With Selection") {
    struct PreviewWrapper: View {
        @State private var selectedTagIds: Set<String> = []

        var body: some View {
            let tags = [
                Tag(name: "Work", colorHex: "#007AFF"),
                Tag(name: "Personal", colorHex: "#FF9500")
            ]
            let stacks: [Stack] = []

            VStack {
                TagFilterBar(tags: tags, stacks: stacks, selectedTagIds: $selectedTagIds)
                    .onAppear {
                        if let firstTag = tags.first {
                            selectedTagIds.insert(firstTag.id)
                        }
                    }
                Text("Selected: \(selectedTagIds.count)")
            }
        }
    }

    return PreviewWrapper()
}
