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
    let isLoading: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Image(systemName: stack.isActive ? "checkmark.circle.fill" : "star.fill")
                        .font(.title3)
                        .foregroundStyle(stack.isActive ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? "Updating..." : (stack.isActive ? "Currently Active" : "Start Working"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(bannerBackgroundColor)
                .padding(.horizontal, -4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(.isButton)
    }

    private var statusDescription: String {
        if isLoading {
            return "Please wait..."
        }
        return stack.isActive
            ? "Tap to deactivate this stack"
            : "Tap to set as your active stack"
    }

    private var bannerBackgroundColor: Color {
        if isLoading {
            return Color.gray.opacity(0.1)
        }
        return stack.isActive
            ? Color.green.opacity(0.1)
            : Color.orange.opacity(0.1)
    }

    private var accessibilityLabelText: String {
        if isLoading {
            return "Updating stack status"
        }
        return stack.isActive
            ? "Stack is currently active"
            : "Stack is not active"
    }

    private var accessibilityHintText: String {
        if isLoading {
            return "Please wait while the status is being updated"
        }
        return stack.isActive
            ? "Double tap to deactivate this stack"
            : "Double tap to set this as your active stack"
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
                isLoading: false,
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
                isLoading: false,
                onToggle: {}
            )
        }
    }
}

#Preview("Loading") {
    List {
        Section {
            StackActiveStatusBanner(
                stack: {
                    let stack = Stack(title: "Test", status: .active, sortOrder: 0)
                    stack.isActive = false
                    return stack
                }(),
                isLoading: true,
                onToggle: {}
            )
        }
    }
}
