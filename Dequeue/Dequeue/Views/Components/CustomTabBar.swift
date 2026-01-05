//
//  CustomTabBar.swift
//  Dequeue
//
//  GitHub-style tab bar with grouped tabs on the left and standalone Add button on the right
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    let onAddTapped: () -> Void

    private let tabs: [(icon: String, label: String, tag: Int)] = [
        ("house", "Home", 0),
        ("doc", "Drafts", 1),
        ("checkmark.circle", "Completed", 2),
        ("gear", "Settings", 3)
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Grouped tabs on the left
            HStack(spacing: 0) {
                ForEach(tabs, id: \.tag) { tab in
                    TabBarButton(
                        icon: tab.icon,
                        label: tab.label,
                        isSelected: selectedTab == tab.tag
                    ) {
                        selectedTab = tab.tag
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )

            Spacer()

            // Standalone Add button on the right
            AddButton(action: onAddTapped)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Tab Bar Button

private struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(label)
                    .font(.caption2)
                    .fontWeight(isSelected ? .medium : .regular)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(minWidth: 64, minHeight: 44)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Add Button

private struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(.accent)
                        .shadow(color: .accent.opacity(0.3), radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add new stack")
    }
}

#Preview {
    VStack {
        Spacer()
        CustomTabBar(
            selectedTab: .constant(0),
            onAddTapped: {}
        )
    }
    .background(Color(.systemGroupedBackground))
}
