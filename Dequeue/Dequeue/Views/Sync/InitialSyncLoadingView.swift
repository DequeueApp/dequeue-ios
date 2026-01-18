//
//  InitialSyncLoadingView.swift
//  Dequeue
//
//  Loading view shown during initial sync on fresh devices
//

import SwiftUI

/// Full-screen loading view displayed during initial sync on fresh devices.
/// Prevents UI flashing by hiding content until sync completes.
internal struct InitialSyncLoadingView: View {
    // MARK: - Constants

    private enum Constants {
        static let iconSize: CGFloat = 60
        static let verticalSpacing: CGFloat = 20
        static let animationDuration: Double = 1.0
    }

    let eventsProcessed: Int

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: Constants.verticalSpacing) {
            // Animated sync icon
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.system(size: Constants.iconSize))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    .linear(duration: Constants.animationDuration)
                    .repeatForever(autoreverses: false),
                    value: isAnimating
                )

            Text("Syncing Your Data")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Setting up your account on this device...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if eventsProcessed > 0 {
                Text("\(eventsProcessed) events synced")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding()
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview

#Preview("Syncing") {
    InitialSyncLoadingView(eventsProcessed: 42)
}

#Preview("Starting") {
    InitialSyncLoadingView(eventsProcessed: 0)
}
