//
//  HomeView+Subviews.swift
//  Dequeue
//
//  HomeView subviews extension - stack list and empty states
//

import SwiftUI

// MARK: - Empty States

extension HomeView {
    var emptyState: some View {
        ContentUnavailableView(
            "No Stacks",
            systemImage: "tray",
            description: Text("Add a stack to get started")
        )
    }

    var noFilterResultsState: some View {
        ContentUnavailableView {
            Label("No Matching Stacks", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No stacks match the selected tags")
        } actions: {
            Button("Clear Filters") {
                selectedTagIds.removeAll()
            }
        }
    }
}

// MARK: - Stack List

extension HomeView {
    var stackList: some View {
        StackListContent(
            stacks: filteredStacks,
            selectedStack: $selectedStack,
            allowMove: selectedTagIds.isEmpty,
            onMove: moveStacks,
            onSetActive: setAsActive,
            onDeactivate: deactivateStack,
            onComplete: handleCompleteButtonTapped,
            onDelete: deleteStack,
            onSync: performSync
        )
    }
}

/// Extracted stack list content to help Swift compiler with type inference.
/// This struct isolates the complex List/ForEach/swipe actions from HomeView's extension context.
private struct StackListContent: View {
    let stacks: [Stack]
    @Binding var selectedStack: Stack?
    let allowMove: Bool
    let onMove: (IndexSet, Int) -> Void
    let onSetActive: (Stack) -> Void
    let onDeactivate: (Stack) -> Void
    let onComplete: (Stack) -> Void
    let onDelete: (Stack) -> Void
    let onSync: () async -> Void

    var body: some View {
        List {
            ForEach(stacks) { stack in
                stackRow(for: stack)
            }
            .onMove(perform: allowMove ? onMove : nil)
        }
        .listStyle(.plain)
        .refreshable {
            await onSync()
        }
    }

    @ViewBuilder
    private func stackRow(for stack: Stack) -> some View {
        StackRowView(stack: stack)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedStack = stack
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                leadingSwipeActions(for: stack)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                trailingSwipeActions(for: stack)
            }
            .contextMenu {
                contextMenuContent(for: stack)
            }
    }

    @ViewBuilder
    private func leadingSwipeActions(for stack: Stack) -> some View {
        if stack.isActive {
            Button {
                onDeactivate(stack)
            } label: {
                Label("Deactivate", systemImage: "star.slash")
            }
            .tint(.gray)
        } else {
            Button {
                onSetActive(stack)
            } label: {
                Label("Set Active", systemImage: "star.fill")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func trailingSwipeActions(for stack: Stack) -> some View {
        Button(role: .destructive) {
            onDelete(stack)
        } label: {
            Label("Delete", systemImage: "trash")
        }

        Button {
            onComplete(stack)
        } label: {
            Label("Complete", systemImage: "checkmark.circle")
        }
        .tint(.green)
    }

    @ViewBuilder
    private func contextMenuContent(for stack: Stack) -> some View {
        Button {
            selectedStack = stack
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        if stack.isActive {
            Button {
                onDeactivate(stack)
            } label: {
                Label("Deactivate", systemImage: "star.slash")
            }
        } else {
            Button {
                onSetActive(stack)
            } label: {
                Label("Set Active", systemImage: "star.fill")
            }
        }

        Button {
            onComplete(stack)
        } label: {
            Label("Complete", systemImage: "checkmark.circle")
        }

        Divider()

        Button(role: .destructive) {
            onDelete(stack)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
