//
//  TagsListView.swift
//  Dequeue
//
//  View for browsing all tags with usage counts
//

import SwiftUI
import SwiftData

/// List view for browsing all tags with their Stack counts.
///
/// Features:
/// - Alphabetically sorted tag list
/// - Shows active Stack count per tag
/// - Navigation to TagDetailView
/// - Empty state when no tags exist
struct TagsListView: View {
    @Query(sort: \Tag.name) private var tags: [Tag]

    /// Filter to only non-deleted tags
    private var activeTags: [Tag] {
        tags.filter { !$0.isDeleted }
    }

    var body: some View {
        Group {
            if activeTags.isEmpty {
                emptyState
            } else {
                tagsList
            }
        }
        .navigationTitle("Tags")
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            "No Tags",
            systemImage: "tag",
            description: Text("Tags you create will appear here")
        )
    }

    private var tagsList: some View {
        List {
            ForEach(activeTags) { tag in
                NavigationLink(value: tag) {
                    TagRow(tag: tag)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Tag.self) { tag in
            TagDetailView(tag: tag)
        }
    }
}

// MARK: - Tag Row

/// Individual row in the tags list showing tag chip and stack count.
private struct TagRow: View {
    let tag: Tag

    var body: some View {
        HStack {
            TagChip(tag: tag, showRemoveButton: false)

            Spacer()

            Text("(\(tag.activeStackCount))")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tag.name), \(tag.activeStackCount) stacks")
    }
}

// MARK: - Previews

#Preview("With Tags") {
    @Previewable @State var container: ModelContainer? = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: Tag.self, Stack.self, configurations: config) else {
            return nil
        }
        let workTag = Tag(name: "Work", colorHex: "#007AFF")
        let personalTag = Tag(name: "Personal", colorHex: "#FF9500")
        let urgentTag = Tag(name: "Urgent", colorHex: "#FF3B30")
        container.mainContext.insert(workTag)
        container.mainContext.insert(personalTag)
        container.mainContext.insert(urgentTag)
        return container
    }()

    if let container {
        NavigationStack {
            TagsListView()
        }
        .modelContainer(container)
    } else {
        Text("Failed to create preview container")
    }
}

#Preview("Empty State") {
    @Previewable @State var container: ModelContainer? = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try? ModelContainer(for: Tag.self, Stack.self, configurations: config)
    }()

    if let container {
        NavigationStack {
            TagsListView()
        }
        .modelContainer(container)
    } else {
        Text("Failed to create preview container")
    }
}
