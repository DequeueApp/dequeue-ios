//
//  InitialSyncLoadingView.swift
//  Dequeue
//
//  Loading view shown during initial sync to prevent flickering UI
//  Enhanced with progress tracking (DEQ-240)
//

import SwiftUI

struct InitialSyncLoadingView: View {
    let eventsProcessed: Int
    let totalEvents: Int?  // DEQ-240: Add total count for progress bar

    var body: some View {
        VStack(spacing: 20) {
            // Show determinate progress bar if we know the total (DEQ-240)
            if let total = totalEvents, total > 0 {
                ProgressView(value: Double(eventsProcessed), total: Double(total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                    .padding(.bottom, 8)
            } else {
                // Indeterminate spinner when total is unknown
                ProgressView()
                    .scaleEffect(1.5)
                    .padding(.bottom, 8)
            }

            Text("Syncing your stacks")
                .font(.headline)

            // DEQ-240: Show "X of Y events" when total is known
            if let total = totalEvents, total > 0 {
                Text("\(eventsProcessed) of \(total) events")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()  // Prevent width jumping as numbers change
            } else if eventsProcessed > 0 {
                Text("\(eventsProcessed) events processed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Connecting to server...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
    }
}

#Preview {
    InitialSyncLoadingView(eventsProcessed: 42, totalEvents: 100)
}

#Preview("Zero Events") {
    InitialSyncLoadingView(eventsProcessed: 0, totalEvents: nil)
}

#Preview("Unknown Total") {
    InitialSyncLoadingView(eventsProcessed: 150, totalEvents: nil)
}
