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
    @Environment(\.syncManager) private var syncManager
    @Query(
        filter: #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == true
        },
        sort: \Stack.updatedAt,
        order: .reverse
    ) private var drafts: [Stack]

    @State private var deleteErrorMessage: String?
    @State private var showDeleteError = false

    private var stackService: StackService {
        StackService(modelContext: modelContext, syncManager: syncManager)
    }

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    emptyState
                } else {
                    draftsList
                }
            }
            .navigationTitle("Drafts")
            .alert("Error", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let deleteErrorMessage {
                    Text(deleteErrorMessage)
                }
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
            }
            .onDelete(perform: deleteDrafts)
        }
    }

    private func deleteDrafts(at offsets: IndexSet) {
        for index in offsets {
            let draft = drafts[index]
            do {
                // Use stackService.discardDraft to properly fire stack.discarded event
                try stackService.discardDraft(draft)
                logger.info("Draft discarded via swipe: \(draft.id)")
            } catch {
                logger.error("Failed to discard draft: \(error.localizedDescription)")
                deleteErrorMessage = "Could not delete draft. Please try again."
                showDeleteError = true
            }
        }
    }
}

#Preview {
    DraftsView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
