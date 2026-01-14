//
//  DraftsStacksListView.swift
//  Dequeue
//
//  Displays list of draft stacks with swipe-to-delete
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "DraftsStacksListView")

struct DraftsStacksListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService

    @Query(
        filter: #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == true
        },
        sort: \Stack.createdAt,
        order: .reverse
    ) private var drafts: [Stack]

    @State private var cachedDeviceId: String = ""
    @State private var deleteErrorMessage: String?
    @State private var showDeleteError = false

    private var stackService: StackService {
        StackService(
            modelContext: modelContext,
            userId: authService.currentUserId ?? "",
            deviceId: cachedDeviceId,
            syncManager: syncManager
        )
    }

    var body: some View {
        Group {
            if drafts.isEmpty {
                emptyState
            } else {
                draftsList
            }
        }
        .task {
            if cachedDeviceId.isEmpty {
                cachedDeviceId = await DeviceService.shared.getDeviceId()
            }
        }
        .alert("Error", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let deleteErrorMessage {
                Text(deleteErrorMessage)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Drafts",
            systemImage: "doc",
            description: Text("Draft stacks will appear here")
        )
    }

    // MARK: - Drafts List

    private var draftsList: some View {
        List {
            ForEach(drafts) { draft in
                NavigationLink {
                    StackEditorView(mode: .edit(draft))
                } label: {
                    VStack(alignment: .leading) {
                        Text(draft.title.isEmpty ? "Untitled" : draft.title)
                            .font(.headline)
                        Text("Created \(draft.createdAt, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteDrafts)
        }
    }

    // MARK: - Actions

    private func deleteDrafts(at offsets: IndexSet) {
        for index in offsets {
            let draft = drafts[index]
            do {
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
    NavigationStack {
        DraftsStacksListView()
    }
    .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
