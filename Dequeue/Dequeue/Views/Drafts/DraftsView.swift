//
//  DraftsView.swift
//  Dequeue
//
//  Shows work-in-progress draft stacks with navigation chrome
//

import SwiftUI
import SwiftData

struct DraftsView: View {
    var body: some View {
        NavigationStack {
            DraftsStacksListView()
                .navigationTitle("Drafts")
        }
    }
}

#Preview {
    DraftsView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
