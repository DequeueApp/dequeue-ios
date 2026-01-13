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
        ContentUnavailableView(
            "No Matching Stacks",
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text("No stacks match the selected tags")
        ) {
            Button("Clear Filters") {
                selectedTagIds.removeAll()
            }
        }
    }
}

// MARK: - Stack List

extension HomeView {
    var stackList: some View {
        List {
            ForEach(filteredStacks) { stack in
                StackRowView(stack: stack)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedStack = stack
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
                    .contextMenu {
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
            // Disable reordering when filters are active to avoid confusion
            .onMove(perform: selectedTagIds.isEmpty ? moveStacks : nil)
        }
        .listStyle(.plain)
        .refreshable {
            await performSync()
        }
    }
}
