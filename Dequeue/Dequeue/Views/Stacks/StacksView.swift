//
//  StacksView.swift
//  Dequeue
//
//  Unified stacks view with segmented control for filtering by status
//

import SwiftUI
import SwiftData

struct StacksView: View {
    enum StackFilter: String, CaseIterable {
        case inProgress = "In Progress"
        case drafts = "Drafts"
        case completed = "Completed"
    }

    @State private var selectedFilter: StackFilter = .inProgress
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control for filtering
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(StackFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityLabel("Stack filter")
                .accessibilityHint("Select to filter stacks by status")

                // Content based on selection
                switch selectedFilter {
                case .inProgress:
                    InProgressStacksListView()
                case .drafts:
                    DraftsStacksListView()
                case .completed:
                    CompletedStacksListView()
                }
            }
            .navigationTitle("Stacks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add new stack")
                    .accessibilityHint("Creates a new stack")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            StackEditorView(mode: .create)
        }
    }
}

#Preview {
    StacksView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self, Tag.self], inMemory: true)
}
