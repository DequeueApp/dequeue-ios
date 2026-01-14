//
//  CompletedStacksView.swift
//  Dequeue
//
//  Shows completed stacks archive with navigation chrome
//

import SwiftUI
import SwiftData

struct CompletedStacksView: View {
    var body: some View {
        NavigationStack {
            CompletedStacksListView()
                .navigationTitle("Completed")
        }
    }
}

#Preview {
    CompletedStacksView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
