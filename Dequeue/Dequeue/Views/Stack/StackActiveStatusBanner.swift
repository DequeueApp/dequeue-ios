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
                    Text(statusTitle)
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

    /// Consolidated state to reduce cyclomatic complexity
    private enum BannerState {
        case loading
        case active
        case inactive

        var title: String {
            switch self {
            case .loading: return "Updating..."
            case .active: return "Currently Active"
            case .inactive: return "Start Working"
            }
        }

        var description: String {
            switch self {
            case .loading: return "Please wait..."
            case .active: return "Tap to deactivate this stack"
            case .inactive: return "Tap to set as your active stack"
            }
        }

        var backgroundColor: Color {
            switch self {
            case .loading: return Color.gray.opacity(0.1)
            case .active: return Color.green.opacity(0.1)
            case .inactive: return Color.orange.opacity(0.1)
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .loading: return "Updating stack status"
            case .active: return "Stack is currently active"
            case .inactive: return "Stack is not active"
            }
        }

        var accessibilityHint: String {
            switch self {
            case .loading: return "Please wait while the status is being updated"
            case .active: return "Double tap to deactivate this stack"
            case .inactive: return "Double tap to set this as your active stack"
            }
        }
    }

    private var bannerState: BannerState {
        if isLoading { return .loading }
        return stack.isActive ? .active : .inactive
    }

    private var statusTitle: String { bannerState.title }
    private var statusDescription: String { bannerState.description }
    private var bannerBackgroundColor: Color { bannerState.backgroundColor }
    private var accessibilityLabelText: String { bannerState.accessibilityLabel }
    private var accessibilityHintText: String { bannerState.accessibilityHint }
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
