//
//  TagChip.swift
//  Dequeue
//
//  Reusable tag chip component for displaying tags
//

import SwiftUI

/// A compact chip view for displaying a single tag.
///
/// Features:
/// - Capsule-shaped background
/// - Optional color indicator dot
/// - Optional remove button
/// - Truncates long names with ellipsis
/// - Cross-platform (iOS and macOS)
struct TagChip: View {
    let tag: Tag
    var showRemoveButton: Bool = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            // Color indicator dot (if tag has a color)
            if let colorHex = tag.colorHex, let color = Color(hex: colorHex) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            Text(tag.name)
                .font(.caption)
                .lineLimit(1)

            if showRemoveButton {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15))
        .foregroundStyle(.secondary)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag: \(tag.name)")
        .accessibilityHint(showRemoveButton ? "Double tap to remove" : "")
    }
}

// MARK: - String-based TagChip

/// A convenience view for displaying a tag chip from just a name string.
/// Used when you don't have a Tag model instance.
struct TagChipLabel: View {
    let name: String
    var colorHex: String?

    var body: some View {
        HStack(spacing: 4) {
            if let colorHex, let color = Color(hex: colorHex) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15))
        .foregroundStyle(.secondary)
        .clipShape(Capsule())
        .accessibilityLabel("Tag: \(name)")
    }
}

// MARK: - Previews

#Preview("Single Tag") {
    let tag = Tag(name: "Swift")
    return TagChip(tag: tag)
        .padding()
}

#Preview("Tag with Color") {
    let tag = Tag(name: "Urgent", colorHex: "#FF5733")
    return TagChip(tag: tag)
        .padding()
}

#Preview("Tag with Remove Button") {
    let tag = Tag(name: "SwiftUI")
    return TagChip(tag: tag, showRemoveButton: true) {
        print("Remove tapped")
    }
    .padding()
}

#Preview("Multiple Tags") {
    let tags = [
        Tag(name: "Swift"),
        Tag(name: "iOS", colorHex: "#007AFF"),
        Tag(name: "SwiftUI", colorHex: "#FF9500"),
        Tag(name: "Very Long Tag Name That Truncates")
    ]

    return HStack(spacing: 6) {
        ForEach(tags, id: \.id) { tag in
            TagChip(tag: tag)
        }
    }
    .padding()
}

#Preview("Tag Chip Label") {
    HStack(spacing: 6) {
        TagChipLabel(name: "Frontend")
        TagChipLabel(name: "Backend", colorHex: "#34C759")
        TagChipLabel(name: "Bug", colorHex: "#FF3B30")
    }
    .padding()
}
