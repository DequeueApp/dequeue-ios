//
//  CustomBottomBar.swift
//  Dequeue
//
//  Custom bottom navigation bar with tabs grouped left and floating Add button right
//  Based on iOS native apps pattern (Photos, News, Messages)
//

import SwiftUI

private struct TabItem: Identifiable {
    let id: Int
    let icon: String
    let label: String
}

struct CustomBottomBar: View {
    @Binding var selectedTab: Int
    let onAddTapped: () -> Void

    private let tabs: [TabItem] = [
        TabItem(id: 0, icon: "square.stack.3d.up", label: "Stacks"),
        TabItem(id: 1, icon: "clock.arrow.circlepath", label: "Activity"),
        TabItem(id: 2, icon: "gear", label: "Settings")
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Navigation tabs grouped on left
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    tabButton(icon: tab.icon, label: tab.label, tag: tab.id)
                }
            }

            Spacer()

            // Floating Add button on right
            addButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func tabButton(icon: String, label: String, tag: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tag
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(selectedTab == tag ? .accent : .secondary)
            .frame(minWidth: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selectedTab == tag ? .isSelected : [])
    }

    private var addButton: some View {
        Button {
            onAddTapped()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add new stack")
        .accessibilityHint("Creates a new stack")
    }
}

#Preview {
    VStack {
        Spacer()
        CustomBottomBar(selectedTab: .constant(0)) { }
    }
}
