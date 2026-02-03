//
//  InitialSyncLoadingView.swift
//  Dequeue
//
//  Loading view shown during initial sync to prevent flickering UI
//

import SwiftUI

struct InitialSyncLoadingView: View {
    let eventsProcessed: Int

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 8)

            Text("Syncing your stacks")
                .font(.headline)

            if eventsProcessed > 0 {
                Text("\(eventsProcessed) events processed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connecting to server...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    InitialSyncLoadingView(eventsProcessed: 42)
}

#Preview("Zero Events") {
    InitialSyncLoadingView(eventsProcessed: 0)
}
