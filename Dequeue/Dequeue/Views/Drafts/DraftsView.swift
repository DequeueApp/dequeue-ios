//
//  DraftsView.swift
//  Dequeue
//
//  Shows work-in-progress draft stacks
//

import SwiftUI
import SwiftData

struct DraftsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == true
        },
        sort: \Stack.updatedAt,
        order: .reverse
    ) private var drafts: [Stack]

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
            drafts[index].isDeleted = true
        }
    }
}

#Preview {
    DraftsView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
