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
    @ViewBuilder
    var stackList: some View {
        let stacks = filteredStacks
        let allowMove = selectedTagIds.isEmpty
        List {
            ForEach(stacks) { stack in
                stackRow(for: stack)
            }
            // Disable reordering when filters are active to avoid confusion
            .onMove(perform: allowMove ? moveStacks : nil)
        }
        .listStyle(.plain)
        .refreshable {
            await performSync()
        }
    }

    // MARK: - Stack Row Helpers

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
                deactivateStack(stack)
            } label: {
                Label("Deactivate", systemImage: "star.slash")
            }
            .tint(.gray)
        } else {
            Button {
                setAsActive(stack)
            } label: {
                Label("Set Active", systemImage: "star.fill")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func trailingSwipeActions(for stack: Stack) -> some View {
        Button(role: .destructive) {
            deleteStack(stack)
        } label: {
            Label("Delete", systemImage: "trash")
        }

        Button {
            handleCompleteButtonTapped(for: stack)
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
                deactivateStack(stack)
            } label: {
                Label("Deactivate", systemImage: "star.slash")
            }
        } else {
            Button {
                setAsActive(stack)
            } label: {
                Label("Set Active", systemImage: "star.fill")
            }
        }

        Button {
            handleCompleteButtonTapped(for: stack)
        } label: {
            Label("Complete", systemImage: "checkmark.circle")
        }

        Divider()

        Button(role: .destructive) {
            deleteStack(stack)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
