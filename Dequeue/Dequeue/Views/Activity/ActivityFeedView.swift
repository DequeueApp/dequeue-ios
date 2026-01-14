//
//  ActivityFeedView.swift
//  Dequeue
//
//  Activity feed showing recent accomplishments (MVP placeholder)
//

import SwiftUI

struct ActivityFeedView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming Soon",
                systemImage: "clock.arrow.circlepath",
                description: Text("Your activity feed will show your recent accomplishments here.")
            )
            .navigationTitle("Activity")
        }
    }
}

#Preview {
    ActivityFeedView()
}
