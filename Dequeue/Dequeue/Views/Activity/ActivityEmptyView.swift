//
//  ActivityEmptyView.swift
//  Dequeue
//
//  Empty state for the activity feed when no events exist
//

import SwiftUI

struct ActivityEmptyView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Activity Yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Complete some tasks to see your daily accomplishments and progress here.")
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ActivityEmptyView()
}
