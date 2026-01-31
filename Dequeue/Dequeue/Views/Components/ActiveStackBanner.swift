//
//  ActiveStackBanner.swift
//  Dequeue
//
//  Persistent banner showing the currently active stack
//

import SwiftUI
import SwiftData

struct ActiveStackBanner: View {
    @Query private var activeStacks: [Stack]

    let onStackTapped: (Stack) -> Void
    let onEmptyTapped: () -> Void

    init(
        onStackTapped: @escaping (Stack) -> Void,
        onEmptyTapped: @escaping () -> Void
    ) {
        // Query for the explicitly active stack (isActive == true)
        // This ensures consistency with StackService.getCurrentActiveStack()
        _activeStacks = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false &&
                stack.isDraft == false &&
                stack.isActive == true
            }
        )
        self.onStackTapped = onStackTapped
        self.onEmptyTapped = onEmptyTapped
    }

    private var activeStack: Stack? {
        activeStacks.first
    }

    var body: some View {
        Button {
            if let stack = activeStack {
                onStackTapped(stack)
            } else {
                onEmptyTapped()
            }
        } label: {
            bannerContent
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: activeStack?.id)
    }

    // MARK: - Banner Content

    @ViewBuilder
    private var bannerContent: some View {
        if let stack = activeStack {
            activeStackContent(stack)
        } else {
            emptyStateContent
        }
    }

    private func activeStackContent(_ stack: Stack) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.fill")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(stack.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let description = stack.stackDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: BannerConstants.minTapHeight)
        .glassEffect(in: RoundedRectangle(cornerRadius: BannerConstants.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: BannerConstants.cornerRadius))
    }

    private var emptyStateContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Tap to set an active stack")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: BannerConstants.minTapHeight)
        .glassEffect(in: RoundedRectangle(cornerRadius: BannerConstants.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: BannerConstants.cornerRadius))
    }
}

// MARK: - Constants

private enum BannerConstants {
    static let minTapHeight: CGFloat = 44
    static let cornerRadius: CGFloat = 12
}

// MARK: - Preview

#Preview("With Active Stack") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    let stack = Stack(
        title: "My Active Stack",
        stackDescription: "Working on the new feature implementation",
        status: .active,
        sortOrder: 0,
        isActive: true
    )
    container.mainContext.insert(stack)

    return VStack {
        Spacer()
        ActiveStackBanner(
            onStackTapped: { _ in },
            onEmptyTapped: { }
        )
        .padding(.horizontal)
    }
    .modelContainer(container)
}

#Preview("Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    return VStack {
        Spacer()
        ActiveStackBanner(
            onStackTapped: { _ in },
            onEmptyTapped: { }
        )
        .padding(.horizontal)
    }
    .modelContainer(container)
}
