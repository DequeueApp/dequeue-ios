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

    @Query private var drafts: [Stack]

    /// Filtered drafts that are truly draft stacks (safety filter in case @Query has issues)
    /// This filters out any stacks that:
    /// - Are not actually drafts (isDraft == false means promoted to full stack)
    /// - Have been completed, closed, or archived
    private var validDrafts: [Stack] {
        drafts.filter { stack in
            stack.isDraft && stack.status == .active
        }
    }

    init() {
        // Query drafts that are not deleted, are marked as draft,
        // and have active status (not completed/closed/archived)
        // Note: Using string literal "active" directly to avoid SwiftData predicate
        // variable capture issues that can cause incorrect filtering
        _drafts = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false &&
                stack.isDraft == true &&
                stack.statusRawValue == "active"
            },
            sort: \Stack.updatedAt,
            order: .reverse
        )
    }

    @State private var stackService: StackService?
    @State private var deleteErrorMessage: String?
    @State private var showDeleteError = false

    var body: some View {
        Group {
            if validDrafts.isEmpty {
                emptyState
            } else {
                draftsList
            }
        }
        .task {
            guard stackService == nil else { return }
            let deviceId = await DeviceService.shared.getDeviceId()
            stackService = StackService(
                modelContext: modelContext,
                userId: authService.currentUserId ?? "",
                deviceId: deviceId,
                syncManager: syncManager
            )
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
            ForEach(validDrafts) { draft in
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
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func deleteDrafts(at offsets: IndexSet) {
        guard let service = stackService else {
            deleteErrorMessage = "Initializing... please try again."
            showDeleteError = true
            return
        }

        // Capture drafts to delete before entering Task (offsets may change)
        let draftsToDelete = offsets.map { validDrafts[$0] }

        Task {
            for draft in draftsToDelete {
                do {
                    try await service.discardDraft(draft)
                    logger.info("Draft discarded via swipe: \(draft.id)")
                } catch {
                    logger.error("Failed to discard draft: \(error.localizedDescription)")
                    deleteErrorMessage = "Could not delete draft. Please try again."
                    showDeleteError = true
                }
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
