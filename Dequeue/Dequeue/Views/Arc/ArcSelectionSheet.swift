//
//  ArcSelectionSheet.swift
//  Dequeue
//
//  Sheet for selecting an Arc when creating a new Stack
//

import SwiftUI
import SwiftData

/// A sheet for selecting an Arc during Stack creation.
/// Unlike ArcPickerSheet, this doesn't require an existing Stack.
struct ArcSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query private var arcs: [Arc]

    /// The currently selected arc (if any)
    let currentArc: Arc?

    /// Callback when an arc is selected or cleared
    let onArcSelected: (Arc?) -> Void

    init(currentArc: Arc? = nil, onArcSelected: @escaping (Arc?) -> Void) {
        self.currentArc = currentArc
        self.onArcSelected = onArcSelected

        // Query for arcs that can have stacks assigned:
        // - Not deleted
        // - Active or paused (not completed or archived)
        let activeRawValue = ArcStatus.active.rawValue
        let pausedRawValue = ArcStatus.paused.rawValue
        _arcs = Query(
            filter: #Predicate<Arc> { arc in
                arc.isDeleted == false &&
                (arc.statusRawValue == activeRawValue || arc.statusRawValue == pausedRawValue)
            },
            sort: \Arc.sortOrder
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if arcs.isEmpty {
                    emptyState
                } else {
                    arcList
                }
            }
            .navigationTitle("Add to Arc")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Active Arcs",
            systemImage: "rays",
            description: Text("Create an arc first to organize your stacks")
        )
    }

    // MARK: - Arc List

    private var arcList: some View {
        List {
            // Option to not assign to any arc
            Button {
                onArcSelected(nil)
                dismiss()
            } label: {
                HStack {
                    Label("No Arc", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)

                    Spacer()

                    if currentArc == nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Available arcs
            ForEach(arcs) { arc in
                Button {
                    onArcSelected(arc)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                // Color indicator
                                Circle()
                                    .fill(arcColor(for: arc))
                                    .frame(width: 12, height: 12)

                                Text(arc.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }

                            if let description = arc.arcDescription, !description.isEmpty {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            // Stack count
                            Text("\(arc.totalStackCount) stack\(arc.totalStackCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        // Check if this arc is currently selected
                        if currentArc?.id == arc.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Helpers

    private func arcColor(for arc: Arc) -> Color {
        if let hex = arc.colorHex {
            return Color(hex: hex) ?? .indigo
        }
        return .indigo
    }
}

// MARK: - Previews

#Preview("With Arcs") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // Safe: In-memory container with known schema types cannot fail in preview context
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Arc.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    let arc1 = Arc(title: "OEM Strategy", arcDescription: "Conference preparation", colorHex: "5E5CE6")
    let arc2 = Arc(title: "Product Launch", colorHex: "FF6B6B")

    container.mainContext.insert(arc1)
    container.mainContext.insert(arc2)

    return ArcSelectionSheet(currentArc: nil) { _ in }
        .modelContainer(container)
}

#Preview("With Selected Arc") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // Safe: In-memory container with known schema types cannot fail in preview context
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Arc.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    let arc1 = Arc(title: "OEM Strategy", arcDescription: "Conference preparation", colorHex: "5E5CE6")
    let arc2 = Arc(title: "Product Launch", colorHex: "FF6B6B")

    container.mainContext.insert(arc1)
    container.mainContext.insert(arc2)

    return ArcSelectionSheet(currentArc: arc1) { _ in }
        .modelContainer(container)
}

#Preview("Empty") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // Safe: In-memory container with known schema types cannot fail in preview context
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Arc.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    return ArcSelectionSheet(currentArc: nil) { _ in }
        .modelContainer(container)
}
