//
//  UndoCompletionBanner.swift
//  Dequeue
//
//  Banner displayed when a stack is pending completion with undo option
//

import SwiftUI

struct UndoCompletionBanner: View {
    let stackTitle: String
    let progress: Double
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at top
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: geometry.size.width * progress)
            }
            .frame(height: 3)

            // Main content
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stack Completed")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(stackTitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    onUndo()
                } label: {
                    Text("Undo")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color.green.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview("Undo Completion Banner") {
    VStack {
        UndoCompletionBanner(
            stackTitle: "My Completed Stack",
            progress: 0.6,
            onUndo: { }
        )
        .padding()

        Spacer()
    }
}

#Preview("Full Progress") {
    VStack {
        UndoCompletionBanner(
            stackTitle: "Almost Done Stack",
            progress: 0.95,
            onUndo: { }
        )
        .padding()

        Spacer()
    }
}
