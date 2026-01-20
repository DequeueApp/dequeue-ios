//
//  ArcCardView.swift
//  Dequeue
//
//  Large card component for displaying an Arc in ArcsView
//

import SwiftUI

/// Large card view displaying an Arc with progress, stacks, and metadata
struct ArcCardView: View {
    let arc: Arc
    let onTap: () -> Void
    let onAddStackTap: () -> Void

    /// Default color when no custom color is set
    private let defaultColorHex = "5E5CE6" // System indigo

    private var accentColor: Color {
        if let hex = arc.colorHex {
            return Color(hex: hex) ?? .indigo
        }
        return .indigo
    }

    /// Non-deleted stacks to display
    private var visibleStacks: [Stack] {
        arc.sortedStacks
    }

    /// Non-deleted reminders count
    private var reminderCount: Int {
        arc.reminders.filter { !$0.isDeleted && $0.status == .active }.count
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Color accent bar at top
                accentColor
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                // Title and description
                VStack(alignment: .leading, spacing: 4) {
                    Text(arc.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let description = arc.arcDescription, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                // Stack pills - horizontal scroll
                stackPillsSection

                // Progress bar
                progressSection

                // Metadata row (reminders count)
                metadataRow
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view arc details")
    }

    // MARK: - Subviews

    private var stackPillsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleStacks.prefix(5)) { stack in
                    StackPill(title: stack.title, isCompleted: stack.status == .completed)
                }

                if visibleStacks.count > 5 {
                    Text("+\(visibleStacks.count - 5)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                // Add stack button
                Button {
                    onAddStackTap()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.quaternary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add stack to arc")
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentColor)
                        .frame(width: geometry.size.width * arc.progress)
                }
            }
            .frame(height: 8)

            // Progress text
            Text("\(Int(arc.progress * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 16) {
            // Stack count
            Label("\(arc.totalStackCount)", systemImage: "square.stack.3d.up")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Reminder count (if any)
            if reminderCount > 0 {
                Label("\(reminderCount)", systemImage: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            // Status badge
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch arc.status {
        case .active:
            EmptyView()
        case .paused:
            Text("Paused")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.15))
                .clipShape(Capsule())
        case .completed:
            Label("Done", systemImage: "checkmark")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.green.opacity(0.15))
                .clipShape(Capsule())
        case .archived:
            Text("Archived")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var accessibilityLabel: String {
        var label = arc.title
        if arc.totalStackCount > 0 {
            label += ", \(arc.completedStackCount) of \(arc.totalStackCount) stacks completed"
        }
        if reminderCount > 0 {
            label += ", \(reminderCount) reminder\(reminderCount == 1 ? "" : "s")"
        }
        return label
    }
}

// MARK: - Stack Pill

/// Small pill showing a stack name within an arc card
private struct StackPill: View {
    let title: String
    let isCompleted: Bool

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(isCompleted ? .secondary : .primary)
            .strikethrough(isCompleted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(isCompleted ? 0.1 : 0.2))
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

// MARK: - Previews

#Preview("Active Arc") {
    let arc = Arc(title: "OEM Strategy for Conference", arcDescription: "Prepare all materials and demos for the upcoming tech conference")
    return ArcCardView(arc: arc, onTap: {}, onAddStackTap: {})
        .padding()
}

#Preview("Paused Arc") {
    let arc = Arc(title: "Product Launch", arcDescription: "Q1 product launch preparation", status: .paused)
    return ArcCardView(arc: arc, onTap: {}, onAddStackTap: {})
        .padding()
}

#Preview("Completed Arc") {
    let arc = Arc(title: "Documentation Update", status: .completed)
    return ArcCardView(arc: arc, onTap: {}, onAddStackTap: {})
        .padding()
}
