//
//  CustomTabBar.swift
//  Dequeue
//
//  GitHub-style tab bar with grouped tabs on the left and standalone Add button on the right
//

import SwiftUI

// MARK: - Layout Constants

private enum TabBarMetrics {
    static let tabMinWidth: CGFloat = 64
    static let tabMinHeight: CGFloat = 44
    static let tabHorizontalPadding: CGFloat = 4
    static let tabVerticalPadding: CGFloat = 8
    static let tabSpacing: CGFloat = 4

    static let groupedTabsCornerRadius: CGFloat = 16

    static let addButtonSize: CGFloat = 56
    static let addButtonShadowRadius: CGFloat = 8
    static let addButtonShadowY: CGFloat = 4
    static let addButtonShadowOpacity: CGFloat = 0.3

    static let barHorizontalPadding: CGFloat = 16
    static let barVerticalPadding: CGFloat = 8
}

// MARK: - Tab Item Model

private struct TabItem: Identifiable {
    let id: Int
    let icon: String
    let label: String

    var tag: Int { id }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    let onAddTapped: () -> Void

    private let tabs: [TabItem] = [
        TabItem(id: 0, icon: "house", label: "Home"),
        TabItem(id: 1, icon: "doc", label: "Drafts"),
        TabItem(id: 2, icon: "checkmark.circle", label: "Completed"),
        TabItem(id: 3, icon: "gear", label: "Settings")
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Grouped tabs on the left
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
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
                RoundedRectangle(cornerRadius: TabBarMetrics.groupedTabsCornerRadius)
                    .fill(.ultraThinMaterial)
            )

            Spacer()

            // Standalone Add button on the right
            AddButton(action: onAddTapped)
        }
        .padding(.horizontal, TabBarMetrics.barHorizontalPadding)
        .padding(.vertical, TabBarMetrics.barVerticalPadding)
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
            VStack(spacing: TabBarMetrics.tabSpacing) {
                Image(systemName: icon)
                    .imageScale(.large)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(label)
                    .font(.caption2)
                    .fontWeight(isSelected ? .medium : .regular)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(minWidth: TabBarMetrics.tabMinWidth, minHeight: TabBarMetrics.tabMinHeight)
            .padding(.horizontal, TabBarMetrics.tabHorizontalPadding)
            .padding(.vertical, TabBarMetrics.tabVerticalPadding)
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
                .font(.title2.weight(.semibold))
                .imageScale(.large)
                .foregroundStyle(.white)
                .frame(
                    width: TabBarMetrics.addButtonSize,
                    height: TabBarMetrics.addButtonSize
                )
                .background(
                    Circle()
                        .fill(.accent)
                        .shadow(
                            color: .accent.opacity(TabBarMetrics.addButtonShadowOpacity),
                            radius: TabBarMetrics.addButtonShadowRadius,
                            x: 0,
                            y: TabBarMetrics.addButtonShadowY
                        )
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
