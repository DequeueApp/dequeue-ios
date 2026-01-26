//
//  StackActiveStatusBanner.swift
//  Dequeue
//
//  Banner showing active status at top of stack editor
//

import SwiftUI

/// A tappable banner that displays and toggles the active status of a stack.
/// Shows "Start Working" for inactive stacks, "Currently Active" for active ones.
struct StackActiveStatusBanner: View {
    let stack: Stack
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: stack.isActive ? "checkmark.circle.fill" : "star.fill")
                    .font(.title3)
                    .foregroundStyle(stack.isActive ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stack.isActive ? "Currently Active" : "Start Working")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(stack.isActive
                         ? "Tap to deactivate this stack"
                         : "Tap to set as your active stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(stack.isActive
                      ? Color.green.opacity(0.1)
                      : Color.orange.opacity(0.1))
                .padding(.horizontal, -4)
        )
    }
}

#Preview("Not Active") {
    List {
        Section {
            StackActiveStatusBanner(
                stack: {
                    let stack = Stack(title: "Test", status: .active, sortOrder: 0)
                    stack.isActive = false
                    return stack
                }(),
                onToggle: {}
            )
        }
    }
}

#Preview("Active") {
    List {
        Section {
            StackActiveStatusBanner(
                stack: {
                    let stack = Stack(title: "Test", status: .active, sortOrder: 0)
                    stack.isActive = true
                    return stack
                }(),
                onToggle: {}
            )
        }
    }
}
