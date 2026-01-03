//
//  DraftsView.swift
//  Dequeue
//
//  Shows work-in-progress draft stacks
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "DraftsView")

struct DraftsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == true
        },
        sort: \Stack.updatedAt,
        order: .reverse
    ) private var drafts: [Stack]

    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var stackService: StackService?

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    emptyState
                } else {
                    draftsList
                }
            }
            .onAppear {
                if stackService == nil {
                    stackService = StackService(modelContext: modelContext)
                }
            }
            .navigationTitle("Drafts")
            .alert("Delete Failed", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteErrorMessage)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Drafts",
            systemImage: "doc",
            description: Text("Draft stacks will appear here")
        )
    }

    private var draftsList: some View {
        List {
            ForEach(drafts) { draft in
                NavigationLink {
                    StackEditorView(mode: .edit(draft))
                } label: {
                    VStack(alignment: .leading) {
                        Text(draft.title.isEmpty ? "Untitled" : draft.title)
                            .font(.headline)
                        Text("Last edited \(draft.updatedAt, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteDraft(draft)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func deleteDraft(_ draft: Stack) {
        guard let service = stackService else {
            logger.error("StackService not initialized")
            deleteErrorMessage = "Service not ready. Please try again."
            showDeleteError = true
            return
        }

        do {
            // Use stackService.discardDraft to properly fire stack.discarded event
            try service.discardDraft(draft)
            logger.info("Draft discarded via swipe: \(draft.id)")
        } catch {
            logger.error("Failed to discard draft: \(error.localizedDescription)")
            // Show error to user - don't silently bypass event emission
            // Note: Using custom swipe action instead of onDelete ensures draft
            // only disappears from list if deletion succeeds
            deleteErrorMessage = "Could not delete draft. Please try again."
            showDeleteError = true
        }
    }
}

#Preview {
    DraftsView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
