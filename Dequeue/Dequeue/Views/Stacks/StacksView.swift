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
        }
    }
}

#Preview {
    StacksView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self, Tag.self], inMemory: true)
}
